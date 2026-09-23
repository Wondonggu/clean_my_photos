import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models/asset_fingerprint_record.dart';
import '../core/models/asset_signature.dart';
import '../core/models/cleanup_category.dart';
import '../core/models/file_size_record.dart';
import '../core/models/media_item.dart';
import '../core/services/cleanup_analyzer.dart';
import '../core/services/thumbnail_analysis.dart';
import '../data/background_task.dart';
import '../data/photo_repository.dart';
import '../data/scan_cache.dart';
import 'settings_controller.dart';

/// 相册页面的整体状态。
enum LibraryPhase {
  /// 还没开始。
  idle,

  /// 正在读取权限。
  checkingPermission,

  /// 缺少权限，需要用户授权。
  needsPermission,

  /// 权限被拒绝或受限。
  permissionBlocked,

  /// 正在读取相册。
  loading,

  /// 可以正常使用。
  ready,

  /// 出错了。
  failure,
}

/// 后台任务的进度。
class TaskProgress {
  const TaskProgress({
    required this.label,
    required this.done,
    required this.total,
    this.reused = 0,
  });

  final String label;
  final int done;
  final int total;

  /// 其中有多少条是直接读缓存来的，没花时间重算。
  ///
  /// 单独拿出来是为了让界面能说清楚「这次为什么这么快」——不然一个瞬间
  /// 跳到 90% 的进度条看起来像出了 bug。
  final int reused;

  double get ratio => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  bool get isIndeterminate => total <= 0;
}

/// 相册清理的核心状态机。
///
/// 负责：权限 → 读取元数据 → 图像指纹分析 → 文件大小扫描 → 生成清理建议。
/// 所有耗时的步骤都是渐进的，界面随时可以读取到当前最好的结果。
class LibraryController extends ChangeNotifier {
  LibraryController({
    required PhotoRepository repository,
    required SettingsController settings,
    SignatureAnalyzer? analyzer,
    int sizeScanLimit = defaultSizeScanLimit,
    ScanCache? cache,
    FileSizeCache? sizeCache,
    BackgroundTaskGuard backgroundTasks = const NoopBackgroundTaskGuard(),
  })  : _repository = repository,
        _settings = settings,
        _signatureAnalyzer = analyzer ?? const SignatureAnalyzer(),
        _sizeScanLimit = sizeScanLimit,
        _cache = cache ?? ScanCache(),
        _sizeCache = sizeCache ?? FileSizeCache(),
        _backgroundTasks = backgroundTasks;

  /// 默认最多查询多少个文件的大小。
  ///
  /// iOS 没有批量获取文件大小的接口，只能逐个查询；对超大相册做全量查询
  /// 会非常慢，因此设一个上限，优先扫描视频和像素最多的照片。
  static const int defaultSizeScanLimit = 4000;

  final PhotoRepository _repository;
  final SettingsController _settings;
  final SignatureAnalyzer _signatureAnalyzer;
  final int _sizeScanLimit;
  final ScanCache _cache;
  final FileSizeCache _sizeCache;
  final BackgroundTaskGuard _backgroundTasks;

  /// 还没落盘的那几批。串成一条链保证写盘顺序，也让「取消」能等到它们收尾。
  Future<void> _cacheWrites = Future<void>.value();

  LibraryPhase _phase = LibraryPhase.idle;
  LibraryPermission _permission = const LibraryPermission.unknown();
  List<MediaItem> _items = const <MediaItem>[];
  List<AssetSignature> _signatures = const <AssetSignature>[];
  Map<CleanupCategoryType, CleanupCategory> _categories =
      const <CleanupCategoryType, CleanupCategory>{};
  LibrarySummary _summary = const LibrarySummary.empty();
  TaskProgress? _loadProgress;
  TaskProgress? _imageProgress;
  TaskProgress? _sizeProgress;
  String? _errorMessage;
  int _totalCount = 0;
  bool _truncated = false;
  bool _disposed = false;

  CancelSignal? _imageCancel;
  CancelSignal? _sizeCancel;
  bool _imageAnalysisDone = false;

