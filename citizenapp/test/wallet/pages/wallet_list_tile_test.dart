import 'dart:io';

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
          walletName: wallet.name,
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

  testWidgets('异常事实仍复用原卡片，按SDK原模式保留配色而不构造正常账户', (tester) async {
    for (final mode in <CitizenWalletSignMode?>[CitizenWalletSignMode.hot, CitizenWalletSignMode.cold, null]) {
      final diagnostic = CitizenWalletDiagnostic(walletIndex: 0, walletName: '原异常钱包',
        accountId: account().accountId, ss58Address: null,
        diagnosticReason: CitizenWalletDiagnosticReason.invalidStructure, signMode: mode, cleanupTargets: null);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WalletListTile(
        wallet: null, diagnostic: diagnostic, walletName: diagnostic.walletName, balance: 0,
        showActions: true, isBroken: true, onTap: () {}, onRename: () {}, onDelete: () {},
      ))));
      expect(find.text('钱包数据异常，请验证热钱包或重新导入冷钱包'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.widget<Icon>(find.byIcon(Icons.account_balance_wallet_rounded)).color,
        mode == CitizenWalletSignMode.hot ? AppTheme.primaryDark : AppTheme.info);
    }
  });

  test('冷钱包导入保留App原界面，只接SDK账户码解析与导入', () {
    final source = File('lib/wallet/pages/wallet_page.dart').readAsStringSync();
    expect(source, contains('mode: QrScanMode.coldAccountImport'));
    expect(source, contains('CitizenQrScanPurpose.coldAccountImport'));
    expect(source, contains('.wallet.importColdAccount('));
    expect(source, isNot(contains('importColdAccountWithUi')));
    expect(source, isNot(contains('extractColdWalletImportAddress')));
    expect(source, isNot(contains('QrRouter().route')));
    expect(source, isNot(contains('QrRouteType.userContact')));
    expect(source, isNot(contains('QrRouteType.userTransfer')));
  });
}
