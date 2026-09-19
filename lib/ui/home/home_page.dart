import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cleanup_category.dart';
import '../../core/utils/formatters.dart';
import '../../state/library_controller.dart';
import '../albums/albums_page.dart';
import '../permission/permission_view.dart';
import '../review/category_review_page.dart';
import '../settings/settings_page.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import '../widgets/empty_state.dart';

/// 首页：相册概况 + 各清理分类的入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('相册清理'),
        actions: <Widget>[
          if (library.phase == LibraryPhase.ready &&
              library.items.isNotEmpty) ...<Widget>[
            IconButton(
              tooltip: '相册',
              icon: const Icon(Icons.photo_album_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AlbumsPage(),
                ),
              ),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsPage(),
                ),
              ),
            ),
          ],
        ],
      ),
      body: _buildBody(context, library),
    );
  }

  Widget _buildBody(BuildContext context, LibraryController library) {
    switch (library.phase) {
      case LibraryPhase.idle:
      case LibraryPhase.checkingPermission:
        return const _StartupPlaceholder();

      case LibraryPhase.needsPermission:
        return PermissionView(
          permission: library.permission,
          isBlocked: false,
          onRequest: library.requestPermission,
          onOpenSettings: library.openSystemSettings,
        );

      case LibraryPhase.permissionBlocked:
        return PermissionView(
          permission: library.permission,
          isBlocked: true,
          onRequest: library.requestPermission,
          onOpenSettings: library.openSystemSettings,
        );

      case LibraryPhase.failure:
        return EmptyState(
          icon: Icons.error_outline,
          title: '读取相册失败',
          message: library.errorMessage ?? '请稍后重试',
          action: FilledButton(
            onPressed: library.refresh,
            child: const Text('重试'),
          ),
        );

      case LibraryPhase.loading:
        if (library.items.isEmpty) {
          return _LoadingView(progress: library.imageProgress);
        }
        return _ReadyView(library: library);

      case LibraryPhase.ready:
        return _ReadyView(library: library);
    }
  }
}

// ------------------------------------------------------------------ 首次加载

class _StartupPlaceholder extends StatelessWidget {
  const _StartupPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.progress});

  final TaskProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = progress?.ratio ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress == null || progress!.isIndeterminate
                      ? null
                      : ratio,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              progress == null
                  ? '正在读取相册…'
                  : '${progress!.label} '
                      '${formatCount(progress!.done)}/${formatCount(progress!.total)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '照片很多时需要一点时间',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 主体内容

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    if (library.items.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: '相册里还没有照片',
        message: library.permission.isLimited
            ? '当前只允许访问选中的照片。点下面的按钮可以更改选择范围。'
            : '拍几张照片再回来看看吧。',
        action: library.permission.isLimited
            ? FilledButton(
                onPressed: library.presentLimitedPicker,
                child: const Text('管理已选照片'),
              )
            : FilledButton(
                onPressed: library.refresh,
                child: const Text('重新读取'),
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: library.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (library.permission.isLimited)
            _LimitedBanner(onManage: library.presentLimitedPicker),
          _SummaryCard(library: library),
          if (library.truncated) ...<Widget>[
            const SizedBox(height: 12),
            _NoticeBanner(
              icon: Icons.info_outline,
              color: AppColors.warning,
              text: '相册条目很多，本次只读取了 '
                  '${formatCount(library.items.length)} 项'
                  '（共 ${formatCount(library.totalCount)} 项）。',
            ),
          ],
          if (library.isBusy) ...<Widget>[
            const SizedBox(height: 12),
            _TaskBanner(library: library),
          ],
          if (!library.imageAnalysisDone && !library.isBusy) ...<Widget>[
            const SizedBox(height: 12),
            _AnalyzePrompt(onStart: library.runImageAnalysis),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '清理建议',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final type in LibraryController.categoryOrder)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CategoryTile(
                type: type,
                category: library.category(type),
                analysisDone: library.imageAnalysisDone,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = library.summary;
    final hasSuggestion = summary.candidateCount > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            theme.colorScheme.primary.withAlpha(200),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasSuggestion ? '可以释放' : '暂无可清理内容',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withAlpha(220),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                formatBytes(summary.reclaimableBytes),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasSuggestion && summary.reclaimableIsEstimate) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '（估算）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasSuggestion
                ? '共 ${formatCount(summary.candidateCount)} 项建议清理'
                : '试试下面的分类，或稍后重新扫描',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withAlpha(230),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: <Widget>[
              _SummaryStat(
                label: '照片',
                value: formatCount(summary.photoCount),
              ),
              _SummaryStat(
                label: '视频',
                value: formatCount(summary.videoCount),
              ),
              _SummaryStat(
                label: '已占用',
                value: formatBytes(summary.totalBytes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withAlpha(200),
          ),
        ),
      ],
    );
  }
}

class _TaskBanner extends StatelessWidget {
  const _TaskBanner({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = library.imageProgress ?? library.sizeProgress;
    if (progress == null) return const SizedBox.shrink();

    return _NoticeBanner(
      icon: Icons.autorenew,
      color: theme.colorScheme.primary,
      text: progress.isIndeterminate
          ? '${progress.label}…'
          : '${progress.label} '
              '${formatCount(progress.done)}/${formatCount(progress.total)}',
      trailing: SizedBox(
        width: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.isIndeterminate ? null : progress.ratio,
            minHeight: 4,
          ),
        ),
      ),
    );
  }
}

class _AnalyzePrompt extends StatelessWidget {
  const _AnalyzePrompt({required this.onStart});

  final Future<void> Function({bool force}) onStart;

  @override
  Widget build(BuildContext context) {
    return _NoticeBanner(
      icon: Icons.search,
      color: AppColors.purple,
      text: '还没分析照片内容，重复和模糊照片可能没被找出来。',
      trailing: TextButton(
        onPressed: () => onStart(),
        child: const Text('开始分析'),
      ),
    );
  }
}

class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onManage});

  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _NoticeBanner(
        icon: Icons.photo_size_select_actual_outlined,
        color: AppColors.warning,
        text: '当前只允许访问部分照片，结果可能不完整。',
        trailing: TextButton(
          onPressed: () => onManage(),
          child: const Text('更改'),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.color,
    required this.text,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- 分类卡

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.type,
    required this.category,
    required this.analysisDone,
  });

  final CleanupCategoryType type;
  final CleanupCategory? category;

  /// 图像分析是否已完成；未完成时重复 / 相似 / 模糊的结论不可信。
  final bool analysisDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = category;
    final count = data?.candidateCount ?? 0;
    final waitingForAnalysis =
        type.requiresImageAnalysis && !analysisDone && count == 0;
    final enabled = count > 0;

    final subtitle = waitingForAnalysis
        ? '等待分析…'
        : enabled
            ? '${formatCount(count)} 项 · 可释放 ${formatBytes(data!.reclaimableBytes)}'
            : '没有找到可以清理的内容';

    return Material(
      color: theme.colorScheme.onSurface.withAlpha(8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryReviewPage(type: type),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: type.iconBackground,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(type.icon, color: type.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          type.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (enabled) ...<Widget>[
                          const SizedBox(width: 8),
                          _CountChip(
                            label: formatCount(count),
                            color: type.color,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withAlpha(enabled ? 120 : 50),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
