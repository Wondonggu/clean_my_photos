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
    MediaFixtures.photo(id: 'a', createdAt: base, width: 4032, height: 3024),
    MediaFixtures.photo(
      id: 'b',
      createdAt: base.subtract(const Duration(minutes: 1)),
      width: 4032,
      height: 3024,
    ),
  ];
}

FakePhotoRepository _repository() {
  final repository = FakePhotoRepository(
    items: _photos(),
    albums: const <MediaAlbum>[
      MediaAlbum(id: 'trip', name: '旅行', assetCount: 2),
    ],
  );
  repository.albumItems['trip'] = _photos();
  return repository;
}

/// 从首页一路点进全屏查看器。
Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.photo_album_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('旅行'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MediaThumbnail).first);
  await tester.pumpAndSettle();
}

/// 双击照片。两次点击必须落在 300ms 的判定窗口里。
Future<void> _doubleTap(WidgetTester tester) async {
  final target = find.byType(InteractiveViewer);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _swipeToNext(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('不放大就不去取高清图，双击放大才取', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    // 预览用的缩略图长边只有 1024，进页面就预取高清图太亏。
    expect(repository.fullImageCalls, isEmpty);

    await _doubleTap(tester);

    expect(repository.fullImageCalls, hasLength(1));
    expect(repository.fullImageCalls.single.id, 'a');
    expect(repository.fullImageCalls.single.size, 3072);
  });

  testWidgets('翻到下一张会重新取高清图，不会拿上一张的凑数', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);
    await _doubleTap(tester);

    await _swipeToNext(tester);
    await _doubleTap(tester);

    expect(repository.fullImageCalls.map((call) => call.id), <String>['a', 'b']);
  });

  testWidgets('所在相册给出摘要，多本时可以展开逐条看', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation(
      assetId: 'a',
      memberships: <AssetAlbumMembership>[
        AssetAlbumMembership(
          albumId: 'trip',
          name: '旅行',
          kind: AssetAlbumKind.user,
          index: 3,
          assetCount: 12,
        ),
        AssetAlbumMembership(
          albumId: 'recent',
          name: '最近项目',
          kind: AssetAlbumKind.smart,
          index: 1234,
        ),
      ],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(
      find.text('所在相册：旅行 第 3 张、最近项目 第 1234 张'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('viewer-album-trip')), findsNothing);

    await tester.tap(find.byKey(const Key('viewer-location-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('旅行 · 相册 · 第 3 / 12 张'), findsOneWidget);
    expect(find.text('最近项目 · 智能相册 · 第 1234 张'), findsOneWidget);
  });

  testWidgets('只属于一本相册时不啰嗦，直接一行说完', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation(
      assetId: 'a',
      memberships: <AssetAlbumMembership>[
        AssetAlbumMembership(
          albumId: 'trip',
          name: '旅行',
          kind: AssetAlbumKind.user,
        ),
      ],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(find.text('所在相册：旅行'), findsOneWidget);
    expect(find.byKey(const Key('viewer-location-toggle')), findsNothing);
  });

  testWidgets('平台不支持反查时说明白，而不是假装没有相册', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation.unsupported('a');

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(find.text('所在相册：当前平台不支持'), findsOneWidget);
  });

  testWidgets('查得到但一个相册都没有时，说的是没有而不是失败', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation(assetId: 'a');

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(find.text('所在相册：不在任何相册里'), findsOneWidget);
  });

  testWidgets('有限访问时提示范围不完整', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation(
      assetId: 'a',
      isLimited: true,
      memberships: <AssetAlbumMembership>[
        AssetAlbumMembership(
          albumId: 'trip',
          name: '旅行',
          kind: AssetAlbumKind.user,
        ),
      ],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(
      find.textContaining('只显示已授权范围内的相册'),
      findsOneWidget,
    );
  });

  testWidgets('翻页后重新查这一张的归属', (tester) async {
    useLargeSurface(tester);
    final repository = _repository();
    repository.locations['a'] = const AssetLocation(
      assetId: 'a',
      memberships: <AssetAlbumMembership>[
        AssetAlbumMembership(
          albumId: 'trip',
          name: '旅行',
          kind: AssetAlbumKind.user,
        ),
      ],
    );
    repository.locations['b'] = const AssetLocation(
      assetId: 'b',
      memberships: <AssetAlbumMembership>[
        AssetAlbumMembership(
          albumId: 'work',
          name: '工作',
          kind: AssetAlbumKind.user,
        ),
      ],
    );

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _openViewer(tester);

    expect(find.text('所在相册：旅行'), findsOneWidget);

    await _swipeToNext(tester);

    expect(find.text('所在相册：工作'), findsOneWidget);
  });
}
