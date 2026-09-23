import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/models/cleanup_progress.dart';
import '../core/models/media_item.dart';
import '../data/cleanup_progress_store.dart';

/// 清理进度的读写与落盘。
///
/// 目标是「杀掉进程重开还能接着清」：每滑几张就写一次盘，切走、被杀、
/// 第二天再打开，都从断点续上。
///
/// 写盘刻意攒着批量做——每滑一张就写一次 SharedPreferences，一次清理下来
/// 是几百次平台调用，既费电又会让界面在滑动时掉帧。攒够 [flushEvery] 次
/// 或者被要求 [flush] 时再落盘，最坏情况丢的是最近二十次滑动，不是整轮进度。
class CleanupProgressController extends ChangeNotifier {
  CleanupProgressController({
    CleanupProgressStore? store,
    this.flushEvery = 20,
  }) : _store = store ?? const PreferencesCleanupProgressStore();

  final CleanupProgressStore _store;

  /// 攒够几次改动就落一次盘。
  final int flushEvery;

  Map<String, CleanupProgress> _progress = <String, CleanupProgress>{};
  int _pendingChanges = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 有进度的作用域，最近更新的排在前面。
  List<CleanupProgress> get startedScopes {
    final list = _progress.values.where((p) => !p.isEmpty).toList();
    list.sort((a, b) {
      final left = a.updatedAt;
      final right = b.updatedAt;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return list;
  }

  CleanupProgress? progressFor(String scope) => _progress[scope];

  /// 该从第几张开始看。
  int startIndexFor(String scope, List<MediaItem> items) =>
      resolveStartIndex(items, _progress[scope]);

  Future<void> load() async {
    _progress = await _store.load();
    _loaded = true;
    _pendingChanges = 0;
    notifyListeners();
  }

  /// 记录牌堆当前的落点。
  ///
  /// [next] 是下一张要看的。传 null 表示这一轮已经看完了——这时把进度删掉，
  /// 而不是留一条「已完成」的记录：下次进来本来就该从头看，留着只会让首页
  /// 一直挂着一个点不动的「继续清理」。
  void recordPosition({
    required String scope,
    required String label,
    required MediaItem? next,
    int processedDelta = 0,
    int deletedDelta = 0,
    int reclaimedBytesDelta = 0,
    List<MediaItem>? items,
    DateTime? now,
  }) {
    final previous = _progress[scope];
    final stamp = now ?? DateTime.now();

    if (next == null) {
      if (previous == null) return;
      _progress.remove(scope);
      _touch();
      return;
    }

    _progress[scope] = CleanupProgress(
      scope: scope,
      label: label,
      anchorId: next.id,
      anchorDate: next.createdAt,
      // 只在第一轮记一次：它是「这一轮开始时最新的是哪张」，
      // 每滑一张都刷新就失去意义了。
      roundStartDate: previous?.roundStartDate ??
          (items != null && items.isNotEmpty ? items.first.createdAt : null),
      // 撤销会带负的增量，夹一下免得计数变成负数——存档读回来时本来
      // 也会夹，但那要等到下次启动，中间这段时间界面会显示成负的。
      processed: ((previous?.processed ?? 0) + processedDelta).clamp(0, 1 << 30),
      deleted: ((previous?.deleted ?? 0) + deletedDelta).clamp(0, 1 << 30),
      reclaimedBytes:
          ((previous?.reclaimedBytes ?? 0) + reclaimedBytesDelta).clamp(0, 1 << 40),
      updatedAt: stamp,
    );
    _touch();
  }

  /// 忘掉某个作用域的进度，从头再来。
  void reset(String scope) {
    if (_progress.remove(scope) == null) return;
    _touch();
  }

  /// 立刻落盘。
  ///
  /// 界面切到后台、离开清理页、或者 App 要退出时调用——攒批的代价是这些
  /// 时刻必须老老实实写一次，否则「杀掉进程重开还能续上」就不成立了。
  Future<void> flush() async {
    if (_pendingChanges == 0) return;
    _pendingChanges = 0;
    await _store.save(_progress);
  }

  void _touch() {
    _pendingChanges++;
    _notify();
    if (_pendingChanges >= flushEvery) {
      // 攒够了就写，但不阻塞调用方：写盘失败没什么可补救的，
      // 顶多是下次从头看一遍。
      unawaited(flush());
    }
  }

  /// 通知监听者，必要时推迟到这一帧画完。
  ///
  /// 清理页在 `dispose` 里记最后一次落点，而那时 widget 树正锁着，
  /// 当场 `notifyListeners()` 会撞上「setState() called when widget tree was
  /// locked」——在真机的 debug 版上也会抛。攒到帧尾再发，效果一样，
  /// 因为真正关心这条记录的相册页此刻还没轮到重建。
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  bool _notifyScheduled = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
