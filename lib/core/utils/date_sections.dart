import '../models/media_item.dart';

/// 时间线上的一个自然日。
class DaySection {
  const DaySection({required this.day, required this.items});

  /// 那一天的零点。为 null 表示这一组里的条目没有拍摄时间。
  final DateTime? day;

  final List<MediaItem> items;

  bool get isUnknownTime => day == null;
}

/// 按自然日把条目分组，保持输入顺序。
///
/// 调用方传进来的本来就是时间倒序（整库读取就是这么给的），这里不再排一遍：
/// 既浪费，又会把「时间未知」的条目挪到意想不到的位置。它们统一放到最后一组，
/// 而不是丢掉——一张时间戳缺失的照片仍然需要被清理。
List<DaySection> groupByDay(List<MediaItem> items) {
  final sections = <DateTime, List<MediaItem>>{};
  final unknown = <MediaItem>[];

  for (final item in items) {
    final date = item.createdAt;
    if (date == null) {
      unknown.add(item);
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    sections.putIfAbsent(day, () => <MediaItem>[]).add(item);
  }

  return <DaySection>[
    for (final entry in sections.entries)
      DaySection(day: entry.key, items: entry.value),
    if (unknown.isNotEmpty) DaySection(day: null, items: unknown),
  ];
}
