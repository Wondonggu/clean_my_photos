import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cleanup_category.dart';
import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../state/library_controller.dart';
import '../../state/selection_controller.dart';
import '../swipe/swipe_clean_page.dart';
import '../theme/app_theme.dart';
import '../viewer/photo_viewer_page.dart';
import '../widgets/delete_flow.dart';
import '../widgets/empty_state.dart';
import 'group_row.dart';
import 'media_grid.dart';

/// 单个分类的复核页。
///
/// 重复 / 相似照片按组展示（默认保留一张），其余分类用网格。
/// 无论哪种视图，最终都是「勾选 → 底部按钮一次删除」。
class CategoryReviewPage extends StatefulWidget {
  const CategoryReviewPage({super.key, required this.type});

  final CleanupCategoryType type;

  @override
  State<CategoryReviewPage> createState() => _CategoryReviewPageState();
}

class _CategoryReviewPageState extends State<CategoryReviewPage> {
  late final LibraryController _library;
  late final SelectionController _selection;

  CleanupCategory? _category;

  /// 分组视图仅对重复 / 相似照片有意义。
  bool get _supportsGroups =>
      widget.type == CleanupCategoryType.duplicates ||
      widget.type == CleanupCategoryType.similar;

  bool _showGroups = false;

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryController>();
    _selection = SelectionController();
    _showGroups = _supportsGroups;
    _library.addListener(_handleLibraryChanged);
    _sync();
  }

  @override
  void dispose() {
    _library.removeListener(_handleLibraryChanged);
    _selection.dispose();
    super.dispose();
  }

  /// 删除之后分类会被重算，这里把新的候选列表同步过来。
  ///
  /// 刻意不调用 `setState`：重建由 `context.watch` 和
  /// [SelectionController] 的通知负责，在监听回调里再 setState 会重复。
  void _handleLibraryChanged() => _sync();

  void _sync() {
    final category = _library.category(widget.type);
    if (identical(category, _category)) return;
    _category = category;
    _selection.sync(category?.items ?? const <MediaItem>[]);
  }

  List<MediaItem> get _candidates => _category?.items ?? const <MediaItem>[];

  Future<void> _deleteSelected() async {
    final items = _selection.selectedItems;
    if (items.isEmpty) return;
    await performDeletion(context, items);
  }

  void _openViewer(int index, {List<MediaItem>? items}) {
    final list = items ?? _candidates;
    if (index < 0 || index >= list.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          items: list,
          initialIndex: index,
          selection: _selection,
        ),
      ),
    );
  }

  void _openSwipe() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeCleanPage(
          title: widget.type.title,
          items: _candidates,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 依赖 LibraryController：删除或分析完成后自动重建。
    context.watch<LibraryController>();
    final category = _category;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type.title),
        actions: <Widget>[
          if (_supportsGroups && _candidates.isNotEmpty)
            IconButton(
              tooltip: '滑动清理',
              icon: const Icon(Icons.swipe),
              onPressed: _openSwipe,
            ),
          if (_candidates.isNotEmpty)
            _SelectAllButton(selection: _selection),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_supportsGroups && _candidates.isNotEmpty)
            _ViewModeSwitch(
              showGroups: _showGroups,
              onChanged: (value) => setState(() => _showGroups = value),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: _selection,
              builder: (context, _) => _buildBody(category),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SelectionBar(
        selection: _selection,
        onDelete: _deleteSelected,
      ),
    );
  }

  Widget _buildBody(CleanupCategory? category) {
    if (category == null || _candidates.isEmpty) {
      final analyzing = _library.imageProgress != null &&
          widget.type.requiresImageAnalysis;
      if (analyzing) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 14),
              Text(
                '正在分析照片…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      }
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: '这里很干净',
        message: '没有找到需要清理的${widget.type.title}。',
      );
    }

    if (_showGroups && category.groups.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: category.groups.length,
        itemBuilder: (context, index) {
          final group = category.groups[index];
          return GroupRow(
            group: group,
            selection: _selection,
            onOpen: (itemIndex) =>
                _openViewer(itemIndex, items: group.items),
          );
        },
      );
    }

    return MediaGrid(
      items: _candidates,
      selection: _selection,
      onOpen: (index) => _openViewer(index),
    );
  }
}

class _SelectAllButton extends StatelessWidget {
  const _SelectAllButton({required this.selection});

  final SelectionController selection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => TextButton(
        onPressed: selection.isAllSelected
            ? selection.clearSelection
            : selection.selectAll,
        child: Text(selection.isAllSelected ? '取消全选' : '全选'),
      ),
    );
  }
}

class _ViewModeSwitch extends StatelessWidget {
  const _ViewModeSwitch({required this.showGroups, required this.onChanged});

  final bool showGroups;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: true,
                  label: Text('按组'),
                  icon: Icon(Icons.view_carousel_outlined, size: 18),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('全部'),
                  icon: Icon(Icons.grid_view, size: 18),
                ),
              ],
              selected: <bool>{showGroups},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onChanged(values.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部常驻的「已选 N 项 / 删除」操作条。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.selection, required this.onDelete});

  final SelectionController selection;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        if (selection.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);

        return Material(
          color: theme.colorScheme.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '已选 ${formatCount(selection.count)} 项',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '预计释放 ${formatBytes(selection.selectedBytes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
