import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../data/photo_repository.dart';
import '../../data/thumbnail_cache.dart';
import '../../state/library_controller.dart';
import 'delete_confirm_sheet.dart';

/// 复核页与滑动清理页共用的删除流程。
///
/// 顺序是：确认弹窗 → 交给系统删除 → 清理缩略图缓存 → 反馈结果。
/// 返回真正被系统删掉的条目数；用户取消时返回 0。
Future<int> performDeletion(
  BuildContext context,
  List<MediaItem> items,
) async {
  if (items.isEmpty) return 0;

  final confirmed = await showDeleteConfirmSheet(context, items: items);
  if (!confirmed || !context.mounted) return 0;

  final library = context.read<LibraryController>();
  final cache = context.read<ThumbnailCache>();
  final messenger = ScaffoldMessenger.of(context);

  final MediaDeletionResult result;
  try {
    result = await library.deleteItems(items);
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
    return 0;
  }

  for (final item in items) {
    cache.evict(item.id);
  }

  if (!context.mounted) return result.deletedCount;

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
  return result.deletedCount;
}