  // ---------------------------------------------------------------- 只读状态

  LibraryPhase get phase => _phase;

  LibraryPermission get permission => _permission;

  List<MediaItem> get items => _items;

  List<AssetSignature> get signatures => _signatures;

  LibrarySummary get summary => _summary;

  /// 相册里的条目总数（可能大于已加载的数量）。
  int get totalCount => _totalCount;

  /// 是否因为超出上限只加载了一部分。
  bool get truncated => _truncated;

  String? get errorMessage => _errorMessage;

  /// 正在读取相册的进度。
  ///
  /// 和图像分析分开：首页在读取阶段自己有一个大的进度环，全局任务条再显示
  /// 一遍就是两个圈转给同一个人看。
  TaskProgress? get loadProgress => _loadProgress;

  /// 图像指纹分析的进度，null 表示没有在跑。
  TaskProgress? get imageProgress => _imageProgress;

  /// 文件大小扫描的进度。
  TaskProgress? get sizeProgress => _sizeProgress;

  /// 是否有后台任务在跑。
  bool get isBusy =>
      _phase == LibraryPhase.loading ||
      _imageProgress != null ||
      _sizeProgress != null;

  /// 图像分析是否已经跑完（决定「重复 / 相似 / 模糊」是否可信）。
  bool get imageAnalysisDone => _imageAnalysisDone;

  CleanupCategory? category(CleanupCategoryType type) => _categories[type];

  /// 所有分类里建议清理的总数量。
  int get totalCandidateCount => _summary.candidateCount;

  /// 首页展示的分类顺序：优先展示能立刻见效的。
  static const List<CleanupCategoryType> categoryOrder = <CleanupCategoryType>[
    CleanupCategoryType.duplicates,
    CleanupCategoryType.similar,
    CleanupCategoryType.screenshots,
    CleanupCategoryType.screenRecordings,
    CleanupCategoryType.blurry,
    CleanupCategoryType.largeVideos,
    CleanupCategoryType.largePhotos,
  ];

  // ------------------------------------------------------------------ 主流程

  /// 启动时调用：检查权限，有权限就直接加载。
  Future<void> initialize() async {
    if (_phase != LibraryPhase.idle) return;
    _setPhase(LibraryPhase.checkingPermission);

    try {
      final permission = await _repository.checkPermission();
      _permission = permission;
      if (!permission.hasAccess) {
        _setPhase(permission.isBlocked
            ? LibraryPhase.permissionBlocked
            : LibraryPhase.needsPermission);
        return;
      }
      await _loadLibrary();
    } catch (error) {
      _fail(error);
    }
  }

  /// 弹出系统授权对话框。
  Future<void> requestPermission() async {
    try {
      final permission = await _repository.requestPermission();
      _permission = permission;
      if (!permission.hasAccess) {
        _setPhase(permission.isBlocked
            ? LibraryPhase.permissionBlocked
            : LibraryPhase.needsPermission);
        return;
      }
      await _loadLibrary();
    } catch (error) {
      _fail(error);
    }
  }

  /// 重新读取相册（例如从系统设置里改了权限之后）。
  Future<void> refresh() async {
    await cancelBackgroundWork();
    _setPhase(LibraryPhase.checkingPermission);
    try {
      final permission = await _repository.checkPermission();
      _permission = permission;
      if (!permission.hasAccess) {
        _setPhase(permission.isBlocked
            ? LibraryPhase.permissionBlocked
            : LibraryPhase.needsPermission);
        return;
      }
      await _loadLibrary();
    } catch (error) {
      _fail(error);
    }
  }

  /// 打开系统设置页。
  Future<void> openSystemSettings() => _repository.openSettings();

  /// 弹出 iOS 的「管理已选照片」。
  Future<void> presentLimitedPicker() async {
    await _repository.presentLimitedPicker();
    await refresh();
  }

