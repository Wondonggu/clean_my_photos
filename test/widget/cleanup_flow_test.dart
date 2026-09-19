import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/ui/widgets/media_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

/// 造 3 张老截图 + 1 张普通照片。
List<MediaItem> _libraryWithScreenshots() {
  final old = DateTime(2020, 3, 1, 10);
  return <MediaItem>[
    MediaFixtures.photo(id: 'shot-1', createdAt: old, isScreenshot: true),
    MediaFixtures.photo(id: 'shot-2', createdAt: old, isScreenshot: true),
    MediaFixtures.photo(id: 'shot-3', createdAt: old, isScreenshot: true),
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

  testWidgets('首页按分类列出可清理内容', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _libraryWithScreenshots());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('截图'), findsOneWidget);
    expect(find.textContaining('3 项 · 可释放'), findsOneWidget);
    // 重复照片要等图像分析，此时不该报出数量。
    expect(find.text('等待分析…'), findsNWidgets(3));
  });

  testWidgets('复核页默认全选，确认后调用系统删除', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _libraryWithScreenshots());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();

    expect(find.text('已选 3 项'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 二次确认：先看清楚会释放多少空间。
    expect(find.text('确认删除'), findsOneWidget);
    expect(find.text('9 MB'), findsOneWidget);

    await tester.tap(find.text('删除 3 项'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, hasLength(1));
    expect(repository.deleteCalls.single..sort(), <String>['shot-1', 'shot-2', 'shot-3']);
    expect(find.text('已删除 3 项'), findsOneWidget);
    expect(repository.items, hasLength(1));
    expect(repository.items.single.id, 'pic-1');
  });

  testWidgets('取消勾选后不会提交给系统', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _libraryWithScreenshots());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();

    expect(find.text('已选 3 项'), findsNothing);
    // 一个都没选时底部操作条收起。
    expect(find.text('删除'), findsNothing);
    expect(repository.deleteCalls, isEmpty);
  });

  testWidgets('收藏的截图不会被勾选', (tester) async {
    useLargeSurface(tester);
    final items = _libraryWithScreenshots();
    items[0] = MediaFixtures.photo(
      id: 'shot-1',
      createdAt: DateTime(2020, 3, 1, 10),
      isScreenshot: true,
      isFavorite: true,
    );
    final repository = FakePhotoRepository(items: items);

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除 2 项'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls.single..sort(), <String>['shot-2', 'shot-3']);
    expect(
      repository.items.map((item) => item.id),
      contains('shot-1'),
    );
  });

  testWidgets('系统拒绝删除时如实反馈，且不移除条目', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _libraryWithScreenshots())
      ..failToDelete.addAll(<String>['shot-1', 'shot-2', 'shot-3']);

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除 3 项'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有删除任何项目'), findsOneWidget);
    expect(repository.items, hasLength(4));
  });

  testWidgets('查看器可以就地切换是否删除', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _libraryWithScreenshots());

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();

    // 长按第一格进查看器。
    //
    // 未选中的格子上盖了一层半透明遮罩，它会吸收命中测试，所以
    // `longPress` 报「没点到目标控件」是正常的——按下位置仍然落在
    // 单元格自己的手势识别器上。
    await tester.longPress(
      find.byType(MediaThumbnail).first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.text('保留这一张'));
    await tester.pumpAndSettle();
    expect(find.text('标记为删除'), findsOneWidget);

    // 回到复核页时勾选状态是同步的。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
  });
}
