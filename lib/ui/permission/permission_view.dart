import 'package:flutter/material.dart';

import '../../data/photo_repository.dart';
import '../theme/app_theme.dart';

/// 权限引导页。
///
/// 两种情况：还没授权（可以弹系统对话框），以及被拒绝/受限
/// （只能引导用户去系统设置里改）。把「为什么需要权限」讲清楚，
/// 用户才愿意点。
class PermissionView extends StatelessWidget {
  const PermissionView({
    super.key,
    required this.permission,
    required this.isBlocked,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final LibraryPermission permission;

  /// true 表示确定无法再弹系统对话框，只能去设置里改。
  final bool isBlocked;

  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(
              isBlocked ? Icons.lock_outline : Icons.photo_library_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              isBlocked ? '需要相册访问权限' : '允许访问你的照片',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              isBlocked
                  ? '当前状态：${permission.status.label}。\n'
                      '请到「设置 → 相册清理 → 照片」里选择「所有照片」，'
                      '然后回到这里重新读取。'
                  : '相册清理需要读取照片和视频，才能找出重复、相似、'
                      '截图和模糊的照片。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            const _PrivacyPoints(),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: isBlocked ? onOpenSettings : onRequest,
              child: Text(isBlocked ? '打开系统设置' : '允许访问'),
            ),
            if (isBlocked) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRequest,
                child: const Text('再试一次'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrivacyPoints extends StatelessWidget {
  const _PrivacyPoints();

  static const List<(IconData, String)> _points = <(IconData, String)>[
    (Icons.phonelink_off, '所有分析都在本机完成，照片不会上传'),
    (Icons.delete_sweep_outlined, '删除前必须二次确认，收藏的照片不会被删'),
    (Icons.undo, '删除的照片会进入系统「最近删除」，30 天内可恢复'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (icon, text) in _points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 18, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
