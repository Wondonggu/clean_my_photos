import 'media_item.dart';

/// 一组的判定类型。
enum GroupKind {
  /// 内容完全一致（哈希距离为 0）。
  duplicate('重复照片'),

  /// 内容高度相似（哈希距离不超过阈值），通常是连拍或轻微修图后的副本。
  similar('相似照片');

  const GroupKind(this.label);

  final String label;
}

/// 一组重复 / 相似的媒体，以及组内建议保留的那一项。
class MediaGroup {
  const MediaGroup({
    required this.items,
    required this.keeperId,
    required this.kind,
    this.maxDistance = 0,
  });

  /// 组内全部条目，按建议保留顺序排序（第一个即 [keeper]）。
  final List<MediaItem> items;

  /// 建议保留的条目 id。
  final String keeperId;

  final GroupKind kind;

  /// 组内任意两项之间的最大哈希距离，0 表示完全相同。
  final int maxDistance;

  /// 建议保留的那一项。
  MediaItem get keeper => items.firstWhere(
        (item) => item.id == keeperId,
        orElse: () => items.first,
      );

  /// 组内全部条目是否都是收藏。
  ///
  /// 收藏是用户明确的「我要留着」信号，因此这种组不提供任何删除建议，
  /// 只在界面上标注出来。
  bool get allFavorites =>
      items.isNotEmpty && items.every((item) => item.isFavorite);

  /// 除保留项之外、可被删除的条目。
  ///
  /// 整组都是收藏时返回空列表——即使用户手动点选，界面也会拦住。
  List<MediaItem> get deletable => allFavorites
      ? const <MediaItem>[]
      : items.where((item) => item.id != keeperId).toList(growable: false);

  /// 清理该组可释放的字节数。
  int get reclaimableBytes =>
      deletable.fold(0, (sum, item) => sum + item.effectiveSize);

  /// 稳定标识：取组内最小 id，方便做列表 key 与去重。
  String get id {
    var min = items.first.id;
    for (final item in items) {
      if (item.id.compareTo(min) < 0) min = item.id;
    }
    return min;
  }

  bool get isEmpty => items.isEmpty;

  @override
  String toString() =>
      'MediaGroup(${kind.name}, ${items.length} items, '
      'maxDistance=$maxDistance, reclaim=$reclaimableBytes)';
}
