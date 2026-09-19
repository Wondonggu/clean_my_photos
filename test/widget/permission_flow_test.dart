import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/data/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

void main() {
  setUp(() {
    // 关掉自动分析：测试里不需要后台任务，也避免进度条一直转导致
    // `pumpAndSettle` 等不到静止。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('尚未授权时展示引导页，点「允许访问」会请求权限', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      items: <MediaItem>[MediaFixtures.photo()],
      permission:
          const LibraryPermission(LibraryPermissionStatus.notDetermined),
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('允许访问你的照片'), findsOneWidget);
    expect(repository.requestPermissionCalls, 0);

    await tester.tap(find.text('允许访问'));
    await tester.pumpAndSettle();

    expect(repository.requestPermissionCalls, 1);
  });

  testWidgets('被拒绝时引导用户去系统设置', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      permission: const LibraryPermission(LibraryPermissionStatus.denied),
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('需要相册访问权限'), findsOneWidget);
    expect(find.textContaining('已拒绝访问'), findsOneWidget);

    await tester.tap(find.text('打开系统设置'));
    await tester.pumpAndSettle();

    expect(repository.openSettingsCalls, 1);
  });

  testWidgets('已授权时直接进入首页', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      items: <MediaItem>[MediaFixtures.photo()],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('相册清理'), findsOneWidget);
    expect(find.text('清理建议'), findsOneWidget);
    expect(repository.loadLibraryCalls, 1);
  });

  testWidgets('有限授权时提示结果可能不完整', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(
      items: <MediaItem>[MediaFixtures.photo()],
      permission: const LibraryPermission(LibraryPermissionStatus.limited),
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('只允许访问部分照片'), findsOneWidget);
  });
}
