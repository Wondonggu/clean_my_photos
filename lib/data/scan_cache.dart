import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../core/models/asset_fingerprint_record.dart';
import '../core/models/file_size_record.dart';

// ---------------------------------------------------------------- 存储抽象

/// 一份按 id 去重的记录集合。
///
/// [key] 是这份数据「按什么参数算出来的」：参数一变，旧记录就该整份作废，
/// 而不是逐条判断新旧。指纹用算法版本 + 缩略图参数做键，大小用格式版本做键。
abstract class RecordStore<T> {
  RecordStore({required this.idOf});

  /// 记录在文件里跟在内存里的主键。
  final String Function(T record) idOf;

  Future<Map<String, T>> load(String key);

  Future<void> append(String key, Iterable<T> records);

  Future<void> clear();
}

/// 纯内存实现：测试用，也是平台目录拿不到时的兜底。
class MemoryRecordStore<T> extends RecordStore<T> {
  MemoryRecordStore({required super.idOf});

  final Map<String, Map<String, T>> _byKey = <String, Map<String, T>>{};

  /// 追加过多少次。测试用来断言「确实落了一批」。
  int appendCount = 0;

  @override
  Future<Map<String, T>> load(String key) async {
    final bucket = _byKey[key];
    // 返回副本：调用方改了不该影响到「落盘」的那份。
    return bucket == null ? <String, T>{} : Map<String, T>.of(bucket);
  }

  @override
  Future<void> append(String key, Iterable<T> records) async {
    appendCount++;
    final bucket = _byKey.putIfAbsent(key, () => <String, T>{});
    for (final record in records) {
      bucket[idOf(record)] = record;
    }
  }

  @override
  Future<void> clear() async {
    _byKey.clear();
  }
}

// ------------------------------------------------------------------ 文件实现

/// 一行一条 JSON 的追加式存储。
///
/// 选 JSONL 而不是一整个 JSON 对象，是因为它**可以只追加**：分析是一批一批
/// 出结果的，每批都重写整份文件的话，三万个条目每批要写几 MB，
/// 而追加只要写这一批。
///
/// 首行是表头，写着这份数据是按什么参数算出来的。参数一变整份作废——
/// 比逐条判断便宜，也不会留下半新半旧的混合体。
class JsonlRecordStore<T> extends RecordStore<T> {
  JsonlRecordStore({
    required this.folderName,
    required super.idOf,
    required this.encode,
    required this.decode,
    this.persist,
  });

  final String folderName;

  /// 是否真的往磁盘上写。null 表示自动判断（见 [_path]）。
  ///
  /// 测试里想验证文件实现本身时才需要显式传 true。
  final bool? persist;

  final Map<String, Object?> Function(T record) encode;

  final T? Function(Object? json) decode;

  /// 平台目录拿不到时（`flutter test`、Linux 桌面）自动退到内存。
  ///
  /// 这是让现有界面测试**一行都不用改**的关键：它们直接构造
  /// `CleanMyPhotosApp(repository: ...)`，没有注入任何 store。
  late final MemoryRecordStore<T> _memory = MemoryRecordStore<T>(idOf: idOf);

  bool _useMemory = false;

  /// 已经确认过表头的键。存键而不是一个 bool：同一个实例换了键就得重新确认，
  /// 不然第二个键的记录会被追加到第一个键的表头下面，变成谁都读不出来的废文件。
  String? _headerKey;

  /// 文件里的行数达到有效记录数的这个倍数就压缩重写一遍。
  ///
  /// 什么时候会出现废行：重扫（`force: true`）会把同一批 id 再写一遍，
  /// 照片被编辑过也会。不压缩的话文件只涨不缩。
  static const double compactRatio = 2.0;

  @override
  Future<Map<String, T>> load(String key) async {
    final path = await _path();
    if (path == null) return _memory.load(key);

    try {
      final file = File(path);
      if (!await file.exists()) return <String, T>{};

      final parsed = await _parseInBackground(path, _header(key));
      // 表头对不上：整份作废，下次写入时重建。
      if (parsed == null) return <String, T>{};

      if (parsed.total > parsed.records.length * compactRatio) {
        unawaited(_compact(path, key, parsed.records.values));
      }
      return parsed.records;
    } catch (_) {
      // 磁盘读不出来不是致命问题，无非是这次多算一点。
      return <String, T>{};
    }
  }

