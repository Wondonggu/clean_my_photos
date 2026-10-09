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

/// 一本「旅行」相册，三张照片。
List<MediaItem> _photos() {
  final base = DateTime(2024, 5, 3, 12);
  return <MediaItem>[
    MediaFixtures.photo(id: 'a', createdAt: base),
    MediaFixtures.photo(id: 'b', createdAt: base.subtract(const Duration(minutes: 1))),
    MediaFixtures.photo(id: 'c', createdAt: base.subtract(const Duration(minutes: 2))),
  ];
}

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

/// 从首页一路点进相册里的全屏查看器。
Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.photo_album_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('旅行'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MediaThumbnail).first);
  await tester.pumpAndSettle();
}

/// 点一下照片本身（不是按钮）。
///
/// 查看器同时挂着双击缩放，单击得等 300ms 的双击判定窗口过去才算数。只
/// `pumpAndSettle()` 不够：它只把已经排队的帧泵完，那个还在计时的 Timer 不会
/// 因此走到头，`onTap` 就一直不触发。所以这里显式把时间推过去。
Future<void> _tapPhoto(WidgetTester tester) async {
  await tester.tap(find.byType(InteractiveViewer));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// 点开确认弹窗里那颗「删除 N 项」。
Future<void> _confirmDelete(WidgetTester tester, int count) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('删除 $count 项'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('从相册浏览时标记的照片，退出时统一确认删除', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    // 一进来就说清楚「这次浏览是会删东西的」。
    expect(find.byKey(const Key('viewer-cleanup-hint')), findsOneWidget);
    expect(find.textContaining('点照片即可标记为删除'), findsOneWidget);

    await tester.tap(find.text('标记为删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('退出时会提示删除已标记的 1 项'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 先弹应用内的确认，不是直接删。
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('确认删除'), findsOneWidget);
    expect(repository.deleteCalls, isEmpty);

    await _confirmDelete(tester, 1);

    expect(repository.deleteCalls, hasLength(1));
    expect(repository.deleteCalls.single, <String>['a']);
    // 确认完就顺势退出查看器，回到相册。
    expect(find.text('1 / 3'), findsNothing);
    expect(find.byType(MediaThumbnail), findsNWidgets(2));
  });

  testWidgets('点照片本身也能标记，退出时一样会问', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    await _tapPhoto(tester);

    expect(find.textContaining('退出时会提示删除已标记的 1 项'), findsOneWidget);
    expect(find.text('保留这一张'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _confirmDelete(tester, 1);

    expect(repository.deleteCalls.single, <String>['a']);
  });

  testWidgets('在确认弹窗里取消就留在原地，标记不丢', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    await tester.tap(find.text('标记为删除'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 没删、也没走，标记还在。
    expect(repository.deleteCalls, isEmpty);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.textContaining('退出时会提示删除已标记的 1 项'), findsOneWidget);

    // 再按一次返回，重新问一遍。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('系统一个都没删成时也照常退出，只如实反馈', (tester) async {
    useLargeSurface(tester);
    final repository = _repository()..failToDelete.add('a');

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    await tester.tap(find.text('标记为删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _confirmDelete(tester, 1);

    // 用户已经明确表达了要走，不该把他扣在页面上反复重弹。
    expect(find.textContaining('没有删除任何项目'), findsOneWidget);
    expect(find.text('1 / 3'), findsNothing);
    // 没删掉，所以相册里还是三张。
    expect(find.byType(MediaThumbnail), findsNWidgets(3));
  });

  testWidgets('什么都没标记时直接退出，不多问一次', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('1 / 3'), findsNothing);
    expect(repository.deleteCalls, isEmpty);
    expect(find.byType(MediaThumbnail), findsNWidgets(3));
  });
}
