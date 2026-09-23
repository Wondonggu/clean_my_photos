import 'package:clean_my_photos/core/models/cleanup_progress.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

void main() {
  setUp(MediaFixtures.reset);

  /// 一串从新到旧的条目，id 依次是 m0、m1、……
  List<MediaItem> library(int count, {DateTime? newest}) {
    final start = newest ?? DateTime(2024, 5, 10, 12);
    return <MediaItem>[
      for (var i = 0; i < count; i++)
        MediaFixtures.photo(
          id: 'm$i',
          createdAt: start.subtract(Duration(hours: i)),
        ),
    ];
  }

  CleanupProgress progressAt(String id, DateTime? date) => CleanupProgress(
        scope: CleanupScopes.timeline,
        label: '时间线',
        anchorId: id,
        anchorDate: date,
      );

  group('断点解析', () {
    test('锚点还在时落在它自己身上', () {
      final items = library(5);

      expect(resolveStartIndex(items, progressAt('m3', items[3].createdAt)), 3);
    });

    test('锚点被删掉时退回到日期水位', () {
      final items = library(5);
      // 锚点是 m3，但它已经被删了——列表里只剩 m0、m1、m2、m4、m5。
      final remaining = <MediaItem>[items[0], items[1], items[2], items[4]];
      final anchorDate = items[3].createdAt;

      // m4 比锚点老，正是断点该落的位置。
      expect(remaining.indexWhere((item) => item.id == 'm4'), 3);
      expect(resolveStartIndex(remaining, progressAt('m3', anchorDate)), 3);
    });

    test('锚点比列表里最老的还老时，整轮算看完', () {
      final items = library(5);
      final anchorDate = items.last.createdAt!.subtract(const Duration(days: 1));

      expect(resolveStartIndex(items, progressAt('gone', anchorDate)), 5);
    });

    test('锚点没了、日期也没有时从头开始', () {
      final items = library(3);

      expect(
        resolveStartIndex(
          items,
          const CleanupProgress(scope: 'timeline', label: '时间线'),
        ),
        0,
      );
    });

    test('没有进度时从头开始', () {
      expect(resolveStartIndex(library(3), null), 0);
    });

    test('空列表返回 0，不会越界', () {
      expect(resolveStartIndex(const <MediaItem>[], progressAt('m0', null)), 0);
    });

    test('时间缺失的条目不会被当成日期水位命中', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'a', createdAt: DateTime(2024, 5, 10)),
        MediaFixtures.photoWithoutTime(id: 'no-time'),
        MediaFixtures.photo(id: 'b', createdAt: DateTime(2024, 5, 8)),
      ];

      // 锚点已删，日期水位落在 b（5-8）上；中间那张没有时间，跳过它。
      expect(
        resolveStartIndex(items, progressAt('gone', DateTime(2024, 5, 10))),
        2,
      );
    });
  });

  group('新照片计数', () {
    test('没有记录过起点时不算', () {
      expect(countNewerThanRoundStart(library(3), progressAt('m1', null)), 0);
    });

    test('只有排在起点上方的新照片会被数出来', () {
      final items = library(3);
      final start = items.first.createdAt;
      final withNew = <MediaItem>[
        MediaFixtures.photo(
          id: 'brand-new',
          createdAt: start!.add(const Duration(hours: 1)),
        ),
        ...items,
      ];

      final progress = CleanupProgress(
        scope: CleanupScopes.timeline,
        label: '时间线',
        anchorId: 'm2',
        anchorDate: items[2].createdAt,
        roundStartDate: start,
      );

      expect(countNewerThanRoundStart(withNew, progress), 1);
    });
  });

  group('存档往返', () {
    test('字段原样带回来', () {
      final original = CleanupProgress(
        scope: CleanupScopes.album('abc'),
        label: '旅行',
        anchorId: 'm7',
        anchorDate: DateTime(2024, 5, 3, 9, 30),
        roundStartDate: DateTime(2024, 5, 10, 12),
        processed: 42,
        deleted: 7,
        reclaimedBytes: 123456,
        updatedAt: DateTime(2024, 5, 11, 8),
      );

      final restored = CleanupProgress.fromJson(
        original.scope,
        original.toJson(),
      );

      expect(restored, isNotNull);
      expect(restored!.scope, original.scope);
      expect(restored.label, original.label);
      expect(restored.anchorId, original.anchorId);
      expect(restored.anchorDate, original.anchorDate);
      expect(restored.roundStartDate, original.roundStartDate);
      expect(restored.processed, original.processed);
      expect(restored.deleted, original.deleted);
      expect(restored.reclaimedBytes, original.reclaimedBytes);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('缺字段或类型不对时当作没有这条进度，而不是抛异常', () {
      expect(CleanupProgress.fromJson('x', <String, Object?>{}), isNull);
      expect(
        CleanupProgress.fromJson('x', <String, Object?>{'label': 42}),
        isNull,
      );
    });

    test('计数是负数时归零，避免存档被写坏之后显示成负的', () {
      final restored = CleanupProgress.fromJson('x', <String, Object?>{
        'label': '时间线',
        'processed': -5,
        'deleted': 'oops',
      });

      expect(restored!.processed, 0);
      expect(restored.deleted, 0);
    });
  });

  group('作用域键', () {
    test('三种作用域互不相同', () {
      expect(CleanupScopes.timeline, 'timeline');
      expect(CleanupScopes.album('a1'), 'album:a1');
      expect(CleanupScopes.category('screenshots'), 'category:screenshots');
    });
  });
}
