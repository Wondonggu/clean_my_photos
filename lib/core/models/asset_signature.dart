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
    this.isReliable = true,
    this.failure,
  });

  final MediaItem item;

  /// 感知哈希。
  final PerceptualHash? hash;

  /// 清晰度（拉普拉斯方差）。
  final double? sharpness;

  /// 清晰度结论是否可信（图太小或接近纯色时不可信）。
  ///
  /// 刻意不在这里存「是否模糊」：那要看用户在设置里选的阈值，
  /// 存下来就得在改阈值时重扫一遍。改由 [CleanupAnalyzer] 现算。
  final bool isReliable;

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
    bool? isReliable,
    String? failure,
  }) {
    return AssetSignature(
      item: item ?? this.item,
      hash: hash ?? this.hash,
      sharpness: sharpness ?? this.sharpness,
      isReliable: isReliable ?? this.isReliable,
      failure: failure ?? this.failure,
    );
  }

  @override
  String toString() =>
      'AssetSignature(${item.id}, hash=${hash?.toHex()}, '
      'sharpness=${sharpness?.toStringAsFixed(1)})';
}