  Future<void> _loadLibrary() async {
    _setPhase(LibraryPhase.loading);
    _errorMessage = null;

    final result = await _repository.loadLibrary(
      onProgress: (loaded, total) {
        // 只在每页结束时刷新，避免过于频繁地重建界面。
        _loadProgress = TaskProgress(
          label: '正在读取相册',
          done: loaded,
          total: total,
        );
        _notify();
      },
    );

    _items = result.items;
    _totalCount = result.totalCount;
    _truncated = result.truncated;
    _signatures = const <AssetSignature>[];
    _imageAnalysisDone = false;
    _loadProgress = null;
    _imageProgress = null;
    _sizeProgress = null;

    _rebuildCategories();
    _setPhase(LibraryPhase.ready);

    if (_settings.autoAnalyze && _items.isNotEmpty) {
      // 不 await：让界面先显示出来，后台继续跑分析。
      // ignore: discarded_futures
      _runBackgroundWork();
    }
  }

  Future<void> _runBackgroundWork() async {
    await runImageAnalysis();
    if (_disposed) return;
    await scanFileSizes();
  }

  /// 计算所有图片的感知哈希与清晰度，用于找重复 / 相似 / 模糊照片。
  ///
  /// 上一次算过的直接从缓存拿，只算没算过的。这是「切走再回来不用重新扫描」
  /// 的关键：缓存是边算边落盘的，所以**杀掉进程重开**也能从断点续上，
  /// 而不必指望系统肯在后台把任务跑完。
  Future<void> runImageAnalysis({bool force = false}) async {
    if (_items.isEmpty) return;
    if (_imageAnalysisDone && !force) return;
    if (_imageProgress != null) return;

    final token = await _backgroundTasks.acquire('图像分析');

    final cancel = CancelSignal();
    _imageCancel = cancel;

    final analyzer = _settings.buildAnalyzer();
    final label = force ? '正在重新分析照片' : '正在分析照片';

    _imageProgress = TaskProgress(label: label, done: 0, total: 0);
    _notify();

    try {
      final imageItems = <MediaItem>[];
      final otherItems = <MediaItem>[];
      for (final item in _items) {
        (item.kind == MediaKind.image ? imageItems : otherItems).add(item);
      }

      // force 时不读缓存：用户点「重新分析」就是要推翻旧结论。
      final cached =
          force ? const <String, AssetFingerprintRecord>{} : await _cache.read();
      if (_disposed) return;

      final reused = <AssetSignature>[];
      final misses = <MediaItem>[];
      for (final item in imageItems) {
        final record = cached[item.id];
        if (record == null) {
          misses.add(item);
        } else {
          reused.add(record.attachTo(item));
        }
      }

      // 缓存里的结果先可见：不用等剩下那几千张算完才看到重复照片。
      // 分类会先按这批算一遍，后面的分析再逐步补上。
      if (reused.isNotEmpty) {
        _signatures = <AssetSignature>[
          ...reused,
          for (final item in otherItems) AssetSignature(item: item),
        ];
        _rebuildCategoriesWith(analyzer);
      }

      // 分母只算要分析的图片：视频不参与分组，算进去会让进度条永远差一截。
      _imageProgress = TaskProgress(
        label: label,
        done: reused.length,
        total: imageItems.length,
        reused: reused.length,
      );
      _notify();

      final analyzed = await _signatureAnalyzer.analyze(
        items: <MediaItem>[...misses, ...otherItems],
        loadThumbnail: (item) => _repository.thumbnail(
          item.id,
          size: _signatureAnalyzer.thumbnailSize,
          quality: _signatureAnalyzer.thumbnailQuality,
        ),
        onProgress: (done, total) {
          _imageProgress = TaskProgress(
            label: label,
            done: reused.length + done,
            total: reused.length + total,
            reused: reused.length,
          );
          _notify();
        },
        onBatch: _cacheBatch,
        cancel: cancel,
      );

      if (_disposed) return;

      _signatures = <AssetSignature>[...reused, ...analyzed];
      _imageAnalysisDone = !cancel.isCancelled;
      _rebuildCategoriesWith(analyzer);
    } catch (error) {
      debugPrint('图像分析失败：$error');
    } finally {
      _imageProgress = null;
      _imageCancel = null;
      _notify();
      await _backgroundTasks.release(token);
    }
  }

