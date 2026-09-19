import 'package:clean_my_photos/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('按 1024 进位', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3 GB');
      expect(formatBytes(1024 * 1024 * 1024 * 1024), '1 TB');
    });

    test('去掉多余的小数位', () {
      expect(formatBytes(2 * 1024 * 1024), '2 MB');
      // 最大单位是 TB，再大也按 TB 显示。
      expect(formatBytes(1024 * 1024 * 1024 * 1024 * 1024), '1024 TB');
    });

    test('可以指定小数位', () {
      expect(formatBytes(1500, fractionDigits: 2), '1.46 KB');
      expect(formatBytes(1500, fractionDigits: 0), '1 KB');
    });
  });

  group('formatDuration', () {
    test('分:秒 与 时:分:秒', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 9)), '0:09');
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('formatDurationText', () {
    test('中文描述', () {
      expect(formatDurationText(const Duration(seconds: 45)), '45 秒');
      expect(formatDurationText(const Duration(seconds: 65)), '1 分 5 秒');
      expect(formatDurationText(const Duration(minutes: 90)), '1 小时 30 分');
    });
  });

  group('日期', () {
    test('formatDate / formatDateTime 补零', () {
      final date = DateTime(2024, 5, 6, 7, 8);
      expect(formatDate(date), '2024-05-06');
      expect(formatDateTime(date), '2024-05-06 07:08');
    });

    test('formatRelativeDate', () {
      final now = DateTime(2024, 5, 10, 12, 0);
      expect(formatRelativeDate(DateTime(2024, 5, 10, 8, 5), now: now),
          '今天 08:05');
      expect(formatRelativeDate(DateTime(2024, 5, 9, 8, 0), now: now), '昨天');
      expect(formatRelativeDate(DateTime(2024, 5, 7, 8, 0), now: now), '3 天前');
      expect(formatRelativeDate(DateTime(2024, 1, 1), now: now), '2024-01-01');
    });
  });

  group('formatCount', () {
    test('千位分隔', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(1234567), '1,234,567');
    });
  });

  group('formatPercent', () {
    test('百分比', () {
      expect(formatPercent(0.72), '72%');
      expect(formatPercent(1.5), '100%');
      expect(formatPercent(-1), '0%');
      expect(formatPercent(0.725, fractionDigits: 1), '72.5%');
    });
  });
}
