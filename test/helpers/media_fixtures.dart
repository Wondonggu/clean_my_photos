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
    DateTime? modifiedAt,
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
      modifiedAt: modifiedAt,
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

  /// 一张 1×1 的透明 PNG。
  ///
  /// 假仓库返回的图像字节必须是真的能解码的图：`Image.memory` 拿到
  /// 随便几个字节会直接抛「Invalid image data」，而那条异常会被
  /// flutter_test 当成测试失败。
  static final Uint8List tinyPng = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

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
    bool isReliable = true,
    String? failure,
  }) {
    return AssetSignature(
      item: item,
      hash: hash ?? zeroHash(),
      sharpness: sharpness,
      isReliable: isReliable,
      failure: failure,
    );
  }
}
