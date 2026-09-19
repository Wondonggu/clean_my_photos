import 'package:flutter/foundation.dart';

import '../core/models/media_group.dart';
import '../core/models/media_item.dart';

/// 管理「哪些条目将被删除」的勾选状态。
///
/// 每个复核页面持有一个实例，页面销毁即丢弃。
class SelectionController extends ChangeNotifier {
  final Set<String> _selectedIds = <String>{};
  List<MediaItem> _candidates = const <MediaItem>[];

  /// 当前页面可以勾选的全部条目。
  List<MediaItem> get candidates => _candidates;

  /// 已勾选的数量。
  int get count => _selectedIds.length;

  bool get isEmpty => _selectedIds.isEmpty;

  /// 是否全部勾选。
  bool get isAllSelected =>
      _candidates.isNotEmpty && _selectedIds.length == _candidates.length;

  /// 已勾选的条目（保持候选列表的顺序）。
  List<MediaItem> get selectedItems =>
      _candidates.where((item) => _selectedIds.contains(item.id)).toList();

  /// 已勾选的条目总体积。
  int get selectedBytes => selectedItems.fold(
        0,
        (sum, item) => sum + item.effectiveSize,
      );

  bool isSelected(String id) => _selectedIds.contains(id);

  /// 重置候选列表。[selectAll] 为 true 时默认全选。
  void reset(Iterable<MediaItem> candidates, {bool selectAll = true}) {
    _candidates = candidates.toList(growable: false);
    _selectedIds.clear();
    if (selectAll) {
      for (final item in _candidates) {
        if (!item.isFavorite) _selectedIds.add(item.id);
      }
    }
    notifyListeners();
  }

  /// 用户在当前候选列表里明确取消勾选的条目。
  ///
  /// 删除若干项之后分类会被重算，候选列表随之变化；[sync] 靠这份记录
  /// 保住用户已经做出的「这张我要留着」的决定。
  Set<String> get deselectedIds => _candidates
      .where((item) => !item.isFavorite && !_selectedIds.contains(item.id))
      .map((item) => item.id)
      .toSet();

  /// 数据更新后同步候选列表，并尽量保留用户的勾选状态。
  ///
  /// - 已经不在候选里的 id 会被丢弃；
  /// - 新增的条目按 [selectAll] 决定是否默认勾选；
  /// - 用户之前取消勾选过的条目不会被重新勾上。
  void sync(Iterable<MediaItem> candidates, {bool selectAll = true}) {
    final deselected = deselectedIds;
    _candidates = candidates.toList(growable: false);

    final valid = <String>{for (final item in _candidates) item.id};
    _selectedIds.removeWhere((id) => !valid.contains(id));

    if (selectAll) {
      for (final item in _candidates) {
        if (!item.isFavorite && !deselected.contains(item.id)) {
          _selectedIds.add(item.id);
        }
      }
    }
    notifyListeners();
  }

  void toggle(String id) {
    final item = _candidates.firstWhere(
      (candidate) => candidate.id == id,
      orElse: () => throw ArgumentError('$id 不在候选列表中'),
    );
    // 收藏项不允许勾选删除。
    if (item.isFavorite) return;

    if (!_selectedIds.remove(id)) {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  /// 勾选 / 取消勾选一整组（用于重复照片的分组视图）。
  void toggleGroup(MediaGroup group, {required bool selected}) {
    for (final item in group.deletable) {
      if (item.isFavorite) continue;
      if (selected) {
        _selectedIds.add(item.id);
      } else {
        _selectedIds.remove(item.id);
      }
    }
    notifyListeners();
  }

  /// 某一组里已勾选的数量。
  int selectedInGroup(MediaGroup group) =>
      group.deletable.where((item) => _selectedIds.contains(item.id)).length;

  void selectAll() {
    for (final item in _candidates) {
      if (!item.isFavorite) _selectedIds.add(item.id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// 反选。
  void invert() {
    for (final item in _candidates) {
      if (item.isFavorite) continue;
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
    }
    notifyListeners();
  }
}
