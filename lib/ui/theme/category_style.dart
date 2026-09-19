import 'package:flutter/material.dart';

import '../../core/models/cleanup_category.dart';
import 'app_theme.dart';

/// 分类的图标与配色。
///
/// 放在展示层，让 core 里的 [CleanupCategoryType] 保持与 Flutter 无关。
extension CleanupCategoryStyle on CleanupCategoryType {
  IconData get icon {
    switch (this) {
      case CleanupCategoryType.duplicates:
        return Icons.filter_none;
      case CleanupCategoryType.similar:
        return Icons.auto_awesome_motion;
      case CleanupCategoryType.screenshots:
        return Icons.smartphone;
      case CleanupCategoryType.screenRecordings:
        return Icons.videocam;
      case CleanupCategoryType.blurry:
        return Icons.blur_on;
      case CleanupCategoryType.largeVideos:
        return Icons.movie;
      case CleanupCategoryType.largePhotos:
        return Icons.photo_size_select_large;
    }
  }

  Color get color {
    switch (this) {
      case CleanupCategoryType.duplicates:
        return AppColors.blue;
      case CleanupCategoryType.similar:
        return AppColors.purple;
      case CleanupCategoryType.screenshots:
        return AppColors.teal;
      case CleanupCategoryType.screenRecordings:
        return AppColors.orange;
      case CleanupCategoryType.blurry:
        return AppColors.pink;
      case CleanupCategoryType.largeVideos:
        return AppColors.indigo;
      case CleanupCategoryType.largePhotos:
        return AppColors.brown;
    }
  }

  /// 卡片上的图标底色。
  ///
  /// `withAlpha` 接受 0–255 的整数，在各版本 Flutter 上都稳定可用
  ///（`withOpacity` / `withValues` 则在不同版本间有过更名）。
  Color get iconBackground => color.withAlpha(38);
}
