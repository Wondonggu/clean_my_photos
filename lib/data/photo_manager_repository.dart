import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../core/models/media_item.dart';
import 'asset_locator_channel.dart';
import 'photo_repository.dart';

/// 基于 `photo_manager` 的真实相册数据源。
///
/// 这里集中处理所有平台差异：
/// * iOS 用「智能相册」识别截图 / 录屏 / 实况照片；
/// * Android 没有对应的标记，退化为按路径与文件名判断；
/// * 相册的「文件大小」在 iOS 上没有批量接口，只能逐个查询。
class PhotoManagerRepository implements PhotoRepository {
  PhotoManagerRepository({AssetLocatorChannel? locator})
      : _locator = locator ?? AssetLocatorChannel(isSupportedPlatform: _isDarwinPlatform);

  static final bool _isDarwinPlatform = Platform.isIOS || Platform.isMacOS;

  /// 「这张照片属于哪些相册」只能问原生，见 [AssetLocatorChannel]。
  final AssetLocatorChannel _locator;

  /// id → AssetEntity，用于后续按 id 取缩略图 / 大小 / 删除。
  final Map<String, AssetEntity> _entities = <String, AssetEntity>{};

  /// id → AssetPathEntity，用于按相册浏览。
  final Map<String, AssetPathEntity> _paths = <String, AssetPathEntity>{};

  static const int _pageSize = 200;

  /// 智能相册最多取多少条 id，避免超大截图库拖慢启动。
  static const int _smartAlbumIdLimit = 20000;

  bool get _isDarwin => Platform.isIOS || Platform.isMacOS;

