import 'package:clean_my_photos/core/models/asset_signature.dart';
import 'package:clean_my_photos/core/models/cleanup_category.dart';
import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/services/cleanup_analyzer.dart';
import 'package:clean_my_photos/core/services/similarity_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

void main() {
  setUp(MediaFixtures.reset);

  const analyzer = CleanupAnalyzer(
    largeVideoBytes: 100 * 1024 * 1024,
    largePhotoBytes: 8 * 1024 * 1024,
  );

  group('分类构建', () {
    test('识别截图，并按时间从新到旧排列', () {
      final items = <MediaItem>[
        MediaFixtures.photo(
          id: 'old',
          isScreenshot: true,
          createdAt: DateTime(2023, 1, 1),
        ),
        MediaFixtures.photo(
          id: 'new',
          isScreenshot: true,
          createdAt: DateTime(2024, 6, 1),
        ),
        MediaFixtures.photo(id: 'normal'),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: const <AssetSignature>[])[
              CleanupCategoryType.screenshots]!;

      expect(category.totalCount, 2);
      expect(category.items.map((item) => item.id), <String>['new', 'old']);
      expect(category.hasCandidates, isTrue);
    });

    test('识别录屏，并按体积从大到小排列', () {
      final items = <MediaItem>[
        MediaFixtures.video(
          id: 'small-rec',
          isScreenRecording: true,
          size: 10 * 1024 * 1024,
        ),
        MediaFixtures.video(
          id: 'big-rec',
          isScreenRecording: true,
          size: 500 * 1024 * 1024,
        ),
        MediaFixtures.video(id: 'normal-video', size: 500 * 1024 * 1024),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: const <AssetSignature>[])[
              CleanupCategoryType.screenRecordings]!;

      expect(category.items.map((item) => item.id), <String>['big-rec', 'small-rec']);
    });

    test('超大视频按体积排序，且不包含录屏（避免重复扣除空间）', () {
      final items = <MediaItem>[
        MediaFixtures.video(id: 'huge', size: 900 * 1024 * 1024),
        MediaFixtures.video(id: 'medium', size: 150 * 1024 * 1024),
        MediaFixtures.video(id: 'tiny', size: 10 * 1024 * 1024),
        MediaFixtures.video(
          id: 'recording',
          size: 900 * 1024 * 1024,
          isScreenRecording: true,
        ),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: const <AssetSignature>[])[
              CleanupCategoryType.largeVideos]!;

      expect(category.items.map((item) => item.id), <String>['huge', 'medium']);
    });

    test('超大照片只包含超过阈值的图片', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'panorama', size: 20 * 1024 * 1024),
        MediaFixtures.photo(id: 'normal', size: 3 * 1024 * 1024),
        MediaFixtures.video(id: 'video', size: 20 * 1024 * 1024),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: const <AssetSignature>[])[
              CleanupCategoryType.largePhotos]!;

      expect(category.items.map((item) => item.id), <String>['panorama']);
    });

    test('模糊照片按清晰度从低到高排列', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'very-blurry'),
        MediaFixtures.photo(id: 'slightly-blurry'),
        MediaFixtures.photo(id: 'sharp'),
      ];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0], sharpness: 5),
        MediaFixtures.signature(items[1], sharpness: 60),
        MediaFixtures.signature(items[2], sharpness: 800),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: signatures)[
              CleanupCategoryType.blurry]!;

      expect(
        category.items.map((item) => item.id),
        <String>['very-blurry', 'slightly-blurry'],
      );
      expect(category.analyzed, isTrue);
    });

    test('模糊结论跟着阈值走，同一批指纹在不同阈值下结果不同', () {
      // 指纹只存清晰度，是否模糊由 CleanupAnalyzer 按当前阈值现算，
      // 所以调设置页的滑杆应该立刻生效，不需要重扫。
      final items = <MediaItem>[MediaFixtures.photo(id: 'mid')];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0], sharpness: 60),
      ];

      final strict = const CleanupAnalyzer(blurThreshold: 30)
          .buildCategories(items: items, signatures: signatures)[
              CleanupCategoryType.blurry]!;
      final lenient = const CleanupAnalyzer(blurThreshold: 100)
          .buildCategories(items: items, signatures: signatures)[
              CleanupCategoryType.blurry]!;

      expect(strict.items, isEmpty);
      expect(lenient.items.map((item) => item.id), <String>['mid']);
    });

    test('清晰度不可信的图片不参与模糊判定', () {
      final items = <MediaItem>[MediaFixtures.photo(id: 'tiny')];
      final signatures = <AssetSignature>[
        // 图太小或接近纯色时拉普拉斯方差没有意义，宁可少判不可错判。
        MediaFixtures.signature(items[0], sharpness: 1, isReliable: false),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: signatures)[
              CleanupCategoryType.blurry]!;

      expect(category.items, isEmpty);
    });

    test('还有图片没算完清晰度时，标记为「分析未完成」', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'done'),
        MediaFixtures.photo(id: 'pending'),
      ];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0], sharpness: 500),
        MediaFixtures.signature(items[1]),
      ];

      final category = analyzer
          .buildCategories(items: items, signatures: signatures)[
              CleanupCategoryType.blurry]!;

      expect(category.analyzed, isFalse);
    });

    test('重复 / 相似分类按分组类型拆分', () {
      final base = DateTime(2024, 5, 1, 10);
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'dup-1', createdAt: base, size: 1000),
        MediaFixtures.photo(
          id: 'dup-2',
          createdAt: base.add(const Duration(seconds: 10)),
          size: 1000,
        ),
        MediaFixtures.photo(id: 'sim-1', createdAt: base),
        MediaFixtures.photo(
          id: 'sim-2',
          createdAt: base.add(const Duration(seconds: 10)),
        ),
      ];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0], hash: MediaFixtures.zeroHash()),
        MediaFixtures.signature(items[1], hash: MediaFixtures.zeroHash()),
        MediaFixtures.signature(
          items[2],
          hash: MediaFixtures.hashAtDistance(40),
        ),
        MediaFixtures.signature(
          items[3],
          hash: MediaFixtures.hashAtDistance(42),
        ),
      ];

      final categories =
          analyzer.buildCategories(items: items, signatures: signatures);

      final duplicates = categories[CleanupCategoryType.duplicates]!;
      final similar = categories[CleanupCategoryType.similar]!;

      expect(duplicates.groups, hasLength(1));
      expect(duplicates.items.map((item) => item.id), <String>['dup-2']);

      expect(similar.groups, hasLength(1));
      expect(similar.items, hasLength(1));
    });

    test('整组都是收藏时不给出任何删除建议', () {
      final base = DateTime(2024, 5, 1, 10);
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'fav-1', createdAt: base, isFavorite: true),
        MediaFixtures.photo(
          id: 'fav-2',
          createdAt: base.add(const Duration(seconds: 5)),
          isFavorite: true,
        ),
      ];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0]),
        MediaFixtures.signature(items[1]),
      ];

      final categories =
          analyzer.buildCategories(items: items, signatures: signatures);

      expect(categories[CleanupCategoryType.duplicates]!.items, isEmpty);
      expect(categories[CleanupCategoryType.duplicates]!.groups, hasLength(1));
    });
  });

  group('汇总', () {
    test('可释放空间按 id 去重，不重复计算', () {
      // 一张模糊的截图会同时出现在两个分类里。
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'both', isScreenshot: true, size: 1000),
        MediaFixtures.photo(id: 'plain', size: 2000),
      ];
      final signatures = <AssetSignature>[
        MediaFixtures.signature(items[0], sharpness: 5),
        MediaFixtures.signature(items[1], sharpness: 500),
      ];

      final categories =
          analyzer.buildCategories(items: items, signatures: signatures);
      final summary = analyzer.summarize(items: items, categories: categories);

      expect(summary.totalCount, 2);
      expect(summary.photoCount, 2);
      expect(summary.totalBytes, 3000);
      // 'both' 只能算一次。
      expect(summary.reclaimableBytes, 1000);
      expect(summary.candidateCount, 1);
    });

    test('系统没有返回文件大小时，标记为估算值', () {
      final items = <MediaItem>[
        const MediaItem(
          id: 'no-size',
          kind: MediaKind.image,
          width: 4000,
          height: 3000,
        ),
      ];

      final categories =
          analyzer.buildCategories(items: items, signatures: const <AssetSignature>[]);
      final summary = analyzer.summarize(items: items, categories: categories);

      expect(summary.reclaimableIsEstimate, isTrue);
      expect(summary.totalBytes, greaterThan(0));
    });

    test('视频与图片分别计数', () {
      final items = <MediaItem>[
        MediaFixtures.photo(id: 'p'),
        MediaFixtures.video(id: 'v1'),
        MediaFixtures.video(id: 'v2'),
      ];

      final categories =
          analyzer.buildCategories(items: items, signatures: const <AssetSignature>[]);
      final summary = analyzer.summarize(items: items, categories: categories);

      expect(summary.photoCount, 1);
      expect(summary.videoCount, 2);
    });
  });

  group('相似度档位', () {
    test('宽松档能把差异更大的照片归为一组，严格档不能', () {
      final base = DateTime(2024, 5, 1, 10);
      final signatures = <AssetSignature>[
        MediaFixtures.signature(
          MediaFixtures.photo(id: 'a', createdAt: base),
          hash: MediaFixtures.zeroHash(),
        ),
        MediaFixtures.signature(
          MediaFixtures.photo(
            id: 'b',
            createdAt: base.add(const Duration(seconds: 5)),
          ),
          hash: MediaFixtures.hashAtDistance(12),
        ),
      ];

      const strict = CleanupAnalyzer(similarity: SimilarityOptions.strict);
      const loose = CleanupAnalyzer(similarity: SimilarityOptions.loose);

      final strictCategories = strict.buildCategories(
        items: signatures.map((s) => s.item).toList(),
        signatures: signatures,
      );
      final looseCategories = loose.buildCategories(
        items: signatures.map((s) => s.item).toList(),
        signatures: signatures,
      );

      expect(strictCategories[CleanupCategoryType.similar]!.groups, isEmpty);
      expect(looseCategories[CleanupCategoryType.similar]!.groups, hasLength(1));
    });
  });
}
