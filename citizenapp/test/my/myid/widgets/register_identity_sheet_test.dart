import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:citizenapp/citizen/cid/cid_generator.dart';
import 'package:citizenapp/my/myid/widgets/register_identity_sheet.dart';
CitizenWalletStateAccount _account({int index = 0, String? id}) =>
    CitizenWalletStateAccount(
      signMode: CitizenWalletSignMode.hot,
      walletIndex: 0,
      accountIndex: index,
      accountId: id ?? '0x${index.toRadixString(16).padLeft(64, '0')}',
      ss58Address: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
      name: '账户$index',
      createdAtMillis: BigInt.zero,
      isDefault: index == 0,
    );

void main() {
  // 打开面板并回传选择结果;`picked` 在面板 pop 后被赋值。
  Future<void> openSheet(
    WidgetTester tester,
    void Function(RegisterChoice?) sink, {
    List<CitizenWalletStateAccount>? accounts,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => sink(
                  await showRegisterIdentitySheet(
                    context,
                    accounts: accounts ?? [_account()],
                  ),
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
  }

  testWidgets('默认选公民 + 默认绑账户0,确认返回 CTZN', (tester) async {
    RegisterChoice? picked;
    await openSheet(tester, (v) => picked = v);

    expect(find.text('公民'), findsOneWidget);
    expect(find.text('居民'), findsOneWidget);
    // 单账户不露出绑定账户选择。
    expect(find.text('绑定钱包账户'), findsNothing);

    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();
    expect(picked?.institution, kCidInstitutionCitizen);
    expect(picked?.bindAccountId, _account().accountId);
  });

  testWidgets('选居民后确认返回 NATP', (tester) async {
    RegisterChoice? picked;
    await openSheet(tester, (v) => picked = v);

    await tester.tap(find.text('居民'));
    await tester.pump();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();
    expect(picked?.institution, kCidInstitutionResident);
  });

  testWidgets('多账户时露出绑定账户选择,可选非0账户', (tester) async {
    RegisterChoice? picked;
    final a0 = _account(index: 0);
    final a5 = _account(
      index: 5,
      id: '0x5555555555555555555555555555555555555555555555555555555555555555',
    );
    await openSheet(tester, (v) => picked = v, accounts: [a0, a5]);

    expect(find.text('绑定钱包账户'), findsOneWidget);
    await tester.tap(find.text('账户5'));
    await tester.pump();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();
    expect(picked?.bindAccountId, a5.accountId);
  });

  testWidgets('含「投票/竞选须去注册局」的风险提示', (tester) async {
    await openSheet(tester, (_) {});
    expect(find.textContaining('投票公民、竞选公民只能在对应注册局'), findsOneWidget);
  });
}
