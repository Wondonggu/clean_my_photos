import 'package:clean_my_photos/core/models/cleanup_progress.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/cleanup_progress_store.dart';
import 'package:clean_my_photos/state/cleanup_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/media_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MediaFixtures.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<MediaItem> library(int count) => <MediaItem>[
        for (var i = 0; i < count; i++)
          MediaFixtures.photo(
            id: 'm$i',
            createdAt: DateTime(2024, 5, 10, 12).subtract(Duration(hours: i)),
          ),
      ];

  group('记录落点', () {
    test('计数是累加的，不是每次覆盖', () async {
      final controller = CleanupProgressController(
        store: MemoryCleanupProgressStore(),
      );
      final items = library(4);

      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[1],
        processedDelta: 1,
        items: items,
      );
      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[2],
        processedDelta: 1,
        deletedDelta: 1,
        reclaimedBytesDelta: 1000,
        items: items,
      );

      final progress = controller.progressFor(CleanupScopes.timeline)!;
      expect(progress.anchorId, 'm2');
      expect(progress.processed, 2);
      expect(progress.deleted, 1);
      expect(progress.reclaimedBytes, 1000);
    });

    test('这一轮的起点只记第一次，之后滑多少张都不改', () {
      final controller = CleanupProgressController(
        store: MemoryCleanupProgressStore(),
      );
      final items = library(4);

      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[1],
        items: items,
      );
      final first = controller.progressFor(CleanupScopes.timeline)!;

      final later = library(5); // 中途又进来一张新照片
      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: later[2],
        items: later,
      );

      expect(
        controller.progressFor(CleanupScopes.timeline)!.roundStartDate,
        first.roundStartDate,
      );
    });

    test('看完之后进度被清掉，而不是留一条「已完成」', () {
      final controller = CleanupProgressController(
        store: MemoryCleanupProgressStore(),
      );
      final items = library(3);

      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[1],
        processedDelta: 1,
        items: items,
      );
      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: null,
      );

      expect(controller.progressFor(CleanupScopes.timeline), isNull);
      expect(controller.startIndexFor(CleanupScopes.timeline, items), 0);
      // 从没记过进度时清一遍不该产生多余的写盘。
      expect(controller.startedScopes, isEmpty);
    });

    test('startIndexFor 直接给出该从第几张开始看', () {
      final controller = CleanupProgressController(
        store: MemoryCleanupProgressStore(),
      );
      final items = library(5);

      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[3],
        items: items,
      );

      expect(controller.startIndexFor(CleanupScopes.timeline, items), 3);
    });
  });

  group('落盘', () {
    test('攒够一批之前不写盘，flush 时才写', () async {
      final store = MemoryCleanupProgressStore();
      final controller = CleanupProgressController(
        store: store,
        flushEvery: 3,
      );
      final items = library(6);

      for (var i = 0; i < 2; i++) {
        controller.recordPosition(
          scope: CleanupScopes.timeline,
          label: '时间线',
          next: items[i],
          items: items,
        );
      }
      await pumpEventQueue();
      expect(store.saveCount, 0);

      // 第三次改动越过阈值，自动落盘。
      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[2],
        items: items,
      );
      await pumpEventQueue();
      expect(store.saveCount, 1);
    });

    test('没有改动时 flush 不做无用功', () async {
      final store = MemoryCleanupProgressStore();
      final controller = CleanupProgressController(store: store);

      await controller.flush();

      expect(store.saveCount, 0);
    });

    test('杀掉进程重开还能续上', () async {
      final store = MemoryCleanupProgressStore();
      final items = library(5);

      final before = CleanupProgressController(store: store);
      before.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[3],
        processedDelta: 3,
        items: items,
      );
      await before.flush();

      // 进程没了，重新起一个。
      final after = CleanupProgressController(store: store);
      await after.load();

      expect(after.progressFor(CleanupScopes.timeline)!.processed, 3);
      expect(after.startIndexFor(CleanupScopes.timeline, items), 3);
    });

    test('重开之后锚点那张已经被删掉了，也能落回大致位置', () async {
      final store = MemoryCleanupProgressStore();
      final items = library(5);

      final before = CleanupProgressController(store: store);
      before.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: items[3],
        items: items,
      );
      await before.flush();

      final remaining = <MediaItem>[items[0], items[1], items[2], items[4]];
      final after = CleanupProgressController(store: store);
      await after.load();

      expect(after.startIndexFor(CleanupScopes.timeline, remaining), 3);
    });
  });

  group('SharedPreferences 存档', () {
    test('写进去再读出来是同一件事', () async {
      const store = PreferencesCleanupProgressStore();
      final items = library(4);

      await store.save(<String, CleanupProgress>{
        CleanupScopes.timeline: CleanupProgress(
          scope: CleanupScopes.timeline,
          label: '时间线',
          anchorId: 'm2',
          anchorDate: items[2].createdAt,
          processed: 12,
          deleted: 3,
          reclaimedBytes: 4096,
        ),
        CleanupScopes.album('trip'): const CleanupProgress(
          scope: 'album:trip',
          label: '旅行',
        ),
      });

      final restored = await store.load();

      expect(restored.keys, containsAll(<String>['timeline', 'album:trip']));
      expect(restored['timeline']!.anchorId, 'm2');
      expect(restored['timeline']!.processed, 12);
      expect(restored['timeline']!.deleted, 3);
      expect(restored['timeline']!.anchorDate, items[2].createdAt);
      expect(restored['album:trip']!.label, '旅行');
    });

    test('存档是坏的时候当作没有进度，时间线仍然打得开', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferencesCleanupProgressStore.key: '这不是 JSON',
      });

      expect(
        await const PreferencesCleanupProgressStore().load(),
        isEmpty,
      );
    });

    test('清空之后不留残余', () async {
      const store = PreferencesCleanupProgressStore();
      await store.save(<String, CleanupProgress>{
        'timeline': const CleanupProgress(scope: 'timeline', label: '时间线'),
      });
      await store.save(<String, CleanupProgress>{});

      expect(await store.load(), isEmpty);
    });
  });

  group('首页的「继续清理」列表', () {
    test('按最近更新排序，空进度不算数', () {
      final controller = CleanupProgressController(
        store: MemoryCleanupProgressStore(),
      );

      controller.recordPosition(
        scope: CleanupScopes.timeline,
        label: '时间线',
        next: MediaFixtures.photo(id: 'a'),
        processedDelta: 1,
        now: DateTime(2024, 5, 1),
      );
      controller.recordPosition(
        scope: CleanupScopes.album('trip'),
        label: '旅行',
        next: MediaFixtures.photo(id: 'b'),
        processedDelta: 1,
        now: DateTime(2024, 5, 9),
      );

      expect(
        controller.startedScopes.map((progress) => progress.label),
        <String>['旅行', '时间线'],
      );
    });
  });
}
