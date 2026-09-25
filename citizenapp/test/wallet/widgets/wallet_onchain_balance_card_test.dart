import 'dart:async';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/wallet/widgets/wallet_onchain_balance_card.dart';

void main() {
  final wallet = CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot,
    walletIndex: 0,
    accountIndex: 0,
    accountId:
        '0x9c0c5bc3b65f2b1aeecec2a0e70e6f0ef3f2dc8d59c12a9fa79ca88e3f2c82a3',
    ss58Address: '5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty',
    name: '测试钱包',
    createdAtMillis: BigInt.zero,
    isDefault: true,
  );
  Future<CitizenAccountBalance> loadBalance(String accountId) async =>
      CitizenAccountBalance(
        accountId: accountId,
        block: CitizenBlockRef(
          hash: '0x${'11' * 32}',
          number: BigInt.one,
          finality: CitizenBlockFinality.finalized,
        ),
        freeFen: BigInt.from(100),
        reservedFen: BigInt.zero,
        totalFen: BigInt.from(100),
      );


  testWidgets('原余额区高度为123，不因SDK接线改变', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 914);
    addTearDown(tester.view.reset);
    final pending = Completer<CitizenAccountBalance>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topCenter,
      child: WalletOnchainBalanceCard(wallet: wallet, balanceLoader: (_) => pending.future),
    ))));
    expect(tester.getSize(find.byKey(const ValueKey('wallet-onchain-balance-section'))).height, 123);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(await loadBalance(wallet.accountId)); await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次失败点击重试；total含reserved；之后失败保留原金额', (tester) async {
    final key = GlobalKey<WalletOnchainBalanceCardState>();
    var failRead = true;
    final base = await loadBalance(wallet.accountId);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WalletOnchainBalanceCard(
      key: key, wallet: wallet,
      balanceLoader: (_) async {
        if (failRead) throw StateError('合成余额失败');
        return CitizenAccountBalance(accountId: base.accountId, block: base.block,
          freeFen: BigInt.from(100), reservedFen: BigInt.from(250), totalFen: BigInt.from(350));
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('查询失败，点击刷新'), findsOneWidget);
    failRead = false;
    await tester.tap(find.text('查询失败，点击刷新')); await tester.pumpAndSettle();
    expect(find.text('3.50'), findsOneWidget);
    expect(find.text('1.00'), findsNothing);
    expect(find.text('元'), findsOneWidget);
    failRead = true;
    await key.currentState!.refresh(); await tester.pumpAndSettle();
    expect(find.text('3.50'), findsOneWidget);
    expect(find.text('查询失败，点击刷新'), findsNothing);
  });

  testWidgets('余额卡保留标题、单一单位且没有内部刷新按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletOnchainBalanceCard(
            wallet: wallet,
            balanceLoader: loadBalance,
          ),
        ),
      ),
    );
    expect(find.text('链上余额'), findsOneWidget);
    expect(find.text('元'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('外层仍可通过 GlobalKey 触发刷新', (tester) async {
    final key = GlobalKey<WalletOnchainBalanceCardState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletOnchainBalanceCard(
            key: key,
            wallet: wallet,
            balanceLoader: loadBalance,
          ),
        ),
      ),
    );
    expect(key.currentState, isNotNull);
    await key.currentState!.refresh();
    await tester.pump();
  });
}
