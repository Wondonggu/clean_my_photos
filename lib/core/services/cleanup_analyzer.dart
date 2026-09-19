import '../models/asset_signature.dart';
import '../models/cleanup_category.dart';
import '../models/media_group.dart';
import '../models/media_item.dart';
import '../utils/blur_analyzer.dart';
import 'similarity_grouper.dart';

/// 把「一堆媒体 + 它们的指纹」变成一份可执行的清理方案。
///
/// 全部是纯函数，不触碰平台 API，因此可以直接用构造出来的假数据测试。
class CleanupAnalyzer {
  const CleanupAnalyzer({
    this.similarity = const SimilarityOptions(),
    this.blurThreshold = BlurAnalyzer.defaultThreshold,
    this.largeVideoBytes = defaultLargeVideoBytes,
    this.largePhotoBytes = defaultLargePhotoBytes,
    this.screenshotMinAge = Duration.zero,
    this.groupSimilarVideos = false,
  });

  /// 超过该体积的视频进入「超大视频」。
  static const int defaultLargeVideoBytes = 100 * 1024 * 1024;

  /// 超过该体积的照片进入「超大照片」。
  static const int defaultLargePhotoBytes = 8 * 1024 * 1024;

  final SimilarityOptions similarity;

  /// 模糊判定阈值，界面上的「灵敏度」滑杆会改这个值。
  final double blurThreshold;

  final int largeVideoBytes;
  final int largePhotoBytes;

  /// 只把「拍摄时间早于该时长之前」的截图列为建议清理项。
  /// 默认 0，即所有截图都建议清理（用户仍可在界面上取消勾选）。
  final Duration screenshotMinAge;

  /// 是否也对视频做相似度分组。默认关闭：
  /// 视频只能取封面帧做哈希，误判率高于照片。
  final bool groupSimilarVideos;

  /// 一次性算出首页需要的全部分类。
  Map<CleanupCategoryType, CleanupCategory> buildCategories({
    required List<MediaItem> items,
    required List<AssetSignature> signatures,
  }) {
    final groups = _groupSignatures(signatures);

    final duplicates = groups.where((g) => g.kind == GroupKind.duplicate).toList();
    final similar = groups.where((g) => g.kind == GroupKind.similar).toList();

    return <CleanupCategoryType, CleanupCategory>{
      CleanupCategoryType.duplicates: _fromGroups(
        CleanupCategoryType.duplicates,
        duplicates,
      ),
      CleanupCategoryType.similar: _fromGroups(
        CleanupCategoryType.similar,
        similar,
      ),
      CleanupCategoryType.screenshots: _fromItems(
        CleanupCategoryType.screenshots,
        _screenshots(items),
      ),
      CleanupCategoryType.screenRecordings: _fromItems(
        CleanupCategoryType.screenRecordings,
        _screenRecordings(items),
      ),
      CleanupCategoryType.blurry: _fromItems(
        CleanupCategoryType.blurry,
        _blurry(signatures),
        analyzed: _hasBlurAnalysis(signatures),
      ),
      CleanupCategoryType.largeVideos: _fromItems(
        CleanupCategoryType.largeVideos,
        _largeVideos(items),
      ),
      CleanupCategoryType.largePhotos: _fromItems(
        CleanupCategoryType.largePhotos,
        _largePhotos(items),
      ),
    };
  }

  /// 汇总整个相册的概况。
  ///
  /// [categories] 里各分类的候选条目可能互相重叠（例如一张模糊的截图），
  /// 因此这里按 id 去重后再统计，避免把可释放空间夸大。
  LibrarySummary summarize({
    required List<MediaItem> items,
    required Map<CleanupCategoryType, CleanupCategory> categories,
  }) {
    var totalBytes = 0;
    var photoCount = 0;
    var videoCount = 0;
    var estimated = false;

    for (final item in items) {
      totalBytes += item.effectiveSize;
      if (item.size == 0 && item.pixelCount > 0) estimated = true;
      if (item.isVideo) {
        videoCount++;
      } else if (item.kind == MediaKind.image) {
        photoCount++;
      }
    }

    final seen = <String>{};
    var reclaimable = 0;
    var candidateCount = 0;
    for (final category in categories.values) {
      for (final item in category.items) {
        if (seen.add(item.id)) {
          reclaimable += item.effectiveSize;
          candidateCount++;
        }
      }
    }

    return LibrarySummary(
      totalCount: items.length,
      photoCount: photoCount,
      videoCount: videoCount,
      totalBytes: totalBytes,
      reclaimableBytes: reclaimable,
      candidateCount: candidateCount,
      reclaimableIsEstimate: estimated,
    );
  }

