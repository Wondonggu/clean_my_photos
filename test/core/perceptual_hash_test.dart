import 'package:clean_my_photos/core/utils/gray_image.dart';
import 'package:clean_my_photos/core/utils/perceptual_hash.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/synthetic_images.dart';

GrayImage _gray(dynamic image, {int maxSide = 256}) =>
    GrayImage.fromImage(image, maxSide: maxSide);

void main() {
  group('GrayImage', () {
    test('转灰度并保留尺寸', () {
      final gray = _gray(SyntheticImage.checkerboard(32, 24));
      expect(gray.width, 32);
      expect(gray.height, 24);
      expect(gray.pixels.length, 32 * 24);
    });

    test('长边超过上限时会等比缩小', () {
      final gray = _gray(SyntheticImage.gradient(400, 200), maxSide: 100);
      expect(gray.maxSide, 100);
      expect(gray.width, 100);
      expect(gray.height, 50);
    });

    test('纯色图被识别为空白', () {
      expect(_gray(SyntheticImage.solid(32, 32, 128)).isNearlyBlank(), isTrue);
      expect(_gray(SyntheticImage.checkerboard(32, 32)).isNearlyBlank(), isFalse);
    });

    test('resample 不会改变纯色图', () {
      final gray = _gray(SyntheticImage.solid(64, 64, 200));
      final small = gray.resample(8, 8);
      expect(small.pixels.every((value) => (value - 200).abs() < 0.001), isTrue);
    });

    test('downscaleToMaxSide 只缩不放', () {
      final gray = _gray(SyntheticImage.gradient(64, 64));
      expect(identical(gray.downscaleToMaxSide(256), gray), isTrue);
      expect(gray.downscaleToMaxSide(32).maxSide, 32);
    });
  });

  group('PerceptualHash.dHash', () {
    test('同一张图距离为 0', () {
      final image = SyntheticImage.blocks(64, 64);
      final a = PerceptualHash.dHash(_gray(image));
      final b = PerceptualHash.dHash(_gray(image));
      expect(a.distanceTo(b), 0);
      expect(a, equals(b));
      expect(a.similarityTo(b), 1.0);
    });

    test('整体提亮不改变哈希（对亮度变化鲁棒）', () {
      final image = SyntheticImage.blocks(64, 64);
      final bright = SyntheticImage.brighten(image, 30);
      final a = PerceptualHash.dHash(_gray(image));
      final b = PerceptualHash.dHash(_gray(bright));
      expect(a.distanceTo(b), 0);
    });

    test('反相后差异极大', () {
      final image = SyntheticImage.gradient(64, 64);
      final a = PerceptualHash.dHash(_gray(image));
      final b = PerceptualHash.dHash(_gray(SyntheticImage.invert(image)));
      expect(a.distanceTo(b), greaterThanOrEqualTo(56));
    });

    test('不同图案差异明显', () {
      final a = PerceptualHash.dHash(_gray(SyntheticImage.blocks(64, 64)));
      final b = PerceptualHash.dHash(_gray(SyntheticImage.gradient(64, 64)));
      expect(a.distanceTo(b), greaterThanOrEqualTo(16));
    });

    test('已知局限：平滑画面之间会碰撞', () {
      // dHash 只看水平方向的相邻像素差，因此「水平渐变」「垂直渐变」
      // 「纯色」这三类画面都会产生全 0 哈希。
      // 这是算法本身的取舍：它换来的是对亮度、缩放和压缩的鲁棒性。
      // 真正兜底的是「时间邻近 + 宽高比一致」这两道额外的门槛。
      final horizontal =
          PerceptualHash.dHash(_gray(SyntheticImage.gradient(64, 64)));
      final vertical = PerceptualHash.dHash(
        _gray(SyntheticImage.gradient(64, 64, vertical: true)),
      );
      expect(horizontal.isAllZero, isTrue);
      expect(vertical.isAllZero, isTrue);
      expect(horizontal.distanceTo(vertical), 0);
    });

    test('有结构的画面与平滑画面不会碰撞', () {
      final blocks = PerceptualHash.dHash(_gray(SyntheticImage.blocks(64, 64)));
      final smooth = PerceptualHash.dHash(_gray(SyntheticImage.gradient(64, 64)));
      expect(smooth.isAllZero, isTrue);
      expect(blocks.isAllZero, isFalse);
      expect(blocks.distanceTo(smooth), greaterThanOrEqualTo(16));
    });

    test('纯色图的 dHash 全为 0', () {
      final hash = PerceptualHash.dHash(_gray(SyntheticImage.solid(32, 32, 180)));
      expect(hash.isAllZero, isTrue);
      expect(hash.toHex(), '0000000000000000');
    });

    test('缩放不影响哈希（同一画面不同分辨率）', () {
      final image = SyntheticImage.blocks(400, 300);
      final scaled = SyntheticImage.blocks(200, 150);
      final a = PerceptualHash.dHash(_gray(image));
      final b = PerceptualHash.dHash(_gray(scaled));
      expect(a.distanceTo(b), lessThanOrEqualTo(2));
    });

    test('距离满足对称性，且自距离为 0', () {
      final a = PerceptualHash.dHash(_gray(SyntheticImage.blocks(64, 64)));
      final b = PerceptualHash.dHash(_gray(SyntheticImage.gradient(64, 64)));
      expect(a.distanceTo(b), b.distanceTo(a));
      expect(a.distanceTo(a), 0);
    });
  });

  group('PerceptualHash.aHash', () {
    test('同一张图距离为 0', () {
      final image = SyntheticImage.blocks(64, 64);
      final a = PerceptualHash.aHash(_gray(image));
      final b = PerceptualHash.aHash(_gray(image));
      expect(a.distanceTo(b), 0);
    });

    test('非全零图案会产生非平凡哈希', () {
      final hash = PerceptualHash.aHash(_gray(SyntheticImage.blocks(64, 64)));
      expect(hash.isAllZero, isFalse);
    });
  });

  group('PerceptualHash 序列化', () {
    test('fromBytes 校验长度', () {
      expect(
        () => PerceptualHash.fromBytes(<int>[1, 2, 3]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('往返转换保持一致', () {
      final original = PerceptualHash.dHash(_gray(SyntheticImage.blocks(64, 64)));
      final restored = PerceptualHash.fromBytes(original.bytes);
      expect(restored, equals(original));
      expect(restored.toHex(), original.toHex());
    });
  });
}
