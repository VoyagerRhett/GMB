import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/create_wallet_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_citizen_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('citizenapp/security'), (_) async => null,
    );
  });

  testWidgets('原12和24词选项保留，18词为已批准增量，冷导入不受热设备门禁影响', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: CreateWalletOnboardingPage(onCreated: () {}, deviceSecureProbe: () async => false)));
    await tester.pumpAndSettle();
    for (final words in [12, 18, 24]) { expect(find.text('$words 个助记词'), findsOneWidget); }
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.ensureVisible(create);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    final cold = find.widgetWithText(TextButton, '导入冷钱包');
    await tester.ensureVisible(cold);
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
    await tester.ensureVisible(create); await tester.tap(create); await tester.pumpAndSettle();
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
      'releasePreparedWallet': (_) => [],
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme,
      home: CreateWalletOnboardingPage(onCreated: () { created++; }, deviceSecureProbe: () async => true))));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, '创建钱包');
    await tester.ensureVisible(create); await tester.tap(create); await tester.pumpAndSettle();
    expect(find.text('请备份助记词'), findsOneWidget); expect(find.text(phrase), findsOneWidget);
    expect(created, 0);
    expect(transport.calls.indexOf('copyRecoveryPhrase'), lessThan(transport.calls.indexOf('commitWalletCreation')));
    expect(transport.calls, isNot(contains('releasePreparedWallet')));
    await tester.tap(find.text('我已备份')); await tester.pumpAndSettle();
    expect(created, 1); expect(transport.calls.where((value) => value == 'releasePreparedWallet'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });
}
