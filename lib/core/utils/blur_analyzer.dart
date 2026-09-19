import 'dart:math' as math;

import 'gray_image.dart';

/// 一张图的清晰度评估结果。
class BlurAssessment {
  const BlurAssessment({
    required this.laplacianVariance,
    required this.meanLuminance,
    required this.isBlurry,
    required this.isReliable,
  });

  /// 拉普拉斯响应方差，越大越清晰。
  final double laplacianVariance;

  /// 平均亮度，用于识别几乎全黑 / 全白的照片。
  final double meanLuminance;

  /// 是否判定为模糊。
  final bool isBlurry;

  /// 结论是否可信。图太小或几乎纯色时，方差没有参考意义。
  final bool isReliable;
}

/// 基于「拉普拉斯方差」的模糊检测。
///
/// 原理：用拉普拉斯算子提取图像的高频边缘，清晰的照片边缘强烈、
/// 响应方差大；失焦或运动模糊的照片边缘被抹平，方差显著变小。
class BlurAnalyzer {
  const BlurAnalyzer({this.threshold = defaultThreshold});

  /// 判定阈值。低于该方差视为模糊。
  ///
  /// 经验值：手机拍摄的清晰照片通常 > 300，明显失焦的照片 < 80。
  /// 100 是一个偏保守（宁可漏判、不可误判）的默认值，界面允许用户调整。
  static const double defaultThreshold = 100.0;

  /// 方差只有在同样尺度上才可比，因此统一把长边缩到这个尺寸再计算。
  static const int analysisSide = 256;

  /// 长边小于该值时无法可靠判断。
  static const int minReliableSide = 96;

  final double threshold;

  /// 计算灰度图的拉普拉斯方差。
  ///
  /// 会将长边统一缩放到 [analysisSide]（只缩不放），保证不同分辨率的
  /// 照片之间分数可比。
  static double laplacianVariance(GrayImage gray) {
    final normalized = gray.downscaleToMaxSide(analysisSide);
    final width = normalized.width;
    final height = normalized.height;

    if (width < 3 || height < 3) return 0;

    var sum = 0.0;
    var sumSquares = 0.0;
    var count = 0;

    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      final rowAbove = row - width;
      final rowBelow = row + width;
      for (var x = 1; x < width - 1; x++) {
        // 卷积核：[0 1 0; 1 -4 1; 0 1 0]
        final value = normalized.pixels[rowAbove + x] +
            normalized.pixels[rowBelow + x] +
            normalized.pixels[row + x - 1] +
            normalized.pixels[row + x + 1] -
            4 * normalized.pixels[row + x];

        sum += value;
        sumSquares += value * value;
        count++;
      }
    }

    if (count == 0) return 0;

    final mean = sum / count;
    final variance = sumSquares / count - mean * mean;
    return math.max(0, variance);
  }

  /// 完整评估。
  BlurAssessment assess(GrayImage gray) {
    final variance = laplacianVariance(gray);
    final mean = gray.meanLuminance;
    final reliable =
        gray.maxSide >= minReliableSide && !gray.isNearlyBlank(tolerance: 3);

    // 几乎全黑 / 全白的照片方差天然很低，但那不是「模糊」，
    // 交给「相似 / 空白图」逻辑处理，这里不下结论。
    final isBlurry = reliable && variance < threshold;

    return BlurAssessment(
      laplacianVariance: variance,
      meanLuminance: mean,
      isBlurry: isBlurry,
      isReliable: reliable,
    );
  }
}
