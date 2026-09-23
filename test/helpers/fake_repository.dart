import 'dart:typed_data';

import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/photo_repository.dart';

import 'media_fixtures.dart';

/// 内存里的假相册，用来在不对接 `photo_manager` 的情况下跑界面测试。
class FakePhotoRepository implements PhotoRepository {
  FakePhotoRepository({
    List<MediaItem> items = const <MediaItem>[],
    this.permission =
        const LibraryPermission(LibraryPermissionStatus.authorized),
    this.albums = const <MediaAlbum>[],
    this.thumbnailBytes,
  }) : items = List<MediaItem>.of(items);

  /// 相册内容；[delete] 会真的从这里移除条目。
  List<MediaItem> items;

  /// [checkPermission] / [requestPermission] 返回的状态。
  LibraryPermission permission;

  List<MediaAlbum> albums;

  /// 按相册 id 指定内容；没配到的相册退化为返回整个 [items]。
  Map<String, List<MediaItem>> albumItems = <String, List<MediaItem>>{};

  /// 按条目 id 指定「它属于哪些相册」；没配到的返回空结果。
  Map<String, AssetLocation> locations = <String, AssetLocation>{};

  /// [fullImage] 返回的字节。默认给一张能解码的图，方便断言「放大了才去取」。
  Uint8List? fullImageBytes = MediaFixtures.tinyPng;

  /// 每次 [fullImage] 收到的参数，按调用顺序记录。
  final List<({String id, int size})> fullImageCalls = <({String id, int size})>[];

  /// [thumbnail] 返回的字节；null 表示读取失败（界面上显示占位图）。
  Uint8List? thumbnailBytes;

  /// 每次 [thumbnail] 收到的参数，按调用顺序记录下来。
  ///
  /// 用来断言「已经算过的照片不会重复请求缩略图」这类缓存行为。
  final List<({String id, int size})> thumbnailCalls = <({String id, int size})>[];

  /// 缩略图读取的模拟耗时，用来观察后台任务进行中的界面。
  Duration thumbnailDelay = Duration.zero;

  /// 每次 [delete] 收到的 id 列表。
  final List<List<String>> deleteCalls = <List<String>>[];

  /// 这些 id 会「删除失败」，用来模拟用户拒绝系统弹窗。
  final Set<String> failToDelete = <String>{};

  int requestPermissionCalls = 0;
  int openSettingsCalls = 0;
  int loadLibraryCalls = 0;

  @override
  Future<LibraryPermission> checkPermission() async => permission;

  @override
  Future<LibraryPermission> requestPermission() async {
    requestPermissionCalls++;
    return permission;
  }

  @override
  Future<void> openSettings() async {
    openSettingsCalls++;
  }

  @override
  Future<void> presentLimitedPicker() async {}

  @override
  Future<LibraryLoadResult> loadLibrary({
    int maxItems = 30000,
    void Function(int loaded, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    loadLibraryCalls++;
    final loaded = items.take(maxItems).toList(growable: false);
    onProgress?.call(loaded.length, items.length);
    return LibraryLoadResult(
      items: loaded,
      totalCount: items.length,
      truncated: loaded.length < items.length,
    );
  }

  @override
  Future<Uint8List?> thumbnail(
    String id, {
    int size = 256,
    int quality = 80,
  }) async {
    thumbnailCalls.add((id: id, size: size));
    if (thumbnailDelay > Duration.zero) await Future<void>.delayed(thumbnailDelay);
    return thumbnailBytes;
  }

  @override
  Future<Uint8List?> fullImage(String id, {int size = 3072}) async {
    fullImageCalls.add((id: id, size: size));
    if (thumbnailDelay > Duration.zero) await Future<void>.delayed(thumbnailDelay);
    return fullImageBytes;
  }

  @override
  Future<AssetLocation> locateAsset(String id) async =>
      locations[id] ?? AssetLocation(assetId: id);

  /// [fileSize] 的返回值；没配到的返回 0（界面会当成「没量到」）。
  Map<String, int> fileSizes = <String, int>{};

  /// 每次 [fileSize] 收到的 id，按调用顺序记录。
  ///
  /// 和 [thumbnailCalls] 一样，用来断言「缓存里已经有的大小不会再去问一遍」。
  final List<String> fileSizeCalls = <String>[];

  /// 查询大小的模拟耗时。大小扫描是逐条串行的，用它把任务拖住看界面。
  Duration fileSizeDelay = Duration.zero;

  @override
  Future<int> fileSize(String id) async {
    fileSizeCalls.add(id);
    if (fileSizeDelay > Duration.zero) {
      await Future<void>.delayed(fileSizeDelay);
    }
    return fileSizes[id] ?? 0;
  }

  @override
  Future<MediaDeletionResult> delete(List<String> ids) async {
    deleteCalls.add(List<String>.of(ids));

    final failed = ids.where(failToDelete.contains).toList(growable: false);
    final deleted = ids.where((id) => !failToDelete.contains(id)).toSet();
    items = items
        .where((item) => !deleted.contains(item.id))
        .toList(growable: false);

    return MediaDeletionResult(requested: ids.length, failedIds: failed);
  }

  @override
  Future<List<MediaAlbum>> loadAlbums() async => albums;

  @override
  Future<List<MediaItem>> loadAlbumItems(
    String albumId, {
    int maxItems = 5000,
  }) async {
    final source = albumItems[albumId] ?? items;
    return source.take(maxItems).toList(growable: false);
  }
}
