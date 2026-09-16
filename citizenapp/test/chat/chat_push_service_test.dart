import 'dart:io';

import 'package:citizenapp/chat/chat_product_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('新应用标识使用各自登记的唯一 Firebase App ID', () {
    final source = File(
      'lib/notifications/app_push_service.dart',
    ).readAsStringSync();
    final appIds = RegExp(
      r"'(1:124593150477:(?:android|ios):[0-9a-f]+)'",
    ).allMatches(source).map((match) => match.group(1)!).toSet();

    expect(
      source,
      contains("iosBundleId: Platform.isIOS ? 'ios.citizenapp' : null"),
    );
    expect(appIds, {
      '1:124593150477:android:436c372ca4779924ba1344',
      '1:124593150477:ios:dcff6e612fb28795ba1344',
    });
    expect(source, isNot(contains('String.fromEnvironment')));
  });

  test('Firebase 客户端 Key 按平台隔离且禁止共享回退', () {
    final source = File(
      'lib/notifications/app_push_service.dart',
    ).readAsStringSync();
    final keys = RegExp(
      r"const _firebase(?:Android|Ios)ApiKey = '(AIza[^']+)'",
    ).allMatches(source).map((match) => match.group(1)!).toList();

    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(2));
    expect(
      source,
      matches(
        RegExp(
          r'final\s+apiKey\s*=\s*Platform\.isIOS\s*\?\s*'
          r'_firebaseIosApiKey\s*:\s*_firebaseAndroidApiKey;',
        ),
      ),
    );
    expect(source, contains('if (apiKey.isEmpty ||'));
    expect(source, contains('apiKey: apiKey'));
  });

  test('只接受无内容聊天唤醒载荷', () {
    expect(ChatPushService.isWakeData(const {'event': 'chat_wake'}), isTrue);
    expect(
      ChatPushService.isWakeData(const {
        'event': 'chat_wake',
        'sender_cid_number': 'forbidden',
      }),
      isFalse,
    );
    expect(
      ChatPushService.isWakeData(const {
        'event': 'chat_wake',
        'conversation_id': 'forbidden',
      }),
      isFalse,
    );
    expect(
      ChatPushService.isWakeData(const {
        'event': 'chat_wake',
        'message': '不得进入推送',
      }),
      isFalse,
    );
    expect(
      ChatPushService.isWakeData(const {'event': 'chat_message'}),
      isFalse,
    );
  });

  test('CitizenApp 双端只展示并清理固定聊天通知', () {
    final android = File(
      'android/app/src/main/kotlin/com/crcfrcn/citizenapp/MainActivity.kt',
    ).readAsStringSync();
    final appPush = File(
      'lib/notifications/app_push_service.dart',
    ).readAsStringSync();

    expect(android, contains('CHAT_NOTIFICATION_CHANNEL_ID = "chat_messages"'));
    expect(android, contains('.setContentText("你有一条新消息")'));
    expect(appPush, contains('setForegroundNotificationPresentationOptions'));
    expect(android, contains('clearChatNotifications(conversationId)'));
    expect(
      File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      contains('clearDeliveredChatNotifications'),
    );
  });

  test('聊天桥不拥有Firebase配置或非聊天通知', () {
    final source = File(
      'lib/chat/chat_product_configuration.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('FirebaseOptions')));
    expect(source, isNot(contains('_firebaseAndroidApiKey')));
    expect(source, isNot(contains('square_post')));
    expect(source, contains('AppPushService'));
  });

  test('普通应用推送由CitizenServe会话登记且不使用聊天数据面', () {
    final client = File(
      'lib/8964/services/square_api_client.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    expect(client, contains("'/square/push-endpoint'"));
    expect(main, contains('registerPushEndpoint'));
    expect(main, contains("data['kind'] == 'storage_cleanup'"));
  });

  test('iOS APNs 环境以 provisioning profile 和 App Store 收据为真源', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(entitlements, contains('<string>\$(APS_ENVIRONMENT)</string>'));
    expect(infoPlist, isNot(contains('\$(APS_ENVIRONMENT)')));
    expect(appDelegate, contains('embedded'));
    expect(appDelegate, contains('mobileprovision'));
    expect(appDelegate, contains('profile["Entitlements"]'));
    expect(appDelegate, contains('entitlements["aps-environment"]'));
    expect(appDelegate, contains('bundle.appStoreReceiptURL'));
  });

  test('iOS 正式包固定声明当前出口合规豁免结论', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    // 当前销售范围排除法国，App Store Connect 已判定标准加密无须上传文稿。
    expect(infoPlist, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
    expect(
      infoPlist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
    expect(infoPlist, isNot(contains('ITSEncryptionExportComplianceCode')));
  });

  test('双端系统备份都排除设备侧聊天内容', () {
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final iosDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(androidManifest, contains('android:allowBackup="false"'));
    expect(iosDelegate, contains('isExcludedFromBackup = true'));
    expect(iosDelegate, contains('appendingPathComponent("chat"'));
    expect(iosDelegate, contains('hasPrefix("tatachat_sdk_chat")'));
    expect(iosDelegate, contains('case "excludeChatDataFromBackup"'));
  });

  test('推送端点缓存同时绑定服务类型、APNs 环境和 Token', () {
    const sandbox = ChatPushToken(
      provider: 'apns',
      token: 'same-token',
      apnsEnvironment: 'sandbox',
    );
    const production = ChatPushToken(
      provider: 'apns',
      token: 'same-token',
      apnsEnvironment: 'production',
    );
    const fcm = ChatPushToken(
      provider: 'fcm',
      token: 'same-token',
      apnsEnvironment: null,
    );
    expect(
      sandbox.registrationCacheValue,
      isNot(production.registrationCacheValue),
    );
    expect(fcm.registrationCacheValue, isNot(sandbox.registrationCacheValue));
  });

  test('后台连续唤醒只持久化一个待补拉标志', () async {
    SharedPreferences.setMockInitialValues({});
    await ChatPushService.storeWake();
    await ChatPushService.storeWake();

    final service = ChatPushService();
    expect(await service.takePendingWake(), isTrue);
    expect(await service.takePendingWake(), isFalse);
    await service.dispose();
  });
}
