import 'package:clean_my_photos/core/models/asset_signature.dart';
import 'package:clean_my_photos/core/models/media_group.dart';
import 'package:clean_my_photos/core/services/similarity_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

void main() {
  setUp(MediaFixtures.reset);

  const grouper = SimilarityGrouper(
    options: SimilarityOptions(
      maxDistance: 8,
      timeWindow: Duration(minutes: 2),
    ),
  );

  test('完全相同的两张照片归为一组，且判定为「重复」', () {
    final base = DateTime(2024, 5, 1, 10);
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: base, size: 1000),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(
        id: 'b',
        createdAt: base.add(const Duration(seconds: 20)),
        size: 900,
      ),
    );

    final groups = grouper.group(<AssetSignature>[a, b]);

    expect(groups, hasLength(1));
    expect(groups.first.kind, GroupKind.duplicate);
    expect(groups.first.items, hasLength(2));
    expect(groups.first.maxDistance, 0);
    expect(groups.first.deletable, hasLength(1));
  });

  test('哈希相同时即使相隔很久也会归为一组（同一张图被保存两次）', () {
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: DateTime(2020, 1, 1)),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(id: 'b', createdAt: DateTime(2024, 8, 8)),
    );

    final groups = grouper.group(<AssetSignature>[a, b]);

    expect(groups, hasLength(1));
    expect(groups.first.kind, GroupKind.duplicate);
  });

  test('哈希接近且时间相邻 → 相似照片', () {
    final base = DateTime(2024, 5, 1, 10);
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: base, size: 2000),
      hash: MediaFixtures.zeroHash(),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(
        id: 'b',
        createdAt: base.add(const Duration(seconds: 5)),
        size: 1800,
      ),
      hash: MediaFixtures.hashAtDistance(5),
    );

    final groups = grouper.group(<AssetSignature>[a, b]);

    expect(groups, hasLength(1));
    expect(groups.first.kind, GroupKind.similar);
    expect(groups.first.maxDistance, 5);
  });

  test('哈希接近但相隔超过时间窗口 → 不分组', () {
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: DateTime(2024, 5, 1, 10)),
      hash: MediaFixtures.zeroHash(),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(id: 'b', createdAt: DateTime(2024, 5, 8, 10)),
      hash: MediaFixtures.hashAtDistance(3),
    );

    expect(grouper.group(<AssetSignature>[a, b]), isEmpty);
  });

  test('哈希差异超过阈值 → 不分组', () {
    final base = DateTime(2024, 5, 1, 10);
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: base),
      hash: MediaFixtures.zeroHash(),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(id: 'b', createdAt: base),
      hash: MediaFixtures.hashAtDistance(20),
    );

    expect(grouper.group(<AssetSignature>[a, b]), isEmpty);
  });

  test('宽高比差异过大 → 不分组（裁剪过的不同画面）', () {
    final base = DateTime(2024, 5, 1, 10);
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: base, width: 4032, height: 3024),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.photo(id: 'b', createdAt: base, width: 1000, height: 1000),
    );

    expect(grouper.group(<AssetSignature>[a, b]), isEmpty);
  });

  test('图片与视频即使哈希相同也不会互相分组', () {
    final base = DateTime(2024, 5, 1, 10);
    final a = MediaFixtures.signature(
      MediaFixtures.photo(id: 'a', createdAt: base),
    );
    final b = MediaFixtures.signature(
      MediaFixtures.video(id: 'b', createdAt: base),
    );

    expect(grouper.group(<AssetSignature>[a, b]), isEmpty);
  });

  test('单链接聚类：A~B、B~C 会合并成一组', () {
    final base = DateTime(2024, 5, 1, 10);
    final signatures = <AssetSignature>[
      MediaFixtures.signature(
        MediaFixtures.photo(id: 'a', createdAt: base),
        hash: MediaFixtures.zeroHash(),
      ),
      MediaFixtures.signature(
        MediaFixtures.photo(id: 'b', createdAt: base.add(const Duration(seconds: 5))),
        hash: MediaFixtures.hashAtDistance(6),
      ),
      MediaFixtures.signature(
        MediaFixtures.photo(id: 'c', createdAt: base.add(const Duration(seconds: 10))),
        hash: MediaFixtures.hashAtDistance(12),
      ),
    ];

    final groups = grouper.group(signatures);

    expect(groups, hasLength(1));
    expect(groups.first.items, hasLength(3));
  });

  test('没有指纹的条目会被忽略', () {
    final item = MediaFixtures.photo(id: 'no-hash');
    final signature = MediaFixtures.signature(item);
    final withoutHash = signature.copyWith(failure: 'x');

    expect(
      grouper.group(<AssetSignature>[withoutHash]),
      isEmpty,
    );
  });

  test('结果按可释放空间从大到小排序', () {
    final base = DateTime(2024, 5, 1, 10);
    final signatures = <AssetSignature>[
      // 小组：只多出 100 字节
      MediaFixtures.signature(
        MediaFixtures.photo(id: 'a1', createdAt: base, size: 100),
      ),
      MediaFixtures.signature(
        MediaFixtures.photo(
          id: 'a2',
          createdAt: base.add(const Duration(seconds: 5)),
          size: 100,
        ),
      ),
      // 大组：多出 3MB
      MediaFixtures.signature(
        MediaFixtures.photo(id: 'b1', createdAt: base, size: 3 * 1024 * 1024),
        hash: MediaFixtures.hashAtDistance(40),
      ),
      MediaFixtures.signature(
        MediaFixtures.photo(
          id: 'b2',
          createdAt: base.add(const Duration(seconds: 5)),
          size: 3 * 1024 * 1024,
        ),
        hash: MediaFixtures.hashAtDistance(40),
      ),
    ];

    final groups = grouper.group(signatures);

    expect(groups, hasLength(2));
    expect(groups.first.reclaimableBytes, greaterThan(groups.last.reclaimableBytes));
  });

  test('空输入不会抛异常', () {
    expect(grouper.group(<AssetSignature>[]), isEmpty);
  });
}
