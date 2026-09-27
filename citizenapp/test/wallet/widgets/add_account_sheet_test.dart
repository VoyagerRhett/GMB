import 'dart:async';
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

  testWidgets('指定多个账户使用带空格键的输入配置并一次提交整批编号', (tester) async {
    List<Object?>? submitted;
    final transport = TestCitizenSdkTransport({
      'getWalletState': (_) => [testCitizenWalletState()],
      'walletWordSuggestions': (_) => [<String>[]],
      'validateWalletPassword': (_) => [0, null],
      'addWalletAccounts': (fields) {
        submitted = fields;
        throw const CitizenSdkException(code: CitizenSdkErrorCode.authenticationCancelled,
          message: 'synthetic cancelled authentication');
      },
    });
    final sdk = await transport.open();
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
      home: Scaffold(body: AddAccountSheet(masterId: testCitizenAccountId, mode: AddAccountMode.specify)))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
    final indices = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == '账户序号');
    await tester.showKeyboard(indices);
    expect(tester.testTextInput.setClientArgs!['inputType'], containsPair('name', 'TextInputType.text'));
    expect(tester.widget<TextField>(indices).autocorrect, isFalse);
    expect(tester.widget<TextField>(indices).enableSuggestions, isFalse);

    // 只有分隔空格不能触发SDK；逐次编辑必须保留尾部空格，才能继续输入下一编号。
    await tester.enterText(indices, '   ');
    await tester.ensureVisible(find.text('确认添加'));
    await tester.tap(find.text('确认添加')); await tester.pumpAndSettle();
    expect(find.text('请输入至少一个账户序号'), findsOneWidget);
    expect(transport.calls, isNot(contains('addWalletAccounts')));
    for (final text in ['1', '1 ', '1 5', '1 5 ', '1 5 9']) {
      await tester.enterText(indices, text);
      expect(tester.widget<TextField>(indices).controller!.text, text);
    }
    // 文本键盘不放宽既有字符白名单；字母与标点仍不会成为编号内容。
    await tester.enterText(indices, '1a 5, 9');
    expect(tester.widget<TextField>(indices).controller!.text, '1 5 9');
    await tester.ensureVisible(find.text('确认添加'));
    await tester.tap(find.text('确认添加')); await tester.pumpAndSettle();
    expect(submitted![2], <int>[1, 5, 9]);
    expect(transport.calls.where((call) => call == 'addWalletAccounts'), hasLength(1));
    expect(find.text('已取消添加账户'), findsOneWidget);
    expect(tester.widget<TextField>(indices).controller!.text, '1 5 9');
    await tester.pumpWidget(const SizedBox.shrink());
    await sdk.close(); await transport.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android,
    TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}));


  for (final mode in AddAccountMode.values) {
    for (final leave in [false, true]) {
      testWidgets('追加${mode.name}：${leave ? '退出取消且迟到不导航' : '成功返回原入口'}', (tester) async {
        final pending = Completer<List<Object?>>();
        final method = mode == AddAccountMode.next ? 'addNextWalletAccount' : 'addWalletAccounts';
        final transport = TestCitizenSdkTransport({
          'getWalletState': (_) => [testCitizenWalletState()],
          'walletWordSuggestions': (_) => [<String>[]], 'validateWalletPassword': (_) => [0, null],
          method: (_) => pending.future, 'cancelOperation': (_) => [true],
        });
        final sdk = await transport.open();
        bool? result;
        await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk,
          child: MaterialApp(home: Builder(builder: (context) => Scaffold(
            body: TextButton(onPressed: () async {
              result = await showAddAccountSheet(context, masterId: testCitizenAccountId, mode: mode);
            }, child: const Text('打开追加')),
          )))));
        await tester.tap(find.text('打开追加')); await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
        if (mode == AddAccountMode.specify) {
          await tester.enterText(find.byWidgetPredicate((w) => w is TextField &&
            w.decoration?.labelText == '账户序号'), '1 5 9');
        }
        await tester.ensureVisible(find.text('确认添加'));
        await tester.tap(find.text('确认添加')); await tester.pump();
        expect(transport.calls, contains(method));
        if (leave) {
          Navigator.of(tester.element(find.byType(AddAccountSheet))).pop();
          await tester.pumpAndSettle();
          expect(transport.calls, contains('cancelOperation'));
        }
        pending.complete([testCitizenWalletProfile()]); await tester.pumpAndSettle();
        expect(result, leave ? isNull : isTrue);
        expect(find.text('打开追加'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
      });
    }
  }

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
      expect(find.text('请检查助记词、钱包密码和账户序号'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink()); await sdk.close(); await transport.dispose();
    });
  }
  for (final mode in AddAccountMode.values) {
    for (final item in <(CitizenSdkErrorCode, String)>[
      (CitizenSdkErrorCode.keyInvalidated, '钱包安全密钥不可用，无法添加账户'),
      (CitizenSdkErrorCode.authenticationCancelled, '已取消添加账户'),
      (CitizenSdkErrorCode.conflict, '钱包状态已变化，请重新打开添加账户'),
      (CitizenSdkErrorCode.storage, '账户保存失败，请重试'),
      (CitizenSdkErrorCode.internal, '添加账户失败，请重试'),
    ]) {
      testWidgets('追加${mode.name}按错误类别显示中文：${item.$1.name}', (tester) async {
        final method = mode == AddAccountMode.next ? 'addNextWalletAccount' : 'addWalletAccounts';
        final transport = TestCitizenSdkTransport({
          'getWalletState': (_) => [testCitizenWalletState()],
          'walletWordSuggestions': (_) => [<String>[]],
          'validateWalletPassword': (_) => [0, null],
          method: (_) => throw CitizenSdkException(code: item.$1, message: 'synthetic internal vault detail'),
        });
        final sdk = await transport.open();
        await tester.pumpWidget(Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
          home: Scaffold(body: AddAccountSheet(masterId: testCitizenAccountId, mode: mode)))));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'synthetic mnemonic input');
        if (mode == AddAccountMode.specify) {
          await tester.enterText(find.byWidgetPredicate((w) => w is TextField &&
            w.decoration?.labelText == '账户序号'), '5');
        }
        await tester.ensureVisible(find.text('确认添加'));
        await tester.tap(find.text('确认添加')); await tester.pumpAndSettle();
        expect(find.text(item.$2), findsOneWidget);
        expect(find.textContaining('synthetic internal vault detail'), findsNothing);
        expect(find.byType(AddAccountSheet), findsOneWidget);
        expect(transport.calls.where((call) => call == method), hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await sdk.close(); await transport.dispose();
      });
    }
  }

}
