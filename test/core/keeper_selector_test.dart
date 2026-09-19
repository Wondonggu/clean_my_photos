import 'package:clean_my_photos/core/models/media_item.dart';
import 'package:clean_my_photos/core/services/keeper_selector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/media_fixtures.dart';

void main() {
  setUp(MediaFixtures.reset);

  const selector = KeeperSelector();

  test('分辨率最高的被保留', () {
    final small = MediaFixtures.photo(id: 'small', width: 1920, height: 1080);
    final large = MediaFixtures.photo(id: 'large', width: 4032, height: 3024);

    final decision = selector.decide(<MediaItem>[small, large]);

    expect(decision.keeper.id, 'large');
    expect(decision.reason, '保留分辨率最高的照片');
  });

  test('收藏的照片一定被保留，哪怕分辨率更低', () {
    final favorite = MediaFixtures.photo(
      id: 'favorite',
      width: 640,
      height: 480,
      isFavorite: true,
    );
    final large = MediaFixtures.photo(id: 'large', width: 4032, height: 3024);

    final decision = selector.decide(<MediaItem>[large, favorite]);

    expect(decision.keeper.id, 'favorite');
    expect(decision.reason, '保留收藏的照片');
  });

  test('本地文件优先于 iCloud 占位符', () {
    final local = MediaFixtures.photo(id: 'local', width: 1920, height: 1080);
    final remote = MediaFixtures.photo(
      id: 'remote',
      width: 4032,
      height: 3024,
      isLocallyAvailable: false,
    );

    final decision = selector.decide(<MediaItem>[remote, local]);

    expect(decision.keeper.id, 'local');
  });

  test('分辨率相同时清晰度更高的胜出', () {
    final blurry = MediaFixtures.photo(id: 'blurry');
    final sharp = MediaFixtures.photo(id: 'sharp');

    final decision = selector.decide(
      <MediaItem>[blurry, sharp],
      sharpness: <String, double>{'blurry': 10, 'sharp': 400},
    );

    expect(decision.keeper.id, 'sharp');
  });

  test('分辨率差距很大时，清晰度不足以翻盘', () {
    final smallSharp = MediaFixtures.photo(id: 'small', width: 1000, height: 800);
    final largeBlurry =
        MediaFixtures.photo(id: 'large', width: 4032, height: 3024);

    final decision = selector.decide(
      <MediaItem>[smallSharp, largeBlurry],
      sharpness: <String, double>{'small': 500, 'large': 0.1},
    );

    expect(decision.keeper.id, 'large');
  });

  test('全部相同时保留最早拍摄的一张（通常是原图）', () {
    final early = MediaFixtures.photo(
      id: 'early',
      createdAt: DateTime(2024, 5, 1, 10),
    );
    final late = MediaFixtures.photo(
      id: 'late',
      createdAt: DateTime(2024, 5, 1, 10, 0, 30),
    );

    final decision = selector.decide(<MediaItem>[late, early]);

    expect(decision.keeper.id, 'early');
  });

  test('排序结果稳定：同样的输入总是同样的顺序', () {
    final items = <MediaItem>[
      MediaFixtures.photo(id: 'b', width: 1000, height: 1000),
      MediaFixtures.photo(id: 'a', width: 1000, height: 1000),
      MediaFixtures.photo(id: 'c', width: 1000, height: 1000),
    ];

    final first = selector.rank(items).map((item) => item.id).toList();
    final second = selector.rank(items.reversed).map((item) => item.id).toList();

    expect(first, second);
    expect(first, <String>['a', 'b', 'c']);
  });

  test('缺少拍摄时间时不会崩溃，且排在有时刻的之后', () {
    final withTime = MediaFixtures.photo(id: 'with-time');
    final withoutTime = MediaFixtures.photoWithoutTime(id: 'without-time');

    final ranked = selector.rank(<MediaItem>[withoutTime, withTime]);

    expect(ranked.first.id, 'with-time');
    expect(ranked.last.id, 'without-time');
  });

  test('空集合抛参数错误', () {
    expect(
      () => selector.decide(<MediaItem>[]),
      throwsA(isA<ArgumentError>()),
    );
  });
}
