import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/photo_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

List<MediaItem> _library() {
  final old = DateTime(2020, 3, 1, 10);
  return <MediaItem>[
    MediaFixtures.photo(id: 'shot-1', createdAt: old, isScreenshot: true),
    MediaFixtures.photo(id: 'pic-1', createdAt: old),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('设置页切换相似度档位后会写入本地存储', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _library());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('相似照片判定'), findsOneWidget);

    await tester.tap(find.text('严格'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('similarity_preset'), 'strict');
  });

  testWidgets('设置页展示大文件门槛的当前值', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _library());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // 默认 100 MB / 8 MB，被选中的那个 chip 就是当前值。
    expect(find.widgetWithText(ChoiceChip, '100 MB'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '8 MB'), findsOneWidget);

    final selected = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '100 MB'),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('相册页列出用户相册并可以浏览内容', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      items: _library(),
      albums: const <MediaAlbum>[
        MediaAlbum(id: 'all', name: '最近项目', assetCount: 2, isAll: true),
        MediaAlbum(id: 'a1', name: '旅行', assetCount: 1),
      ],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.photo_album_outlined));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('最近项目'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('2 项'), findsOneWidget);

    await tester.tap(find.text('旅行'));
    await tester.pump();
    await tester.pumpAndSettle();

    // AppBar 标题 + 内容网格。
    expect(find.text('旅行'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });
}