  @override
  Future<void> append(String key, Iterable<T> records) async {
    final list = records.toList(growable: false);
    if (list.isEmpty) return;

    final path = await _path();
    if (path == null) return _memory.append(key, list);

    try {
      final file = File(path);
      if (_headerKey != key) {
        // 表头不对时直接截断重写：旧记录本来就用不了，留着只是占地方。
        if (!await file.exists() || await _firstLine(file) != _header(key)) {
          await file.writeAsString('${_header(key)}\n');
        }
        _headerKey = key;
      }

      final buffer = StringBuffer();
      for (final record in list) {
        buffer.writeln(jsonEncode(encode(record)));
      }
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } catch (_) {
      // 磁盘写不进去不是致命问题，无非是下次多算一点。
    }
  }

  @override
  Future<void> clear() async {
    _headerKey = null;
    // 允许下次再试一次磁盘：用户点了「清空缓存」，说明环境可能已经变了。
    _useMemory = false;
    await _memory.clear();

    final path = await _path();
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉就下次再说。
    }
  }

  /// 数据文件的位置。拿不到平台目录时返回 null，调用方转投内存。
  Future<String?> _path() async {
    if (_useMemory) return null;

    // `flutter test` 里没有平台插件应答 path_provider，而且 flutter_test 用的是
    // 假时钟：那个 Future 既不会成功也不会失败，会一直挂着把整个扫描拖死。
    // 测试进程本来也不跨轮次共享文件，直接走内存反而更贴近真实使用。
    if (!(persist ?? Platform.environment['FLUTTER_TEST'] != 'true')) {
      _useMemory = true;
      return null;
    }

    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      return '${directory.path}/$folderName.jsonl';
    } catch (_) {
      // `MissingPluginException`（测试环境）和磁盘真出问题都走这里。
      _useMemory = true;
      return null;
    }
  }

  static String _header(String key) => '#clean_my_photos $key';

  /// 只读文件开头的一小段，取第一行。
  ///
  /// 不用 `readAsLines`：那会把几 MB 的文件整个读进内存，而我们只是想知道
  /// 表头对不对。
  static Future<String?> _firstLine(File file) async {
    try {
      final handle = await file.open();
      try {
        final chunk = await handle.read(128);
        final text = utf8.decode(chunk, allowMalformed: true);
        final end = text.indexOf('\n');
        return (end < 0 ? text : text.substring(0, end)).trimRight();
      } finally {
        await handle.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// 在后台 isolate 里解析，避免三万多行把界面卡住。
  ///
  /// `Isolate.run` 要求闭包可跨 isolate 传递，也就是它捕获的东西必须都是
  /// 可传递的；两个函数都是不捕获任何状态的顶层闭包，所以没问题。真出了问题
  /// （比如某个平台上传递失败）就在原地同步解析——慢一点，但不至于读不到。
  Future<_Parsed<T>?> _parseInBackground(String path, String header) async {
    final idOf = this.idOf;
    final decode = this.decode;
    try {
      return await Isolate.run(() => _parse<T>(path, header, idOf, decode));
    } catch (_) {
      return _parse<T>(path, header, idOf, decode);
    }
  }

  static _Parsed<T>? _parse<T>(
    String path,
    String header,
    String Function(T record) idOf,
    T? Function(Object? json) decode,
  ) {
    final lines = File(path).readAsLinesSync();
    if (lines.isEmpty) return _Parsed<T>(0, <String, T>{});
    if (lines.first.trimRight() != header) return null;

    final records = <String, T>{};
    var total = 0;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      total++;
      try {
        final record = decode(jsonDecode(line));
        if (record != null) records[idOf(record)] = record;
      } on FormatException {
        // 某一行坏了不该作废整份缓存：追加写最怕的就是写到一半断电。
      }
    }
    return _Parsed<T>(total, records);
  }

  Future<void> _compact(String path, String key, Iterable<T> records) async {
    try {
      final buffer = StringBuffer('${_header(key)}\n');
      for (final record in records) {
        buffer.writeln(jsonEncode(encode(record)));
      }
      await File(path).writeAsString(buffer.toString());
      _headerKey = key;
    } catch (_) {
      // 压缩失败不影响正确性，下次再说。
    }
  }
}

class _Parsed<T> {
  const _Parsed(this.total, this.records);

  /// 文件里的有效行数（不含表头）。和 [records] 的长度一比就知道废行多不多。
  final int total;

  final Map<String, T> records;
}

// ---------------------------------------------------------------- 两个缓存

/// 图像指纹缓存。
///
/// 图像分析是整个 App 里最慢的一步，而它的结果只跟「图本身」有关。每分析完
/// 一批就落盘，**杀掉进程重开也不用从头再算**——这才是「切走再回来能直接开始
/// 清理」的实现方式，比指望系统在后台把任务跑完可靠得多。
class ScanCache {
  ScanCache({
    RecordStore<AssetFingerprintRecord>? store,
    String? key,
    this.thumbnailSize = 256,
    this.thumbnailQuality = 75,
  })  : _store = store ?? defaultStore(),
        key = key ??
            defaultFingerprintKey(
              size: thumbnailSize,
              quality: thumbnailQuality,
            );

  /// 算法版本。改了哈希算法或缩略图参数就加一，旧缓存整份作废。
  static const int algorithmVersion = 1;

  final RecordStore<AssetFingerprintRecord> _store;
  final String key;
  final int thumbnailSize;
  final int thumbnailQuality;

  static RecordStore<AssetFingerprintRecord> defaultStore() {
    return JsonlRecordStore<AssetFingerprintRecord>(
      folderName: 'scan_fingerprints',
      idOf: (record) => record.id,
      encode: (record) => record.toJson(),
      decode: AssetFingerprintRecord.fromJson,
    );
  }

  Future<Map<String, AssetFingerprintRecord>> read() => _store.load(key);

  /// 追加一批结果。
  ///
  /// 不可缓存的（iCloud 占位符这种「过一会儿就好」的失败）在这里就挡掉，
  /// 免得下次启动把它们当成永久结论，那张照片就再也回不到重复 / 模糊的
  /// 判定里了。
  Future<void> append(Iterable<AssetFingerprintRecord> records) async {
    final cacheable =
        records.where((record) => record.isCacheable).toList(growable: false);
    if (cacheable.isEmpty) return;
    await _store.append(key, cacheable);
  }

  Future<void> clear() => _store.clear();
}

/// 指纹键：算法版本 + 缩略图边长 + 质量。
///
/// **刻意不含模糊阈值**：阈值只影响「算不算模糊」这个结论，而缓存里存的是
/// 客观量（哈希、清晰度）。含进去的话，用户拖一次滑杆整份缓存就废了。
String defaultFingerprintKey({
  int version = ScanCache.algorithmVersion,
  int size = 256,
  int quality = 75,
}) =>
    'v$version-t$size-q$quality';

/// 文件大小缓存。
///
/// iOS 上没有批量取文件大小的接口，只能逐个问系统；三万个条目就是三万次平台
/// 调用。大小几乎不变，存下来下次直接用。
class FileSizeCache {
  FileSizeCache({RecordStore<FileSizeRecord>? store, String? key})
      : _store = store ?? defaultStore(),
        key = key ?? defaultFileSizeKey();

  /// 记录格式版本。
  static const int schemaVersion = 1;

  final RecordStore<FileSizeRecord> _store;
  final String key;

  static RecordStore<FileSizeRecord> defaultStore() {
    return JsonlRecordStore<FileSizeRecord>(
      folderName: 'scan_sizes',
      idOf: (record) => record.id,
      encode: (record) => record.toJson(),
      decode: FileSizeRecord.fromJson,
    );
  }

  Future<Map<String, FileSizeRecord>> read() => _store.load(key);

  Future<void> append(Iterable<FileSizeRecord> records) async {
    final list =
        records.where((record) => record.size > 0).toList(growable: false);
    if (list.isEmpty) return;
    await _store.append(key, list);
  }

  Future<void> clear() => _store.clear();
}

String defaultFileSizeKey({int version = FileSizeCache.schemaVersion}) =>
    's$version';
