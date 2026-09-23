import 'package:clean_my_photos/core/models/asset_fingerprint_record.dart';
import 'package:clean_my_photos/core/models/file_size_record.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/services/thumbnail_analysis.dart';
import 'package:clean_my_photos/data/scan_cache.dart';
import 'package:clean_my_photos/state/library_controller.dart';
import 'package:clean_my_photos/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repository.dart';
import '../helpers/media_fixtures.dart';

/// 三张照片，id 好认。
List<MediaItem> _library() => <MediaItem>[
      MediaFixtures.photo(id: 'a'),
      MediaFixtures.photo(id: 'b'),
      MediaFixtures.photo(id: 'c'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePhotoRepository repository;
  late MemoryRecordStore<AssetFingerprintRecord> fingerprints;
  late MemoryRecordStore<FileSizeRecord> sizes;

  setUp(() {
    // 关掉自动分析：测试要自己决定什么时候跑，不然断言会和后台任务抢时间。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auto_analyze': false,
    });
    MediaFixtures.reset();

    repository = FakePhotoRepository(items: _library());
    repository.thumbnailBytes = MediaFixtures.tinyPng;
    fingerprints = MemoryRecordStore<AssetFingerprintRecord>(
      idOf: (record) => record.id,
    );
    sizes = MemoryRecordStore<FileSizeRecord>(idOf: (record) => record.id);
  });

  /// 造一个控制器。缓存用的是同一份存储，模拟「杀掉进程重开」。
  Future<LibraryController> boot() async {
    final settings = SettingsController();
    await settings.load();

    final library = LibraryController(
      repository: repository,
      settings: settings,
      // 分析放主 isolate：测试里起后台 isolate 只会让结果更难等。
      analyzer: const SignatureAnalyzer(useIsolates: false),
      cache: ScanCache(store: fingerprints),
      sizeCache: FileSizeCache(store: sizes),
    );
    await library.initialize();
    return library;
  }

  group('图像分析缓存', () {
    test('算完的结果会落盘', () async {
      final library = await boot();
      await library.runImageAnalysis();

      expect(repository.thumbnailCalls.map((call) => call.id),
          unorderedEquals(<String>['a', 'b', 'c']));
      expect(fingerprints.appendCount, greaterThan(0));
      expect((await ScanCache(store: fingerprints).read()).keys,
          unorderedEquals(<String>['a', 'b', 'c']));

      library.dispose();
    });

    test('重开一次直接复用，一张缩略图都不用再取', () async {
      final first = await boot();
      await first.runImageAnalysis();
      first.dispose();

      repository.thumbnailCalls.clear();

      final second = await boot();
      await second.runImageAnalysis();

      expect(repository.thumbnailCalls, isEmpty);
      expect(second.imageAnalysisDone, isTrue);
      expect(second.signatures, hasLength(3));

      second.dispose();
    });

    test('上次只算完一部分时，只补没算过的那几张', () async {
      // 假装上次分析到一半就被系统杀掉了。
      await ScanCache(store: fingerprints).append(<AssetFingerprintRecord>[
        AssetFingerprintRecord(
          id: 'a',
          hash: AssetFingerprintRecord.fromSignature(
            MediaFixtures.signature(
              MediaFixtures.photo(id: 'a'),
              hash: MediaFixtures.hashAtDistance(3),
            ),
          )!
              .hash,
        ),
        AssetFingerprintRecord(
          id: 'b',
          hash: AssetFingerprintRecord.fromSignature(
            MediaFixtures.signature(
              MediaFixtures.photo(id: 'b'),
              hash: MediaFixtures.hashAtDistance(5),
            ),
          )!
              .hash,
        ),
      ]);

      final library = await boot();
      await library.runImageAnalysis();

      expect(repository.thumbnailCalls.map((call) => call.id), <String>['c']);
      // 三张都在，只是两张是捡回来的。
      expect(library.signatures, hasLength(3));
      expect(library.imageAnalysisDone, isTrue);

      library.dispose();
    });

    test('复用来的指纹和重新算出来的等价', () async {
      final first = await boot();
      await first.runImageAnalysis();
      final fresh = <String, String>{
        for (final signature in first.signatures)
          if (signature.hash != null)
            signature.item.id: signature.hash!.bytes.join(','),
      };
      first.dispose();

      final second = await boot();
      await second.runImageAnalysis();

      for (final signature in second.signatures) {
        final hash = signature.hash;
        if (hash == null) continue;
        expect(hash.bytes.join(','), fresh[signature.item.id]);
      }

      second.dispose();
    });

    test('重新分析会绕过缓存重算一遍', () async {
      final library = await boot();
      await library.runImageAnalysis();

      repository.thumbnailCalls.clear();
      await library.runImageAnalysis(force: true);

      expect(repository.thumbnailCalls, hasLength(3));

      library.dispose();
    });

    test('缩略图读不到（iCloud）不会写进缓存，下次还会再试', () async {
      repository.thumbnailBytes = null;

      final first = await boot();
      await first.runImageAnalysis();
      expect(fingerprints.appendCount, 0);
      expect((await ScanCache(store: fingerprints).read()), isEmpty);
      first.dispose();

      // 照片从 iCloud 下载回来了，这次应该真的算出来并存上。
      repository.thumbnailBytes = MediaFixtures.tinyPng;
      final second = await boot();
      await second.runImageAnalysis(force: true);

      expect(second.imageAnalysisDone, isTrue);
      expect((await ScanCache(store: fingerprints).read()).keys,
          unorderedEquals(<String>['a', 'b', 'c']));
      second.dispose();
    });

    test('清空缓存之后一切从头再来', () async {
      final first = await boot();
      await first.runImageAnalysis();
      await first.clearScanCaches();
      first.dispose();

      expect(await ScanCache(store: fingerprints).read(), isEmpty);

      repository.thumbnailCalls.clear();
      final second = await boot();
      await second.runImageAnalysis();

      expect(repository.thumbnailCalls, hasLength(3));
      second.dispose();
    });
  });

  group('文件大小缓存', () {
    test('量到的大小会落盘，重开不用再逐个问系统', () async {
      repository.fileSizes = <String, int>{'a': 111, 'b': 222, 'c': 333};

      final first = await boot();
      await first.scanFileSizes();
      expect(repository.fileSizeCalls, hasLength(3));
      first.dispose();

      repository.fileSizeCalls.clear();

      final second = await boot();
      await second.scanFileSizes();

      expect(repository.fileSizeCalls, isEmpty);
      expect(
        second.items.where((item) => item.id == 'a').single.size,
        111,
      );
      second.dispose();
    });

    test('缓存过的条目不再占用本次扫描的名额', () async {
      // 只有 a 有缓存，limit 只够扫一张：这一张必须是没量过的 b，不能是 a。
      await FileSizeCache(store: sizes).append(<FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 111),
      ]);
      repository.fileSizes = <String, int>{'b': 222, 'c': 333};

      final library = await boot();
      await library.scanFileSizes(limit: 1);

      expect(repository.fileSizeCalls, <String>['b']);

      library.dispose();
    });

    test('照片被编辑过（修改时间变了）就重新量一次', () async {
      repository.items = <MediaItem>[
        MediaFixtures.photo(id: 'a', modifiedAt: DateTime(2024, 6, 1)),
      ];
      await FileSizeCache(store: sizes).append(<FileSizeRecord>[
        FileSizeRecord(id: 'a', size: 111, modifiedAt: DateTime(2024, 5, 1)),
      ]);
      repository.fileSizes = <String, int>{'a': 999};

      final library = await boot();
      await library.scanFileSizes();

      expect(repository.fileSizeCalls, <String>['a']);
      expect(library.items.single.size, 999);

      library.dispose();
    });
  });
}
