import 'media_group.dart';
import 'media_item.dart';

/// 首页上的清理分类。
///
/// 图标与配色属于展示层，放在 `lib/ui/theme/category_style.dart`，
/// 这里只保留与界面框架无关的文案和数据。
enum CleanupCategoryType {
  duplicates(
    title: '重复照片',
    description: '内容完全相同的照片，只保留一张',
    actionLabel: '查看重复项',
  ),
  similar(
    title: '相似照片',
    description: '同一场景连拍或轻微改动，挑最好的一张',
    actionLabel: '挑选最佳',
  ),
  screenshots(
    title: '截图',
    description: '屏幕截图，看完通常就不再需要',
    actionLabel: '清理截图',
  ),
  screenRecordings(
    title: '屏幕录制',
    description: '录屏文件，往往体积很大',
    actionLabel: '清理录屏',
  ),
  blurry(
    title: '模糊照片',
    description: '失焦或手抖拍糊的照片',
    actionLabel: '清理模糊照片',
  ),
  largeVideos(
    title: '超大视频',
    description: '占用空间最多的视频文件',
    actionLabel: '查看大视频',
  ),
  largePhotos(
    title: '超大照片',
    description: '体积异常大的照片，例如全景原片',
    actionLabel: '查看大照片',
  );

  const CleanupCategoryType({
    required this.title,
    required this.description,
    required this.actionLabel,
  });

  /// 分类名，例如「重复照片」。
  final String title;

  /// 一句话说明，展示在卡片副标题。
  final String description;

  /// 卡片按钮文案。
  final String actionLabel;

  /// 是否需要先做图像分析（只有这类分类会读缩略图）。
  bool get requiresImageAnalysis =>
      this == CleanupCategoryType.duplicates ||
      this == CleanupCategoryType.similar ||
      this == CleanupCategoryType.blurry;
}

/// 一个分类下的清理建议。
class CleanupCategory {
  const CleanupCategory({
    required this.type,
    this.groups = const <MediaGroup>[],
    this.items = const <MediaItem>[],
    this.totalCount = 0,
    this.totalBytes = 0,
    this.analyzed = true,
  });

  final CleanupCategoryType type;

  /// 分组结果，仅重复 / 相似分类非空。
  final List<MediaGroup> groups;

  /// 建议清理的条目（用户可以在界面上取消勾选其中一部分）。
  final List<MediaItem> items;

  /// 该分类下的条目总数（包括建议保留的）。
  final int totalCount;

  /// 该分类下所有条目的总体积。
  final int totalBytes;

  /// 图像分析是否已经跑完。未完成时 [items] 可能不完整。
  final bool analyzed;

  /// 建议清理的数量。
  int get candidateCount => items.length;

  /// 清理后可释放的字节数。
  int get reclaimableBytes =>
      items.fold(0, (sum, item) => sum + item.effectiveSize);

  /// 是否有可清理的内容。
  bool get hasCandidates => items.isNotEmpty;

  CleanupCategory copyWith({
    List<MediaItem>? items,
    int? totalCount,
    int? totalBytes,
    bool? analyzed,
  }) {
    return CleanupCategory(
      type: type,
      groups: groups,
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      totalBytes: totalBytes ?? this.totalBytes,
      analyzed: analyzed ?? this.analyzed,
    );
  }

  @override
  String toString() =>
      'CleanupCategory(${type.name}, $candidateCount/$totalCount, '
      '$reclaimableBytes B)';
}

/// 整个相册的概况，展示在首页顶部。
class LibrarySummary {
  const LibrarySummary({
    required this.totalCount,
    required this.photoCount,
    required this.videoCount,
    required this.totalBytes,
    required this.reclaimableBytes,
    required this.candidateCount,
    this.reclaimableIsEstimate = false,
  });

  const LibrarySummary.empty()
      : totalCount = 0,
        photoCount = 0,
        videoCount = 0,
        totalBytes = 0,
        reclaimableBytes = 0,
        candidateCount = 0,
        reclaimableIsEstimate = false;

  final int totalCount;
  final int photoCount;
  final int videoCount;
  final int totalBytes;

  /// 所有分类加起来可释放的字节数。
  final int reclaimableBytes;

  /// 所有分类加起来建议清理的条目数。
  final int candidateCount;

  /// 可释放空间里是否包含估算值（部分资源系统未提供文件大小）。
  final bool reclaimableIsEstimate;
}