  /// 相似度分组。[groupSimilarVideos] 为 false 时只对图片分组。
  List<MediaGroup> _groupSignatures(List<AssetSignature> signatures) {
    final candidates = groupSimilarVideos
        ? signatures
        : signatures.where((s) => !s.item.isVideo).toList();

    final grouper = SimilarityGrouper(options: similarity);
    return grouper.group(candidates);
  }

  CleanupCategory _fromGroups(
    CleanupCategoryType type,
    List<MediaGroup> groups,
  ) {
    final items = <MediaItem>[];
    var totalBytes = 0;
    var totalCount = 0;

    for (final group in groups) {
      items.addAll(group.deletable);
      for (final item in group.items) {
        totalBytes += item.effectiveSize;
        totalCount++;
      }
    }

    return CleanupCategory(
      type: type,
      groups: groups,
      items: items,
      totalCount: totalCount,
      totalBytes: totalBytes,
    );
  }

  CleanupCategory _fromItems(
    CleanupCategoryType type,
    List<MediaItem> items, {
    bool analyzed = true,
  }) {
    var totalBytes = 0;
    for (final item in items) {
      totalBytes += item.effectiveSize;
    }

    return CleanupCategory(
      type: type,
      items: items,
      totalCount: items.length,
      totalBytes: totalBytes,
      analyzed: analyzed,
    );
  }

  /// 截图：新的排在前面（通常越久远的截图越没用）。
  List<MediaItem> _screenshots(List<MediaItem> items) {
    final cutoff = screenshotMinAge == Duration.zero
        ? null
        : DateTime.now().subtract(screenshotMinAge);

    final result = items.where((item) {
      if (!item.isScreenshot) return false;
      if (cutoff == null) return true;
      final created = item.createdAt;
      return created == null || created.isBefore(cutoff);
    }).toList();

    result.sort((a, b) => _compareDateDesc(a.createdAt, b.createdAt));
    return result;
  }

  List<MediaItem> _screenRecordings(List<MediaItem> items) {
    final result = items.where((item) => item.isScreenRecording).toList();
    result.sort((a, b) => b.effectiveSize.compareTo(a.effectiveSize));
    return result;
  }

  /// 模糊照片：最模糊的排最前面，方便优先处理。
  List<MediaItem> _blurry(List<AssetSignature> signatures) {
    final blurry = signatures
        .where((s) => s.isBlurry && s.item.kind == MediaKind.image)
        .toList();

    blurry.sort((a, b) =>
        (a.sharpness ?? 0).compareTo(b.sharpness ?? 0));

    return blurry.map((s) => s.item).toList();
  }

  /// 只要还有一张图没能算出清晰度，就说明分析尚未完成。
  bool _hasBlurAnalysis(List<AssetSignature> signatures) {
    final images = signatures.where((s) => s.item.kind == MediaKind.image);
    if (images.isEmpty) return true;
    return images.every((s) => s.hasSharpness);
  }

  List<MediaItem> _largeVideos(List<MediaItem> items) {
    final result = items
        .where((item) =>
            item.isVideo &&
            !item.isScreenRecording &&
            item.effectiveSize >= largeVideoBytes)
        .toList();
    result.sort((a, b) => b.effectiveSize.compareTo(a.effectiveSize));
    return result;
  }

  List<MediaItem> _largePhotos(List<MediaItem> items) {
    final result = items
        .where((item) =>
            item.kind == MediaKind.image && item.effectiveSize >= largePhotoBytes)
        .toList();
    result.sort((a, b) => b.effectiveSize.compareTo(a.effectiveSize));
    return result;
  }

  int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}
