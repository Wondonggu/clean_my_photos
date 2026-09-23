import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/models/swipe_gesture.dart';
import '../../core/utils/formatters.dart';
import '../../state/cleanup_progress_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/delete_flow.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_thumbnail.dart';

/// 滑动清理。
///
/// 一张一张地看：**上滑删除、下滑保留、左滑撤销**。比在网格里逐个点选快得多，
/// 而且每一张都能看清，不容易误删。滑到底之后再一次性确认。
///
/// 方向是竖着的，跟系统相册（上滑删除）一致；横向留给「撤销」，因为它是个
/// 回头动作，跟「往前推进」的上下滑不该抢同一根轴。
class SwipeCleanPage extends StatefulWidget {
  const SwipeCleanPage({
    super.key,
    required this.title,
    required this.items,
    this.startIndex = 0,
    this.scope,
    this.onDeleted,
  });

  final String title;
  final List<MediaItem> items;

  /// 从第几张开始看。按时间线或相册进来时会带上上次的断点。
  final int startIndex;

  /// 进度记在哪个作用域下，见 `CleanupScopes`。
  ///
  /// 为 null 时不记进度——从分类复核页进来就是这样：那一页的候选列表
  /// 每次分析完都会重算，用一个会变的列表做断点没有意义。
  final String? scope;

  /// 系统真的删掉这些 id 之后回调，方便调用方把列表里的对应条目去掉。
  ///
  /// 传的是**真正被删掉的** id，不是「标记过要删的」：用户在系统弹窗里
  /// 取消、或者部分条目删不掉时，两者并不相同。
  final ValueChanged<Set<String>>? onDeleted;

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

  /// 牌堆里还没处理完的条目。
  late List<MediaItem> _remaining = List<MediaItem>.of(widget.items);

  int _index = 0;
  SwipeGestureState _gesture = SwipeGestureState.idle;

  /// 动画期间额外叠加的位移：飞出屏幕、撤销飞回来都走这里。
  ///
  /// 手指拖出来的位移始终留在 [_gesture] 里，两者相加才是卡片该在的位置。
  Offset _flyOffset = Offset.zero;

  bool _animating = false;
  bool _showChrome = true;

  final List<_Decision> _decisions = <_Decision>[];

  /// 在 [didChangeDependencies] 里取好：`dispose` 时已经不能再看祖先了，
  /// 而那正是最需要记一次落点的时刻。
  CleanupProgressController? _progress;

  List<MediaItem> get _marked => <MediaItem>[
        for (final decision in _decisions)
          if (decision.deleteIt) decision.item,
      ];

  bool get _finished => _index >= _remaining.length;

  /// 卡片当前该画在哪儿。
  Offset get _cardOffset => Offset(
        _gesture.offsetX + _flyOffset.dx,
        _gesture.offsetY + _flyOffset.dy,
      );

