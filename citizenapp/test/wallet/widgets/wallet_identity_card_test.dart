import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/widgets/wallet_identity_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_qr_dialog.dart';

void main() {
  final wallet = CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot,
    walletIndex: 0,
    accountIndex: 0,
    accountId:
        '0x0000000000000000000000000000000000000000000000000000000000000000',
    ss58Address: '5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty',
    name: '我的钱包',
    createdAtMillis: BigInt.zero,
    isDefault: true,
  );

  Future<void> pumpCard(
    WidgetTester tester,
    Future<void> Function(String) onNameChanged,
  ) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: WalletIdentityCard(
              wallet: wallet,
              onNameChanged: onNameChanged,
            ),
          ),
        ),
      );

  testWidgets('保留钱包名称、完整地址、复制和二维码入口', (tester) async {
    await pumpCard(tester, (_) async {});
    expect(find.text('我的钱包'), findsOneWidget);
    final first = tester.widget<Text>(
      find.byKey(const ValueKey('wallet-identity-address-line-1')),
    );
    final second = tester.widget<Text>(
      find.byKey(const ValueKey('wallet-identity-address-line-2')),
    );
    expect('${first.data}${second.data}', wallet.ss58Address);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_rounded), findsOneWidget);
  });

  testWidgets('钱包名编辑仍只通过回调提交', (tester) async {
    String? received;
    await pumpCard(tester, (value) async => received = value);
    await tester.tap(find.text('我的钱包'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新钱包名');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(received, '新钱包名');
  });

  test('账户码生成直接调用 CitizenQr', () async {
    final qr = _RecordingQr();
    final encoded = await buildWalletAccountQrData(qr, wallet.accountId);
    expect(qr.accountId, wallet.accountId);
    expect(encoded, 'sdk-account:${wallet.accountId}');
  });
}

final class _RecordingQr implements CitizenQr {
  String? accountId;

  @override
  Future<String> encodeAccountId(String accountId) async {
    this.accountId = accountId;
    return 'sdk-account:$accountId';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
