import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cleanup_progress.dart';
import '../../core/models/media_item.dart';
import '../../core/utils/date_sections.dart';
import '../../core/utils/formatters.dart';
import '../../state/cleanup_progress_controller.dart';
import '../../state/library_controller.dart';
import '../swipe/swipe_clean_page.dart';
import '../theme/app_theme.dart';
import '../viewer/photo_viewer_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_thumbnail.dart';

/// 按时间线浏览并清理。
///
/// 首页那几个分类回答的是「清什么」；这里回答的是「什么时候拍的」。
/// 两者互补：想清理上个月旅行那一堆照片时，按分类翻是找不到的。
class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  static const String scope = CleanupScopes.timeline;

  /// 每天表头的高度。`SliverPersistentHeader` 要求一个确定的数字，
  /// 所以这里得写死，不能用内容自适应。
  static const double _headerExtent = 56;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final progress = context.watch<CleanupProgressController>();
    final items = library.items;
    final record = progress.progressFor(scope);

    return Scaffold(
      appBar: AppBar(
        title: const Text('时间线'),
        actions: <Widget>[
          if (items.isNotEmpty)
            IconButton(
              key: const Key('timeline-swipe'),
              tooltip: '滑动清理',
              icon: const Icon(Icons.swipe),
              onPressed: () => _openSwipe(context, items, progress),
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.photo_library_outlined,
              title: '相册里还没有照片',
              message: '拍几张照片再回来看看吧。',
            )
          : _buildTimeline(context, items, record, progress),
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    List<MediaItem> items,
    CleanupProgress? record,
    CleanupProgressController progress,
  ) {
    // 每天在整条时间线里的起始下标。查看器要能跨天连续翻阅，
    // 所以传给它的是整条列表，而不是当天的切片。
    final blocks = <({DaySection section, int start})>[];
    var start = 0;
    for (final section in groupByDay(items)) {
      blocks.add((section: section, start: start));
      start += section.items.length;
    }

    final newCount = countNewerThanRoundStart(items, record);

    return CustomScrollView(
      slivers: <Widget>[
        if (record != null)
          SliverToBoxAdapter(
            child: _ResumeBanner(
              record: record,
              onContinue: () => _openSwipe(context, items, progress),
              onRestart: () => progress.reset(scope),
            ),
          ),
        if (newCount > 0)
          SliverToBoxAdapter(
            child: _Notice(
              icon: Icons.fiber_new_outlined,
              color: AppColors.warning,
              text: '有 $newCount 张照片是这一轮开始之后才出现的，'
                  '断点在它们下面，这一轮看不到。',
              actionLabel: '从头看一遍',
              onAction: () => progress.reset(scope),
            ),
          ),
        for (final block in blocks) ...<Widget>[
          SliverPersistentHeader(
            pinned: true,
            delegate: _DayHeaderDelegate(
              extent: _headerExtent,
              child: _DayHeader(
                section: block.section,
                // 单日清理不记进度：一天的量有限，走完就走完了；
                // 记下来反而会攒出一堆再也不用的作用域。
                onSwipe: () => _openSwipe(context, block.section.items, null),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final globalIndex = block.start + index;
                  return GestureDetector(
                    onTap: () => _openViewer(context, items, globalIndex),
                    child: MediaThumbnail(
                      item: block.section.items[index],
                      size: 200,
                    ),
                  );
                },
                childCount: block.section.items.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _openSwipe(
    BuildContext context,
    List<MediaItem> items,
    CleanupProgressController? progress,
  ) {
    if (items.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeCleanPage(
          title: '时间线',
          items: items,
          // 没给进度控制器（单日清理）时从头看。
          startIndex: progress?.startIndexFor(scope, items) ?? 0,
          scope: progress == null ? null : scope,
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, List<MediaItem> items, int index) {
    if (index < 0 || index >= items.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          items: items,
          initialIndex: index,
          selection: null,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 表头与横幅

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.section, required this.onSwipe});

  final DaySection section;
  final VoidCallback onSwipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = section.day;

    return Material(
      // 得有底色：不然网格会从表头底下透出来。
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                day == null ? '未知时间' : formatDayLabel(day),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatCount(section.items.length)} 项',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '滑动清理这一天',
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: const Icon(Icons.swipe),
              onPressed: onSwipe,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate({required this.extent, required this.child});

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(height: extent, child: child);

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.extent != extent || old.child != child;
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({
    required this.record,
    required this.onContinue,
    required this.onRestart,
  });

  final CleanupProgress record;
  final VoidCallback onContinue;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anchor = record.anchorDate;

    final summary = <String>[
      if (anchor != null) '上次清理到 ${formatDayLabel(anchor)}',
      '已处理 ${formatCount(record.processed)} 张',
      if (record.deleted > 0) '已删除 ${formatCount(record.deleted)} 项',
      if (record.reclaimedBytes > 0) '释放 ${formatBytes(record.reclaimedBytes)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(summary, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              TextButton(onPressed: onRestart, child: const Text('重新开始')),
              const Spacer(),
              FilledButton(
                onPressed: onContinue,
                child: const Text('继续清理'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
