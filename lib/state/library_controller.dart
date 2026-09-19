import 'package:flutter/foundation.dart';

import '../core/models/asset_signature.dart';
import '../core/models/cleanup_category.dart';
import '../core/models/media_item.dart';
import '../core/services/cleanup_analyzer.dart';
import '../core/services/thumbnail_analysis.dart';
import '../data/photo_repository.dart';
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
  });

  final String label;
  final int done;
  final int total;

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
  })  : _repository = repository,
        _settings = settings,
        _signatureAnalyzer = analyzer ?? const SignatureAnalyzer(),
        _sizeScanLimit = sizeScanLimit;

  /// 默认最多查询多少个文件的大小。
  ///
  /// iOS 没有批量获取文件大小的接口，只能逐个查询；对超大相册做全量查询
  /// 会非常慢，因此设一个上限，优先扫描视频和像素最多的照片。
  static const int defaultSizeScanLimit = 4000;

  final PhotoRepository _repository;
  final SettingsController _settings;
  final SignatureAnalyzer _signatureAnalyzer;
  final int _sizeScanLimit;

  LibraryPhase _phase = LibraryPhase.idle;
  LibraryPermission _permission = const LibraryPermission.unknown();
  List<MediaItem> _items = const <MediaItem>[];
  List<AssetSignature> _signatures = const <AssetSignature>[];
  Map<CleanupCategoryType, CleanupCategory> _categories =
      const <CleanupCategoryType, CleanupCategory>{};
  LibrarySummary _summary = const LibrarySummary.empty();
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
    _cancelBackgroundWork();
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
        _imageProgress = TaskProgress(
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
  Future<void> runImageAnalysis({bool force = false}) async {
    if (_items.isEmpty) return;
    if (_imageAnalysisDone && !force) return;
    if (_imageProgress != null) return;

    final cancel = CancelSignal();
    _imageCancel = cancel;

    final analyzer = _settings.buildAnalyzer();

    _imageProgress = const TaskProgress(label: '正在分析照片', done: 0, total: 0);
    _notify();

    try {
      final signatures = await _signatureAnalyzer.analyze(
        items: _items,
        loadThumbnail: (item) => _repository.thumbnail(
          item.id,
          size: _signatureAnalyzer.thumbnailSize,
          quality: _signatureAnalyzer.thumbnailQuality,
        ),
        onProgress: (done, total) {
          _imageProgress = TaskProgress(label: '正在分析照片', done: done, total: total);
          _notify();
        },
        cancel: cancel,
      );

      if (_disposed) return;

      _signatures = signatures;
      _imageAnalysisDone = !cancel.isCancelled;
      _rebuildCategoriesWith(analyzer);
    } catch (error) {
      debugPrint('图像分析失败：$error');
    } finally {
      _imageProgress = null;
      _imageCancel = null;
      _notify();
    }
  }

  /// 逐个查询文件大小。视频优先，然后是像素最多的照片。
  Future<void> scanFileSizes({int? limit}) async {
    final maxCount = limit ?? _sizeScanLimit;
    if (_items.isEmpty) return;
    if (_sizeProgress != null) return;

    final targets = _sizeScanTargets(maxCount);
    if (targets.isEmpty) return;

    final cancel = CancelSignal();
    _sizeCancel = cancel;

    _sizeProgress = TaskProgress(
      label: '正在统计文件大小',
      done: 0,
      total: targets.length,
    );
    _notify();

    final sizes = <String, int>{};
    var done = 0;

    try {
      for (final item in targets) {
        if (cancel.isCancelled || _disposed) break;
        final size = await _repository.fileSize(item.id);
        if (size > 0) sizes[item.id] = size;

        done++;
        if (done % 20 == 0 || done == targets.length) {
          _sizeProgress = TaskProgress(
            label: '正在统计文件大小',
            done: done,
            total: targets.length,
          );
          _notify();
        }
      }

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
    }
  }

  /// 挑选需要查询大小的条目：先视频（通常最占空间），再按像素数从多到少。
  List<MediaItem> _sizeScanTargets(int maxCount) {
    final videos = _items.where((item) => item.isVideo).toList()
      ..sort((a, b) => b.effectiveSize.compareTo(a.effectiveSize));

    final photos = _items
        .where((item) => item.kind == MediaKind.image)
        .toList()
      ..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));

    return <MediaItem>[...videos, ...photos].take(maxCount).toList();
  }

  /// 取消所有后台任务（退出页面或重新加载时调用）。
  void _cancelBackgroundWork() {
    _imageCancel?.cancel();
    _sizeCancel?.cancel();
    _imageCancel = null;
    _sizeCancel = null;
    _imageProgress = null;
    _sizeProgress = null;
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
    _cancelBackgroundWork();
    super.dispose();
  }
}