  @override
  Future<LibraryPermission> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.readWrite,
      ),
    );
    return _mapPermission(state);
  }

  @override
  Future<LibraryPermission> checkPermission() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.readWrite,
      ),
    );
    return _mapPermission(state);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> presentLimitedPicker() =>
      PhotoManager.presentLimited(type: RequestType.common);

  @override
  Future<LibraryLoadResult> loadLibrary({
    int maxItems = 30000,
    void Function(int loaded, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    final filter = _defaultFilter();

    // iOS 的截图 / 录屏标记来自智能相册，必须在转换条目之前取好。
    await prepareSmartAlbums();

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
      filterOption: filter,
    );
    if (paths.isEmpty) return const LibraryLoadResult.empty();

    final allPath = paths.first;
    _paths[allPath.id] = allPath;

    final total = await allPath.assetCountAsync;
    if (total == 0) return const LibraryLoadResult.empty();

    final limit = math.min(total, maxItems);
    final entities = <AssetEntity>[];

    for (var start = 0; start < limit; start += _pageSize) {
      if (cancel?.isCancelled ?? false) {
        return LibraryLoadResult(
          items: _toMediaItems(entities),
          totalCount: total,
          truncated: true,
          cancelled: true,
        );
      }

      final end = math.min(start + _pageSize, limit);
      final page = await allPath.getAssetListRange(
        start: start,
        end: end,
        type: RequestType.common,
      );
      if (page.isEmpty) break;

      entities.addAll(page);
      onProgress?.call(entities.length, total);
    }

    return LibraryLoadResult(
      items: _toMediaItems(entities),
      totalCount: total,
      truncated: total > entities.length,
    );
  }

  @override
  Future<List<MediaAlbum>> loadAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      hasAll: true,
      type: RequestType.common,
      filterOption: _defaultFilter(),
    );

    final albums = <MediaAlbum>[];
    for (final path in paths) {
      _paths[path.id] = path;
      albums.add(
        MediaAlbum(
          id: path.id,
          name: path.name,
          assetCount: await path.assetCountAsync,
          isAll: path.isAll,
        ),
      );
    }

    // 「全部」排最前，其余按名称排序。
    albums.sort((a, b) {
      if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return albums;
  }

  @override
  Future<List<MediaItem>> loadAlbumItems(
    String albumId, {
    int maxItems = 5000,
  }) async {
    final path = _paths[albumId];
    if (path == null) return const <MediaItem>[];

    await prepareSmartAlbums();

    final total = await path.assetCountAsync;
    final limit = math.min(total, maxItems);
    final entities = <AssetEntity>[];

    for (var start = 0; start < limit; start += _pageSize) {
      final end = math.min(start + _pageSize, limit);
      final page = await path.getAssetListRange(
        start: start,
        end: end,
        type: RequestType.common,
      );
      if (page.isEmpty) break;
      entities.addAll(page);
    }

    return _toMediaItems(entities);
  }

  @override
  Future<Uint8List?> thumbnail(
    String id, {
    int size = 256,
    int quality = 80,
  }) async {
    final entity = _entities[id];
    if (entity == null) return null;

    try {
      return await entity.thumbnailDataWithSize(
        ThumbnailSize.square(size),
        quality: quality,
        format: ThumbnailFormat.jpeg,
      );
    } catch (_) {
      // iCloud 未下载、原文件损坏等情况都会走到这里：跳过这一张即可。
      return null;
    }
  }

  @override
  Future<Uint8List?> fullImage(String id, {int size = 3072}) async {
    final entity = _entities[id];
    if (entity == null) return null;

    // 原图本来就没那么大时不必再放大一次：插值出来的「高清」只是更占内存。
    final shortest = math.min(entity.width, entity.height);
    if (shortest > 0 && shortest <= _fullImageSkipBelow) return null;

    try {
      return await entity.thumbnailDataWithSize(
        ThumbnailSize(size, size),
        quality: 92,
        format: ThumbnailFormat.jpeg,
      );
    } catch (_) {
      return null;
    }
  }

  /// 短边不超过这个值时，放大没有意义。
  static const int _fullImageSkipBelow = 1024;

  @override
  Future<AssetLocation> locateAsset(String id) => _locator.locate(id);

  @override
  Future<int> fileSize(String id) async {
    final entity = _entities[id];
    if (entity == null) return 0;
    try {
      return await entity.fileSize;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<MediaDeletionResult> delete(List<String> ids) async {
    if (ids.isEmpty) {
      return const MediaDeletionResult(requested: 0);
    }

    final failed = await PhotoManager.editor.deleteWithIds(ids);
    for (final id in ids) {
      if (!failed.contains(id)) _entities.remove(id);
    }
    return MediaDeletionResult(requested: ids.length, failedIds: failed);
  }

  FilterOptionGroup _defaultFilter() {
    // needTitle 让系统在批量查询时顺带返回文件名，Android 上用于识别截图和录屏。
    return FilterOptionGroup(
      imageOption: const FilterOption(needTitle: true),
      videoOption: const FilterOption(needTitle: true),
      orders: const <OrderOption>[
        OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
  }

  List<MediaItem> _toMediaItems(List<AssetEntity> entities) {
    // 智能相册是异步拉取的，调用方必须先 await prepareSmartAlbums()。
    final screenshotIds =
        _smartAlbumCache[PMDarwinAssetCollectionSubtype.smartAlbumScreenshots] ??
            const <String>{};
    final recordingIds = _smartAlbumCache[
            PMDarwinAssetCollectionSubtype.smartAlbumScreenRecordings] ??
        const <String>{};
    final livePhotoIds =
        _smartAlbumCache[PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos] ??
            const <String>{};

    final items = <MediaItem>[];
    for (final entity in entities) {
      _entities[entity.id] = entity;
      items.add(
        _toMediaItem(
          entity,
          screenshotIds: screenshotIds,
          recordingIds: recordingIds,
          livePhotoIds: livePhotoIds,
        ),
      );
    }
    return items;
  }

  MediaItem _toMediaItem(
    AssetEntity entity, {
    required Set<String> screenshotIds,
    required Set<String> recordingIds,
    required Set<String> livePhotoIds,
  }) {
    final kind = switch (entity.type) {
      AssetType.image => MediaKind.image,
      AssetType.video => MediaKind.video,
      AssetType.audio => MediaKind.audio,
      AssetType.other => MediaKind.other,
    };

    final createdSecond = entity.createDateSecond;
    final modifiedSecond = entity.modifiedDateSecond;

    return MediaItem(
      id: entity.id,
      kind: kind,
      title: entity.title,
      createdAt: createdSecond == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdSecond * 1000),
      modifiedAt: modifiedSecond == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedSecond * 1000),
      width: entity.width,
      height: entity.height,
      // 文件大小需要单独异步查询，先给 0，由「空间扫描」补齐。
      size: 0,
      duration: Duration(seconds: entity.duration),
      isFavorite: entity.isFavorite,
      isLivePhoto: entity.isLivePhoto || livePhotoIds.contains(entity.id),
      isScreenshot: screenshotIds.contains(entity.id) ||
          (!_isDarwin && _looksLikeScreenshot(entity)),
      isScreenRecording: recordingIds.contains(entity.id) ||
          _looksLikeScreenRecording(entity),
      mimeType: entity.mimeType,
      relativePath: entity.relativePath,
    );
  }

  /// Android 上没有截图标记，只能按文件名 / 路径猜。
  bool _looksLikeScreenshot(AssetEntity entity) {
    final haystack =
        '${entity.relativePath ?? ''}/${entity.title ?? ''}'.toLowerCase();
    return haystack.contains('screenshot') || haystack.contains('截屏');
  }

  /// iOS 的录屏文件固定叫 `RPReplay_Final*.mp4`，Android 上则常见于
  /// `Screen recordings` 目录。
  bool _looksLikeScreenRecording(AssetEntity entity) {
    if (entity.type != AssetType.video) return false;
    final title = (entity.title ?? '').toLowerCase();
    final path = (entity.relativePath ?? '').toLowerCase();
    return title.startsWith('rpreplay') ||
        title.contains('screen record') ||
        path.contains('screen record') ||
        path.contains('录屏');
  }

  /// 智能相册的 id 缓存。首次访问时异步拉取。
  final Map<PMDarwinAssetCollectionSubtype, Set<String>> _smartAlbumCache =
      <PMDarwinAssetCollectionSubtype, Set<String>>{};

  /// 预先拉取 iOS 智能相册的 id 集合。
  ///
  /// 必须在 [_toMediaItems] 之前调用，否则截图 / 录屏 / 实况照片标记会丢失。
  /// 非 Darwin 平台直接返回（Android 走文件名启发式）。
  Future<void> prepareSmartAlbums() async {
    if (!_isDarwin) return;
    await Future.wait<void>(<Future<void>>[
      _loadSmartAlbumIds(PMDarwinAssetCollectionSubtype.smartAlbumScreenshots),
      _loadSmartAlbumIds(
        PMDarwinAssetCollectionSubtype.smartAlbumScreenRecordings,
      ),
      _loadSmartAlbumIds(PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos),
    ]);
  }

  Future<void> _loadSmartAlbumIds(
    PMDarwinAssetCollectionSubtype subtype,
  ) async {
    if (!_isDarwin || _smartAlbumCache.containsKey(subtype)) return;

    try {
      final paths = await PhotoManager.getAssetPathList(
        hasAll: false,
        type: RequestType.common,
        pathFilterOption: PMPathFilter(
          darwin: PMDarwinPathFilter(
            type: const <PMDarwinAssetCollectionType>[
              PMDarwinAssetCollectionType.smartAlbum,
            ],
            subType: <PMDarwinAssetCollectionSubtype>[subtype],
          ),
        ),
      );
      if (paths.isEmpty) {
        _smartAlbumCache[subtype] = const <String>{};
        return;
      }

      final path = paths.first;
      final total = await path.assetCountAsync;
      final limit = math.min(total, _smartAlbumIdLimit);
      final ids = <String>{};

      for (var start = 0; start < limit; start += 500) {
        final end = math.min(start + 500, limit);
        final page = await path.getAssetListRange(
          start: start,
          end: end,
          type: RequestType.common,
        );
        if (page.isEmpty) break;
        for (final entity in page) {
          ids.add(entity.id);
        }
      }

      _smartAlbumCache[subtype] = ids;
    } catch (_) {
      // 智能相册在某些系统版本上可能不存在，静默降级。
      _smartAlbumCache[subtype] = const <String>{};
    }
  }

  LibraryPermission _mapPermission(PermissionState state) {
    final status = switch (state) {
      PermissionState.notDetermined => LibraryPermissionStatus.notDetermined,
      PermissionState.restricted => LibraryPermissionStatus.restricted,
      PermissionState.denied => LibraryPermissionStatus.denied,
      PermissionState.authorized => LibraryPermissionStatus.authorized,
      PermissionState.limited => LibraryPermissionStatus.limited,
    };
    return LibraryPermission(status, rawStatus: state.name);
  }
}
