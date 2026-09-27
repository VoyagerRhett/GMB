import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// 截屏保护工具（进程级全局资源，引用计数管理）。
///
/// - Android: 通过 FLAG_SECURE 阻止截屏和屏幕录制。
/// - iOS: 进入后台时添加模糊遮罩；前台截屏时通过事件通知 Flutter
///   隐藏敏感内容；检测到录屏时主动通知隐藏。
///
/// 多个敏感页可能同时需要保护（如钱包详情揭示助记词后进入账户详情揭示私钥）。
/// 因平台侧的 FLAG_SECURE 是**全局单一开关**,这里用**引用计数**管理:每个页面
/// `enable(cb)` 计数 +1、`disable(cb)` 计数 -1,只有计数归零才真正关闭平台保护;
/// 回调用**集合**保存,截屏事件广播给所有在用页面——避免子页 dispose 单方面关掉
/// 父页仍在用的保护。
class ScreenshotGuard {
  const ScreenshotGuard._();

  // 内部通道与 Android/iOS 应用标识解耦，两端只共享产品级稳定名称。
  static const MethodChannel _channel = MethodChannel('citizenwallet/security');

  static const EventChannel _eventChannel = EventChannel(
    'citizenwallet/security_events',
  );

  static StreamSubscription<dynamic>? _eventSubscription;

  // 原生 FLAG_SECURE 是全局开关；串行化跨页开关，避免先关闭后开启的异步乱序。
  static Future<void>? _operation;

  /// 当前持有保护的页面数(引用计数)。
  static int _refCount = 0;
  static bool _recordingActive = false;
  static bool _eventStreamFailed = false;

  /// 已启用保护的页面仍需在异步解密或签名结束前复查采集状态。
  static bool get canDisplaySensitiveContent =>
      !_recordingActive && !_eventStreamFailed;

  /// 截屏/录屏事件监听器集合(多页共存时每个在用页各注册一份)。
  ///
  /// 事件类型：
  /// - `screenshot_taken`：用户在前台截屏（iOS，截屏已完成）
  /// - `screen_recording_started`：屏幕录制开始（iOS）
  /// - `screen_recording_stopped`：屏幕录制结束（iOS）
  static final Set<void Function(String event)> _listeners = {};

  static Future<void> _enqueue(Future<void> Function() action) {
    // 空闲时在当前调用区创建新 Future；已结束的旧区 Future 不跨页面或测试保留。
    final pending = (_operation ?? Future<void>.value()).then((_) => action());
    // 队列自身恢复到可用状态；调用者仍收到原始失败，不能把启用失败当作成功。
    final recovered = pending.catchError((Object _) {});
    _operation = recovered;
    unawaited(
      recovered.then((_) {
        if (identical(_operation, recovered)) _operation = null;
      }),
    );
    return pending;
  }

  /// 组件测试卸载敏感页面后等待其异步原生关闭完成，避免跨测试遗留队列。
  @visibleForTesting
  static Future<void> waitForIdleForTest() =>
      _operation ?? Future<void>.value();

  /// 原生确认保护启用后才允许调用方展示秘密；失败不增加引用计数。
  static Future<void> enable([void Function(String event)? onEvent]) =>
      _enqueue(() async {
        if (_recordingActive || _eventStreamFailed) {
          throw StateError('屏幕采集或保护事件通道不可用');
        }
        if (_refCount == 0) {
          final captured = await _channel.invokeMethod<bool>(
            'enableScreenshotProtection',
          );
          if (captured == true) {
            // iOS 已处于录屏时不等待状态变更事件；本次不交付任何保护租约。
            try {
              await _channel.invokeMethod('disableScreenshotProtection');
            } catch (_) {}
            throw StateError('屏幕录制正在进行');
          }
        }
        _refCount++;
        if (onEvent != null) _listeners.add(onEvent);
        if (_refCount == 1) _startListening();
      });

  /// 关闭截屏保护;传入的回调从集合移除。引用计数 -1,归零才真正关闭平台保护。
  static Future<void> disable([void Function(String event)? onEvent]) =>
      _enqueue(() async {
        if (_refCount == 0) return;
        if (onEvent != null) _listeners.remove(onEvent);
        _refCount--;
        if (_refCount == 0) {
          // 进程级事件订阅只建立一次，避免页面切换时原生 cancel/listen 乱序。
          // 无租约时 _broadcast 忽略事件；平台保护开关仍按引用计数关闭。
          _recordingActive = false;
          // 事件通道失效不能凭一次页面关闭恢复，进程重启前持续拒绝展示秘密。
          try {
            await _channel.invokeMethod('disableScreenshotProtection');
          } catch (_) {
            // 关闭失败只会保留更严格的平台保护；下次启用仍重新向原生确认。
          }
        }
      });

  /// 检测设备是否已 root（Android）或越狱（iOS）。
  static Future<bool> isDeviceRooted() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDeviceRooted');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static void _startListening() {
    if (_eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) _broadcast(event);
      },
      onError: (_) {
        // iOS 录屏事件通道失效时立即隐藏各页敏感内容。
        if (_refCount == 0) {
          _eventStreamFailed = true;
          return;
        }
        _broadcast('protection_failed');
      },
    );
  }

  static void _broadcast(String event) {
    // 无页面持有保护时忽略事件，不污染下一次保护租约。
    if (_refCount == 0) return;
    if (event == 'screen_recording_started') _recordingActive = true;
    if (event == 'screen_recording_stopped') _recordingActive = false;
    if (event == 'protection_failed') _eventStreamFailed = true;
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }
}
