import 'dart:convert';
import 'dart:io';

import 'package:clean_my_photos/core/models/asset_fingerprint_record.dart';
import 'package:clean_my_photos/core/models/file_size_record.dart';
import 'package:clean_my_photos/data/scan_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

/// 把 `path_provider` 指到一个临时目录。
///
/// 真机上这个通道由平台插件实现，测试里没人应答，`JsonlRecordStore` 会
/// 安静地退回内存——想看文件实现本身，就得自己把通道接上。
void _useTempDir(String path) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async =>
        call.method == 'getApplicationSupportDirectory' ? path : null,
  );
}

void _clearTempDirMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('通用记录存储（文件实现）', () {
    late Directory dir;
    late JsonlRecordStore<FileSizeRecord> store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('scan_cache_test');
      _useTempDir(dir.path);
      store = JsonlRecordStore<FileSizeRecord>(
        folderName: 'sizes',
        idOf: (record) => record.id,
        encode: (record) => record.toJson(),
        decode: FileSizeRecord.fromJson,
        // 默认在测试里只走内存，这里要验的就是文件实现本身。
        persist: true,
      );
    });

    tearDown(() {
      _clearTempDirMock();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    File dataFile() => File('${dir.path}/sizes.jsonl');

    test('写进去再读出来，同 id 以后写的为准', () async {
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
        const FileSizeRecord(id: 'b', size: 200),
      ]);
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 999),
      ]);

      final loaded = await store.load('s1');
      expect(loaded.keys, unorderedEquals(<String>['a', 'b']));
      expect(loaded['a']!.size, 999);
      expect(loaded['b']!.size, 200);
    });

    test('文件还不存在时安静地返回空', () async {
      expect(await store.load('s1'), isEmpty);
    });

    test('表头对不上就整份作废', () async {
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);

      // 参数变了（比如换了压缩格式版本），旧记录一律不算数。
      expect(await store.load('s2'), isEmpty);
    });

    test('换成新表头之后旧记录不会混进来', () async {
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);
      await store.append('s2', <FileSizeRecord>[
        const FileSizeRecord(id: 'b', size: 200),
      ]);

      final loaded = await store.load('s2');
      expect(loaded.keys, <String>['b']);
      expect(dataFile().readAsStringSync(), startsWith('#clean_my_photos s2\n'));
    });

    test('坏掉的行不会拖垮整份缓存', () async {
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);
      // 追加写最怕的就是写到一半断电，留半行在文件里。
      dataFile().writeAsStringSync(
        '{"id":"b","size":\n'
        'not json at all\n'
        '{"id":"c","size":300}\n',
        mode: FileMode.append,
      );

      final loaded = await store.load('s1');
      expect(loaded.keys, unorderedEquals(<String>['a', 'c']));
    });

    test('废行多到一定程度会自动压缩', () async {
      for (var i = 0; i < 5; i++) {
        await store.append('s1', <FileSizeRecord>[
          const FileSizeRecord(id: 'a', size: 100),
        ]);
      }
      expect(dataFile().readAsLinesSync().length, 6);

      // 读一次就会顺手把重复行压掉。压缩是异步的，给它一轮事件循环。
      await store.load('s1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dataFile().readAsLinesSync().length, 2);
      expect((await store.load('s1'))['a']!.size, 100);
    });

    test('清空之后文件没了，读回来也是空的', () async {
      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);
      await store.clear();
      expect(dataFile().existsSync(), isFalse);
      expect(await store.load('s1'), isEmpty);
    });
  });

  group('拿不到平台目录时退到内存', () {
    test('没有插件实现也不报错，只是这次不落盘', () async {
      // 真机上偶尔也会遇到（比如还没注册插件），不能因此让扫描挂掉。
      _clearTempDirMock();
      final store = JsonlRecordStore<FileSizeRecord>(
        folderName: 'sizes',
        idOf: (record) => record.id,
        encode: (record) => record.toJson(),
        decode: FileSizeRecord.fromJson,
        persist: true,
      );

      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);
      expect((await store.load('s1'))['a']!.size, 100);
    });

    test('测试进程里默认不碰磁盘', () async {
      // flutter_test 用的是假时钟，path_provider 的通道回复永远不会到达，
      // 真去等就会把整个扫描挂死。所以默认只走内存。
      final store = JsonlRecordStore<FileSizeRecord>(
        folderName: 'sizes',
        idOf: (record) => record.id,
        encode: (record) => record.toJson(),
        decode: FileSizeRecord.fromJson,
      );

      await store.append('s1', <FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 100),
      ]);
      expect((await store.load('s1'))['a']!.size, 100);
    });
  });

  group('指纹缓存', () {
    late MemoryRecordStore<AssetFingerprintRecord> store;
    late ScanCache cache;

    setUp(() {
      store = MemoryRecordStore<AssetFingerprintRecord>(
        idOf: (record) => record.id,
      );
      cache = ScanCache(store: store);
    });

    test('算好的指纹能原样贴回条目上', () async {
      final item = MediaFixtures.photo(id: 'a');
      final hash = MediaFixtures.hashAtDistance(7);

      await cache.append(<AssetFingerprintRecord>[
        AssetFingerprintRecord.fromSignature(
          MediaFixtures.signature(item, hash: hash, sharpness: 3.5),
        )!,
      ]);

      final record = (await cache.read())['a']!;
      final restored = record.attachTo(item);
      expect(restored.hash, hash);
      expect(restored.sharpness, 3.5);
      expect(restored.isReliable, isTrue);
      expect(restored.failure, isNull);
    });

    test('iCloud 占位符这种失败不落盘，下次还得再试一次', () async {
      final item = MediaFixtures.photo(id: 'a');
      // 连记录都不该造出来：写进去的话这张照片就永远回不到重复/模糊判定里了。
      expect(
        AssetFingerprintRecord.fromSignature(
          MediaFixtures.signature(item, failure: '缩略图不可用'),
        ),
        isNull,
      );
      // 就算有人绕过 fromSignature 直接构造，append 这关也要挡住。
      await cache.append(<AssetFingerprintRecord>[
        const AssetFingerprintRecord(id: 'a', hash: '', failure: '缩略图不可用'),
      ]);

      expect(await cache.read(), isEmpty);
    });

    test('解码不了这种失败会落盘，不必每次重试', () async {
      final item = MediaFixtures.photo(id: 'a');

      await cache.append(<AssetFingerprintRecord>[
        AssetFingerprintRecord.fromSignature(
          MediaFixtures.signature(item, failure: '图片解码失败'),
        )!,
      ]);

      final restored = (await cache.read())['a']!.attachTo(item);
      expect(restored.failure, '图片解码失败');
      expect(restored.hash, isNull);
    });

    test('指纹损坏时贴回去是「失败」，而不是一条假指纹', () async {
      final item = MediaFixtures.photo(id: 'a');
      const broken =
          AssetFingerprintRecord(id: 'a', hash: '这不是 base64 的长度');

      final restored = broken.attachTo(item);
      expect(restored.hash, isNull);
      expect(restored.failure, isNotNull);
    });

    test('指纹键只认算法版本和缩略图参数，跟模糊阈值无关', () {
      expect(defaultFingerprintKey(), 'v1-t256-q75');
      // 阈值只影响「算不算模糊」的结论，缓存里存的是客观量，
      // 拖一次滑杆不该让整份缓存作废。
      expect(
        defaultFingerprintKey(size: 256, quality: 75),
        defaultFingerprintKey(size: 256, quality: 75),
      );
      expect(
        defaultFingerprintKey(size: 512, quality: 75),
        isNot(defaultFingerprintKey(size: 256, quality: 75)),
      );
      expect(ScanCache(store: store).key, 'v1-t256-q75');
    });

    test('落盘的是 base64 的短哈希，不是一堆数字', () async {
      final item = MediaFixtures.photo(id: 'a');
      await cache.append(<AssetFingerprintRecord>[
        AssetFingerprintRecord.fromSignature(
          MediaFixtures.signature(item, hash: MediaFixtures.zeroHash()),
        )!,
      ]);

      final json = jsonEncode((await cache.read())['a']!.toJson());
      expect(json, contains('"hash":"AAAAAAAAAAA="'));
    });
  });

  group('文件大小缓存', () {
    test('修改时间变了就不作数（照片被编辑过，文件重写过）', () {
      final edited = MediaFixtures.photo(
        id: 'a',
        modifiedAt: DateTime(2024, 5, 2),
      );
      final record = FileSizeRecord(
        id: 'a',
        size: 300,
        modifiedAt: DateTime(2024, 5, 1),
      );

      expect(record.matches(edited), isFalse);
    });

    test('修改时间没变就一直作数', () {
      final item = MediaFixtures.photo(
        id: 'a',
        modifiedAt: DateTime(2024, 5, 1),
      );
      final record = FileSizeRecord(
        id: 'a',
        size: 300,
        modifiedAt: DateTime(2024, 5, 1),
      );

      expect(record.matches(item), isTrue);
    });

    test('两边有一边拿不到修改时间时选择相信缓存', () {
      // 总比每次都重新问一遍强，而且 iOS 上绝大多数照片都带着修改时间。
      final withTime = MediaFixtures.photo(
        id: 'a',
        modifiedAt: DateTime(2024, 5, 1),
      );
      final withoutTime = MediaFixtures.photo(id: 'a');

      expect(const FileSizeRecord(id: 'a', size: 300).matches(withTime), isTrue);
      expect(
        FileSizeRecord(id: 'a', size: 300, modifiedAt: DateTime(2024, 5, 1))
            .matches(withoutTime),
        isTrue,
      );
    });

    test('大小为 0 的记录不落盘，也不作数', () async {
      final store = MemoryRecordStore<FileSizeRecord>(
        idOf: (record) => record.id,
      );
      final cache = FileSizeCache(store: store);

      await cache.append(<FileSizeRecord>[
        const FileSizeRecord(id: 'a', size: 0),
        const FileSizeRecord(id: 'b', size: 500),
      ]);

      expect((await cache.read()).keys, <String>['b']);
      expect(
        const FileSizeRecord(id: 'a', size: 0).matches(MediaFixtures.photo(id: 'a')),
        isFalse,
      );
    });

    test('大小缓存的键只跟着格式版本走', () {
      expect(defaultFileSizeKey(), 's1');
    });
  });

  group('记录序列化', () {
    test('文件大小往返', () {
      final record = FileSizeRecord(
        id: 'a',
        size: 300,
        modifiedAt: DateTime(2024, 5, 1, 12, 30),
      );
      final restored = FileSizeRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())),
      );
      expect(restored!.id, 'a');
      expect(restored.size, 300);
      expect(restored.modifiedAt, DateTime(2024, 5, 1, 12, 30));
    });

    test('字段缺失或类型不对时丢掉这一条', () {
      expect(FileSizeRecord.fromJson(null), isNull);
      expect(FileSizeRecord.fromJson(<String, Object?>{'id': 'a'}), isNull);
      expect(
        FileSizeRecord.fromJson(<String, Object?>{'id': 'a', 'size': -1}),
        isNull,
      );
      expect(
        FileSizeRecord.fromJson(<String, Object?>{'id': '', 'size': 10}),
        isNull,
      );
      expect(
        FileSizeRecord.fromJson(<String, Object?>{'id': 'a', 'size': 10})
            ?.modifiedAt,
        isNull,
      );
    });

    test('指纹往返，不可信的标记也带得回来', () {
      final record = AssetFingerprintRecord(
        id: 'a',
        hash: base64Encode(List<int>.filled(8, 0xAA)),
        sharpness: 1.25,
        isReliable: false,
      );
      final restored = AssetFingerprintRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())),
      );

      expect(restored!.hash, record.hash);
      expect(restored.sharpness, 1.25);
      expect(restored.isReliable, isFalse);
      expect(restored.attachTo(MediaFixtures.photo(id: 'a')).isReliable, isFalse);
    });
  });
}
