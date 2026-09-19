import '../utils/perceptual_hash.dart';
import 'media_item.dart';

/// 一个媒体条目 + 它的图像指纹，是相似度分组与模糊检测的输入。
///
/// [hash] / [sharpness] 可能为 `null`：视频、iCloud 未下载的照片、
/// 或者解码失败的图片都无法计算，这类条目会被保守地排除在自动建议之外。
class AssetSignature {
  const AssetSignature({
    required this.item,
    this.hash,
    this.sharpness,
    this.isBlurry = false,
    this.failure,
  });

  final MediaItem item;

  /// 感知哈希。
  final PerceptualHash? hash;

  /// 清晰度（拉普拉斯方差）。
  final double? sharpness;

  /// 是否被判定为模糊。
  final bool isBlurry;

  /// 分析失败的原因，仅用于诊断。
  final String? failure;

  bool get hasHash => hash != null;

  bool get hasSharpness => sharpness != null;

  /// 图像分析是否成功完成。
  bool get isAnalyzed => hasHash && failure == null;

  AssetSignature copyWith({
    MediaItem? item,
    PerceptualHash? hash,
    double? sharpness,
    bool? isBlurry,
    String? failure,
  }) {
    return AssetSignature(
      item: item ?? this.item,
      hash: hash ?? this.hash,
      sharpness: sharpness ?? this.sharpness,
      isBlurry: isBlurry ?? this.isBlurry,
      failure: failure ?? this.failure,
    );
  }

  @override
  String toString() =>
      'AssetSignature(${item.id}, hash=${hash?.toHex()}, '
      'sharpness=${sharpness?.toStringAsFixed(1)})';
}