  /// 用来推蒙层、徽标和倾角的状态。
  ///
  /// 动画期间手指没动（[_gesture] 是空的），位移全在 [_flyOffset] 上，
  /// 得把它重新当成一次拖动看，否则卡片在飞出去的路上章会突然消失。
  SwipeGestureState get _visual => _flyOffset == Offset.zero
      ? _gesture
      : SwipeGestureState.fromOffset(_cardOffset.dx, _cardOffset.dy);

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _index = widget.startIndex.clamp(0, _remaining.length);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progress = context.read<CleanupProgressController>();
  }

  @override
  void dispose() {
    // 离开清理页就是最后一次记录：用户可能直接一路返回，之后再也回不来。
    _recordPosition();
    unawaited(_progress?.flush() ?? Future<void>.value());
    _fly.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 进度记录

  /// 把当前落点写进进度。
  ///
  /// [next] 为空表示牌堆已经走到底，这时进度会被清掉——下次进来从头看，
  /// 也顺手把「开始清理之后新拍的照片」收了进来。
  void _recordPosition({
    int processedDelta = 0,
    int deletedDelta = 0,
    int reclaimedBytesDelta = 0,
  }) {
    final scope = widget.scope;
    final progress = _progress;
    if (scope == null || progress == null) return;

    progress.recordPosition(
      scope: scope,
      label: widget.title,
      next: _finished ? null : _remaining[_index],
      processedDelta: processedDelta,
      deletedDelta: deletedDelta,
      reclaimedBytesDelta: reclaimedBytesDelta,
      items: _remaining,
    );
  }

  // ---------------------------------------------------------------- 滑动逻辑

  void _onPanStart(DragStartDetails details) {
    if (_animating) return;
    setState(() => _gesture = SwipeGestureState.idle);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_animating) return;
    setState(
      () => _gesture = _gesture.dragBy(details.delta.dx, details.delta.dy),
    );
  }

  void _onPanEnd(DragEndDetails details) {
    if (_animating) return;
    final size = MediaQuery.of(context).size;

    final verdict = _gesture.verdictAtEnd(
      velocityX: details.velocity.pixelsPerSecond.dx,
      velocityY: details.velocity.pixelsPerSecond.dy,
      extentX: size.width,
      extentY: size.height,
    );

    switch (verdict) {
      case SwipeVerdict.delete:
        _commit(deleteIt: true);
      case SwipeVerdict.keep:
        _commit(deleteIt: false);
      case SwipeVerdict.undo:
        _rewind();
      case null:
        setState(() => _gesture = SwipeGestureState.idle);
    }
  }

  /// 卡片离场的方向。删除往上、保留往下，跟手势方向一致。
  Offset _exitOffset({required bool deleteIt, required Size extent}) => Offset(
        0,
        deleteIt ? -extent.height * 1.2 : extent.height * 1.2,
      );

  /// 把卡片从当前位置飞到 [to]，沿途更新 [_flyOffset]。
  Future<void> _animate({required Offset to, required Curve curve}) async {
    final animation = Tween<Offset>(begin: _flyOffset, end: to)
        .animate(CurvedAnimation(parent: _fly, curve: curve));

    void listener() {
      if (mounted) setState(() => _flyOffset = animation.value);
    }

    animation.addListener(listener);
    await _fly.forward(from: 0);
    animation.removeListener(listener);
    _fly.reset();
  }

  Future<void> _commit({required bool deleteIt}) async {
    if (_animating || _finished) return;

    final item = _remaining[_index];
    final to = _exitOffset(deleteIt: deleteIt, extent: MediaQuery.of(context).size);
    // 从卡片当前的位置接着往外飞：按钮触发时它停在正中，甩出去触发时它已经
    // 跟着手指走了一截，直接跳到终点会闪一下。
    final from = _cardOffset;

    setState(() {
      _animating = true;
      _flyOffset = from;
      _gesture = SwipeGestureState.idle;
    });

    await _animate(to: to, curve: Curves.easeOut);
    if (!mounted) return;

    setState(() {
      _decisions.add(_Decision(item, deleteIt: deleteIt));
      _index++;
      _flyOffset = Offset.zero;
      _animating = false;
    });

    _recordPosition(processedDelta: 1);
  }

  /// 撤销上一步：把刚处理掉的那张从它离开的方向请回来。
  ///
  /// 不做成「瞬间回到上一张」是因为那样看不出撤销了什么，尤其连续滑了几张
  /// 之后，画面只是换了一张脸。
  Future<void> _rewind() async {
    if (_decisions.isEmpty || _animating) return;

    final decision = _decisions.last;
    final size = MediaQuery.of(context).size;

    setState(() {
      _animating = true;
      _decisions.removeLast();
      _index--;
      _gesture = SwipeGestureState.idle;
      _flyOffset = _exitOffset(deleteIt: decision.deleteIt, extent: size);
    });

    await _animate(to: Offset.zero, curve: Curves.easeOutCubic);
    if (!mounted) return;

    setState(() {
      _flyOffset = Offset.zero;
      _animating = false;
    });

    // 撤销也要记：断点得跟着退回去，否则重开时会跳过刚被撤销的那一张。
    _recordPosition(processedDelta: -1);
  }

  Future<void> _delete() async {
    final items = _marked;
    if (items.isEmpty) return;

    final result = await performDeletion(context, items);
    if (!mounted || result == null || result.deletedCount == 0) return;

    // 系统可能只删掉了一部分，因此以它实际删掉的那些 id 为准，
    // 而不是假设标记过的都删成功了。
    //
    // 这里刻意不拿整库列表来算「还剩下谁」：本页可能是从某个相册或某段时间线
    // 打开的，条目未必完整地出现在整库列表里（整库读取有 30000 条上限），
    // 那样会把没删掉的也一起丢掉。
    final failed = result.failedIds.toSet();
    final deleted = <String>{
      for (final item in items)
        if (!item.isFavorite && !failed.contains(item.id)) item.id,
    };

    setState(() {
      _remaining =
          _remaining.where((item) => !deleted.contains(item.id)).toList();
      _decisions.clear();
      _index = 0;
      _gesture = SwipeGestureState.idle;
      _flyOffset = Offset.zero;
    });

    final reclaimed = items
        .where((item) => deleted.contains(item.id))
        .fold<int>(0, (sum, item) => sum + item.effectiveSize);

    _recordPosition(
      deletedDelta: deleted.length,
      reclaimedBytesDelta: reclaimed,
    );
    widget.onDeleted?.call(deleted);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final finished = remaining.isEmpty || _finished;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (!finished)
            IconButton(
              tooltip: _showChrome ? '隐藏信息' : '显示信息',
              icon: Icon(
                _showChrome
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
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
      body: finished
          ? _DoneView(
              marked: _marked,
              onUndo: _rewind,
              onDelete: _delete,
              onRestart: () => setState(() {
                _decisions.clear();
                _index = 0;
              }),
              total: remaining.length,
            )
          : _Deck(
              key: const Key('swipe-deck'),
              items: remaining,
              index: _index,
              gesture: _visual,
              extent: MediaQuery.of(context).size,
              showChrome: _showChrome,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onToggleChrome: () => setState(() => _showChrome = !_showChrome),
            ),
      bottomNavigationBar: finished
          ? null
          : _ActionBar(
              enabled: !_animating,
              canUndo: _decisions.isNotEmpty,
              onKeep: () => _commit(deleteIt: false),
              onDelete: () => _commit(deleteIt: true),
              onUndo: _rewind,
            ),
    );
  }
}

