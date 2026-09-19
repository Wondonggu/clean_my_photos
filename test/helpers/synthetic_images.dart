import 'package:image/image.dart' as img;

/// 测试用的合成图片工厂。
///
/// 全部是确定性生成，没有随机数，保证测试可复现。
class SyntheticImage {
  const SyntheticImage._();

  /// 棋盘格。`cell` 越小边缘越密，拉普拉斯方差越大。
  static img.Image checkerboard(int width, int height, {int cell = 4}) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final on = ((x ~/ cell) + (y ~/ cell)) % 2 == 0;
        final value = on ? 255 : 0;
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  /// 水平 / 垂直渐变。
  static img.Image gradient(int width, int height, {bool vertical = false}) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final ratio = vertical ? y / (height - 1) : x / (width - 1);
        final value = (ratio * 255).round().clamp(0, 255);
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  /// 纯色。
  static img.Image solid(int width, int height, int value) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  /// 有结构的图案：左半亮、右半暗，中间夹一条竖带。
  ///
  /// dHash 会稳定地产生非平凡的位模式，适合用来做「不同图片」的对照。
  static img.Image blocks(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final ratio = x / width;
        final int value;
        if (ratio < 0.3) {
          value = 30;
        } else if (ratio < 0.5) {
          value = 240;
        } else if (ratio < 0.75) {
          value = 90;
        } else {
          value = 200;
        }
        // 加上一层细横纹，保证不同高度上的行也不完全相同。
        final striped = (y ~/ 8) % 2 == 0 ? value : (value * 0.8).round();
        image.setPixelRgb(x, y, striped, striped, striped);
      }
    }
    return image;
  }

  /// 整体提亮（不改变像素之间的相对明暗关系）。
  static img.Image brighten(img.Image source, int delta) {
    final image = img.Image(width: source.width, height: source.height);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        int shift(num channel) =>
            (channel.toDouble() + delta).round().clamp(0, 255);
        image.setPixelRgb(
          x,
          y,
          shift(pixel.r),
          shift(pixel.g),
          shift(pixel.b),
        );
      }
    }
    return image;
  }

  /// 反相。
  static img.Image invert(img.Image source) {
    final image = img.Image(width: source.width, height: source.height);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        int flip(num channel) => 255 - channel.round().clamp(0, 255);
        image.setPixelRgb(x, y, flip(pixel.r), flip(pixel.g), flip(pixel.b));
      }
    }
    return image;
  }

  /// 高斯模糊，用来模拟失焦。
  ///
  /// 注意：`image` 包的 `gaussianBlur` 是**原地修改**并返回同一个对象，
  /// 所以这里必须先深拷贝，否则调用方传进来的「清晰原图」也会一起被模糊掉。
  static img.Image blurred(img.Image source, {int radius = 8}) =>
      img.gaussianBlur(img.Image.from(source), radius: radius);
}
