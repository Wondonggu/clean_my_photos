import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../data/photo_repository.dart';
import '../../data/thumbnail_cache.dart';
import '../../state/library_controller.dart';
import 'delete_confirm_sheet.dart';

/// 复核页、滑动清理页与浏览页共用的删除流程。
///
/// 顺序是：确认弹窗 → 交给系统删除 → 清理缩略图缓存 → 反馈结果。
///
/// 返回系统实际的删除结果；**用户取消、条目为空或删除过程出错时返回 `null`**。
/// 调用方要算出「真正被删掉的是哪些」时，用
/// `请求的 id 集合 − result.failedIds`，不要用 `deletedCount` 反推：
/// 用户取消时没有结果对象，而 `MediaDeletionResult.deletedCount` 只在
/// 真的提交过删除之后才有意义。
Future<MediaDeletionResult?> performDeletion(
  BuildContext context,
  List<MediaItem> items,
) async {
  if (items.isEmpty) return null;

  final confirmed = await showDeleteConfirmSheet(context, items: items);
  if (!confirmed || !context.mounted) return null;

  final library = context.read<LibraryController>();
  final cache = context.read<ThumbnailCache>();
  final messenger = ScaffoldMessenger.of(context);

  final MediaDeletionResult result;
  try {
    result = await library.deleteItems(items);
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
    return null;
  }

  for (final item in items) {
    cache.evict(item.id);
  }

  final String message;
  if (result.isFullSuccess) {
    message = '已删除 ${result.deletedCount} 项';
  } else if (result.isFullFailure) {
    message = '没有删除任何项目，可能是在系统弹窗里取消了';
  } else {
    message = '已删除 ${result.deletedCount} 项，'
        '${result.failedIds.length} 项未能删除';
  }

  messenger.showSnackBar(SnackBar(content: Text(message)));
  return result;
}

/// 从一次删除的结果里算出**真正被删掉**的 id。
///
/// 系统可能只删掉一部分，所以以它报告的失败项为准，而不是假设标记过的都删
/// 成功了；收藏的照片本来就删不掉，一并剔掉。
///
/// 刻意不在这里回调 `onDeleted`：什么时候通知调用方（先出栈还是先更新列表）
/// 由各自的时序决定，这个函数只负责算，不负责喊。
Set<String> deletedIds(
  Iterable<MediaItem> requested,
  MediaDeletionResult result,
) {
  final failed = result.failedIds.toSet();
  return <String>{
    for (final item in requested)
      if (!item.isFavorite && !failed.contains(item.id)) item.id,
  };
}
