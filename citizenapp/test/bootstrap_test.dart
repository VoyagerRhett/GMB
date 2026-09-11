import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/main.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';
import 'package:citizenapp/security/app_permission_gate.dart';
import 'package:citizenapp/wallet/core/sign_mode.dart';

import 'support/isar_test_env.dart';
import 'support/smoldot_native_probe.dart';

/// 直插一条热钱包记录（绕开 createWallet 的设备锁屏前置），让账户门禁放行。
Future<void> seedHotWallet() async {
  await WalletIsar.instance.writeTxn((isar) async {
    final entity = WalletProfileEntity()
      ..walletIndex = 1
      ..walletName = '钱包1'
      ..walletIcon = 'wallet'
      ..balance = 0
      ..ss58Address = 'bootstrap-test-address'
      ..accountId = 'ab' * 32
      ..masterId = 'ab' * 32
      ..alg = 'sr25519'
      ..ss58 = 2027
      ..createdAtMillis = 0
      ..source = 'created'
      ..signMode = SignMode.hot.name;
    await isar.walletProfileEntitys.put(entity);
  });
}

/// 门禁的 Isar 查询走真实事件循环，FakeAsync 的 pumpAndSettle 等不到；
/// 用 runAsync 让真异步推进，直到目标文案出现或超时。
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxRounds = 80,
}) async {
  for (var i = 0; i < maxRounds && !tester.any(finder); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

class _ForegroundWakeChatRuntime extends ChatSdk {
  _ForegroundWakeChatRuntime() : super(host: createCitizenChatRuntimeHost());

  int wakeCount = 0;

  @override
  Future<void> handleWake() async {
    wakeCount += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();

  test('主 Tab 系统栏按当前背景切换且底部导航始终使用深色图标', () {
    for (var tabIndex = 0; tabIndex < 4; tabIndex++) {
      final style = AppShell.systemUiOverlayStyleForTab(tabIndex);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    }

    final myStyle = AppShell.systemUiOverlayStyleForTab(4);
    expect(myStyle.statusBarIconBrightness, Brightness.light);
    expect(myStyle.statusBarBrightness, Brightness.dark);
    expect(myStyle.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('AppShell按需创建并复用同一ChatRuntime', (tester) async {
    final openedPushes = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(openedPushes.close);
    final runtime = _ForegroundWakeChatRuntime();
    var chatRuntimeCreations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          openedPushData: openedPushes.stream,
          initialPushDataLoader: () async => null,
          chatRuntimeFactory: () {
            chatRuntimeCreations++;
            return runtime;
          },
          tabBuilder: (index, runtime) => Center(
            child: Text(
              'test-tab-$index-${runtime == null ? 'plain' : 'chat'}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('test-tab-0-plain'), findsOneWidget);
    expect(chatRuntimeCreations, 0);

    await tester.tap(find.text('公民'));
    await tester.pump();
    expect(find.text('test-tab-1-plain'), findsOneWidget);
    expect(chatRuntimeCreations, 0);

    openedPushes.add(const <String, dynamic>{'kind': 'square_post'});
    await tester.pump();
    expect(find.text('test-tab-0-plain'), findsOneWidget);
    expect(chatRuntimeCreations, 0);

    await tester.tap(find.text('聊天'));
    await tester.pump();
    expect(find.text('test-tab-2-chat'), findsOneWidget);
    expect(chatRuntimeCreations, 1);
  });

  testWidgets('聊天首页第一帧只构造聊天且广场推送仍切回广场', (tester) async {
    final openedPushes = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(openedPushes.close);
    final runtime = _ForegroundWakeChatRuntime();
    var chatRuntimeCreations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          initialTabIndex: 2,
          openedPushData: openedPushes.stream,
          initialPushDataLoader: () async => null,
          chatRuntimeFactory: () {
            chatRuntimeCreations++;
            // 本测试只验证壳层导航；禁止在 Widget fake-async 中启动真实 WSS 和 WalletIsar。
            return runtime;
          },
          tabBuilder: (index, runtime) => Center(
            child: Text(
              'home-tab-$index-${runtime == null ? 'plain' : 'chat'}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home-tab-2-chat'), findsOneWidget);
    expect(find.text('home-tab-0-plain'), findsNothing);
    expect(chatRuntimeCreations, 1);

    // 首页偏好只决定普通启动；明确的广场帖子推送仍有更高导航优先级。
    openedPushes.add(const <String, dynamic>{'kind': 'square_post'});
    await pumpUntilFound(tester, find.text('home-tab-0-plain'));
    expect(find.text('home-tab-0-plain'), findsOneWidget);
    expect(chatRuntimeCreations, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HomeTabGate 缺省映射广场、打开映射聊天且读取失败可重试', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabGate(
          preferenceReader: () async {
            calls++;
            if (calls == 1) throw StateError('test read failure');
            return true;
          },
          shellBuilder: (index) => Text('resolved-home-$index'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-tab-gate-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-tab-gate-retry')));
    await tester.pumpAndSettle();
    expect(find.text('resolved-home-2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabGate(
          preferenceReader: () async => false,
          shellBuilder: (index) => Text('resolved-default-$index'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('resolved-default-0'), findsOneWidget);
  });

  testWidgets('AppPermissionGate 永久 pending 有界失败且重试不受旧结果覆盖', (tester) async {
    final blocked = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPermissionGate(
          operationTimeout: const Duration(milliseconds: 20),
          guideStateLoader: () {
            calls++;
            return calls == 1 ? blocked.future : Future.value(false);
          },
          child: const Text('permission-child'),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 25));
    expect(find.byKey(const ValueKey('permission-gate-error')), findsOneWidget);
    expect(find.text('permission-child'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('permission-gate-retry')));
    await tester.pumpAndSettle();
    expect(find.text('permission-child'), findsOneWidget);

    blocked.complete(true);
    await tester.pump();
    expect(find.text('permission-child'), findsOneWidget);
  });

  testWidgets('App级聊天打开推送由同一运行态补拉密文邮箱', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final openedPushes = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(openedPushes.close);
    final runtime = _ForegroundWakeChatRuntime();
    var chatRuntimeCreations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          openedPushData: openedPushes.stream,
          initialPushDataLoader: () async => null,
          chatRuntimeFactory: () {
            chatRuntimeCreations++;
            return runtime;
          },
          tabBuilder: (index, runtime) => Text('push-tab-$index'),
        ),
      ),
    );
    await tester.pump();

    openedPushes.add(const <String, dynamic>{'event': 'chat_wake'});
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );

    expect(chatRuntimeCreations, 1);
    expect(runtime.wakeCount, 1);
  });

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserIsar.instance.writeTxn((isar) async {
      await isar.userSettingsEntitys.put(
        UserSettingsEntity()
          ..id = 0
          ..permissionGuideSeen = true,
      );
    });

    // Mock secure storage — return null for all reads (no PIN set, no device lock).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
        case 'delete':
        case 'deleteAll':
          return null;
        case 'containsKey':
          return false;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });

    // Mock local_auth — device not supported (skips device lock gate).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
        case 'deviceSupportsBiometrics':
          return false;
        case 'getAvailableBiometrics':
          return const <String>[];
        case 'authenticate':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
  });

  testWidgets('first run shows permission guide', (tester) async {
    addTearDown(() async {
      // CitizenApp 使用全局 Navigator key；显式卸载，避免下一个用例复用已销毁的
      // Navigator / 启动门禁状态而渲染空树。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.runAsync(() => UserIsar.instance.resetForTest());

    // 每个用例使用不同根 key，强制重建全部启动门禁，避免上一用例的
    // AppPermissionGate / WalletGate 状态跨用例复用。
    await tester.pumpWidget(
      const CitizenApp(key: ValueKey('permission-guide')),
    );
    await pumpUntilFound(tester, find.text('权限设置'));
    await tester.pump();

    expect(find.text('权限设置'), findsOneWidget);
    expect(find.text('开启通知并继续'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);

    // 启动维护最多按 1 秒间隔重试两次；完整启动测试必须推进这些
    // 已知窗口，不能在根组件销毁时遗留假时钟定时器。
    for (var attempt = 0; attempt < 2; attempt += 1) {
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets(
    'app bootstraps',
    (tester) async {
      // 账户门禁要求至少 1 个热钱包才放行主界面。
      await tester.runAsync(() async {
        await WalletIsar.instance.resetForTest();
        await seedHotWallet();
      });

      await tester.pumpWidget(const CitizenApp(key: ValueKey('app-bootstrap')));
      // 等待异步锁检查 + 账户门禁的 Isar 查询完成并渲染主界面。
      await pumpUntilFound(tester, find.text('广场'));
      await tester.pumpAndSettle();

      // 底部导航最左侧为广场，公民 tab 右移；个人多签入口迁到交易页。
      expect(find.text('广场'), findsWidgets);
      expect(find.text('暂无推荐动态'), findsOneWidget);
      expect(find.text('交易'), findsWidgets);
      expect(find.text('多签'), findsNothing);
      expect(find.text('消息'), findsNothing);
      // app 启动会初始化链 RPC（smoldot）；官方 CI 先构建宿主库。开发者在无库环境
      // 直跑时跳过此全量启动冒烟（首启权限引导用例不依赖 native，仍跑）。
      // testWidgets 的 skip 仅接受 bool。连活链的全量启动冒烟默认跳过(离线会 hang 到超时);
      // 本地设 RUN_BOOTSTRAP_CHAIN_SMOKE=1 且 libsmoldot native 可用时才跑,由集成 / APK 测试覆盖。
    },
    skip: Platform.environment['RUN_BOOTSTRAP_CHAIN_SMOKE'] == null ||
        smoldotNativeSkipReason() != null,
  );

  testWidgets('no wallet: bootstraps into forced create-wallet page', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    // 无任何钱包时，账户门禁应拦在强制创建页，不进广场。
    // 强制创建页不建 AppShell（不触发 smoldot），无宿主库的本地测试也照跑。
    // 页面内容较长,高视口避免 ListView 懒加载导致底部按钮未构建。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => WalletIsar.instance.resetForTest());

    await tester.pumpWidget(
      const CitizenApp(key: ValueKey('no-wallet-bootstrap')),
    );
    await pumpUntilFound(tester, find.text('创建钱包'));
    await tester.pump();

    // 标题与创建按钮同为"创建钱包"（两处 Text），故 findsWidgets（≥1）。
    if (!tester.any(find.text('创建钱包'))) {
      final visibleTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      fail('未进入创建钱包页，当前文本：$visibleTexts');
    }
    expect(find.text('创建钱包'), findsWidgets);
    expect(find.text('广场'), findsNothing);

    // 与真实启动生命周期一致，等待短命 Chat 文件维护结束后再销毁根组件。
    for (var attempt = 0; attempt < 2; attempt += 1) {
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
