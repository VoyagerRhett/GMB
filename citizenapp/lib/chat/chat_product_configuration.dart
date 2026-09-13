import 'dart:async';
import 'dart:io';

import 'package:tatachat_sdk/tatachat_sdk.dart' as sdk;
import 'package:citizenapp/log/app_log.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _wakePendingKey = 'chat.push.wake_pending';

// Firebase 客户端标识属于公开应用配置，不是服务端授权凭据。Android 与 iOS 必须使用
// Firebase 为各自应用登记的独立 Key 与 App ID；当前只有一套正式项目。
const _firebaseAndroidApiKey = 'AIzaSyBfXLIwqGoOX_h75MxZYcorJncT3uSZrm4';
const _firebaseIosApiKey = 'AIzaSyBIVrjuAzf_TguwS88lf50PTeYXYlxTocU';
const _firebaseProjectId = 'citizenapp-23542';
const _firebaseSenderId = '124593150477';
const _firebaseAndroidAppId = '1:124593150477:android:436c372ca4779924ba1344';
const _firebaseIosAppId = '1:124593150477:ios:dcff6e612fb28795ba1344';

FirebaseOptions _firebaseOptions() {
  final apiKey = Platform.isIOS ? _firebaseIosApiKey : _firebaseAndroidApiKey;
  final appId = Platform.isIOS ? _firebaseIosAppId : _firebaseAndroidAppId;
  if (apiKey.isEmpty ||
      _firebaseProjectId.isEmpty ||
      _firebaseSenderId.isEmpty ||
      appId.isEmpty) {
    throw StateError('Chat 推送缺少 Firebase 构建参数');
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: _firebaseSenderId,
    projectId: _firebaseProjectId,
    iosBundleId: Platform.isIOS ? 'ios.citizenapp' : null,
  );
}

Future<void> ensureChatFirebaseReady() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: _firebaseOptions());
  }
}

class ChatPushToken implements sdk.ChatPushToken {
  const ChatPushToken({
    required this.provider,
    required this.token,
    required this.apnsEnvironment,
  });

  @override
  final String provider;
  @override
  final String token;
  @override
  final String? apnsEnvironment;

  /// 本地只缓存登记输入摘要，不把 Token 是否仍在 TataChatServer 当作权威状态。
  @override
  String get registrationCacheValue =>
      '$provider|${apnsEnvironment ?? ''}|$token';
}

/// iOS 原生侧把签名包配置映射为正式 APNs 环境；未知值必须拒绝。
String requireApnsEnvironment(String? value) {
  if (value == 'sandbox' || value == 'production') return value!;
  throw StateError('iOS 应用签名缺少有效 APNs 环境');
}

/// 平台推送只负责唤醒本机补拉密文邮箱，不承载发送者、会话、消息或附件内容。
class ChatPushService implements sdk.ChatPushBridge {
  ChatPushService({
    MethodChannel? permissionsChannel,
    MethodChannel? notificationsChannel,
    Future<sdk.ChatPushToken> Function()? tokenProvider,
  })  : _tokenProvider = tokenProvider,
        _permissionsChannel =
            permissionsChannel ?? const MethodChannel('citizenapp/permissions'),
        _notificationsChannel = notificationsChannel ??
            const MethodChannel('citizenapp/chat_notifications');

  final Future<sdk.ChatPushToken> Function()? _tokenProvider;
  final MethodChannel _permissionsChannel;
  final MethodChannel _notificationsChannel;

  final StreamController<sdk.ChatPushWake> _wakeController =
      StreamController<sdk.ChatPushWake>.broadcast();
  final StreamController<sdk.ChatPushToken> _tokenController =
      StreamController<sdk.ChatPushToken>.broadcast();
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;

  @override
  Stream<sdk.ChatPushWake> get wakes => _wakeController.stream;

  @override
  Stream<sdk.ChatPushToken> get tokenChanges => _tokenController.stream;

  @override
  Future<sdk.ChatPushToken> initialize() async {
    final token = await readToken(requestPermission: true);
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );
    }
    _messageSubscription ??= FirebaseMessaging.onMessage.listen(_handleMessage);
    _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen((
      _,
    ) async {
      try {
        _tokenController.add(await readToken(requestPermission: false));
      } catch (_) {
        // Token 刷新读取失败时等待下一次平台回调或 Chat 初始化重试。
      }
    });
    return token;
  }

  /// 后台唤醒只读取已有平台 Token，不触发权限弹窗或前台消息订阅。
  Future<sdk.ChatPushToken> readToken({required bool requestPermission}) async {
    final custom = _tokenProvider;
    if (custom != null) return custom();
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('Chat 推送只支持 Android 和 iOS');
    }
    await ensureChatFirebaseReady();
    final messaging = FirebaseMessaging.instance;
    if (requestPermission) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    if (Platform.isIOS) {
      final token = await messaging.getAPNSToken();
      if (token == null || token.isEmpty) {
        throw StateError('APNs Token 尚未生成');
      }
      final environment = requireApnsEnvironment(
        await _permissionsChannel.invokeMethod<String>('getApnsEnvironment'),
      );
      return ChatPushToken(
        provider: 'apns',
        token: token,
        apnsEnvironment: environment,
      );
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('FCM Token 尚未生成');
    }
    return ChatPushToken(provider: 'fcm', token: token, apnsEnvironment: null);
  }

  static bool isWakeData(Map<String, dynamic> data) =>
      data.length == 1 && data['event'] == 'chat_wake';

  static Future<void> storeWake() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wakePendingKey, true);
  }

  @override
  Future<bool> takePendingWake() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_wakePendingKey) ?? false;
    await prefs.remove(_wakePendingKey);
    return pending;
  }

  void _handleMessage(RemoteMessage message) {
    if (!isWakeData(message.data)) return;
    _wakeController.add(const sdk.ChatPushWake());
  }

  /// 页面已读提交成功后只清理当前会话通知；Android 与 iOS 共用原生通道。
  @override
  Future<void> clearConversationNotifications(String conversationId) async {
    if ((!Platform.isAndroid && !Platform.isIOS) || conversationId.isEmpty) {
      return;
    }
    await _notificationsChannel.invokeMethod<void>(
      'clearConversationNotifications',
      <String, String>{'conversationId': conversationId},
    );
  }

  @override
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _wakeController.close();
    await _tokenController.close();
  }
}

/// Firebase 后台 isolate 只按无内容唤醒补拉端到端密文；推送载荷不是消息真源。
@pragma('vm:entry-point')
Future<void> chatRuntimeBackgroundHandler(RemoteMessage message) async {
  if (!ChatPushService.isWakeData(message.data)) return;
  try {
    await sdk.ChatRuntimeCore.runStartupPreflight<void>(
      operation: () async {
        await ensureChatFirebaseReady();
        // 后台 isolate 不得另开第二个 CitizenSDK 钱包 owner。只持久记录无内容唤醒，
        // 前台唯一 ChatSdk 实例恢复后从同一邮箱继续补拉端到端密文。
        await ChatPushService.storeWake();
      },
    );
  } catch (error) {
    AppLog.d('chat background mailbox wake deferred: $error');
  }
}
