import 'dart:convert';

import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/cleanup_progress_store.dart';
import 'package:clean_my_photos/ui/widgets/media_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

/// 三个月里的五张照片，时间从新到旧。
///
/// 刻意跨三个月：按月分段之后，全落在一个月里的夹具会塌成一段，
/// 分组本身就没得测了。
List<MediaItem> _library() {
  final may = DateTime(2024, 5, 3, 12);
  final apr = DateTime(2024, 4, 20, 12);
  final mar = DateTime(2024, 3, 8, 12);
  return <MediaItem>[
    MediaFixtures.photo(id: 'a', createdAt: may),
    MediaFixtures.photo(id: 'b', createdAt: may.subtract(const Duration(days: 1))),
    MediaFixtures.photo(id: 'c', createdAt: apr),
    MediaFixtures.photo(id: 'd', createdAt: mar),
    MediaFixtures.photo(id: 'e', createdAt: mar.subtract(const Duration(days: 1))),
  ];
}

/// 12 个月、每月三张，总量超过一屏。用来验证滚动时表头不会堆在顶上。
List<MediaItem> _yearOfPhotos() {
  final items = <MediaItem>[];
  for (var month = 1; month <= 12; month++) {
    for (var i = 0; i < 3; i++) {
      items.add(
        MediaFixtures.photo(
          id: 'm$month-$i',
          createdAt: DateTime(2024, month, 10 - i, 12),
        ),
      );
    }
  }
  // 时间倒序：新的月份在前。
  return items.reversed.toList();
}

/// 往存档里塞一条整条时间线的进度，模拟「上次没清完就退出了」。
void _seedProgress({
  required String anchorId,
  DateTime? anchorDate,
  int processed = 2,
  int deleted = 1,
  int reclaimedBytes = 3 * 1024 * 1024,
  DateTime? roundStartDate,
}) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auto_analyze': false,
    PreferencesCleanupProgressStore.key: jsonEncode(<String, Object?>{
      'timeline': <String, Object?>{
        'label': '时间线',
        'anchorId': anchorId,
        'anchorDate': anchorDate?.toIso8601String(),
        'roundStartDate': roundStartDate?.toIso8601String(),
        'processed': processed,
        'deleted': deleted,
        'reclaimedBytes': reclaimedBytes,
        'updatedAt': DateTime(2024, 5, 4).toIso8601String(),
      },
    }),
  });
}

Future<void> _openTimeline(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.calendar_view_day_outlined));
  await tester.pumpAndSettle();
}

