import 'package:flutter/services.dart';

/// 向系统申请一小段「别急着挂起我」的时间。
///
/// iOS 的 `beginBackgroundTask` 只买到**有界**的延长窗口（大约 30 秒），
/// 到点系统照样挂起。所以它只是加分项：让「切走时正好还剩最后一批」的
/// 情况能跑完，正确的做法是边扫边落盘（见 `ScanCache`），切回来从断点续上。
///
/// 名字里的 "background" 容易让人误以为可以把长任务扔后台跑完——不能。
abstract class BackgroundTaskGuard {
  /// 申请一段延长执行时间。
  ///
  /// 成功返回一个令牌，交给 [release] 归还；**平台不支持时返回 null**。
  Future<Object?> acquire(String reason);

  /// 归还令牌。传 null 或重复归还都是安全的。
  Future<void> release(Object? token);
}

/// 什么都不做的实现。桌面与测试用。
class NoopBackgroundTaskGuard implements BackgroundTaskGuard {
  const NoopBackgroundTaskGuard();

  @override
  Future<Object?> acquire(String reason) async => null;

  @override
  Future<void> release(Object? token) async {}
}

/// 走平台通道的实现。
///
/// 通道不存在（Linux 上跑测试、Android 上没实现）时安静地返回 null，
/// 不往外抛。
class ChannelBackgroundTaskGuard implements BackgroundTaskGuard {
  const ChannelBackgroundTaskGuard({this.isSupportedPlatform = true});

  static const MethodChannel channel =
      MethodChannel('clean_my_photos/background_task');

  final bool isSupportedPlatform;

  @override
  Future<Object?> acquire(String reason) async {
    if (!isSupportedPlatform) return null;
    try {
      return await channel.invokeMethod<Object>('begin', <String, Object?>{
        'reason': reason,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> release(Object? token) async {
    if (token == null || !isSupportedPlatform) return;
    try {
      await channel.invokeMethod<void>('end', <String, Object?>{'id': token});
    } catch (_) {
      // 还不上也没关系，系统到点会自己收走。
    }
  }
}
