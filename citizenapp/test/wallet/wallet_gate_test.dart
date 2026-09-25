import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/wallet/wallet_gate.dart';
import 'package:citizenapp/wallet/pages/create_wallet_onboarding_page.dart';
import '../support/fake_citizen_sdk.dart';

void main() {
  late CitizenSdk sdk;
  late TestCitizenSdkTransport transport;
  setUp(() async {
    transport = TestCitizenSdkTransport({
      'getCapabilities': (_) => throw const CitizenSdkException(code: CitizenSdkErrorCode.unavailable, message: '合成能力不可用'),
    });
    sdk = await transport.open();
  });
  tearDown(() async { await sdk.close(); await transport.dispose(); });

  Widget gate(Future<CitizenWalletState> Function() loader, {Duration timeout = const Duration(seconds: 5), VoidCallback? introduced}) =>
      Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(home: WalletGate(
        walletStateLoader: loader, loadTimeout: timeout,
        onInitialized: (_) => introduced?.call(), child: const Scaffold(body: Text('main-shell')),
      )));

  testWidgets('无钱包保留原App入口，SDK就绪事件不越过原备份结束回调', (tester) async {
    var ready = false, introduced = 0;
    await tester.pumpWidget(gate(() async => ready ? _state([_account(CitizenWalletSignMode.cold)]) : _state([]),
      introduced: () => introduced++));
    await tester.pumpAndSettle();
    // 原页面使用惰性ListView，先按真实滚动行为使底部按钮进入构建范围。
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, '创建钱包'), 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.widgetWithText(FilledButton, '创建钱包'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('已有钱包？导入助记词'), 150,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.text('已有钱包？导入助记词'), findsOneWidget);
    expect(find.byType(CreateWalletOnboardingPage), findsOneWidget);
    ready = true; transport.walletChanged();
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsNothing);
    tester.widget<CreateWalletOnboardingPage>(find.byType(CreateWalletOnboardingPage)).onCreated();
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsOneWidget); expect(introduced, 1);
    expect(transport.calls, isNot(contains('initializeWallet')));
  });

  testWidgets('热账户或冷账户任一存在都放行，不触发初始化', (tester) async {
    for (final mode in CitizenWalletSignMode.values) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(gate(() async => _state([_account(mode)])));
      await tester.pumpAndSettle();
      expect(find.text('main-shell'), findsOneWidget);
      expect(find.byType(CreateWalletOnboardingPage), findsNothing);
    }
  });

  testWidgets('异常钱包也不是空目录，门禁放行由SDK事实决定', (tester) async {
    await tester.pumpWidget(gate(() async => CitizenWalletState(revision: BigInt.one, hotProfile: null,
      accounts: const [], initializationState: CitizenWalletInitializationState.ready, cleanupPending: false,
      diagnostics: [CitizenWalletDiagnostic(walletIndex: 0, walletName: '异常', accountId: testCitizenAccountId,
        ss58Address: null, diagnosticReason: CitizenWalletDiagnosticReason.invalidStructure, signMode: null, cleanupTargets: null)])));
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('SDK读取失败不当空，原重试成功后放行', (tester) async {
    var calls = 0;
    await tester.pumpWidget(gate(() async {
      if (++calls == 1) throw Exception('合成读取失败');
      return _state([_account(CitizenWalletSignMode.hot)]);
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地钱包读取失败'), findsOneWidget);
    expect(find.byType(CreateWalletOnboardingPage), findsNothing);
    await tester.tap(find.text('重试')); await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('运行期SDK删除至空回原门禁，不自动调用SDK窗口', (tester) async {
    var state = _state([_account(CitizenWalletSignMode.hot)]);
    await tester.pumpWidget(gate(() async => state)); await tester.pumpAndSettle();
    state = _state([]); transport.walletChanged(); await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsNothing);
    expect(find.byType(CreateWalletOnboardingPage), findsOneWidget);
    expect(transport.calls, isNot(contains('initializeWallet')));
  });

  testWidgets('未收敛状态和超时保留原错误与重试，不启动初始化', (tester) async {
    await tester.pumpWidget(gate(() async => CitizenWalletState(revision: BigInt.one, hotProfile: null,
      accounts: const [], initializationState: CitizenWalletInitializationState.recovering, cleanupPending: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地钱包读取失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final pending = Completer<CitizenWalletState>();
    await tester.pumpWidget(gate(() => pending.future, timeout: const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 25));
    expect(find.textContaining('本地钱包读取失败'), findsOneWidget);
    expect(find.byType(CreateWalletOnboardingPage), findsNothing);
  });
}

CitizenWalletState _state(List<CitizenWalletStateAccount> accounts) => CitizenWalletState(
  revision: BigInt.one, hotProfile: accounts.any((value) => value.signMode == CitizenWalletSignMode.hot)
    ? const CitizenSdkFlutterCodec().decodeWalletProfile(testCitizenWalletProfile()) : null,
  accounts: accounts, initializationState: accounts.isEmpty ? CitizenWalletInitializationState.empty : CitizenWalletInitializationState.ready,
  cleanupPending: false);

CitizenWalletStateAccount _account(CitizenWalletSignMode mode) {
  final hot = const CitizenSdkFlutterCodec().decodeWalletState(testCitizenWalletState()).accounts.single;
  return mode == CitizenWalletSignMode.hot ? hot : CitizenWalletStateAccount(
    signMode: mode, walletIndex: 1, accountIndex: null, accountId: hot.accountId, ss58Address: hot.ss58Address,
    name: 'cold', createdAtMillis: BigInt.one, isDefault: true);
}
