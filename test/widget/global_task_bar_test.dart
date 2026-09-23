import 'dart:async';

import 'package:clean_my_photos/app.dart';
import 'package:clean_my_photos/core/models/asset_fingerprint_record.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/services/thumbnail_analysis.dart';
import 'package:clean_my_photos/data/scan_cache.dart';
import 'package:clean_my_photos/state/library_controller.dart';
import 'package:clean_my_photos/state/settings_controller.dart';
import 'package:clean_my_photos/ui/widgets/global_task_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';
import '../helpers/surface.dart';

/// 让任务停在半路，界面才有「正在忙」的那一刻可看。
const Duration _slow = Duration(seconds: 3);

List<MediaItem> _library() => <MediaItem>[
      MediaFixtures.photo(id: 'a'),
      MediaFixtures.photo(id: 'b'),
      MediaFixtures.photo(id: 'c'),
    ];

/// 打开设置页，点「重新统计文件大小」。
///
/// 走的是大小扫描而不是图像分析：图像分析要起 isolate，而 flutter_test 的
/// 假时钟推不动真 isolate 的回调，测试会直接挂住。
Future<void> _startSizeScan(WidgetTester tester) async {
  await tester.tap(find.byTooltip('设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('重新统计文件大小'));
  // 扫描真正开始前要先过几道异步：申请后台时间、读缓存、挑目标。
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(() {
    // 关掉自动分析：图像分析会起 isolate，而假时钟推不动它。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();
  });

  testWidgets('任务跑起来之后，换个页面也看得见任务条', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _library())
      ..fileSizes = <String, int>{'a': 111, 'b': 222, 'c': 333}
      ..fileSizeDelay = _slow;

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();

    // 什么都不忙的时候，它连一块地方都不占。
    expect(find.byKey(const Key('global-task-bar')), findsNothing);

    await _startSizeScan(tester);

    // 此刻人在设置页上，任务条照样浮在上面——它挂在 Navigator 之上。
    expect(find.byKey(const Key('global-task-bar')), findsOneWidget);
    expect(find.textContaining('正在统计文件大小'), findsOneWidget);

    // 让扫描跑完，免得测试结束时报「还有没还回去的定时器」。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('global-task-bar')), findsNothing);
  });

  testWidgets('点取消就停下来', (tester) async {
    useLargeSurface(tester);
    final repository = FakePhotoRepository(items: _library())
      ..fileSizes = <String, int>{'a': 111, 'b': 222, 'c': 333}
      ..fileSizeDelay = _slow;

    await tester.pumpWidget(CleanMyPhotosApp(repository: repository));
    await tester.pumpAndSettle();
    await _startSizeScan(tester);
    expect(find.byKey(const Key('global-task-bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('global-task-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('global-task-bar')), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('有缓存可用时会说明省掉了多少', (tester) async {
    usePhoneSurface(tester);
    final store = MemoryRecordStore<AssetFingerprintRecord>(
      idOf: (record) => record.id,
    );
    // 上次已经算过 a 了。
    await ScanCache(store: store).append(<AssetFingerprintRecord>[
      AssetFingerprintRecord.fromSignature(
        MediaFixtures.signature(
          MediaFixtures.photo(id: 'a'),
          hash: MediaFixtures.hashAtDistance(4),
        ),
      )!,
    ]);

    final repository = FakePhotoRepository(items: _library())
      ..thumbnailBytes = MediaFixtures.tinyPng
      ..thumbnailDelay = const Duration(seconds: 30);
    final settings = SettingsController();
    await settings.load();

    final library = LibraryController(
      repository: repository,
      settings: settings,
      // 主 isolate 里算，测试才推得动。
      analyzer: const SignatureAnalyzer(useIsolates: false),
      cache: ScanCache(store: store),
    );
    await library.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<LibraryController>.value(
          value: library,
          child: const Scaffold(body: GlobalTaskBar()),
        ),
      ),
    );

    unawaited(library.runImageAnalysis());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('global-task-reused')), findsOneWidget);
    expect(find.textContaining('已复用 1 条缓存'), findsOneWidget);
    // a 是捡回来的，剩下两张要从头算——一张都没算完，所以是 1/3。
    expect(find.textContaining('1/3'), findsOneWidget);

    await library.cancelBackgroundWork();
    library.dispose();
    await tester.pump(const Duration(seconds: 40));
  });
}
