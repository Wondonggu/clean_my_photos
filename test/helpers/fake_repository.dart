import 'dart:typed_data';

import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/photo_repository.dart';

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

  /// [thumbnail] 返回的字节；null 表示读取失败（界面上显示占位图）。
  Uint8List? thumbnailBytes;

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
  }) async =>
      thumbnailBytes;

  /// 界面上的「文件大小扫描」靠这个补全体积；假实现里直接用条目自带的 size。
  @override
  Future<int> fileSize(String id) async => 0;

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
  }) async =>
      items.take(maxItems).toList(growable: false);
}