// -------------------------------------------------------------------- 牌堆

class _Deck extends StatelessWidget {
  const _Deck({
    super.key,
    required this.items,
    required this.index,
    required this.gesture,
    required this.extent,
    required this.showChrome,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onToggleChrome,
  });

  final List<MediaItem> items;
  final int index;
  final SwipeGestureState gesture;
  final Size extent;
  final bool showChrome;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onToggleChrome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = items[index];
    final next = index + 1 < items.length ? items[index + 1] : null;

    final intent = gesture.intent;
    final progress = gesture.progress(
      extentX: extent.width,
      extentY: extent.height,
    );
    // 撤销是中性的：它既不是删除也不是保留，用主题色比另造一个颜色更稳。
    final tone = switch (intent) {
      SwipeVerdict.delete => AppColors.danger,
      SwipeVerdict.keep => AppColors.success,
      SwipeVerdict.undo => theme.colorScheme.onSurface,
      null => theme.colorScheme.onSurface,
    };

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
            offset: Offset(gesture.offsetX, gesture.offsetY),
            child: Transform.rotate(
              angle: gesture.tiltRadians(extentX: extent.width),
              child: GestureDetector(
                // 默认的 `start` 会把「按下到识别成功」之间的位移全部丢掉
                // （横向拖动有 36 像素的死区），卡片要等手指走完这段才开始跟。
                // `down` 把这些位移一并补上，卡片从按下的那一刻就贴着手。
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: onPanStart,
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
                onTap: onToggleChrome,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 带上 id 的 Key：卡片内容换了但类型没换，测试需要一个
                    // 能指名道姓断言「现在轮到哪一张」的抓手。
                    _Card(
                      key: Key('swipe-card-${item.id}'),
                      item: item,
                      showChrome: showChrome,
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: tone
                              .withAlpha((progress * 110).round().clamp(0, 255)),
                        ),
                      ),
                    ),
                    if (intent != null && progress > 0.05)
                      IgnorePointer(
                        child: Align(
                          // 徽标停在卡片的「反端」——离退出方向最远、停留最久
                          // 的那一端，这样章在整个滑动过程里都看得见。
                          alignment: _anchorFor(intent),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Opacity(
                              opacity: progress,
                              child: _Verdict(
                                key: Key('verdict-${intent.name}'),
                                label: _labelFor(intent),
                                color: tone,
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

  static Alignment _anchorFor(SwipeVerdict verdict) => switch (verdict) {
        SwipeVerdict.delete => Alignment.bottomCenter,
        SwipeVerdict.keep => Alignment.topCenter,
        SwipeVerdict.undo => Alignment.centerRight,
      };

  static String _labelFor(SwipeVerdict verdict) => switch (verdict) {
        SwipeVerdict.delete => '删除',
        SwipeVerdict.keep => '保留',
        SwipeVerdict.undo => '撤销',
      };
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.item, required this.showChrome});

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
  const _Verdict({super.key, required this.label, required this.color});

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
    required this.enabled,
    required this.canUndo,
    required this.onKeep,
    required this.onDelete,
    required this.onUndo,
  });

  /// 卡片正在飞的时候不接受新的操作，免得两次动画叠在一起。
  final bool enabled;
  final bool canUndo;
  final VoidCallback onKeep;
  final VoidCallback onDelete;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(150);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _CircleAction(
                  key: const Key('swipe-action-undo'),
                  icon: Icons.arrow_back,
                  label: '撤销',
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                  onPressed: enabled && canUndo ? onUndo : null,
                ),
                _CircleAction(
                  key: const Key('swipe-action-keep'),
                  icon: Icons.arrow_downward,
                  label: '保留',
                  color: AppColors.success,
                  onPressed: enabled ? onKeep : null,
                  large: true,
                ),
                _CircleAction(
                  key: const Key('swipe-action-delete'),
                  icon: Icons.arrow_upward,
                  label: '删除',
                  color: AppColors.danger,
                  onPressed: enabled ? onDelete : null,
                  large: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 手势本身没法被发现，这行常驻提示是最省事的补救。
            Text(
              '上滑删除 · 下滑保留 · 左滑撤销',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    super.key,
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
              // ignore: avoid_print
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
                    key: const Key('swipe-delete-all'),
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
