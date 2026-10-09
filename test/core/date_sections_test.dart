import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/utils/date_sections.dart';
import 'package:clean_my_photos/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

void main() {
  setUp(MediaFixtures.reset);

  group('按月分组', () {
    test('同一个月的照片归到一组，顺序不变', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'a', createdAt: DateTime(2024, 5, 3, 18)),
        MediaFixtures.photo(id: 'b', createdAt: DateTime(2024, 5, 1, 9)),
        MediaFixtures.photo(id: 'c', createdAt: DateTime(2024, 4, 30, 23)),
      ];

      final sections = groupByMonth(items);

      expect(sections, hasLength(2));
      expect(sections[0].month, DateTime(2024, 5));
      expect(sections[0].items.map((item) => item.id), <String>['a', 'b']);
      expect(sections[1].month, DateTime(2024, 4));
      expect(sections[1].items.map((item) => item.id), <String>['c']);
    });

    test('同一年不同月、不同年同月都不合并', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'may24', createdAt: DateTime(2024, 5, 20)),
        MediaFixtures.photo(id: 'jun24', createdAt: DateTime(2024, 6, 1)),
        MediaFixtures.photo(id: 'may23', createdAt: DateTime(2023, 5, 31)),
      ];

      final sections = groupByMonth(items);

      expect(sections, hasLength(3));
      expect(
        sections.map((section) => section.month),
        <DateTime>[DateTime(2024, 5), DateTime(2024, 6), DateTime(2023, 5)],
      );
    });

    test('分组顺序跟着输入走，不重新排序', () {
      // 输入是时间倒序，输出也该是新的月份在前。
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'new', createdAt: DateTime(2024, 5, 3)),
        MediaFixtures.photo(id: 'old', createdAt: DateTime(2020, 1, 1)),
      ];

      final sections = groupByMonth(items);

      expect(sections.first.month, DateTime(2024, 5));
    });

    test('没有拍摄时间的归入末尾一组，不会被丢掉', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'a', createdAt: DateTime(2024, 5, 3)),
        MediaFixtures.photoWithoutTime(id: 'no-time'),
      ];

      final sections = groupByMonth(items);

      expect(sections, hasLength(2));
      expect(sections.last.month, isNull);
      expect(sections.last.isUnknownTime, isTrue);
      expect(sections.last.items.single.id, 'no-time');
    });

    test('全是未知时间时只剩一组', () {
      final sections = groupByMonth(<MediaItem>[
        MediaFixtures.photoWithoutTime(id: 'a'),
        MediaFixtures.photoWithoutTime(id: 'b'),
      ]);

      expect(sections, hasLength(1));
      expect(sections.single.items, hasLength(2));
    });

    test('空列表得到空分组', () {
      expect(groupByMonth(const <MediaItem>[]), isEmpty);
    });
  });

  group('月份表头', () {
    final now = DateTime(2024, 5, 10, 15, 30);

    test('本月和上个月说人话', () {
      expect(formatMonthLabel(DateTime(2024, 5), now: now), '本月');
      expect(formatMonthLabel(DateTime(2024, 4), now: now), '上个月');
    });

    test('跨年时的上个月仍然叫上个月', () {
      expect(
        formatMonthLabel(DateTime(2023, 12), now: DateTime(2024, 1, 5)),
        '上个月',
      );
    });

    test('今年内只写到月份', () {
      expect(formatMonthLabel(DateTime(2024, 2), now: now), '2 月');
    });

    test('跨年时补上年份', () {
      expect(formatMonthLabel(DateTime(2023, 5), now: now), '2023 年 5 月');
    });

    test('表头不带时刻，跟单张照片的「今天 14:30」区分开', () {
      expect(formatMonthLabel(DateTime(2024, 5), now: now), isNot(contains(':')));
    });
  });

  group('日期表头（续清横幅仍按天说）', () {
    final now = DateTime(2024, 5, 10, 15, 30);

    test('今天和昨天说人话', () {
      expect(formatDayLabel(DateTime(2024, 5, 10), now: now), '今天');
      expect(formatDayLabel(DateTime(2024, 5, 9), now: now), '昨天');
    });

    test('今年内只写到月日', () {
      expect(formatDayLabel(DateTime(2024, 5, 6), now: now), '5 月 6 日');
    });

    test('跨年时补上年份', () {
      expect(
        formatDayLabel(DateTime(2023, 5, 6), now: now),
        '2023 年 5 月 6 日',
      );
    });

    test('表头不带时刻，跟单张照片的「今天 14:30」区分开', () {
      expect(formatDayLabel(DateTime(2024, 5, 10), now: now), isNot(contains(':')));
    });
  });
}
