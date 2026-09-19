import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../theme/app_theme.dart';

/// 删除前的二次确认。
///
/// 这里刻意把「会释放多少空间」和「是否可恢复」讲清楚：
/// iOS 上删除的照片会进入系统「最近删除」并保留 30 天，
/// 用户知道这一点之后才敢放心地批量清理。
Future<bool> showDeleteConfirmSheet(
  BuildContext context, {
  required List<MediaItem> items,
}) async {
  if (items.isEmpty) return false;

  final bytes = items.fold<int>(0, (sum, item) => sum + item.effectiveSize);
  final videoCount = items.where((item) => item.isVideo).length;
  final photoCount = items.length - videoCount;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.delete_outline, color: AppColors.danger),
                const SizedBox(width: 10),
                Text(
                  '确认删除',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryRow(label: '照片', value: '$photoCount 张'),
            if (videoCount > 0)
              _SummaryRow(label: '视频', value: '$videoCount 个'),
            _SummaryRow(
              label: '预计释放',
              value: formatBytes(bytes),
              emphasized: true,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '系统会再弹出一次确认框。删除的照片会进入「最近删除」，'
                      '保留 30 天，期间可以随时恢复。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text('删除 ${items.length} 项'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? false;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: emphasized ? AppColors.danger : null,
              fontWeight: emphasized ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}
