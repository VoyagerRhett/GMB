import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:citizenapp/my/myid/widgets/rebind_account_sheet.dart';
CitizenWalletStateAccount _account({
  int index = 5,
  String name = '账户5',
  String accountId =
      '0x1111111111111111111111111111111111111111111111111111111111111111',
}) {
  return CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot,
    walletIndex: 0,
    accountIndex: index,
    accountId: accountId,
    ss58Address: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
    name: name,
    createdAtMillis: BigInt.zero,
    isDefault: index == 0,
  );
}

void main() {
  testWidgets('空 targets 显示「暂无可换绑」提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RebindAccountSheet(targets: [])),
      ),
    );
    expect(find.text('更换公民号绑定的账户'), findsOneWidget);
    expect(
      find.text(
        '更换公民号绑定的签名账户为以下选中的账户，更换绑定需当前钱包账户与目标钱包账户'
        '各签名一次（共两次生物识别授权）。',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('暂无可换绑'), findsOneWidget);
  });

  testWidgets('点选账户回传其 accountId', (tester) async {
    String? picked = 'UNSET';
    final account = _account();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => picked = await showRebindAccountSheet(
                  context,
                  targets: [account],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('账户5'), findsOneWidget);
    expect(find.text('#5'), findsOneWidget);

    await tester.tap(find.text('账户5'));
    await tester.pumpAndSettle();
    expect(picked, account.accountId);
  });
}
