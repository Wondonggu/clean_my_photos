import 'package:clean_my_photos/core/utils/blur_analyzer.dart';
import 'package:clean_my_photos/core/utils/gray_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/synthetic_images.dart';

void main() {
  const analyzer = BlurAnalyzer();

  double varianceOf(dynamic image) =>
      BlurAnalyzer.laplacianVariance(GrayImage.fromImage(image, maxSide: 256));

  group('laplacianVariance', () {
    test('纯色图为 0', () {
      expect(varianceOf(SyntheticImage.solid(256, 256, 128)), lessThan(1));
    });

    test('边缘越密集，方差越大', () {
      final coarse = varianceOf(SyntheticImage.checkerboard(256, 256, cell: 16));
      final fine = varianceOf(SyntheticImage.checkerboard(256, 256, cell: 2));
      expect(fine, greaterThan(coarse));
    });

    test('模糊后方差显著下降', () {
      final sharp = SyntheticImage.checkerboard(256, 256, cell: 4);
      final blurred = SyntheticImage.blurred(sharp, radius: 8);
      expect(varianceOf(blurred), lessThan(varianceOf(sharp) / 10));
    });
  });

  group('assess', () {
    test('清晰的照片判定为不模糊', () {
      final result = analyzer.assess(
        GrayImage.fromImage(
          SyntheticImage.checkerboard(256, 256, cell: 4),
          maxSide: 256,
        ),
      );
      expect(result.isReliable, isTrue);
      expect(result.isBlurry, isFalse);
    });

    test('明显失焦的照片判定为模糊', () {
      final blurred = SyntheticImage.blurred(
        SyntheticImage.checkerboard(256, 256, cell: 4),
        radius: 8,
      );
      final result = analyzer.assess(GrayImage.fromImage(blurred, maxSide: 256));
      expect(result.isBlurry, isTrue);
      expect(result.laplacianVariance,
          lessThan(BlurAnalyzer.defaultThreshold));
    });

    test('纯色图不下「模糊」的结论（不可靠）', () {
      final result = analyzer.assess(
        GrayImage.fromImage(SyntheticImage.solid(256, 256, 0), maxSide: 256),
      );
      expect(result.isReliable, isFalse);
      expect(result.isBlurry, isFalse);
    });

    test('小图不下结论', () {
      final result = analyzer.assess(
        GrayImage.fromImage(
          SyntheticImage.checkerboard(48, 48, cell: 2),
          maxSide: 256,
        ),
      );
      expect(result.isReliable, isFalse);
      expect(result.isBlurry, isFalse);
    });

    test('阈值可调：放宽阈值后不再判为模糊', () {
      final blurred = SyntheticImage.blurred(
        SyntheticImage.checkerboard(256, 256, cell: 4),
        radius: 8,
      );
      final gray = GrayImage.fromImage(blurred, maxSide: 256);
      final strict = const BlurAnalyzer(threshold: 1000).assess(gray);
      final lenient = const BlurAnalyzer(threshold: 0.5).assess(gray);
      expect(strict.isBlurry, isTrue);
      expect(lenient.isBlurry, false);
    });
  });
}
