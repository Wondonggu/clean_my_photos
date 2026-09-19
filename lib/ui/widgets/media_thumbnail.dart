import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../data/thumbnail_cache.dart';
import '../theme/app_theme.dart';

/// 从系统相册读取并显示一张缩略图。
///
/// 自己管理加载状态，避免在 build 里发起异步请求。
class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.item,
    this.size = 200,
    this.fit = BoxFit.cover,
    this.showVideoBadge = true,
  });

  final MediaItem item;

  /// 请求的缩略图边长（像素）。
  final int size;

  final BoxFit fit;

  /// 视频是否显示时长角标。
  final bool showVideoBadge;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.size != widget.size) {
      _bytes = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final cache = context.read<ThumbnailCache>();

    final cached = cache.peek(widget.item.id, size: widget.size);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _loading = false;
        });
      }
      return;
    }

    final bytes = await cache.get(widget.item.id, size: widget.size);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (bytes != null)
          Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          )
        else
          Container(
            // 不用 `colorScheme.surfaceVariant`：该字段在较新的 Flutter 里
            // 已被弃用，用 onSurface 加透明度在所有版本上都安全。
            color: theme.colorScheme.onSurface.withAlpha(20),
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.item.isVideo
                        ? Icons.videocam_off_outlined
                        : Icons.image_not_supported_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        if (widget.showVideoBadge && widget.item.isVideo)
          Positioned(
            left: 4,
            bottom: 4,
            child: _Badge(
              icon: Icons.play_arrow,
              label: formatDuration(widget.item.duration),
            ),
          ),
        if (widget.item.isScreenshot)
          const Positioned(
            right: 4,
            top: 4,
            child: _Badge(icon: Icons.smartphone, label: '截图'),
          ),
        if (widget.item.isFavorite)
          Positioned(
            right: 4,
            top: widget.item.isScreenshot ? 26 : 4,
            child: const Icon(
              Icons.favorite,
              size: 16,
              color: AppColors.danger,
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: const BoxDecoration(
        color: AppColors.scrim,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
