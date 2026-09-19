import '../models/media_item.dart';

/// 保留项的选择结果。
class KeeperDecision {
  const KeeperDecision({required this.keeper, required this.ranked, required this.reason});

  /// 建议保留的那一项。
  final MediaItem keeper;

  /// 按「值得保留」从高到低排序的完整列表。
  final List<MediaItem> ranked;

  /// 选择理由的中文说明，直接展示给用户看。
  final String reason;
}

/// 决定一组相似照片里「保留哪一张」。
///
/// 打分原则（权重从高到低）：
/// 1. 收藏的照片永不删除；
/// 2. 本地已有的优先于 iCloud 占位符（删掉占位符并不会释放空间）；
/// 3. 分辨率高的优先；
/// 4. 清晰度高的优先（作为同分辨率下的决胜项）；
/// 5. 文件更大的优先（通常保留了更多细节）；
/// 6. 最后按拍摄时间、id 排序，保证结果稳定可复现。
class KeeperSelector {
  const KeeperSelector();

  /// 收藏项的权重，足以压过其他所有因素。
  static const double _favoriteWeight = 1e12;

  /// 本地文件的权重。
  static const double _localWeight = 1e9;

  /// 实况照片略微优先于普通照片（保留下来的信息更多）。
  static const double _livePhotoWeight = 5e5;

  /// 清晰度权重：清晰度最大按 500 归一化，再乘该系数。
  static const double _sharpnessWeight = 200;

  /// 计算单个条目的保留得分，越大越应该保留。
  double score(
    MediaItem item, {
    double? sharpness,
  }) {
    var score = 0.0;

    if (item.isFavorite) score += _favoriteWeight;
    if (item.isLocallyAvailable) score += _localWeight;
    if (item.isLivePhoto) score += _livePhotoWeight;

    // 主排序项：像素总数（分辨率）。
    score += item.pixelCount.toDouble();

    // 次排序项：清晰度。归一化后最多贡献 10 万，不会盖过分辨率差异。
    if (sharpness != null && sharpness > 0) {
      score += sharpness.clamp(0, 500) * _sharpnessWeight;
    }

    // 三次排序项：文件大小（KB），最多贡献几万。
    score += item.effectiveSize / 1024;

    return score;
  }

  /// 按保留优先级排序（第一个最值得保留）。
  List<MediaItem> rank(
    Iterable<MediaItem> items, {
    Map<String, double>? sharpness,
  }) {
    final sorted = items.toList();
    final scores = <String, double>{
      for (final item in sorted) item.id: score(item, sharpness: sharpness?[item.id]),
    };

    sorted.sort((a, b) {
      final byScore = scores[b.id]!.compareTo(scores[a.id]!);
      if (byScore != 0) return byScore;

      // 相同得分时按拍摄时间升序（保留最早的那张，通常是原始照片）。
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime != null && bTime != null && aTime != bTime) {
        return aTime.compareTo(bTime);
      }
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;

      // 最后按 id 排序，保证顺序稳定。
      return a.id.compareTo(b.id);
    });

    return sorted;
  }

  /// 选出一组中应保留的那一项。
  KeeperDecision decide(
    Iterable<MediaItem> items, {
    Map<String, double>? sharpness,
  }) {
    final ranked = rank(items, sharpness: sharpness);
    if (ranked.isEmpty) {
      throw ArgumentError('不能对空集合选择保留项');
    }
    final keeper = ranked.first;
    return KeeperDecision(
      keeper: keeper,
      ranked: ranked,
      reason: describeReason(keeper, ranked.skip(1)),
    );
  }

  /// 生成人类可读的选择理由。
  static String describeReason(MediaItem keeper, Iterable<MediaItem> others) {
    if (keeper.isFavorite) return '保留收藏的照片';

    final othersList = others.toList();
    if (othersList.isEmpty) return '保留这张';

    final maxPixels =
        othersList.map((item) => item.pixelCount).fold<int>(0, (a, b) => a > b ? a : b);
    if (keeper.pixelCount > maxPixels && keeper.pixelCount > 0) {
      return '保留分辨率最高的照片';
    }

    final anyCloudPlaceholder = othersList.any((item) => !item.isLocallyAvailable);
    if (anyCloudPlaceholder && keeper.isLocallyAvailable) {
      return '保留本地已有的照片';
    }

    if (keeper.isLivePhoto &&
        othersList.every((item) => !item.isLivePhoto)) {
      return '保留实况照片';
    }

    final maxSize = othersList
        .map((item) => item.effectiveSize)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (keeper.effectiveSize > maxSize) return '保留文件最大（细节最完整）的一张';

    return '保留最早拍摄的一张';
  }
}
