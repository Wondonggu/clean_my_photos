import 'dart:typed_data';

import 'photo_repository.dart';

/// 缩略图的内存缓存（最近最少使用淘汰）。
///
/// 网格在滚动时会反复重建单元格，没有缓存的话同一个缩略图会被反复
/// 从系统相册里解码出来，既慢又耗电。这里只缓存最近用到的少量图片，
/// 内存占用可控（400 张 200px 的 JPEG 大约 10 MB）。
class ThumbnailCache {
  ThumbnailCache(this.repository, {this.capacity = 400})
      : assert(capacity > 0, 'capacity 必须为正数');

  final PhotoRepository repository;
  final int capacity;

  /// `LinkedHashMap` 保持插入顺序，头部就是最久未使用的。
  final Map<String, Uint8List> _entries = <String, Uint8List>{};

  int get length => _entries.length;

  static String _key(String id, int size) => '$id@$size';

  /// 取缩略图；命中缓存时不会访问系统相册。
  Future<Uint8List?> get(String id, {int size = 200}) async {
    final key = _key(id, size);

    final cached = _entries.remove(key);
    if (cached != null) {
      // 重新插入到末尾，标记为「最近使用」。
      _entries[key] = cached;
      return cached;
    }

    final bytes = await repository.thumbnail(id, size: size);
    if (bytes != null && bytes.isNotEmpty) {
      _entries[key] = bytes;
      _evictIfNeeded();
    }
    return bytes;
  }

  /// 只有缓存里已经有这张图时才同步返回，避免在 build 里触发异步加载。
  Uint8List? peek(String id, {int size = 200}) {
    final key = _key(id, size);
    final cached = _entries.remove(key);
    if (cached == null) return null;
    _entries[key] = cached;
    return cached;
  }

  /// 条目被删除后清掉对应的缓存。
  void evict(String id) {
    _entries.removeWhere((key, _) => key.startsWith('$id@'));
  }

  void clear() => _entries.clear();

  void _evictIfNeeded() {
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
    }
  }
}
