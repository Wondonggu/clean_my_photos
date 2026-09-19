import 'dart:typed_data';

import 'gray_image.dart';

/// 64 位感知哈希（dHash / aHash）。
///
/// 位模式按「大端」存放：第 0 位是 `bytes[0]` 的最高位。
/// 不使用 Dart 的 `int` 做位运算，是为了在所有平台（含 Web 的 JS 数值语义）上行为一致。
class PerceptualHash {
  const PerceptualHash._(this.bytes);

  /// 8 字节 = 64 位。
  final Uint8List bytes;

  static const int byteLength = 8;
  static const int bitCount = byteLength * 8;

  /// 差异哈希：把图缩成 (列数+1) × 行数，逐行比较相邻像素的明暗关系。
  ///
  /// 默认 9 × 8 输入产生 64 位结果，对整体亮度变化、轻微缩放和 JPEG 压缩鲁棒。
  static PerceptualHash dHash(GrayImage gray, {int columns = 8, int rows = 8}) {
    final small = gray.resample(columns + 1, rows);
    final out = Uint8List(byteLength);
    var bit = 0;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final left = small.at(x, y);
        final right = small.at(x + 1, y);
        if (left > right) {
          out[bit >> 3] |= 0x80 >> (bit & 7);
        }
        bit++;
      }
    }
    return PerceptualHash._(out);
  }

  /// 平均哈希：与整图平均亮度比较，高于平均记 1。
  static PerceptualHash aHash(GrayImage gray, {int size = 8}) {
    final small = gray.resample(size, size);
    final mean = small.meanLuminance;

    final out = Uint8List(byteLength);
    var bit = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (small.at(x, y) > mean) {
          out[bit >> 3] |= 0x80 >> (bit & 7);
        }
        bit++;
      }
    }
    return PerceptualHash._(out);
  }

  /// 从 8 字节原始数据构造（用于反序列化）。
  factory PerceptualHash.fromBytes(List<int> raw) {
    if (raw.length != byteLength) {
      throw ArgumentError.value(raw.length, 'raw', '哈希必须是 $byteLength 字节');
    }
    return PerceptualHash._(Uint8List.fromList(raw));
  }

  /// 汉明距离：不同的位数，0 表示完全一致。
  int distanceTo(PerceptualHash other) {
    var distance = 0;
    for (var i = 0; i < byteLength; i++) {
      distance += _popCount(bytes[i] ^ other.bytes[i]);
    }
    return distance;
  }

  /// 相似度，1.0 表示完全一致。
  double similarityTo(PerceptualHash other) =>
      1.0 - distanceTo(other) / bitCount;

  bool get isAllZero => bytes.every((byte) => byte == 0);

  /// 十六进制字符串，便于打日志。
  String toHex() => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static int _popCount(int value) {
    var v = value;
    var count = 0;
    while (v != 0) {
      v &= v - 1;
      count++;
    }
    return count;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PerceptualHash) return false;
    for (var i = 0; i < byteLength; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 17;
    for (final byte in bytes) {
      hash = hash * 31 + byte;
    }
    return hash;
  }

  @override
  String toString() => 'PerceptualHash(${toHex()})';
}
