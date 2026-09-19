import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../state/selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail.dart';

/// 全屏查看单张照片，并就地切换「是否删除」。
///
/// 复核时经常需要放大确认两张照片到底是不是同一张，
/// 来回切换页面太慢，所以查看器直接内嵌勾选开关。
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.selection,
  });

  final List<MediaItem> items;
  final int initialIndex;

  /// 与复核页共享的勾选状态；为空时只做浏览。
  final SelectionController? selection;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final item = widget.items[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15, color: Colors.white),
        ),
        actions: <Widget>[
          if (item.isScreenshot)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.smartphone, size: 18, color: Colors.white70),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final current = widget.items[index];
                return GestureDetector(
                  onTap: selection == null || current.isFavorite
                      ? null
                      : () => selection.toggle(current.id),
                  child: Center(
                    child: MediaThumbnail(
                      item: current,
                      size: 1024,
                      fit: BoxFit.contain,
                      showVideoBadge: false,
                    ),
                  ),
                );
              },
            ),
          ),
          _InfoBar(
            item: item,
            selection: selection,
          ),
        ],
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.item, required this.selection});

  final MediaItem item;
  final SelectionController? selection;

  @override
  Widget build(BuildContext context) {
    final controller = selection;

    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _describe(item),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  if (item.isFavorite)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.favorite, size: 14, color: AppColors.danger),
                        SizedBox(width: 4),
                        Text(
                          '收藏',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
              if (controller != null && !item.isFavorite) ...<Widget>[
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final selected = controller.isSelected(item.id);
                    return SizedBox(
                      width: double.infinity,
                      child: selected
                          ? OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => controller.toggle(item.id),
                              icon: const Icon(Icons.undo, size: 18),
                              label: const Text('保留这一张'),
                            )
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                              ),
                              onPressed: () => controller.toggle(item.id),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('标记为删除'),
                            ),
                    );
                  },
                ),
              ],
              if (item.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '收藏的照片不会被清理',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(MediaItem item) {
    final parts = <String>[];
    final date = item.createdAt;
    if (date != null) parts.add(formatDateTime(date));
    if (item.pixelCount > 0) parts.add('${item.width}×${item.height}');
    parts.add(formatBytes(item.effectiveSize));
    if (item.isVideo) parts.add('时长 ${formatDurationText(item.duration)}');
    return parts.join(' · ');
  }
}
