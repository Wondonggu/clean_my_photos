import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../state/selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail.dart';

/// 可勾选的照片网格。
///
/// 单元格各自监听 [SelectionController]，勾选一张只重建对应的小方块，
/// 不会把整个网格刷一遍。
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.selection,
    this.onOpen,
    this.padding = const EdgeInsets.all(2),
  });

  final List<MediaItem> items;
  final SelectionController selection;

  /// 点开大图预览。
  final void Function(int index)? onOpen;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 手机竖屏大约 3~4 列，横屏 / iPad 上自动变多。
        final columns =
            (constraints.maxWidth / 118).floor().clamp(3, 6);

        return GridView.builder(
          padding: padding,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _SelectableCell(
              item: item,
              selection: selection,
              onOpen: onOpen == null ? null : () => onOpen!(index),
            );
          },
        );
      },
    );
  }
}

class _SelectableCell extends StatelessWidget {
  const _SelectableCell({
    required this.item,
    required this.selection,
    this.onOpen,
  });

  final MediaItem item;
  final SelectionController selection;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final selected = selection.isSelected(item.id);
        final locked = item.isFavorite;

        return GestureDetector(
          onTap: locked ? null : () => selection.toggle(item.id),
          onLongPress: onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              MediaThumbnail(item: item, size: 200),
              // 未选中的加一层浅色蒙版，让选中的更醒目。
              if (!selected)
                const ColoredBox(color: AppColors.scrimLight),
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 4,
                bottom: 4,
                child: _SelectionDot(selected: selected, locked: locked),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected, required this.locked});

  final bool selected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (locked) {
      // 收藏的照片不参与清理，用一把锁代替勾选框。
      return const _Dot(
        background: AppColors.scrim,
        border: Colors.white,
        child: Icon(Icons.lock, size: 12, color: Colors.white),
      );
    }

    return _Dot(
      background: selected ? primary : AppColors.scrim,
      border: Colors.white,
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.background,
    required this.border,
    this.child,
  });

  final Color background;
  final Color border;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
      child: child,
    );
  }
}
