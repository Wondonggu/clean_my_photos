import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 一张灰度图，行优先存储，像素值范围 0–255。
///
/// 这是所有图像算法的公共输入：它不依赖任何 Flutter / 平台 API，
/// 因此可以在纯 Dart 测试里手工构造。
class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
      : assert(width > 0, 'width 必须为正数'),
        assert(height > 0, 'height 必须为正数'),
        assert(pixels.length == width * height, '像素数量与尺寸不匹配');

  final int width;
  final int height;

  /// 行优先的亮度数据，长度为 `width * height`。
  final Float32List pixels;

  int get pixelCount => width * height;

  /// 长边长度。
  int get maxSide => math.max(width, height);

  double at(int x, int y) => pixels[y * width + x];

  /// 是否是一张纯色（或接近纯色）的图，例如全黑、全白的失败截图。
  bool isNearlyBlank({double tolerance = 2.0}) {
    if (pixels.isEmpty) return true;
    var min = pixels[0];
    var max = pixels[0];
    for (final value in pixels) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    return (max - min) <= tolerance;
  }

  /// 平均亮度。
  double get meanLuminance {
    if (pixels.isEmpty) return 0;
    var sum = 0.0;
    for (final value in pixels) {
      sum += value;
    }
    return sum / pixels.length;
  }

  /// 缩放为 [targetWidth] × [targetHeight]。
  ///
  /// 缩小使用面积平均（box filter），可以避免采样锯齿影响哈希与方差；
  /// 放大使用最近邻，仅在输入本身很小时发生。
  GrayImage resample(int targetWidth, int targetHeight) {
    if (targetWidth == width && targetHeight == height) return this;

    final out = Float32List(targetWidth * targetHeight);
    final scaleX = width / targetWidth;
    final scaleY = height / targetHeight;

    for (var ty = 0; ty < targetHeight; ty++) {
      final yStart = (ty * scaleY).floor().clamp(0, height - 1);
      final yEnd = math.max(yStart + 1, ((ty + 1) * scaleY).ceil()).clamp(0, height);

      for (var tx = 0; tx < targetWidth; tx++) {
        final xStart = (tx * scaleX).floor().clamp(0, width - 1);
        final xEnd =
            math.max(xStart + 1, ((tx + 1) * scaleX).ceil()).clamp(0, width);

        var sum = 0.0;
        var count = 0;
        for (var y = yStart; y < yEnd; y++) {
          final rowOffset = y * width;
          for (var x = xStart; x < xEnd; x++) {
            sum += pixels[rowOffset + x];
            count++;
          }
        }
        out[ty * targetWidth + tx] = count == 0 ? 0 : sum / count;
      }
    }

    return GrayImage(targetWidth, targetHeight, out);
  }

  /// 把长边缩放到 [maxSide]（只会缩小，不会放大）。
  GrayImage downscaleToMaxSide(int maxSide) {
    if (this.maxSide <= maxSide) return this;
    if (width >= height) {
      final targetHeight = math.max(1, (height * maxSide / width).round());
      return resample(maxSide, targetHeight);
    }
    final targetWidth = math.max(1, (width * maxSide / height).round());
    return resample(targetWidth, maxSide);
  }

  /// 解码后的图片转灰度图，并把长边限制在 [maxSide] 以内。
  ///
  /// 返回 `null` 表示图片无法解码。
  static GrayImage? fromEncoded(Uint8List bytes, {int maxSide = 256}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }
    return fromImage(decoded, maxSide: maxSide);
  }

  /// [img.Image] 转灰度图。
  static GrayImage fromImage(img.Image source, {int maxSide = 256}) {
    var image = source;
    if (maxSide > 0 && math.max(image.width, image.height) > maxSide) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? maxSide : null,
        height: image.height > image.width ? maxSide : null,
        interpolation: img.Interpolation.average,
      );
    }

    final pixels = Float32List(image.width * image.height);
    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        // ITU-R BT.601 亮度公式，与常见的图像处理实现保持一致。
        pixels[index++] = 0.299 * r + 0.587 * g + 0.114 * b;
      }
    }

    return GrayImage(image.width, image.height, pixels);
  }

  @override
  String toString() => 'GrayImage(${width}x$height)';
}
