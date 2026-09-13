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
