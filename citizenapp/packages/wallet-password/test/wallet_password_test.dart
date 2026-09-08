import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmb_wallet_password/wallet_password.dart';

void main() {
  test('空 password 表示沿用现有钱包', () {
    expect(WalletPassword.parse('').value, isEmpty);
  });

  test('五类字符和长度边界均按用户可见字符校验', () {
    for (final value in [
      'ABCDEF',
      'abcdef',
      '123456',
      '!@#\$%^',
      '中华民族复兴',
      'Aa1!中华',
    ]) {
      expect(WalletPassword.parse(value).value, value);
    }
    expect(
      WalletPassword.parse(
        List<String>.filled(30, '中').join(),
      ).value.characters.length,
      30,
    );
  });

  test('非空 password 的长度必须为 6–30 位', () {
    for (final value in [
      'a',
      'abcde',
      List<String>.filled(31, 'a').join(),
    ]) {
      expect(
        () => WalletPassword.parse(value),
        throwsA(isA<WalletPasswordException>()),
      );
    }
  });

  test('空白、emoji、全角和其他文字体系全部拒绝', () {
    for (final value in [
      'abcde ',
      'abc de',
      'abcde\n',
      'abcde😀',
      'Ａbcdef',
      '가나다라마바',
      'абвгде',
    ]) {
      expect(
        () => WalletPassword.parse(value),
        throwsA(isA<WalletPasswordException>()),
      );
    }
  });

  testWidgets('空 password 不弹窗，非空 password 只弹一次风险确认', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('页面'));
          },
        ),
      ),
    );

    expect(
      await confirmWalletPasswordUse(pageContext, WalletPassword.parse('')),
      isTrue,
    );
    expect(find.text('确认钱包密码'), findsNothing);

    final confirmation = confirmWalletPasswordUse(
      pageContext,
      WalletPassword.parse('Ab1!中华'),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认钱包密码'), findsOneWidget);
    expect(
      find.text(
        '钱包密码将用于派生钱包账户，不同的密码会派生完全不同的账户，'
        '请务必牢记密码，忘记密码将无法恢复钱包。',
      ),
      findsOneWidget,
    );
    final cancelButton = find.widgetWithText(TextButton, '取消');
    final confirmButton = find.widgetWithText(FilledButton, '确认');
    expect(
      tester.getSize(cancelButton).width,
      closeTo(tester.getSize(confirmButton).width, 0.01),
    );
    expect(
      tester.getCenter(cancelButton).dx,
      lessThan(tester.getCenter(confirmButton).dx),
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
  });
}
