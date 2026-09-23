import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cleanup_progress.dart';
import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../data/photo_repository.dart';
import '../../state/cleanup_progress_controller.dart';
import '../swipe/swipe_clean_page.dart';
import '../viewer/photo_viewer_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_thumbnail.dart';

/// 相册列表。
///
/// 点进去可以浏览，也可以整本滑动清理——在设置里建的相册（「证件照」
/// 「待打印」）往往才是真的需要一口气处理完的那一批。
class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  late Future<List<MediaAlbum>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PhotoRepository>().loadAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('相册')),
      body: FutureBuilder<List<MediaAlbum>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: '读取相册失败',
              message: '${snapshot.error}',
            );
          }

          final albums = snapshot.data ?? const <MediaAlbum>[];
          if (albums.isEmpty) {
            return const EmptyState(
              icon: Icons.photo_album_outlined,
              title: '没有找到相册',
              message: '你还没有创建过相册。',
            );
          }

          return ListView.separated(
            itemCount: albums.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final album = albums[index];
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    album.isAll
                        ? Icons.photo_library
                        : Icons.photo_album_outlined,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(album.name),
                subtitle: Text('${formatCount(album.assetCount)} 项'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlbumDetailPage(album: album),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 单个相册里的内容，可以浏览，也可以整本滑动清理。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.album});

  final MediaAlbum album;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  /// 从仓库读回来的全部条目；null 表示还在读。
  ///
  /// 刻意不把 `Future` 直接交给 `FutureBuilder`：删掉几张之后重新拉一遍
  /// 整个相册，两千项就是十次往返，而本地已经把列表拿在手里了。
  List<MediaItem>? _loaded;

  Object? _error;

  /// 已经删掉的 id。从 [_loaded] 里抠掉，而不是改动它。
  final Set<String> _deleted = <String>{};

  String get _scope => CleanupScopes.album(widget.album.id);

  List<MediaItem> get _visible {
    final loaded = _loaded;
    if (loaded == null) return const <MediaItem>[];
    if (_deleted.isEmpty) return loaded;
    return loaded
        .where((item) => !_deleted.contains(item.id))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<PhotoRepository>();
    try {
      final items =
          await repository.loadAlbumItems(widget.album.id, maxItems: 2000);
      if (!mounted) return;
      setState(() => _loaded = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _openSwipe() {
    final items = _visible;
    if (items.isEmpty) return;

    final progress = context.read<CleanupProgressController>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeCleanPage(
          title: widget.album.name,
          items: items,
          startIndex: progress.startIndexFor(_scope, items),
          scope: _scope,
          onDeleted: (ids) => setState(() => _deleted.addAll(ids)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: <Widget>[
          if (items.isNotEmpty)
            IconButton(
              key: const Key('album-swipe'),
              tooltip: '滑动清理',
              icon: const Icon(Icons.swipe),
              onPressed: _openSwipe,
            ),
        ],
      ),
      body: _buildBody(items),
    );
  }

  Widget _buildBody(List<MediaItem> items) {
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '读取失败',
        message: '$_error',
      );
    }

    if (_loaded == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.image_outlined,
        title: '这个相册是空的',
      );
    }

    return Column(
      children: <Widget>[
        _AlbumProgressBar(scope: _scope),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PhotoViewerPage(
                    items: items,
                    initialIndex: index,
                    selection: null,
                  ),
                ),
              ),
              child: MediaThumbnail(item: items[index], size: 200),
            ),
          ),
        ),
      ],
    );
  }
}

/// 这个相册上次清到哪儿了；没清理过就什么都不显示。
class _AlbumProgressBar extends StatelessWidget {
  const _AlbumProgressBar({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<CleanupProgressController>();
    final record = progress.progressFor(scope);
    if (record == null || record.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final anchor = record.anchorDate;
    final parts = <String>[
      if (anchor != null) '上次清理到 ${formatDayLabel(anchor)}',
      '已处理 ${formatCount(record.processed)} 张',
      if (record.deleted > 0) '已删除 ${formatCount(record.deleted)} 项',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: theme.colorScheme.primary.withAlpha(16),
      child: Row(
        children: <Widget>[
          Icon(Icons.history, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => progress.reset(scope),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
  }
}