  /// 每算完一批就写进缓存。
  ///
  /// 不 await：分析本身已经够慢了，不该再被写盘挡住。但写盘要**按顺序**排队，
  /// 否则两个 append 同时往同一个文件尾部写，几 MB 的缓冲区会互相插进去。
  void _cacheBatch(List<AssetSignature> batch) {
    final records = <AssetFingerprintRecord>[];
    for (final signature in batch) {
      final record = AssetFingerprintRecord.fromSignature(signature);
      if (record != null) records.add(record);
    }
    if (records.isEmpty) return;

    _cacheWrites = _cacheWrites
        .then((_) => _cache.append(records))
        .catchError((Object _) {});
  }

  /// 逐个查询文件大小。视频优先，然后是像素最多的照片。
  ///
  /// 和图像分析一样先查缓存：三万个条目就是三万次平台调用，而大小几乎不变。
  /// 缓存命中的条目会**先从候选里剔掉**——否则它们会白吃掉 [maxCount] 的预算，
  /// 真正没查过的照片反而排不上队。
  Future<void> scanFileSizes({int? limit}) async {
    final maxCount = limit ?? _sizeScanLimit;
    if (_items.isEmpty) return;
    if (_sizeProgress != null) return;

    final token = await _backgroundTasks.acquire('文件大小扫描');

    final cancel = CancelSignal();
    _sizeCancel = cancel;

    try {
      final known = await _applyCachedSizes();
      if (_disposed) return;

      final targets = _sizeScanTargets(maxCount, known);
      if (targets.isEmpty) return;

      _sizeProgress = TaskProgress(
        label: '正在统计文件大小',
        done: 0,
        total: targets.length,
        reused: known.length,
      );
      _notify();

      final sizes = <String, int>{};
      final records = <FileSizeRecord>[];
      var done = 0;

      for (final item in targets) {
        if (cancel.isCancelled || _disposed) break;
        final size = await _repository.fileSize(item.id);
        if (size > 0) {
          sizes[item.id] = size;
          records.add(
            FileSizeRecord(
              id: item.id,
              size: size,
              modifiedAt: item.modifiedAt,
            ),
          );
        }

        done++;
        if (done % 20 == 0 || done == targets.length) {
          _cacheSizes(records);
          records.clear();
          _sizeProgress = TaskProgress(
            label: '正在统计文件大小',
            done: done,
            total: targets.length,
            reused: known.length,
          );
          _notify();
        }
      }

      _cacheSizes(records);
      if (_disposed) return;

      if (sizes.isNotEmpty) {
        _items = <MediaItem>[
          for (final item in _items)
            sizes.containsKey(item.id) ? item.withSize(sizes[item.id]!) : item,
        ];
        _rebuildCategories();
      }
    } catch (error) {
      debugPrint('大小扫描失败：$error');
    } finally {
      _sizeProgress = null;
      _sizeCancel = null;
      _notify();
      await _backgroundTasks.release(token);
    }
  }

  /// 把缓存里还对得上的大小贴回条目上，返回这批条目的 id。
  ///
  /// 对不上的是编辑过的照片（[FileSizeRecord.matches] 比修改时间），
  /// 交给下面的扫描重新量一次。
  Future<Set<String>> _applyCachedSizes() async {
    final cached = await _sizeCache.read();
    if (cached.isEmpty) return const <String>{};

    final applied = <String, int>{};
    for (final item in _items) {
      final record = cached[item.id];
      if (record != null && record.matches(item)) applied[item.id] = record.size;
    }
    if (applied.isEmpty) return const <String>{};

    _items = <MediaItem>[
      for (final item in _items)
        applied.containsKey(item.id) ? item.withSize(applied[item.id]!) : item,
    ];
    _rebuildCategories();
    return applied.keys.toSet();
  }

  void _cacheSizes(List<FileSizeRecord> records) {
    if (records.isEmpty) return;
    final batch = List<FileSizeRecord>.of(records);
    _cacheWrites =
        _cacheWrites.then((_) => _sizeCache.append(batch)).catchError((Object _) {});
  }

