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
