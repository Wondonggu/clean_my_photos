import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/formatters.dart';
import '../../data/photo_repository.dart';
import '../viewer/photo_viewer_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_thumbnail.dart';

/// 相册列表。
///
/// 这里只做浏览：iOS 上按相册删除资源的行为不容易预期，
/// 清理仍然统一走首页那几个分类。
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

/// 单个相册里的内容，只读浏览。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.album});

  final MediaAlbum album;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Future<List<MediaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<PhotoRepository>()
        .loadAlbumItems(widget.album.id, maxItems: 2000);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: FutureBuilder<List<MediaItem>>(
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
              title: '读取失败',
              message: '${snapshot.error}',
            );
          }

          final items = snapshot.data ?? const <MediaItem>[];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.image_outlined,
              title: '这个相册是空的',
            );
          }

          return GridView.builder(
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
          );
        },
      ),
    );
  }
}
