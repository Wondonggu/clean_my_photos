import 'dart:typed_data';

import '../utils/blur_analyzer.dart';
import '../utils/gray_image.dart';
import '../utils/perceptual_hash.dart';

/// 单张图片的指纹。
class ImageFingerprint {
  const ImageFingerprint({
    required this.hash,
    required this.sharpness,
    required this.isBlurry,
    required this.isReliable,
    required this.meanLuminance,
    required this.width,
    required this.height,
  });

  final PerceptualHash hash;

  /// 拉普拉斯方差。
  final double sharpness;

  final bool isBlurry;

  /// 清晰度结论是否可信（图太小或接近纯色时不可信）。
  final bool isReliable;

  final double meanLuminance;

  final int width;
  final int height;
}

/// 从缩略图字节里提取感知哈希与清晰度。
///
/// 设计为无状态纯计算，便于放进 isolate 执行。
class ImageAnalyzer {
  const ImageAnalyzer({
    this.blurThreshold = BlurAnalyzer.defaultThreshold,
    this.maxSide = 256,
  });

  final double blurThreshold;

  /// 解码后把长边限制在该尺寸内——缩略图本身很小，这一步主要是防御性处理。
  final int maxSide;

  /// 分析失败（例如字节不是合法图片）时返回 `null`。
  ImageFingerprint? analyzeBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final gray = GrayImage.fromEncoded(bytes, maxSide: maxSide);
    if (gray == null) return null;
    return analyzeGray(gray);
  }

  ImageFingerprint analyzeGray(GrayImage gray) {
    final hash = PerceptualHash.dHash(gray);
    final assessment =
        BlurAnalyzer(threshold: blurThreshold).assess(gray);

    return ImageFingerprint(
      hash: hash,
      sharpness: assessment.laplacianVariance,
      isBlurry: assessment.isBlurry,
      isReliable: assessment.isReliable,
      meanLuminance: assessment.meanLuminance,
      width: gray.width,
      height: gray.height,
    );
  }
}

/// 一次分析请求。参数与返回值都可跨 isolate 传递，
/// 因此可以配合 `Isolate.run` / `compute` 使用。
class AnalyzeRequest {
  const AnalyzeRequest({
    required this.bytes,
    this.blurThreshold = BlurAnalyzer.defaultThreshold,
    this.maxSide = 256,
  });

  final Uint8List bytes;
  final double blurThreshold;
  final int maxSide;
}

/// isolate 入口：顶层函数，供 [AnalyzeRequest] 使用。
ImageFingerprint? analyzeThumbnail(AnalyzeRequest request) {
  return ImageAnalyzer(
    blurThreshold: request.blurThreshold,
    maxSide: request.maxSide,
  ).analyzeBytes(request.bytes);
}
