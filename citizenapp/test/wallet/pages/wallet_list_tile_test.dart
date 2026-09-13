import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';

void main() {
  CitizenWalletStateAccount account({
    CitizenWalletSignMode mode = CitizenWalletSignMode.hot,
    int index = 1,
    String name = '我的钱包',
    bool isDefault = false,
  }) {
    final accountId = '0x${index.toRadixString(16).padLeft(64, '0')}';
    return CitizenWalletStateAccount(
      signMode: mode,
      walletIndex: index,
      accountIndex: mode == CitizenWalletSignMode.hot ? index : null,
      accountId: accountId,
      ss58Address: ss58FromAccountIdText(accountId),
      name: name,
      createdAtMillis: BigInt.zero,
      isDefault: isDefault,
    );
  }

  Future<void> pumpTile(
    WidgetTester tester, {
    required CitizenWalletStateAccount wallet,
    bool showActions = true,
    bool isBroken = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WalletListTile(
          wallet: wallet,
          balance: 1234567.89,
          showActions: showActions,
          isDefault: wallet.isDefault,
          isBroken: isBroken,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ),
  );

  testWidgets('保留名称、余额、默认文字和冷热配色', (tester) async {
    await pumpTile(
      tester,
      wallet: account(mode: CitizenWalletSignMode.cold, isDefault: true),
    );
    expect(find.text('我的钱包'), findsOneWidget);
    expect(find.text('1,234,567.89'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.byIcon(Icons.account_balance_wallet_rounded).first,
    );
    expect(icon.color, AppTheme.info);
  });

  testWidgets('操作菜单仍只有重命名和删除钱包', (tester) async {
    await pumpTile(tester, wallet: account());
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除钱包'), findsOneWidget);
    expect(find.text('钱包详情'), findsNothing);
  });

  test('SDK 公开账户事实决定异常行', () {
    expect(isBrokenCitizenWalletStateAccount(account()), isFalse);
    final valid = account();
    final broken = CitizenWalletStateAccount(
      signMode: valid.signMode,
      walletIndex: valid.walletIndex,
      accountIndex: valid.accountIndex,
      accountId: valid.accountId,
      ss58Address: 'wrong',
      name: valid.name,
      createdAtMillis: valid.createdAtMillis,
      isDefault: valid.isDefault,
    );
    expect(isBrokenCitizenWalletStateAccount(broken), isTrue);
  });

  test('冷钱包账户码由 CitizenQr 解析，业务用户码仍由 App 解析', () async {
    const accountId =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const qr = _AccountQr(accountId);
    expect(
      await extractColdWalletImportAddress(qr, 'sdk-account-code'),
      ss58FromAccountIdText(accountId),
    );
    const userQr =
        '{"p":"QR_V1","k":3,"b":{"c":"CN001-CTZN-000000001-2026","n":"$accountId"}}';
    expect(
      await extractColdWalletImportAddress(qr, userQr),
      ss58FromAccountIdText(accountId),
    );
  });
}

final class _AccountQr implements CitizenQr {
  const _AccountQr(this.accountId);
  final String accountId;

  @override
  Future<CitizenQrDocument> parse(String text) async {
    if (text != 'sdk-account-code') throw const FormatException('business');
    return CitizenQrDocument(
      kind: CitizenQrKind.accountId,
      canonicalText: text,
      accountId: accountId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
