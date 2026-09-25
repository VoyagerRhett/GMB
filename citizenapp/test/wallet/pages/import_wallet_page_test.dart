import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/import_wallet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../support/fake_citizen_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('citizenapp/security'), (_) async => null));


  for (final leave in [false, true]) {
    testWidgets('导入${leave ? '退出后迟到结果不导航' : '成功清输入并返回true'}', (tester) async {
      final pending = Completer<List<Object?>>();
      final transport = TestCitizenSdkTransport({
        'walletWordSuggestions': (_) => [<String>[]],
        'validateWalletPassword': (_) => [0, null],
        'importWallet': (_) => pending.future,
        'cancelOperation': (_) => [true],
      });
      final sdk = await transport.open();
      bool? result;
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
        child: MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ImportWalletPage()));
          }, child: const Text('打开导入')),
        )))));
      await tester.tap(find.text('打开导入')); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认导入')); await tester.pump();
      expect(transport.calls, contains('importWallet'));
      if (leave) {
        Navigator.of(tester.element(find.byType(ImportWalletPage))).pop();
        await tester.pumpAndSettle();
        expect(transport.calls, contains('cancelOperation'));
      }
      pending.complete([testCitizenWalletProfile()]);
      await tester.pumpAndSettle();
      expect(result, leave ? isNull : isTrue);
      expect(find.text('打开导入'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
    });
  }

  testWidgets('导入失败使用原弹窗，重试后仍留页并保留输入', (tester) async {
    final transport = TestCitizenSdkTransport({
      'walletWordSuggestions': (_) => [<String>[]],
      'validateWalletPassword': (_) => [0, null],
      'importWallet': (_) => throw const CitizenSdkException(code: CitizenSdkErrorCode.invalidArgument, message: '合成助记词错误'),
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme, home: const ImportWalletPage())));
    await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认导入')); await tester.pumpAndSettle();
    expect(find.text('导入失败'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '重试')); await tester.pumpAndSettle();
    expect(find.byType(ImportWalletPage), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'synthetic mnemonic input');
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });

  testWidgets('取消原密码确认不调用导入，也不清空助记词输入', (tester) async {
    final transport = TestCitizenSdkTransport({
      'walletWordSuggestions': (_) => [<String>[]], 'validateWalletPassword': (_) => [0, null],
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme, home: const ImportWalletPage())));
    await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
    await tester.enterText(find.byType(TextField).last, 'Test123'); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认导入')); await tester.pumpAndSettle();
    expect(find.text('确认钱包密码'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消')); await tester.pumpAndSettle();
    expect(transport.calls, isNot(contains('importWallet')));
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'synthetic mnemonic input');
    await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
  });
}
