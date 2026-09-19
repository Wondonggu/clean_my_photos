import 'dart:typed_data';

import 'package:clean_my_photos/core/models/asset_signature.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/utils/perceptual_hash.dart';

/// 测试用的媒体条目 / 指纹构造工具。
class MediaFixtures {
  const MediaFixtures._();

  static int _autoId = 0;

  /// 重置自增 id，保证每个测试的 id 稳定。
  static void reset() => _autoId = 0;

  /// 造一张图片条目。
  static MediaItem photo({
    String? id,
    DateTime? createdAt,
    int width = 4032,
    int height = 3024,
    int size = 3 * 1024 * 1024,
    bool isFavorite = false,
    bool isScreenshot = false,
    bool isLivePhoto = false,
    bool isLocallyAvailable = true,
    String? title,
  }) {
    return MediaItem(
      id: id ?? 'photo-${_autoId++}',
      kind: MediaKind.image,
      title: title,
      createdAt: createdAt ?? DateTime(2024, 5, 1, 12),
      width: width,
      height: height,
      size: size,
      isFavorite: isFavorite,
      isScreenshot: isScreenshot,
      isLivePhoto: isLivePhoto,
      isLocallyAvailable: isLocallyAvailable,
    );
  }

  /// 造一个没有拍摄时间的照片（系统偶尔会返回空时间戳）。
  static MediaItem photoWithoutTime({String? id}) {
    return MediaItem(
      id: id ?? 'no-time-${_autoId++}',
      kind: MediaKind.image,
      width: 4032,
      height: 3024,
      size: 3 * 1024 * 1024,
    );
  }

  /// 造一个视频条目。
  static MediaItem video({
    String? id,
    DateTime? createdAt,
    int width = 1920,
    int height = 1080,
    int size = 200 * 1024 * 1024,
    Duration duration = const Duration(minutes: 3),
    bool isScreenRecording = false,
    String? title,
  }) {
    return MediaItem(
      id: id ?? 'video-${_autoId++}',
      kind: MediaKind.video,
      title: title,
      createdAt: createdAt ?? DateTime(2024, 5, 1, 12),
      width: width,
      height: height,
      size: size,
      duration: duration,
      isScreenRecording: isScreenRecording,
    );
  }

  /// 用给定的「1 位位置」造一个哈希。
  static PerceptualHash hashOfBits(Set<int> oneBits) {
    final bytes = Uint8List(PerceptualHash.byteLength);
    for (final bit in oneBits) {
      bytes[bit >> 3] |= 0x80 >> (bit & 7);
    }
    return PerceptualHash.fromBytes(bytes);
  }

  /// 造一个全 0 哈希。
  static PerceptualHash zeroHash() => hashOfBits(const <int>{});

  /// 造一个与全 0 哈希汉明距离恰好为 [distance] 的哈希。
  static PerceptualHash hashAtDistance(int distance) =>
      hashOfBits(<int>{for (var i = 0; i < distance; i++) i});

  /// 造一个带指纹的签名。
  static AssetSignature signature(
    MediaItem item, {
    PerceptualHash? hash,
    double? sharpness,
    bool isBlurry = false,
    String? failure,
  }) {
    return AssetSignature(
      item: item,
      hash: hash ?? zeroHash(),
      sharpness: sharpness,
      isBlurry: isBlurry,
      failure: failure,
    );
  }
}
