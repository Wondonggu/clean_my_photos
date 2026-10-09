import '../models/media_item.dart';

/// 时间线上的一个月份。
class MonthSection {
  const MonthSection({required this.month, required this.items});

  /// 那个月的 1 日零点。为 null 表示这一组里的条目没有拍摄时间。
  final DateTime? month;

  final List<MediaItem> items;

  bool get isUnknownTime => month == null;
}

/// 按月份把条目分组，保持输入顺序。
///
/// 调用方传进来的本来就是时间倒序（整库读取就是这么给的），这里不再排一遍：
/// 既浪费，又会把「时间未知」的条目挪到意想不到的位置。它们统一放到最后一组，
/// 而不是丢掉——一张时间戳缺失的照片仍然需要被清理。
List<MonthSection> groupByMonth(List<MediaItem> items) {
  final sections = <DateTime, List<MediaItem>>{};
  final unknown = <MediaItem>[];

  for (final item in items) {
    final date = item.createdAt;
    if (date == null) {
      unknown.add(item);
      continue;
    }
    final month = DateTime(date.year, date.month);
    sections.putIfAbsent(month, () => <MediaItem>[]).add(item);
  }

  return <MonthSection>[
    for (final entry in sections.entries)
      MonthSection(month: entry.key, items: entry.value),
    if (unknown.isNotEmpty) MonthSection(month: null, items: unknown),
  ];
}