/// 点开某个月表头上的「滑动清理」。
///
/// `.last` 是最后一段的表头：Scaffold 先放 body 再放 AppBar，
/// 所以 AppBar 上那个整条时间线的入口反而排在最后。
Future<void> _openLastMonth(WidgetTester tester) async {
  await tester.tap(find.byTooltip('滑动清理这个月').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('按月分段，表头是月份而不是日期', (tester) async {
    useLargeSurface(tester);

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(find.text('2024 年 5 月'), findsOneWidget);
    expect(find.text('2024 年 4 月'), findsOneWidget);
    expect(find.text('2024 年 3 月'), findsOneWidget);
    // 5 月和 3 月各两张，4 月一张。
    expect(find.text('2 项'), findsNWidgets(2));
    expect(find.text('1 项'), findsOneWidget);
    expect(find.byType(MediaThumbnail), findsNWidgets(5));
  });

  testWidgets('表头不再吸顶，滚过去的月份不会一直堆在顶上', (tester) async {
    useLargeSurface(tester);

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _yearOfPhotos())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(find.text('2024 年 12 月'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    // 回归用例：表头曾经是 `pinned: true`，每个月都钉在视口顶部，滚过去
    // 几个月就叠成一片，把后面的内容全盖住。现在它们跟着内容一起滚走。
    expect(find.text('2024 年 12 月'), findsNothing);
    expect(find.text('2024 年 11 月'), findsNothing);
    expect(find.text('2024 年 10 月'), findsOneWidget);
  });

  testWidgets('没有进度时不显示横幅', (tester) async {
    useLargeSurface(tester);

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(find.text('继续清理'), findsNothing);
    expect(find.textContaining('上次清理到'), findsNothing);
  });

  testWidgets('有进度时顶部横幅报出上次清到哪儿了', (tester) async {
    useLargeSurface(tester);
    _seedProgress(
      anchorId: 'c',
      anchorDate: DateTime(2024, 4, 20, 12),
      roundStartDate: DateTime(2024, 5, 3, 12),
    );

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(
      find.text(
        '上次清理到 2024 年 4 月 20 日 · 已处理 2 张 · 已删除 1 项 · 释放 3 MB',
      ),
      findsOneWidget,
    );
    expect(find.text('继续清理'), findsOneWidget);
  });

  testWidgets('继续清理直接从断点那张开始，不用重看一遍', (tester) async {
    useLargeSurface(tester);
    _seedProgress(anchorId: 'c', anchorDate: DateTime(2024, 4, 20, 12));

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    await tester.tap(find.text('继续清理'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swipe-card-c')), findsOneWidget);
    expect(find.byKey(const Key('swipe-card-a')), findsNothing);
  });

  testWidgets('断点那张已经被删掉时，退回到日期水位继续', (tester) async {
    useLargeSurface(tester);
    // 锚点 c 在存档里，但这次读回来的列表里已经没有它了。
    _seedProgress(anchorId: 'c', anchorDate: DateTime(2024, 4, 20, 12));

    await tester.pumpWidget(
      CleanMyPhotosApp(
        repository: FakePhotoRepository(
          items: _library().where((item) => item.id != 'c').toList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    await tester.tap(find.text('继续清理'));
    await tester.pumpAndSettle();

    // 下一个比 4 月 20 日更老的是 d。
    expect(find.byKey(const Key('swipe-card-d')), findsOneWidget);
  });

  testWidgets('重新开始会清掉进度，横幅随之消失', (tester) async {
    useLargeSurface(tester);
    _seedProgress(anchorId: 'c', anchorDate: DateTime(2024, 4, 20, 12));

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    await tester.tap(find.text('重新开始'));
    await tester.pumpAndSettle();

    expect(find.textContaining('上次清理到'), findsNothing);
    expect(find.text('继续清理'), findsNothing);

    // 落点也回到开头。
    await tester.tap(find.byKey(const Key('timeline-swipe')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swipe-card-a')), findsOneWidget);
  });

  testWidgets('出现断点上方的新照片时给出提示，并可以从头看一遍', (tester) async {
    useLargeSurface(tester);
    _seedProgress(
      anchorId: 'c',
      anchorDate: DateTime(2024, 4, 20, 12),
      roundStartDate: DateTime(2024, 5, 3, 12),
    );

    final withNew = <MediaItem>[
      MediaFixtures.photo(id: 'brand-new', createdAt: DateTime(2024, 5, 4, 9)),
      ..._library(),
    ];

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: withNew)),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(find.textContaining('有 1 张照片是这一轮开始之后才出现的'), findsOneWidget);

    await tester.tap(find.text('从头看一遍'));
    await tester.pumpAndSettle();

    expect(find.textContaining('才出现的'), findsNothing);
    expect(find.textContaining('上次清理到'), findsNothing);
  });

  testWidgets('整条时间线上删掉的照片会立刻从网格里消失', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _library());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    expect(find.byType(MediaThumbnail), findsNWidgets(5));

    // 从 3 月那一段进滑动清理，删掉 d、e 两张。
    await _openLastMonth(tester);
    expect(find.byKey(const Key('swipe-card-d')), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      await tester.fling(
        find.byKey(const Key('swipe-deck')),
        const Offset(0, -400),
        3000,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('swipe-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('删除 2 项'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(MediaThumbnail), findsNWidgets(3));
    expect(find.text('2024 年 3 月'), findsNothing);
  });

  testWidgets('从某个月进去清理，断点记在那个月身上', (tester) async {
    useLargeSurface(tester);
    const store = PreferencesCleanupProgressStore();

    await tester.pumpWidget(
      CleanMyPhotosApp(repository: FakePhotoRepository(items: _library())),
    );
    await tester.pumpAndSettle();
    await _openTimeline(tester);

    // 3 月有 d、e 两张，过掉第一张就退出。
    await _openLastMonth(tester);
    expect(find.byKey(const Key('swipe-card-d')), findsOneWidget);
    await tester.fling(
      find.byKey(const Key('swipe-deck')),
      const Offset(0, -400),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 断点记在月份自己的作用域下，而不是整条时间线。
    final saved = await store.load();
    expect(saved.keys, contains('timeline:2024-03'));
    expect(saved['timeline:2024-03']!.anchorId, 'e');
    expect(saved['timeline:2024-03']!.processed, 1);
    expect(saved.containsKey('timeline'), isFalse);

    // 表头上看得见这个月清到哪儿了。
    expect(find.text('已处理 1'), findsOneWidget);

    // 再进去直接落在断点那张上。
    await _openLastMonth(tester);
    expect(find.byKey(const Key('swipe-card-e')), findsOneWidget);
  });
}
