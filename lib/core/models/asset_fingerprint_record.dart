import 'dart:convert';
import 'dart:typed_data';

import '../utils/perceptual_hash.dart';
import 'asset_signature.dart';
import 'media_item.dart';

/// 一条落盘的图像指纹。
///
/// 图像分析是整个 App 里最慢的一步（解码 + 哈希 + 拉普拉斯），而它的结果
/// 只跟「图本身」有关，跟用户偏好无关。所以每分析完一批就写进缓存，
/// **杀掉进程重开也不用从头再算一遍**——这正是「切走再回来能直接开始清理」
/// 的实现方式，比指望系统在后台把任务跑完可靠得多。
///
/// 刻意**不存 `isBlurry`**：模糊与否要看用户在设置里选的阈值，存下来就会
/// 在改阈值时变成错的。这里只存客观量（哈希、清晰度、可信度），结论现算。
class AssetFingerprintRecord {
  const AssetFingerprintRecord({
    required this.id,
    required this.hash,
    this.sharpness,
    this.isReliable = true,
    this.failure,
  });

  final String id;

  /// 8 字节的 dHash，base64 存。
  final String hash;

  final double? sharpness;

  /// 清晰度结论是否可信（图太小或接近纯色时不可信）。
  final bool isReliable;

  /// 分析失败的原因。
  ///
  /// **只记录不会自己好的失败**（解码不了、格式不支持）。iCloud 占位符这
  /// 种「过一会儿就能读到」的情况不能落盘：一旦写进去，这张照片就永远被
  /// 排除在重复 / 模糊判定之外了。
  final String? failure;

  bool get isRetryable =>
      failure != null &&
      (failure!.contains('缩略图不可用') || failure!.contains('iCloud'));

  /// 能不能写进缓存。可重试的失败留给下次。
  bool get isCacheable => failure == null || !isRetryable;

  /// 把这条记录贴回条目上，还原成分析结果。
  AssetSignature attachTo(MediaItem item) {
    final bytes = _decodeHash(hash);
    if (bytes == null) {
      // 哈希坏了就当没缓存过，别把一条假指纹喂给分组算法。
      return AssetSignature(item: item, failure: failure ?? '缓存里的指纹已损坏');
    }

    return AssetSignature(
      item: item,
      hash: failure == null ? PerceptualHash.fromBytes(bytes) : null,
      sharpness: failure == null ? sharpness : null,
      isReliable: isReliable,
      failure: failure,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'hash': hash,
        if (sharpness != null) 'sharpness': sharpness,
        if (!isReliable) 'unreliable': true,
        if (failure != null) 'failure': failure,
      };

  /// 从一行 JSON 还原。字段缺失或类型不对时返回 null，由调用方跳过这一行。
  static AssetFingerprintRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final hash = raw['hash'];
    if (id is! String || id.isEmpty || hash is! String) return null;

    final sharpness = raw['sharpness'];
    final failure = raw['failure'];

    return AssetFingerprintRecord(
      id: id,
      hash: hash,
      sharpness: sharpness is num ? sharpness.toDouble() : null,
      isReliable: raw['unreliable'] != true,
      failure: failure is String ? failure : null,
    );
  }

  /// 从一次分析结果建记录；不可缓存的返回 null。
  static AssetFingerprintRecord? fromSignature(AssetSignature signature) {
    final failure = signature.failure;
    if (failure != null) {
      final record = AssetFingerprintRecord(
        id: signature.item.id,
        hash: '',
        failure: failure,
      );
      return record.isCacheable ? record : null;
    }

    final hash = signature.hash;
    if (hash == null) return null;

    return AssetFingerprintRecord(
      id: signature.item.id,
      hash: base64Encode(hash.bytes),
      sharpness: signature.sharpness,
      isReliable: signature.isReliable,
    );
  }

  static Uint8List? _decodeHash(String encoded) {
    if (encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      return bytes.length == PerceptualHash.byteLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'AssetFingerprintRecord($id)';
}
