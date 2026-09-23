import 'package:flutter/services.dart';

import 'photo_repository.dart';

/// 反查「这张照片在系统相册里属于哪些相册」的平台通道。
///
/// `photo_manager` 只有「相册 → 条目」这一个方向，没有反向查询，所以这段
/// 只能自己接一个通道到原生（iOS 侧用 `fetchAssetCollectionsContaining`）。
///
/// 通道不存在时要安静地降级：Linux 上跑 `flutter test`、或者哪天原生实现
/// 被摘掉，都不该让界面崩掉，只是那块信息不显示而已。
class AssetLocatorChannel {
  const AssetLocatorChannel({this.isSupportedPlatform = true});

  static const MethodChannel channel =
      MethodChannel('clean_my_photos/asset_locator');

  /// 平台是否可能有这个通道。默认只在 iOS 上尝试，省掉一次必然失败的调用。
  final bool isSupportedPlatform;

  /// 反查归属。
  ///
  /// 任何异常都会被吞掉并转成 [AssetLocation] 上的状态字段，不往外抛。
  Future<AssetLocation> locate(String assetId) async {
    if (!isSupportedPlatform) {
      return AssetLocation.unsupported(assetId);
    }

    try {
      final raw = await channel.invokeMapMethod<String, Object?>(
        'locateAsset',
        <String, Object?>{'assetId': assetId},
      );
      if (raw == null) return AssetLocation.unsupported(assetId);
      return _parse(assetId, raw);
    } on MissingPluginException {
      // 没有原生实现：非 iOS 平台，或者原生代码还没编进去。
      return AssetLocation.unsupported(assetId);
    } on PlatformException catch (error) {
      // `notFound` 说明这张照片已经不在相册里了——这不是错误，是一个
      // 正常的空结果；其余才当成失败。
      if (error.code == 'notFound') {
        return AssetLocation(assetId: assetId);
      }
      return AssetLocation.failed(assetId, error);
    } catch (error) {
      return AssetLocation.failed(assetId, error);
    }
  }

  /// 把原生返回的字典解析成模型。
  ///
  /// 原生那边的字段是弱类型的（`Map<String, Any>`），这里逐个容错：
  /// 缺字段、类型不对都退化成「没这条信息」，而不是让整次查询作废。
  static AssetLocation _parse(String assetId, Map<String, Object?> raw) {
    final list = raw['albums'];
    final memberships = <AssetAlbumMembership>[];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final albumId = entry['albumId'];
        final name = entry['name'];
        if (albumId is! String || name is! String) continue;
        memberships.add(
          AssetAlbumMembership(
            albumId: albumId,
            name: name,
            kind: _kind(entry['kind']),
            index: _positiveInt(entry['index']),
            assetCount: _positiveInt(entry['assetCount']),
          ),
        );
      }
    }

    return AssetLocation(
      assetId: assetId,
      memberships: memberships,
      isLimited: raw['isLimited'] == true,
    );
  }

  static AssetAlbumKind _kind(Object? raw) => switch (raw) {
        'user' => AssetAlbumKind.user,
        'moment' => AssetAlbumKind.moment,
        _ => AssetAlbumKind.smart,
      };

  /// 原生侧用 0 / -1 表示「没算出来」，这里统一成 null。
  static int? _positiveInt(Object? raw) {
    if (raw is int) return raw > 0 ? raw : null;
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    return null;
  }
}

/// 把归属压成一行摘要，给查看器的信息栏用。
String describeLocation(AssetLocation location) {
  if (location.unsupported) return '所在相册：当前平台不支持';
  if (location.error != null) return '所在相册：读取失败';
  if (location.memberships.isEmpty) return '所在相册：不在任何相册里';
  return '所在相册：${location.memberships.map(_label).join('、')}';
}

String _label(AssetAlbumMembership m) =>
    m.hasIndex ? '${m.name} 第 ${m.index} 张' : m.name;
