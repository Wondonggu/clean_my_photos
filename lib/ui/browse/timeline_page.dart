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
              onPressed: () => _openSwipe(
                context,
                items,
                title: '时间线',
                scope: scope,
                progress: progress,
              ),
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
    // 每个月在整条时间线里的起始下标。查看器要能跨月连续翻阅，
    // 所以传给它的是整条列表，而不是这个月的切片。
    final blocks = <({MonthSection section, int start})>[];
    var start = 0;
    for (final section in groupByMonth(items)) {
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
              onContinue: () => _openSwipe(
                context,
                items,
                title: '时间线',
                scope: scope,
                progress: progress,
              ),
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
          // 表头**不吸顶**：`pinned: true` 会让每个月的表头依次叠在视口
          // 顶部，滚过几个月就堆成一片，把后续内容盖住。
          SliverToBoxAdapter(
            child: _MonthHeader(
              section: block.section,
              record: _recordFor(block.section, progress),
              onSwipe: () => _openSwipe(
                context,
                block.section.items,
                title: block.section.month == null
                    ? '未知时间'
                    : formatMonthLabel(block.section.month!),
                scope: _scopeFor(block.section),
                progress: progress,
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

  /// 这些条目记在哪个作用域下。时间未知的那一组不记。
  static String? _scopeFor(MonthSection section) =>
      section.month == null ? null : CleanupScopes.month(section.month!);

  static CleanupProgress? _recordFor(
    MonthSection section,
    CleanupProgressController progress,
  ) {
    final scope = _scopeFor(section);
    return scope == null ? null : progress.progressFor(scope);
  }

  void _openSwipe(
    BuildContext context,
    List<MediaItem> items, {
    required String title,
    String? scope,
    required CleanupProgressController progress,
  }) {
    if (items.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeCleanPage(
          title: title,
          items: items,
          // 没有作用域（时间未知的那一组）时从头看，也不记进度。
          startIndex:
              scope == null ? 0 : progress.startIndexFor(scope, items),
          scope: scope,
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

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.section,
    required this.record,
    required this.onSwipe,
  });

  final MonthSection section;

  /// 这个月上次清到哪儿了；没清理过为 null。
  final CleanupProgress? record;

  final VoidCallback onSwipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = section.month;
    final done = record != null && !record!.isEmpty;

    return Material(
      // 得有底色：不然网格会从表头底下透出来。
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                month == null ? '未知时间' : formatMonthLabel(month),
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
            if (done) ...<Widget>[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // 一个月可能上千张，看得见「清到一半」比什么都重要。
                  '已处理 ${formatCount(record!.processed)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: '滑动清理这个月',
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
