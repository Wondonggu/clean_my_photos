import '../models/asset_signature.dart';
import '../models/media_group.dart';
import '../models/media_item.dart';
import '../utils/perceptual_hash.dart';
import 'keeper_selector.dart';

/// 相似度分组的参数。
///
/// 三档预设对应界面上的「严格 / 均衡 / 宽松」：
/// 距离阈值越宽松，越能把同一场景的连拍归到一组，但误判风险也越高。
class SimilarityOptions {
  const SimilarityOptions({
    this.maxDistance = 8,
    this.timeWindow = const Duration(minutes: 2),
    this.aspectRatioTolerance = 0.06,
  });

  /// 只有严格一致的照片才会被归为一组。
  static const SimilarityOptions strict = SimilarityOptions(
    maxDistance: 2,
    timeWindow: Duration(seconds: 30),
    aspectRatioTolerance: 0.02,
  );

  /// 默认档：对绝大多数相册都适用。
  static const SimilarityOptions balanced = SimilarityOptions();

  /// 更激进：把构图相近的连拍也归为一组。
  static const SimilarityOptions loose = SimilarityOptions(
    maxDistance: 14,
    timeWindow: Duration(minutes: 10),
    aspectRatioTolerance: 0.15,
  );

  /// 64 位哈希的汉明距离阈值，超过则不算相似。
  final int maxDistance;

  /// 只有拍摄时间相近的照片才会互相比较（避免把不同时期的照片误判为重复）。
  final Duration timeWindow;

  /// 宽高比的相对容差。差异过大说明是裁剪过的不同画面，不参与聚类。
  final double aspectRatioTolerance;

  SimilarityOptions copyWith({
    int? maxDistance,
    Duration? timeWindow,
    double? aspectRatioTolerance,
  }) {
    return SimilarityOptions(
      maxDistance: maxDistance ?? this.maxDistance,
      timeWindow: timeWindow ?? this.timeWindow,
      aspectRatioTolerance: aspectRatioTolerance ?? this.aspectRatioTolerance,
    );
  }

  /// 界面上展示的档位名。
  String get label {
    if (maxDistance <= 2) return '严格';
    if (maxDistance <= 10) return '均衡';
    return '宽松';
  }
}

/// 把一批带指纹的媒体聚成「重复 / 相似」分组。
///
/// 算法：
/// 1. **完全相同的一批**：哈希一致的条目直接归为一组，忽略拍摄时间，
///    这能覆盖「同一张图被保存了两次」这类时间跨度很大的情况；
/// 2. **时间邻近的一批**：按拍摄时间排序后做滑动窗口，只在
///    [SimilarityOptions.timeWindow] 范围内两两比较汉明距离，取并查集连通分量。
///    使用单链接聚类，因此 A~B、B~C 会把 A、B、C 归到同一组。
class SimilarityGrouper {
  const SimilarityGrouper({
    this.options = const SimilarityOptions(),
    this.keeperSelector = const KeeperSelector(),
  });

  final SimilarityOptions options;
  final KeeperSelector keeperSelector;