  /// 挑选需要查询大小的条目：先视频（通常最占空间），再按像素数从多到少。
  ///
  /// [known] 是已经从缓存里拿到大小的 id，不再重复查询。
  List<MediaItem> _sizeScanTargets(int maxCount, [Set<String>? known]) {
    final skip = known ?? const <String>{};
    final videos = _items
        .where((item) => item.isVideo && !skip.contains(item.id))
        .toList()
      ..sort((a, b) => b.effectiveSize.compareTo(a.effectiveSize));

    final photos = _items
        .where((item) =>
            item.kind == MediaKind.image && !skip.contains(item.id))
        .toList()
      ..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));

    return <MediaItem>[...videos, ...photos].take(maxCount).toList();
  }

  /// 取消所有后台任务（退出页面或重新加载时调用）。
  ///
  /// 先把还没落盘的那几批刷完再收工：取消的代价应该只是「少算一点」，
  /// 而不是「刚才那几分钟白算了」。
  Future<void> cancelBackgroundWork() async {
    _imageCancel?.cancel();
    _sizeCancel?.cancel();
    _imageCancel = null;
    _sizeCancel = null;
    _imageProgress = null;
    _sizeProgress = null;
    await _cacheWrites;
    _notify();
  }

  /// 清空扫描缓存（设置页用）。下次分析会从头再算一遍。
  Future<void> clearScanCaches() async {
    await _cache.clear();
    await _sizeCache.clear();
  }

  // -------------------------------------------------------------------- 删除

  /// 删除条目。返回系统实际删除的结果。
  ///
  /// 只有确认删除成功的条目才会从内存里移除，被系统拒绝的会原样保留。
  Future<MediaDeletionResult> deleteItems(Iterable<MediaItem> targets) async {
    final list = targets.toList(growable: false);
    if (list.isEmpty) {
      return const MediaDeletionResult(requested: 0);
    }

    // 收藏项绝不上报给系统删除，双保险。
    final deletable =
        list.where((item) => !item.isFavorite).map((item) => item.id).toList();
    if (deletable.isEmpty) {
      // 全都是收藏项：一个都不提交。
      return MediaDeletionResult(
        requested: list.length,
        failedIds: list.map((item) => item.id).toList(growable: false),
      );
    }

    final result = await _repository.delete(deletable);
    final deleted = deletable
        .where((id) => !result.failedIds.contains(id))
        .toSet();

    if (deleted.isNotEmpty) {
      _items = _items
          .where((item) => !deleted.contains(item.id))
          .toList(growable: false);
      _signatures = _signatures
          .where((signature) => !deleted.contains(signature.item.id))
          .toList(growable: false);
      _totalCount = (_totalCount - deleted.length).clamp(0, 1 << 30);
      _rebuildCategories();
      _notify();
    }

    return result;
  }

  // ---------------------------------------------------------------- 分类计算

  void _rebuildCategories() => _rebuildCategoriesWith(_settings.buildAnalyzer());

  void _rebuildCategoriesWith(CleanupAnalyzer analyzer) {
    _categories = analyzer.buildCategories(
      items: _items,
      signatures: _signatures,
    );
    _summary = analyzer.summarize(items: _items, categories: _categories);
    _notify();
  }

  /// 设置变化后重新计算相似度分组与阈值。
  void onSettingsChanged() {
    if (_items.isEmpty) return;
    if (_signatures.isNotEmpty) {
      _rebuildCategories();
    }
  }

  // -------------------------------------------------------------------- 工具

  void _setPhase(LibraryPhase phase) {
    _phase = phase;
    _notify();
  }

  void _fail(Object error) {
    _errorMessage = error.toString();
    _phase = LibraryPhase.failure;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // 不能 await：dispose 是同步的。但缓存写盘还得让它跑完，
    // 否则「退出到别的页面」会丢掉最后那几批结果。
    unawaited(cancelBackgroundWork());
    super.dispose();
  }
}
