import 'package:clean_my_photos/core/models/cleanup_progress.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/cleanup_progress_store.dart';
import 'package:clean_my_photos/data/thumbnail_cache.dart';
import 'package:clean_my_photos/state/cleanup_progress_controller.dart';
import 'package:clean_my_photos/state/library_controller.dart';
import 'package:clean_my_photos/state/settings_controller.dart';
import 'package:clean_my_photos/ui/swipe/swipe_clean_page.dart';
import 'package:clean_my_photos/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

/// 三张带稳定 id 的照片，方便断言「现在轮到哪一张」。
List<MediaItem> _threePhotos() {
  final base = DateTime(2024, 5, 1, 12);
  return <MediaItem>[
    MediaFixtures.photo(id: 'a', createdAt: base),
    MediaFixtures.photo(id: 'b', createdAt: base.add(const Duration(minutes: 1))),
    MediaFixtures.photo(id: 'c', createdAt: base.add(const Duration(minutes: 2))),
  ];
}

/// 单独把滑动清理页挂起来跑。
///
/// 不走首页那条路：手势判定按屏幕宽高的比例算，从首页点进去还得先绕开
/// 分类页，画布也未必是手机尺寸，测出来的阈值不是真实手感。
Future<void> _pumpSwipe(
  WidgetTester tester, {
  required FakePhotoRepository repository,
  required List<MediaItem> items,
  int startIndex = 0,
  String? scope,
  ValueChanged<Set<String>>? onDeleted,
  MemoryCleanupProgressStore? store,
}) async {
  final settings = SettingsController();
  await settings.load();
  final library = LibraryController(repository: repository, settings: settings);
  final progress = CleanupProgressController(
    store: store ?? MemoryCleanupProgressStore(),
  );
  await progress.load();
  addTearDown(library.dispose);
  addTearDown(progress.dispose);
  addTearDown(settings.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ThumbnailCache>.value(value: ThumbnailCache(repository)),
        ChangeNotifierProvider<CleanupProgressController>.value(value: progress),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<LibraryController>.value(value: library),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: SwipeCleanPage(
          title: '测试',
          items: items,
          startIndex: startIndex,
          scope: scope,
          onDeleted: onDeleted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _card(String id) => find.byKey(Key('swipe-card-$id'));

/// 牌堆本身，拖动的落点。
Finder get _deck => find.byKey(const Key('swipe-deck'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('提示常驻，告诉用户三个方向分别是什么', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    expect(find.text('上滑删除 · 下滑保留 · 左滑撤销'), findsOneWidget);
  });

  testWidgets('上滑删除：每一张都记进待删列表，滑完进入结束页', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    for (final id in <String>['a', 'b', 'c']) {
      expect(_card(id), findsOneWidget, reason: '轮到 $id 了');
      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
    }

    expect(find.text('标记了 3 项'), findsOneWidget);
  });

  testWidgets('下滑保留：什么都不记，滑完只剩「都留下了」', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    for (final id in <String>['a', 'b', 'c']) {
      expect(_card(id), findsOneWidget);
      await tester.fling(_deck, const Offset(0, 200), 3000);
      await tester.pumpAndSettle();
    }

    expect(find.text('这些照片都留下了'), findsOneWidget);
    expect(find.textContaining('标记了'), findsNothing);
  });

  testWidgets('左滑撤销：把上一张请回来', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    await tester.fling(_deck, const Offset(0, -200), 3000);
    await tester.pumpAndSettle();
    expect(_card('a'), findsNothing);
    expect(_card('b'), findsOneWidget);

    await tester.fling(_deck, const Offset(-250, 0), 3000);
    await tester.pumpAndSettle();

    expect(_card('a'), findsOneWidget);
    expect(_card('b'), findsNothing);
  });

  testWidgets('右滑没有对应操作，甩得再快也弹回原样', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    await tester.fling(_deck, const Offset(250, 0), 4000);
    await tester.pumpAndSettle();

    expect(_card('a'), findsOneWidget);
    expect(_card('b'), findsNothing);
  });

  testWidgets('滑得不够远就弹回，不算数', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    // 拖满 1 秒：位移够看的，但速度远低于判定线，测的是「距离」这一条。
    await tester.timedDrag(
      _deck,
      const Offset(0, -60),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(_card('a'), findsOneWidget);
  });

  testWidgets('慢慢滑够距离也判定，不必甩得快', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    await tester.timedDrag(
      _deck,
      const Offset(0, -400),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(_card('a'), findsNothing);
    expect(_card('b'), findsOneWidget);
  });

  testWidgets('拖动途中就亮出徽标，说明松手会发生什么', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    final gesture = await tester.startGesture(tester.getCenter(_deck));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();

    expect(find.byKey(const Key('verdict-delete')), findsOneWidget);

    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();

    expect(find.byKey(const Key('verdict-delete')), findsNothing);
    expect(find.byKey(const Key('verdict-keep')), findsOneWidget);

    // 松手时还没滑够，弹回原位。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_card('a'), findsOneWidget);
  });

  testWidgets('左滑途中亮的是撤销徽标', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    final gesture = await tester.startGesture(tester.getCenter(_deck));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();

    expect(find.byKey(const Key('verdict-undo')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('按钮与手势等价：点删除等同于上滑', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
    );

    await tester.tap(find.byKey(const Key('swipe-action-delete')));
    await tester.pumpAndSettle();

    expect(_card('a'), findsNothing);
    expect(_card('b'), findsOneWidget);

    await tester.tap(find.byKey(const Key('swipe-action-undo')));
    await tester.pumpAndSettle();

    expect(_card('a'), findsOneWidget);
  });

  testWidgets('确认后交给系统删除，并把真正删掉的 id 回调出去', (tester) async {
    usePhoneSurface(tester);
    final repository = FakePhotoRepository();
    final reported = <Set<String>>[];

    await _pumpSwipe(
      tester,
      repository: repository,
      items: _threePhotos(),
      onDeleted: reported.add,
    );

    for (var i = 0; i < 3; i++) {
      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('swipe-delete-all')));
    await tester.pumpAndSettle();

    // 确认弹窗里的按钮和结束页上的按钮文案一样，得限定在弹窗里点。
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('删除 3 项'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, hasLength(1));
    expect(repository.deleteCalls.single..sort(), <String>['a', 'b', 'c']);
    expect(reported, hasLength(1));
    expect(reported.single, <String>{'a', 'b', 'c'});
  });

  testWidgets('系统只删掉一部分时，留下来的仍然在牌堆里', (tester) async {
    usePhoneSurface(tester);
    final repository = FakePhotoRepository()
      ..failToDelete.addAll(<String>['b', 'c']);
    final reported = <Set<String>>[];

    await _pumpSwipe(
      tester,
      repository: repository,
      items: _threePhotos(),
      onDeleted: reported.add,
    );

    for (var i = 0; i < 3; i++) {
      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('swipe-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('删除 3 项'),
      ),
    );
    await tester.pumpAndSettle();

    // 只有 a 真的删掉了，b、c 还在——不能按「标记过的都删了」来清理。
    expect(reported.single, <String>{'a'});
    expect(find.textContaining('2 项未能删除'), findsOneWidget);
  });

  testWidgets('带断点进来时直接落在那一张上', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
      startIndex: 2,
    );

    expect(_card('c'), findsOneWidget);
    expect(_card('a'), findsNothing);
  });

  testWidgets('断点已经在末尾时直接进入结束页', (tester) async {
    usePhoneSurface(tester);

    await _pumpSwipe(
      tester,
      repository: FakePhotoRepository(),
      items: _threePhotos(),
      startIndex: 3,
    );

    expect(find.text('这些照片都留下了'), findsOneWidget);
  });

  group('清理进度', () {
    testWidgets('滑一张就记一次，离开时把落点留在盘上', (tester) async {
      usePhoneSurface(tester);
      final store = MemoryCleanupProgressStore();

      await _pumpSwipe(
        tester,
        repository: FakePhotoRepository(),
        items: _threePhotos(),
        scope: CleanupScopes.timeline,
        store: store,
      );

      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();

      // 换掉页面，走到 dispose。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final saved = (await store.load())[CleanupScopes.timeline]!;
      expect(saved.anchorId, 'b');
      expect(saved.processed, 1);
    });

    testWidgets('撤销会把落点也退回去', (tester) async {
      usePhoneSurface(tester);
      final store = MemoryCleanupProgressStore();

      await _pumpSwipe(
        tester,
        repository: FakePhotoRepository(),
        items: _threePhotos(),
        scope: CleanupScopes.timeline,
        store: store,
      );

      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
      await tester.fling(_deck, const Offset(-250, 0), 3000);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final saved = (await store.load())[CleanupScopes.timeline]!;
      expect(saved.anchorId, 'a');
      expect(saved.processed, 0);
    });

    testWidgets('看完整轮之后进度被清掉，下次进来从头开始', (tester) async {
      usePhoneSurface(tester);
      final store = MemoryCleanupProgressStore();

      await _pumpSwipe(
        tester,
        repository: FakePhotoRepository(),
        items: _threePhotos(),
        scope: CleanupScopes.timeline,
        store: store,
      );

      for (var i = 0; i < 3; i++) {
        await tester.fling(_deck, const Offset(0, -200), 3000);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(await store.load(), isEmpty);
    });

    testWidgets('删除成功后累计已删除与释放的空间', (tester) async {
      usePhoneSurface(tester);
      final store = MemoryCleanupProgressStore();

      await _pumpSwipe(
        tester,
        repository: FakePhotoRepository(),
        items: _threePhotos(),
        scope: CleanupScopes.timeline,
        store: store,
      );

      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
      await tester.fling(_deck, const Offset(0, 200), 3000);
      await tester.pumpAndSettle();
      await tester.fling(_deck, const Offset(0, 200), 3000);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('swipe-delete-all')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('删除 1 项'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final saved = (await store.load())[CleanupScopes.timeline]!;
      expect(saved.deleted, 1);
      expect(saved.reclaimedBytes, 3 * 1024 * 1024);
      // 删完之后牌堆回到剩下的第一张上，b、c 都还在。
      expect(saved.anchorId, 'b');
    });

    testWidgets('没给作用域时完全不碰进度', (tester) async {
      usePhoneSurface(tester);
      final store = MemoryCleanupProgressStore();

      await _pumpSwipe(
        tester,
        repository: FakePhotoRepository(),
        items: _threePhotos(),
        store: store,
      );

      await tester.fling(_deck, const Offset(0, -200), 3000);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(store.saveCount, 0);
    });
  });
}
