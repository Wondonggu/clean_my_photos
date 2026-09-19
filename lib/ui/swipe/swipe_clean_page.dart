import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../state/library_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/delete_flow.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_thumbnail.dart';

/// 滑动清理。
///
/// 一张一张地看：左滑标记删除，右滑留下。比在网格里逐个点选快得多，
/// 而且每一张都能看清，不容易误删。滑到底之后再一次性确认。
class SwipeCleanPage extends StatefulWidget {
  const SwipeCleanPage({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<MediaItem> items;

  @override
  State<SwipeCleanPage> createState() => _SwipeCleanPageState();
}

/// 一次滑动决定，用于撤销。
class _Decision {
  const _Decision(this.item, {required this.deleteIt});

  final MediaItem item;
  final bool deleteIt;
}

class _SwipeCleanPageState extends State<SwipeCleanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fly;

  int _index = 0;
  Offset _drag = Offset.zero;
  bool _animating = false;
  bool _showChrome = true;

  final List<_Decision> _decisions = <_Decision>[];

  List<MediaItem> get _marked => <MediaItem>[
        for (final decision in _decisions)
          if (decision.deleteIt) decision.item,
      ];

  bool get _finished => _index >= widget.items.length;

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 滑动逻辑

  void _onPanUpdate(DragUpdateDetails details) {
    if (_animating) return;
    setState(() => _drag += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_animating) return;
    final width = MediaQuery.of(context).size.width;
    final velocity = details.velocity.pixelsPerSecond.dx;

    if (_drag.dx.abs() > width * 0.26 || velocity.abs() > 800) {
      _commit(deleteIt: _drag.dx < 0);
    } else {
      setState(() => _drag = Offset.zero);
    }
  }

  Future<void> _commit({required bool deleteIt}) async {
    if (_animating || _finished) return;
    setState(() => _animating = true);

    final width = MediaQuery.of(context).size.width;
    final animation = Tween<Offset>(
      begin: _drag,
      end: Offset(
        deleteIt ? -width * 1.4 : width * 1.4,
        _drag.dy + 60,
      ),
    ).animate(CurvedAnimation(parent: _fly, curve: Curves.easeOut));

    void listener() {
      if (mounted) setState(() => _drag = animation.value);
    }

    animation.addListener(listener);
    await _fly.forward(from: 0);
    animation.removeListener(listener);
    _fly.reset();

    if (!mounted) return;
    setState(() {
      _decisions.add(_Decision(widget.items[_index], deleteIt: deleteIt));
      _index++;
      _drag = Offset.zero;
      _animating = false;
    });
  }

  void _undo() {
    if (_decisions.isEmpty || _animating) return;
    setState(() {
      _decisions.removeLast();
      _index--;
      _drag = Offset.zero;
    });
  }

  Future<void> _delete() async {
    final items = _marked;
    if (items.isEmpty) return;

    final library = context.read<LibraryController>();
    final deleted = await performDeletion(context, items);
    if (!mounted || deleted == 0) return;

    // 系统可能只删掉了一部分，因此以相册里「还剩下谁」为准，
    // 而不是假设标记过的都删成功了。
    final alive = <String>{for (final item in library.items) item.id};
    setState(() {
      _remaining =
          _remaining.where((item) => alive.contains(item.id)).toList();
      _decisions.clear();
      _index = 0;
      _drag = Offset.zero;
    });
  }

  /// 牌堆里还没处理完的条目。
  late List<MediaItem> _remaining = List<MediaItem>.of(widget.items);

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (!_finished && remaining.isNotEmpty)
            IconButton(
              tooltip: _showChrome ? '隐藏信息' : '显示信息',
              icon: Icon(
                _showChrome ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showChrome = !_showChrome),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: remaining.isEmpty ? 1 : _index / remaining.length,
            minHeight: 3,
          ),
        ),
      ),
      body: remaining.isEmpty || _finished
          ? _DoneView(
              marked: _marked,
              onUndo: _undo,
              onDelete: _delete,
              onRestart: () => setState(() {
                _decisions.clear();
                _index = 0;
              }),
              total: remaining.length,
            )
          : _Deck(
              items: remaining,
              index: _index,
              drag: _drag,
              showChrome: _showChrome,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onToggleChrome: () => setState(() => _showChrome = !_showChrome),
            ),
      bottomNavigationBar: remaining.isEmpty || _finished
          ? null
          : _ActionBar(
              canUndo: _decisions.isNotEmpty,
              onKeep: () => _commit(deleteIt: false),
              onDelete: () => _commit(deleteIt: true),
              onUndo: _undo,
            ),
    );
  }
}

