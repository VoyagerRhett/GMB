import 'dart:async';
import 'dart:io';

import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/notifications/app_push_service.dart';
import 'package:citizenapp/notifications/app_push_token.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart' as sdk;

const _wakePendingKey = 'chat.push.wake_pending';

class ChatPushToken implements sdk.ChatPushToken {
  const ChatPushToken({
    required this.provider,
    required this.token,
    required this.apnsEnvironment,
  });

  factory ChatPushToken.fromApp(AppPushToken token) => ChatPushToken(
    provider: token.provider,
    token: token.token,
    apnsEnvironment: token.apnsEnvironment,
  );

  @override
  final String provider;
  @override
  final String token;
  @override
  final String? apnsEnvironment;

  @override
  String get registrationCacheValue =>
      provider + '|' + (apnsEnvironment ?? '') + '|' + token;
}

/// 只把CitizenApp通用平台推送映射为TataChatSDK聊天唤醒桥；不拥有Firebase配置或非聊天通知。
class ChatPushService implements sdk.ChatPushBridge {
  ChatPushService({
    AppPushService? appPushService,
    MethodChannel? notificationsChannel,
    Future<sdk.ChatPushToken> Function()? tokenProvider,
  }) : _appPushService = appPushService ?? AppPushService(),
       _tokenProvider = tokenProvider,
       _notificationsChannel =
           notificationsChannel ??
           const MethodChannel('citizenapp/chat_notifications');

  final AppPushService _appPushService;
  final Future<sdk.ChatPushToken> Function()? _tokenProvider;
  final MethodChannel _notificationsChannel;
  final StreamController<sdk.ChatPushWake> _wakeController =
      StreamController<sdk.ChatPushWake>.broadcast();
  final StreamController<sdk.ChatPushToken> _tokenController =
      StreamController<sdk.ChatPushToken>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<AppPushToken>? _tokenSubscription;

  @override
  Stream<sdk.ChatPushWake> get wakes => _wakeController.stream;

  @override
  Stream<sdk.ChatPushToken> get tokenChanges => _tokenController.stream;

  @override
  Future<sdk.ChatPushToken> initialize() async {
    final custom = _tokenProvider;
    if (custom != null) return custom();
    final token = ChatPushToken.fromApp(await _appPushService.initialize());
    _messageSubscription ??= _appPushService.foregroundMessages.listen(
      _handleMessage,
    );
    _tokenSubscription ??= _appPushService.tokenChanges.listen(
      (next) => _tokenController.add(ChatPushToken.fromApp(next)),
    );
    return token;
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

  void _handleMessage(Map<String, dynamic> data) {
    if (!isWakeData(data)) return;
    _wakeController.add(const sdk.ChatPushWake());
  }

  /// 页面已读提交成功后只清理当前会话通知；Android与iOS共用原生通道。
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

/// Firebase后台isolate只持久记录无内容唤醒，前台唯一ChatSdk恢复后再补拉端到端密文。
@pragma('vm:entry-point')
Future<void> chatRuntimeBackgroundHandler(RemoteMessage message) async {
  if (!ChatPushService.isWakeData(message.data)) return;
  try {
    await sdk.ChatRuntimeCore.runStartupPreflight<void>(
      operation: () async {
        await ensureAppFirebaseReady();
        await ChatPushService.storeWake();
      },
    );
  } catch (error) {
    AppLog.d('chat background mailbox wake deferred: $error');
  }
}