  /// 返回按「可释放空间」从大到小排序的分组列表。
  List<MediaGroup> group(List<AssetSignature> signatures) {
    final entries = <AssetSignature>[];
    for (final signature in signatures) {
      if (signature.hash != null) entries.add(signature);
    }
    if (entries.length < 2) return const <MediaGroup>[];

    final unionFind = _UnionFind(entries.length);

    // 第一步：完全相同的哈希（忽略时间）。
    final byHash = <PerceptualHash, List<int>>{};
    for (var i = 0; i < entries.length; i++) {
      byHash.putIfAbsent(entries[i].hash!, () => <int>[]).add(i);
    }
    for (final bucket in byHash.values) {
      if (bucket.length < 2) continue;
      for (var k = 1; k < bucket.length; k++) {
        if (_compatible(entries[bucket.first], entries[bucket[k]])) {
          unionFind.union(bucket.first, bucket[k]);
        }
      }
    }

    // 第二步：时间邻近的相似哈希。
    final ordered = List<int>.generate(entries.length, (i) => i)
      ..sort((a, b) => _compareByTime(entries[a], entries[b]));

    for (var i = 0; i < ordered.length; i++) {
      final left = entries[ordered[i]];
      final leftTime = left.item.createdAt;
      // 没有拍摄时间的条目已在第一步处理过完全一致的情况，这里跳过。
      if (leftTime == null) continue;

      for (var j = i + 1; j < ordered.length; j++) {
        final right = entries[ordered[j]];
        final rightTime = right.item.createdAt;
        if (rightTime == null) break;

        if (rightTime.difference(leftTime).abs() > options.timeWindow) break;
        if (unionFind.connected(ordered[i], ordered[j])) continue;
        if (!_compatible(left, right)) continue;

        final distance = left.hash!.distanceTo(right.hash!);
        if (distance <= options.maxDistance) {
          unionFind.union(ordered[i], ordered[j]);
        }
      }
    }

    // 收集连通分量。
    final components = <int, List<int>>{};
    for (var i = 0; i < entries.length; i++) {
      components.putIfAbsent(unionFind.find(i), () => <int>[]).add(i);
    }

    final groups = <MediaGroup>[];
    for (final indices in components.values) {
      if (indices.length < 2) continue;
      groups.add(_buildGroup(entries, indices));
    }

    groups.sort((a, b) {
      final byReclaim = b.reclaimableBytes.compareTo(a.reclaimableBytes);
      if (byReclaim != 0) return byReclaim;
      return b.items.length.compareTo(a.items.length);
    });

    return groups;
  }

  MediaGroup _buildGroup(List<AssetSignature> entries, List<int> indices) {
    final items = <MediaItem>[];
    final sharpness = <String, double>{};

    for (final index in indices) {
      final signature = entries[index];
      items.add(signature.item);
      if (signature.sharpness != null) {
        sharpness[signature.item.id] = signature.sharpness!;
      }
    }

    final decision = keeperSelector.decide(items, sharpness: sharpness);
    final keeperHash = entries[indices.firstWhere(
      (index) => entries[index].item.id == decision.keeper.id,
    )].hash!;

    // 以「与建议保留项的差异」作为整组的相似度指标，计算量是 O(n)。
    var maxDistance = 0;
    for (final index in indices) {
      final distance = entries[index].hash!.distanceTo(keeperHash);
      if (distance > maxDistance) maxDistance = distance;
    }

    return MediaGroup(
      items: decision.ranked,
      keeperId: decision.keeper.id,
      kind: maxDistance == 0 ? GroupKind.duplicate : GroupKind.similar,
      maxDistance: maxDistance,
    );
  }

  /// 只有同类型、宽高比接近的条目才值得比较。
  bool _compatible(AssetSignature a, AssetSignature b) {
    if (a.item.kind != b.item.kind) return false;

    final ratioA = a.item.aspectRatio;
    final ratioB = b.item.aspectRatio;
    if (ratioA <= 0 || ratioB <= 0) return true;

    return (ratioA - ratioB).abs() / ratioA <= options.aspectRatioTolerance;
  }

  int _compareByTime(AssetSignature a, AssetSignature b) {
    final timeA = a.item.createdAt;
    final timeB = b.item.createdAt;
    if (timeA == null && timeB == null) return a.item.id.compareTo(b.item.id);
    if (timeA == null) return 1;
    if (timeB == null) return -1;
    final byTime = timeA.compareTo(timeB);
    if (byTime != 0) return byTime;
    return a.item.id.compareTo(b.item.id);
  }
}

/// 并查集。
class _UnionFind {
  _UnionFind(int size)
      : _parent = List<int>.generate(size, (i) => i),
        _rank = List<int>.filled(size, 0);

  final List<int> _parent;
  final List<int> _rank;

  int find(int value) {
    var root = value;
    while (_parent[root] != root) {
      // 路径压缩：先找到根，再统一改父指针。
      _parent[root] = _parent[_parent[root]];
      root = _parent[root];
    }
    return root;
  }

  bool connected(int a, int b) => find(a) == find(b);

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA == rootB) return;

    if (_rank[rootA] < _rank[rootB]) {
      _parent[rootA] = rootB;
    } else if (_rank[rootA] > _rank[rootB]) {
      _parent[rootB] = rootA;
    } else {
      _parent[rootB] = rootA;
      _rank[rootA]++;
    }
  }
}
