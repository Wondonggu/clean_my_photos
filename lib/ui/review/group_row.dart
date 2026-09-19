import 'package:flutter/material.dart';

import '../../core/models/media_group.dart';
import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../state/selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail.dart';

/// 重复 / 相似照片的一组。
///
/// 建议保留的那张固定排在第一位并标上「保留」，其余默认勾选。
/// 整组都是收藏时不显示勾选框——收藏照片不参与清理。
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.group,
    required this.selection,
    this.onOpen,
  });

  final MediaGroup group;
  final SelectionController selection;

  /// 点开大图预览，参数是组内的下标。
  final void Function(int index)? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final selectedCount = selection.selectedInGroup(group);
        final deletableCount = group.deletable.length;
        final allSelected =
            deletableCount > 0 && selectedCount == deletableCount;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _header(context, selectedCount, deletableCount, allSelected),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: group.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = group.items[index];
                    return _GroupTile(
                      item: item,
                      isKeeper: item.id == group.keeperId,
                      selected: selection.isSelected(item.id),
                      onTap: () => selection.toggle(item.id),
                      onLongPress:
                          onOpen == null ? null : () => onOpen!(index),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    int selectedCount,
    int deletableCount,
    bool allSelected,
  ) {
    final theme = Theme.of(context);
    final kindLabel = group.kind == GroupKind.duplicate ? '完全相同' : '高度相似';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${group.items.length} 张$kindLabel',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  group.allFavorites
                      ? '整组都是收藏，已跳过'
                      : '保留 1 张，可清理 $deletableCount 张 · '
                          '${formatBytes(group.reclaimableBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          if (!group.allFavorites)
            TextButton(
              onPressed: () =>
                  selection.toggleGroup(group, selected: !allSelected),
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.item,
    required this.isKeeper,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final MediaItem item;
  final bool isKeeper;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: isKeeper || item.isFavorite ? null : onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: MediaThumbnail(item: item, size: 200),
                  ),
                  if (!isKeeper && !selected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.scrimLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isKeeper
                              ? AppColors.success
                              : selected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: isKeeper
                        ? const _Tag(
                            label: '保留',
                            color: AppColors.success,
                          )
                        : _Tag(
                            label: selected ? '删除' : '保留',
                            color: selected
                                ? AppColors.danger
                                : AppColors.scrim,
                          ),
                  ),
                  if (item.isFavorite)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        Icons.favorite,
                        size: 13,
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _caption(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(150),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _caption() {
    final date = item.createdAt;
    final size = item.effectiveSize;
    if (date == null) return formatBytes(size);
    return '${formatRelativeDate(date)} · ${formatBytes(size)}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
