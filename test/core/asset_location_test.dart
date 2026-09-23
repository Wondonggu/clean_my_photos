import 'package:clean_my_photos/data/asset_locator_channel.dart';
import 'package:clean_my_photos/data/photo_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 装一个假的平台通道，模拟 iOS 侧的返回值。
void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AssetLocatorChannel.channel, handler);
}

void _clearChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AssetLocatorChannel.channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_clearChannel);

  group('平台通道', () {
    test('不支持反查的平台直接给 unsupported，不发调用', () async {
      var called = false;
      _mockChannel((call) async {
        called = true;
        return null;
      });

      final location =
          await const AssetLocatorChannel(isSupportedPlatform: false)
              .locate('a');

      expect(location.unsupported, isTrue);
      expect(called, isFalse);
    });

    test('缺原生实现时安静降级，不抛异常', () async {
      // 不装 handler 就等于通道不存在，和 Linux 上跑测试一样。
      _clearChannel();

      final location = await const AssetLocatorChannel().locate('a');

      expect(location.unsupported, isTrue);
      expect(location.memberships, isEmpty);
    });

    test('正常返回时解析出相册、序号和总数', () async {
      _mockChannel((call) async {
        expect(call.method, 'locateAsset');
        expect((call.arguments as Map)['assetId'], 'a');
        return <String, Object?>{
          'albums': <Object?>[
            <String, Object?>{
              'albumId': 'trip',
              'name': '旅行',
              'kind': 'user',
              'index': 3,
              'assetCount': 12,
            },
            <String, Object?>{
              'albumId': 'recent',
              'name': '最近项目',
              'kind': 'smart',
              'index': 0,
            },
          ],
          'isLimited': true,
        };
      });

      final location = await const AssetLocatorChannel().locate('a');

      expect(location.unsupported, isFalse);
      expect(location.error, isNull);
      expect(location.isLimited, isTrue);
      expect(location.memberships, hasLength(2));

      final trip = location.memberships.first;
      expect(trip.name, '旅行');
      expect(trip.kind, AssetAlbumKind.user);
      expect(trip.index, 3);
      expect(trip.assetCount, 12);

      // 原生侧用 0 表示「没算出来」，解析时统一成 null。
      expect(location.memberships.last.hasIndex, isFalse);
    });

    test('条目缺字段或类型不对时跳过那一条，不作废整次查询', () async {
      _mockChannel((call) async {
        return <String, Object?>{
          'albums': <Object?>[
            <String, Object?>{'albumId': 'trip', 'name': '旅行'},
            <String, Object?>{'albumId': 'no-name'},
            'not-a-map',
            <String, Object?>{'albumId': 42, 'name': '类型不对'},
          ],
        };
      });

      final location = await const AssetLocatorChannel().locate('a');

      expect(location.hasResult, isTrue);
      expect(location.memberships, hasLength(1));
      expect(location.memberships.single.name, '旅行');
      // 没报 kind 就当成智能相册，总比崩掉强。
      expect(location.memberships.single.kind, AssetAlbumKind.smart);
      expect(location.memberships.single.kind.label, '智能相册');
    });

    test('照片已经不在相册里是空结果，不是失败', () async {
      _mockChannel((call) async {
        throw PlatformException(code: 'notFound');
      });

      final location = await const AssetLocatorChannel().locate('a');

      expect(location.hasResult, isTrue);
      expect(location.isEmpty, isTrue);
    });

    test('其它平台错误算失败，界面照常显示', () async {
      _mockChannel((call) async {
        throw PlatformException(code: 'unknown');
      });

      final location = await const AssetLocatorChannel().locate('a');

      expect(location.error, isNotNull);
      expect(location.hasResult, isFalse);
      expect(location.unsupported, isFalse);
    });
  });

  group('摘要文案', () {
    test('分成不支持、失败、没有相册、正常四种', () {
      expect(describeLocation(const AssetLocation.unsupported('a')), '所在相册：当前平台不支持');
      expect(
        describeLocation(const AssetLocation.failed('a', 'boom')),
        '所在相册：读取失败',
      );
      expect(describeLocation(const AssetLocation(assetId: 'a')), '所在相册：不在任何相册里');
      expect(
        describeLocation(
          const AssetLocation(
            assetId: 'a',
            memberships: <AssetAlbumMembership>[
              AssetAlbumMembership(
                albumId: 'trip',
                name: '旅行',
                kind: AssetAlbumKind.user,
                index: 3,
              ),
              AssetAlbumMembership(
                albumId: 'recent',
                name: '最近项目',
                kind: AssetAlbumKind.smart,
              ),
            ],
          ),
        ),
        '所在相册：旅行 第 3 张、最近项目',
      );
    });
  });
}
