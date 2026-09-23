import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../data/asset_locator_channel.dart';
import '../../data/photo_repository.dart';
import '../../state/selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail.dart';

/// 全屏查看单张照片，并就地切换「是否删除」。
///
/// 复核时经常需要放大确认两张照片到底是不是同一张，
/// 来回切换页面太慢，所以查看器直接内嵌勾选开关。
///
/// 另外还会显示这张照片在系统「照片」App 里属于哪些相册——用户想确认
/// 「这张删了会不会把某个相册清空」时，只能回到系统相册里一张张翻，
/// 这里直接给出答案。
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
  ///
  /// 为空也会照常显示「所在相册」——纯浏览时反而更需要它。
  final SelectionController? selection;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller;
  late int _index;

  /// 当前这张的高清图。
  ///
  /// 刻意只有一份，翻页即弃：一张 3072 的长边就是好几 MB，按页缓存很快
  /// 就会把内存吃满。也不走 `ThumbnailCache`——那个缓存按**条数**限量
  /// （400 条），放缩略图正合适，放高清图就是几百 MB。
  Uint8List? _hiRes;

  /// 已经为哪张发起过高清请求，用来去重：缩放过程中每帧都会问一次。
  String? _hiResRequestedId;

  /// 系统「照片」App 里的归属，按当前这张惰性查询。
  AssetLocation? _location;
  String? _locationLoadingId;

  bool _albumsExpanded = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _index);
    _loadLocation(_current);
  }

  MediaItem get _current => widget.items[_index];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- 高清与原图

  /// 用户在放大时才去取高清图。
  ///
  /// 预览用的缩略图长边只有 1024，放大了就是一团糊；但一进页面就预取
  /// 又太亏——用户大多数时候只是扫一眼就走了。
  void _requestHiRes(MediaItem item) {
    if (_hiResRequestedId == item.id) return;
    _hiResRequestedId = item.id;
    unawaited(_loadHiRes(item));
  }

  Future<void> _loadHiRes(MediaItem item) async {
    final repository = context.read<PhotoRepository>();
    final bytes = await repository.fullImage(item.id);
    // 翻页之后结果就过期了，直接丢掉。
    if (!mounted || _hiResRequestedId != item.id) return;
    setState(() => _hiRes = bytes);
  }

  // ---------------------------------------------------------------- 相册归属

  void _loadLocation(MediaItem item) {
    if (_location?.assetId == item.id || _locationLoadingId == item.id) return;
    _locationLoadingId = item.id;
    unawaited(_fetchLocation(item));
  }

  Future<void> _fetchLocation(MediaItem item) async {
    final repository = context.read<PhotoRepository>();
    final location = await repository.locateAsset(item.id);
    if (!mounted || _locationLoadingId != item.id) return;
    setState(() {
      _location = location;
      _locationLoadingId = null;
    });
  }

  void _onPageChanged(int value) {
    setState(() {
      _index = value;
      _hiRes = null;
      _hiResRequestedId = null;
      _location = null;
      _locationLoadingId = null;
      _albumsExpanded = false;
    });
    _loadLocation(_current);
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final item = _current;

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
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) => _ZoomablePhoto(
                key: ValueKey<String>(widget.items[index].id),
                item: widget.items[index],
                selection: selection,
                // 只有当前这张的高清图会留在内存里。
                hiRes: widget.items[index].id == _hiResRequestedId
                    ? _hiRes
                    : null,
                onNeedsFullImage: () => _requestHiRes(widget.items[index]),
              ),
            ),
          ),
          _InfoBar(
            item: item,
            selection: selection,
            location: _location,
            loadingLocation: _locationLoadingId != null,
            albumsExpanded: _albumsExpanded,
            onToggleAlbums: () =>
                setState(() => _albumsExpanded = !_albumsExpanded),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 可缩放的照片

/// 一张可以双指缩放、双击放大到 2.5 倍的照片。
///
/// 缩放状态是**每页各自持有**的：`PageView` 会同时留着相邻页，共用一个
/// `TransformationController` 会让翻页时缩放跟着串台。
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.item,
    required this.selection,
    required this.hiRes,
    required this.onNeedsFullImage,
  });

  final MediaItem item;
  final SelectionController? selection;
  final Uint8List? hiRes;

  /// 需要更清楚的图了（第一次放大时触发一次）。
  final VoidCallback onNeedsFullImage;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  /// 双击放大的倍数。再大就该靠双指微调了，一步到位反而容易迷失。
  static const double doubleTapScale = 2.5;

  /// 超过这个倍数就算「放大了」。
  static const double zoomThreshold = 1.01;

  final TransformationController _transform = TransformationController();
  late final AnimationController _zoom;
  Animation<Matrix4>? _zoomAnimation;

  /// 当前是否处于放大状态。只用来决定要不要把拖动让给 PageView。
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final value = _zoomAnimation?.value;
        if (value != null) _transform.value = value;
      });
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > zoomThreshold;
    if (zoomed) widget.onNeedsFullImage();
    // 只有状态真的翻转时才重建：缩放过程中每帧都 setState 会让整页重画。
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _handleDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > zoomThreshold) {
      _animateTo(Matrix4.identity());
      return;
    }
    widget.onNeedsFullImage();
    _animateTo(Matrix4.identity()..scale(doubleTapScale));
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final item = widget.item;
    final canToggle = selection != null && !item.isFavorite;

    return GestureDetector(
      // 双击会让单击产生约 250ms 的判定延迟，这是双击缩放必须付的代价。
      onDoubleTap: _handleDoubleTap,
      onTap: canToggle ? () => selection.toggle(item.id) : null,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        // 没放大时把拖动让给 PageView：否则往左右划会被这里吃掉，
        // 翻不动页。
        panEnabled: _zoomed,
        child: Center(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              MediaThumbnail(
                item: item,
                size: 1024,
                fit: BoxFit.contain,
                showVideoBadge: false,
              ),
              // 高清图盖在缩略图上，尺寸和适配方式完全一致，所以换上去
              // 不会跳一下，只是从糊变清楚。
              if (widget.hiRes != null)
                Image.memory(
                  widget.hiRes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- 信息栏

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.item,
    required this.selection,
    required this.location,
    required this.loadingLocation,
    required this.albumsExpanded,
    required this.onToggleAlbums,
  });

  final MediaItem item;
  final SelectionController? selection;
  final AssetLocation? location;
  final bool loadingLocation;
  final bool albumsExpanded;
  final VoidCallback onToggleAlbums;

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 6),
              _LocationBlock(
                location: location,
                loading: loadingLocation,
                expanded: albumsExpanded,
                onToggle: onToggleAlbums,
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

/// 「这张照片在系统相册里属于哪儿」。
///
/// 结果没回来之前先占着位置（只说「读取中」），免得信息栏高度跳来跳去。
class _LocationBlock extends StatelessWidget {
  const _LocationBlock({
    required this.location,
    required this.loading,
    required this.expanded,
    required this.onToggle,
  });

  final AssetLocation? location;
  final bool loading;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final data = location;

    return Column(
      key: const Key('viewer-location'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.photo_album_outlined, size: 13, color: Colors.white38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                data == null
                    ? (loading ? '所在相册：读取中…' : '所在相册：—')
                    : describeLocation(data),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            if (data != null && data.memberships.length > 1)
              TextButton(
                key: const Key('viewer-location-toggle'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onToggle,
                child: Text(
                  expanded ? '收起' : '展开',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        if (data != null && data.isLimited)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '当前只允许访问部分照片，这里只显示已授权范围内的相册。',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        if (expanded && data != null)
          for (final membership in data.memberships)
            Padding(
              key: Key('viewer-album-${membership.albumId}'),
              padding: const EdgeInsets.only(top: 4, left: 19),
              child: Text(
                _describeMembership(membership),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
      ],
    );
  }

  static String _describeMembership(AssetAlbumMembership m) {
    final parts = <String>[m.name, m.kind.label];
    if (m.hasIndex) {
      final total = m.assetCount;
      parts.add(total == null ? '第 ${m.index} 张' : '第 ${m.index} / $total 张');
    }
    return parts.join(' · ');
  }
}
