import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../state/library_controller.dart';

/// 悬浮在所有页面之上的任务条。
///
/// 扫描是能跑几分钟的事，而用户完全可以一边扫一边翻相册、进查看器。
/// 进度只挂在首页的话，一进子页面就不知道后台还在不在跑了。
///
/// 挂在 `MaterialApp.builder` 上意味着它**浮在 `Navigator` 之上**——
/// 代价是会短暂压住 SnackBar，换来的是任何页面都看得见。空闲时是零尺寸，
/// 不占地方也拦不到点击。
class GlobalTaskBar extends StatelessWidget {
  const GlobalTaskBar({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final progress = library.imageProgress ?? library.sizeProgress;

    if (progress == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          key: const Key('global-task-bar'),
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          color: theme.colorScheme.inverseSurface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        progress.isIndeterminate
                            ? '${progress.label}…'
                            : '${progress.label} '
                                '${formatCount(progress.done)}/'
                                '${formatCount(progress.total)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                    // 读缓存的那几秒也是「总数还不知道」的状态，但照样该能取消。
                    TextButton(
                      key: const Key('global-task-cancel'),
                      onPressed: library.cancelBackgroundWork,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.inversePrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('取消'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.isIndeterminate ? null : progress.ratio,
                    minHeight: 4,
                    backgroundColor:
                        theme.colorScheme.onInverseSurface.withAlpha(40),
                  ),
                ),
                if (progress.reused > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    key: const Key('global-task-reused'),
                    '已复用 ${formatCount(progress.reused)} 条缓存，不用重算',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface.withAlpha(170),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
