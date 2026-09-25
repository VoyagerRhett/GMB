import 'dart:async';
import 'dart:convert';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/create_wallet_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_citizen_sdk.dart';

// 同时推进测试帧与平台异步回包，按真实完成条件有界等待；不把帧稳定当作资源已归还。
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; !done() && attempt < 50; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'SDK资源归还及原完成回调必须在有界等待内结束');
}

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('citizenapp/security'), (_) async => null,
    );
  });


  for (final reject in [false, true]) {
    testWidgets('校验期间退出，迟到${reject ? '失败' : '成功'}不更新页面或创建钱包', (tester) async {
      final validation = Completer<List<Object?>>();
      final transport = TestCitizenSdkTransport({
        'validateWalletPassword': (_) => validation.future,
      });
      final sdk = await transport.open();
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
        child: MaterialApp(home: CreateWalletOnboardingPage(
          onCreated: () => fail('退出后不得放行'),
          deviceSecureProbe: () async => true))));
      await tester.pumpAndSettle();
      final create = find.widgetWithText(FilledButton, '创建钱包');
      await tester.scrollUntilVisible(create, 250,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(create); await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      if (reject) {
        validation.completeError(const CitizenSdkException(
          code: CitizenSdkErrorCode.invalidArgument, message: '合成迟到校验失败'));
      } else { validation.complete([0, null]); }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(transport.calls, isNot(contains('prepareWalletCreation')));
      await sdk.close(); await transport.dispose();
    });
  }

  testWidgets('校验等待期间连续点击只校验一次，取消确认后可以重新发起', (tester) async {
    final validation = Completer<List<Object?>>();
    final transport = TestCitizenSdkTransport({
      'validateWalletPassword': (_) => validation.future,
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
      child: MaterialApp(home: CreateWalletOnboardingPage(onCreated: () {},
        deviceSecureProbe: () async => true))));
    await tester.pumpAndSettle();
    final password = find.byType(TextField);
    await tester.ensureVisible(password); await tester.enterText(password, 'Test123');
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(create); await tester.pump();
    await tester.tap(create); await tester.pump();
    expect(transport.calls.where((m) => m == 'validateWalletPassword'), hasLength(1));
    expect(find.text('创建中…'), findsNothing);
    validation.complete([0, null]); await tester.pumpAndSettle();
    expect(find.text('确认钱包密码'), findsOneWidget);
    await tester.tap(find.text('取消')); await tester.pumpAndSettle();
    expect(transport.calls, isNot(contains('prepareWalletCreation')));
    await tester.tap(create); await tester.pumpAndSettle();
    expect(transport.calls.where((m) => m == 'validateWalletPassword'), hasLength(2));
    expect(find.text('确认钱包密码'), findsOneWidget);
    await tester.tap(find.text('取消')); await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });

  testWidgets('原12和24词选项保留，18词为已批准增量，冷导入不受热设备门禁影响', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: CreateWalletOnboardingPage(onCreated: () {}, deviceSecureProbe: () async => false)));
    await tester.pumpAndSettle();
    for (final words in [12, 18, 24]) { expect(find.text('$words 个助记词'), findsOneWidget); }
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    final cold = find.widgetWithText(TextButton, '导入冷钱包');
    await tester.scrollUntilVisible(cold, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(tester.widget<TextButton>(cold).onPressed, isNotNull);
  });

  testWidgets('18词准确传到SDK，失败保留原创建失败弹窗且不放行', (tester) async {
    int? selected;
    var created = 0;
    final transport = TestCitizenSdkTransport({
      'validateWalletPassword': (_) => [0, null],
      'prepareWalletCreation': (fields) {
        selected = fields[0] as int;
        throw const CitizenSdkException(code: CitizenSdkErrorCode.invalidArgument, message: '合成创建失败');
      },
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme,
      home: CreateWalletOnboardingPage(onCreated: () { created++; }, deviceSecureProbe: () async => true))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('18 个助记词'));
    await tester.tap(find.text('18 个助记词'));
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first); await tester.tap(create); await tester.pumpAndSettle();
    expect(selected, 18); expect(created, 0);
    expect(find.text('创建钱包失败'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });

  testWidgets('提交成功后显示原备份框，关闭备份才放行并释放资源', (tester) async {
    const phrase = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    var created = 0;
    final transport = TestCitizenSdkTransport({
      'validateWalletPassword': (_) => [0, null],
      'prepareWalletCreation': (_) => ['prepared_1'],
      'copyRecoveryPhrase': (_) => [Uint8List.fromList(utf8.encode(phrase))],
      'commitWalletCreation': (_) => [testCitizenWalletProfile()],
      'getWalletState': (_) => [testCitizenWalletState()],
      'releasePreparedWallet': (_) => [],
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme,
      home: CreateWalletOnboardingPage(onCreated: () { created++; }, deviceSecureProbe: () async => true))));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first); await tester.tap(create); await tester.pumpAndSettle();
    expect(find.text('请备份助记词'), findsOneWidget); expect(find.text(phrase), findsOneWidget);
    expect(created, 0);
    expect(transport.calls.indexOf('copyRecoveryPhrase'), lessThan(transport.calls.indexOf('commitWalletCreation')));
    expect(transport.calls, isNot(contains('releasePreparedWallet')));
    await tester.tap(find.text('我已备份')); await tester.pumpAndSettle();
    await _pumpUntil(tester, () => created == 1);
    expect(created, 1); expect(transport.calls.where((value) => value == 'releasePreparedWallet'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });

  for (final reason in ['后台', '目录变更', '读取失败']) {
    testWidgets('原备份框$reason立即清屏，返回前台或迟到事件不重开', (tester) async {
      addTearDown(() => _foreground(tester));
      const phrase = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      var created = 0;
      var revision = '1';
      var readFails = false;
      final transport = TestCitizenSdkTransport({
        'validateWalletPassword': (_) => [0, null],
        'prepareWalletCreation': (_) => ['prepared_1'],
        'copyRecoveryPhrase': (_) => [Uint8List.fromList(utf8.encode(phrase))],
        'commitWalletCreation': (_) => [testCitizenWalletProfile()],
        'getWalletState': (_) {
          if (readFails) {
            throw const CitizenSdkException(
              code: CitizenSdkErrorCode.storage, message: '合成目录读取失败');
          }
          return [testCitizenWalletState()..[0] = revision];
        },
        'releasePreparedWallet': (_) => [],
      });
      final sdk = await transport.open();
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
        child: MaterialApp(theme: AppTheme.lightTheme, home: CreateWalletOnboardingPage(
          onCreated: () { created++; }, deviceSecureProbe: () async => true))));
      await tester.pumpAndSettle();
      final create = find.widgetWithText(FilledButton, '创建钱包');
      await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first); await tester.tap(create); await tester.pumpAndSettle();
      expect(find.text(phrase), findsOneWidget);
      if (reason == '后台') {
        _background(tester);
      } else {
        revision = '2'; readFails = reason == '读取失败';
        transport.walletChanged();
      }
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => created == 1);
      expect(find.text(phrase), findsNothing);
      expect(find.text('请备份助记词'), findsNothing);
      expect(created, 1); // 提交已成功，清屏不再删除钱包或伪报创建失败。
      if (reason == '后台') _foreground(tester);
      transport.walletChanged();
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => created == 1);
      expect(find.text(phrase), findsNothing);
      expect(transport.calls.where((value) => value == 'releasePreparedWallet'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
    });
  }

  testWidgets('提交期间进入后台，迟到成功不显示备份并归还准备资源', (tester) async {
    addTearDown(() => _foreground(tester));
    final commit = Completer<List<Object?>>();
    var created = 0;
    final transport = TestCitizenSdkTransport({
      'validateWalletPassword': (_) => [0, null],
      'prepareWalletCreation': (_) => ['prepared_1'],
      'copyRecoveryPhrase': (_) => [Uint8List.fromList(utf8.encode(
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'))],
      'commitWalletCreation': (_) => commit.future,
      'releasePreparedWallet': (_) => [],
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
      child: MaterialApp(theme: AppTheme.lightTheme, home: CreateWalletOnboardingPage(
        onCreated: () { created++; }, deviceSecureProbe: () async => true))));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.scrollUntilVisible(create, 250,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first); await tester.tap(create); await tester.pump();
    expect(transport.calls, contains('commitWalletCreation'));
    _background(tester);
    commit.complete([testCitizenWalletProfile()]);
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => created == 1);
    expect(find.text('请备份助记词'), findsNothing);
    expect(created, 1);
    expect(transport.calls.where((value) => value == 'releasePreparedWallet'), hasLength(1));
    _foreground(tester);
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });
}