// -------------------------------------------------------------------- 牌堆

class _Deck extends StatelessWidget {
  const _Deck({
    required this.items,
    required this.index,
    required this.drag,
    required this.showChrome,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onToggleChrome,
  });

  final List<MediaItem> items;
  final int index;
  final Offset drag;
  final bool showChrome;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onToggleChrome;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final item = items[index];
    final next = index + 1 < items.length ? items[index + 1] : null;

    // 拖动越远，倾斜和染色越明显。
    final progress = (drag.dx.abs() / (width * 0.5)).clamp(0.0, 1.0);
    final willDelete = drag.dx < 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (next != null)
            Transform.scale(
              scale: 1 - 0.04 * (1 - progress),
              child: Opacity(
                opacity: 0.6,
                child: _Card(item: next, showChrome: false),
              ),
            ),
          Transform.translate(
            offset: drag,
            child: Transform.rotate(
              angle: drag.dx / width * 0.18,
              child: GestureDetector(
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
                onTap: onToggleChrome,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _Card(item: item, showChrome: showChrome),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: (willDelete ? AppColors.danger : AppColors.success)
                              .withAlpha((progress * 110).round().clamp(0, 255)),
                        ),
                      ),
                    ),
                    if (progress > 0.05)
                      IgnorePointer(
                        child: Align(
                          alignment: willDelete
                              ? Alignment.topRight
                              : Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Opacity(
                              opacity: progress,
                              child: _Verdict(
                                label: willDelete ? '删除' : '保留',
                                color: willDelete
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.showChrome});

  final MediaItem item;
  final bool showChrome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: theme.colorScheme.onSurface.withAlpha(20),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            MediaThumbnail(item: item, size: 1024, fit: BoxFit.contain),
            if (showChrome)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  color: AppColors.scrim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _title(item),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(item),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _title(MediaItem item) {
    final date = item.createdAt;
    return date == null ? '未知时间' : formatRelativeDate(date);
  }

  static String _subtitle(MediaItem item) {
    final parts = <String>[formatBytes(item.effectiveSize)];
    if (item.pixelCount > 0) parts.add('${item.width}×${item.height}');
    if (item.isVideo) parts.add('视频 ${formatDurationText(item.duration)}');
    if (item.isFavorite) parts.add('已收藏');
    return parts.join(' · ');
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 操作条

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canUndo,
    required this.onKeep,
    required this.onDelete,
    required this.onUndo,
  });

  final bool canUndo;
  final VoidCallback onKeep;
  final VoidCallback onDelete;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _CircleAction(
              icon: Icons.undo,
              label: '撤销',
              color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              onPressed: canUndo ? onUndo : null,
            ),
            _CircleAction(
              icon: Icons.check,
              label: '保留',
              color: AppColors.success,
              onPressed: onKeep,
              large: true,
            ),
            _CircleAction(
              icon: Icons.close,
              label: '删除',
              color: AppColors.danger,
              onPressed: onDelete,
              large: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 60.0 : 48.0;
    final enabled = onPressed != null;
    final tint = enabled ? color : color.withAlpha(60);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: tint.withAlpha(28),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, color: tint, size: large ? 28 : 22),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 结束页

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.marked,
    required this.onUndo,
    required this.onDelete,
    required this.onRestart,
    required this.total,
  });

  final List<MediaItem> marked;
  final VoidCallback onUndo;
  final Future<void> Function() onDelete;
  final VoidCallback onRestart;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (marked.isEmpty) {
      return EmptyState(
        icon: Icons.thumb_up_alt_outlined,
        title: '这些照片都留下了',
        message: total == 0 ? '没有需要处理的照片。' : '你放过了 $total 张照片。',
        action: OutlinedButton(
          onPressed: onRestart,
          child: const Text('重新看一遍'),
        ),
      );
    }

    final bytes = marked.fold<int>(0, (sum, item) => sum + item.effectiveSize);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '标记了 ${formatCount(marked.length)} 项',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '预计释放 ${formatBytes(bytes)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(150),
                          ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onUndo,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤销一步'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: marked.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: MediaThumbnail(item: marked[index], size: 200),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRestart,
                    child: const Text('重新看一遍'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('删除 ${marked.length} 项'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
