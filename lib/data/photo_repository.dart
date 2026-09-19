import 'dart:typed_data';

import '../core/models/media_item.dart';
import '../core/utils/cancel_signal.dart';

export '../core/utils/cancel_signal.dart' show CancelSignal, OperationCancelled;

/// 相册权限状态。
///
/// 直接对应 iOS 的 `PHAuthorizationStatus`，并保留 Android 的语义。
enum LibraryPermissionStatus {
  /// 还没有询问过用户。
  notDetermined('尚未授权'),

  /// 被家长控制等策略限制。
  restricted('访问受限'),

  /// 用户明确拒绝。
  denied('已拒绝访问'),

  /// 完全授权。
  authorized('已授权'),

  /// iOS 14+ 的「仅允许访问选中的照片」。
  limited('仅可访问选中的照片');

  const LibraryPermissionStatus(this.label);

  final String label;
}

/// 权限状态 + 一些便捷判断。
class LibraryPermission {
  const LibraryPermission(this.status, {this.rawStatus});

  const LibraryPermission.unknown() : status = LibraryPermissionStatus.notDetermined, rawStatus = null;

  final LibraryPermissionStatus status;

  /// 平台原始状态值，仅用于排查问题。
  final String? rawStatus;

  /// 是否能够读取相册（含「仅选中」）。
  bool get hasAccess =>
      status == LibraryPermissionStatus.authorized ||
      status == LibraryPermissionStatus.limited;

  /// 是否处于 iOS 的「有限访问」模式。
  bool get isLimited => status == LibraryPermissionStatus.limited;

  /// 是否被拒绝或限制。
  bool get isBlocked =>
      status == LibraryPermissionStatus.denied ||
      status == LibraryPermissionStatus.restricted;

  @override
  String toString() => 'LibraryPermission(${status.name})';
}

/// 相册中的用户相册（不含「最近项目」这类智能相册之外的含义）。
class MediaAlbum {
  const MediaAlbum({
    required this.id,
    required this.name,
    required this.assetCount,
    this.isAll = false,
  });

  final String id;
  final String name;
  final int assetCount;

  /// 是否是「全部 / 最近项目」这个聚合相册。
  final bool isAll;
}

/// 一次相册加载的结果。
class LibraryLoadResult {
  const LibraryLoadResult({
    required this.items,
    required this.totalCount,
    this.truncated = false,
    this.cancelled = false,
  });

  const LibraryLoadResult.empty()
      : items = const <MediaItem>[],
        totalCount = 0,
        truncated = false,
        cancelled = false;

  final List<MediaItem> items;

  /// 相册里的条目总数。当 [truncated] 为 true 时大于 `items.length`。
  final int totalCount;

  /// 是否因为达到上限而只加载了一部分。
  final bool truncated;

  /// 是否被用户中途取消。
  final bool cancelled;
}

/// 一次删除操作的结果。
class MediaDeletionResult {
  const MediaDeletionResult({
    required this.requested,
    this.failedIds = const <String>[],
  });

  /// 请求删除的数量。
  final int requested;

  /// 系统未能删除的条目 id。
  final List<String> failedIds;

  int get deletedCount => requested - failedIds.length;

  bool get isFullSuccess => failedIds.isEmpty;

  bool get isFullFailure => requested > 0 && failedIds.length == requested;

  @override
  String toString() =>
      'MediaDeletionResult(deleted: $deletedCount/$requested)';
}

/// 相册数据源。
///
/// 界面与业务逻辑只依赖这个接口，因此可以注入假实现做测试，
/// 也可以在真机上换成别的后端。
abstract class PhotoRepository {
  /// 请求权限（会弹系统对话框）。
  Future<LibraryPermission> requestPermission();

  /// 只查询当前权限，不弹窗。
  Future<LibraryPermission> checkPermission();

  /// 跳转到系统设置页。
  Future<void> openSettings();

  /// 弹出 iOS 的「管理已选照片」选择器。
  Future<void> presentLimitedPicker();

  /// 读取相册元数据。
  ///
  /// [maxItems] 是安全上限，避免超大相册一次性把内存吃满；
  /// 达到上限时返回结果的 `truncated` 为 true。
  Future<LibraryLoadResult> loadLibrary({
    int maxItems = 30000,
    void Function(int loaded, int total)? onProgress,
    CancelSignal? cancel,
  });

  /// 读取缩略图字节。失败或无权限时返回 `null`。
  Future<Uint8List?> thumbnail(String id, {int size = 256, int quality = 80});

  /// 读取原始文件大小（字节）。失败时返回 0。
  Future<int> fileSize(String id);

  /// 删除指定条目。
  ///
  /// iOS 上系统会再弹一次确认框，用户拒绝时这些 id 会出现在
  /// [MediaDeletionResult.failedIds] 里。
  Future<MediaDeletionResult> delete(List<String> ids);

  /// 列出用户相册。
  Future<List<MediaAlbum>> loadAlbums();

  /// 读取某个相册里的条目。
  Future<List<MediaItem>> loadAlbumItems(String albumId, {int maxItems = 5000});
}
