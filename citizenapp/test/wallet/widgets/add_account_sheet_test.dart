import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/widgets/add_account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../support/fake_citizen_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('citizenapp/security'), (_) async => null));

  for (final mode in AddAccountMode.values) {
    testWidgets('原${mode.name}模式只调用对应SDK追加，不另加密码确认或面板模式切换', (tester) async {
      List<Object?>? submitted;
      final method = mode == AddAccountMode.next ? 'addNextWalletAccount' : 'addWalletAccounts';
      final transport = TestCitizenSdkTransport({
        'getWalletState': (_) => [testCitizenWalletState()],
        'walletWordSuggestions': (_) => [<String>[]],
        'validateWalletPassword': (_) => [0, null],
        method: (fields) { submitted = fields; throw const CitizenSdkException(code: CitizenSdkErrorCode.invalidArgument, message: '合成追加错误'); },
      });
      final sdk = await transport.open();
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(theme: AppTheme.lightTheme,
        home: Scaffold(body: AddAccountSheet(masterId: testCitizenAccountId, mode: mode)))));
      await tester.pumpAndSettle();
      expect(find.text(mode == AddAccountMode.next ? '添加下一个账户' : '添加指定账户'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
      final password = find.byWidgetPredicate((value) => value is TextField && value.obscureText);
      await tester.enterText(password, 'Test123');
      if (mode == AddAccountMode.specify) {
        await tester.enterText(find.byWidgetPredicate((value) => value is TextField && value.decoration?.labelText == '账户序号'), '1 5 9');
      }
      await tester.ensureVisible(find.text('确认添加')); await tester.tap(find.text('确认添加')); await tester.pumpAndSettle();
      expect(find.text('确认钱包密码'), findsNothing);
      expect(submitted, isNotNull); expect(submitted![1], 'Test123');
      if (mode == AddAccountMode.next) { expect(submitted, hasLength(2)); }
      else { expect(submitted![2], <int>[1, 5, 9]); }
      expect(find.text('合成追加错误'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
    });
  }
}
