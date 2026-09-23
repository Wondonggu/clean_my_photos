import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/photo_repository.dart';
import 'package:clean_my_photos/ui/widgets/media_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

List<MediaItem> _photos() {
  final base = DateTime(2024, 5, 3, 12);
  return <MediaItem>[
    MediaFixtures.photo(id: 'a', createdAt: base),
    MediaFixtures.photo(id: 'b', createdAt: base.subtract(const Duration(minutes: 1))),
    MediaFixtures.photo(id: 'c', createdAt: base.subtract(const Duration(minutes: 2))),
  ];
}

/// 造一个「旅行」相册，内容就是那三张照片。
FakePhotoRepository _repository() {
  final repository = FakePhotoRepository(
    items: _photos(),
    albums: const <MediaAlbum>[
      MediaAlbum(id: 'trip', name: '旅行', assetCount: 3),
    ],
  );
  repository.albumItems['trip'] = _photos();
  return repository;
}

Future<void> _openAlbum(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.photo_album_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('旅行'));
  await tester.pumpAndSettle();
}

/// 把当前这张往上甩（标记删除）或往下甩（标记保留）。
Future<void> _swipe(WidgetTester tester, {required bool deleteIt}) async {
  await tester.fling(
    find.byKey(const Key('swipe-deck')),
    Offset(0, deleteIt ? -400 : 400),
    3000,
  );
  await tester.pumpAndSettle();
}

Future<void> _openSwipe(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('album-swipe')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('相册详情显示的是这个相册的内容，不是整个相册库', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      items: _photos(),
      albums: const <MediaAlbum>[
        MediaAlbum(id: 'trip', name: '旅行', assetCount: 1),
      ],
    );
    repository.albumItems['trip'] = <MediaItem>[_photos().first];

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openAlbum(tester);

    expect(find.byType(MediaThumbnail), findsOneWidget);
  });

  testWidgets('相册里可以滑动清理，删掉的照片立刻从网格消失', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openAlbum(tester);

    expect(find.byType(MediaThumbnail), findsNWidgets(3));

    await _openSwipe(tester);
    // 上滑标记删除、下滑标记保留；三张都过完一遍才会出现确认按钮。
    await _swipe(tester, deleteIt: true);
    await _swipe(tester, deleteIt: false);
    await _swipe(tester, deleteIt: true);

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

    // 回归用例：这一页曾经把 Future 交给 FutureBuilder，删完会重新分页拉
    // 整个相册，删掉的那张又被系统拉回来，网格看起来像没删成功。
    expect(repository.deleteCalls.single, <String>['a', 'c']);
    expect(find.byType(MediaThumbnail), findsOneWidget);
  });

  testWidgets('没清完就退出，相册头上留着进度，可以重新开始', (tester) async {
    useLargeSurface(tester);

    await tester.pumpWidget(CleanMyPhotosApp(repository: _repository()));
    await tester.pumpAndSettle();
    await _openAlbum(tester);

    await _openSwipe(tester);
    await _swipe(tester, deleteIt: true);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('已处理 1 张'), findsOneWidget);

    await tester.tap(find.text('重新开始'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已处理'), findsNothing);
  });

  testWidgets('相册进度与时间线进度各记各的，互不干扰', (tester) async {
    useLargeSurface(tester);

    await tester.pumpWidget(CleanMyPhotosApp(repository: _repository()));
    await tester.pumpAndSettle();
    await _openAlbum(tester);

    await _openSwipe(tester);
    await _swipe(tester, deleteIt: true);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 相册里清了，时间线上不该冒出进度来：一路退回首页再走时间线。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_view_day_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('上次清理到'), findsNothing);
    expect(find.textContaining('已处理'), findsNothing);
  });
}
