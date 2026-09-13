import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_page.dart';
import 'package:citizenapp/transaction/personal-manage/personal_account_entry.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/transaction_tab_page.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';

const _walletAAccountId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _walletBAccountId =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

CitizenWalletStateAccount _wallet({
  required int index,
  required String name,
  required String address,
  required String accountId,
}) {
  return CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot,
    walletIndex: index,
    accountIndex: index,
    name: name,
    ss58Address: address,
    accountId: accountId,
    createdAtMillis: BigInt.from(index),
    isDefault: true,
  );
}

LocalTxEntity _tx({
  required String recordKey,
  required String ss58Address,
  required String accountId,
  required String amountDeltaFen,
  required String status,
}) {
  return LocalTxEntity()
    ..recordKey = recordKey
    ..ss58Address = ss58Address
    ..accountId = LocalTxStore.requireAccountId(accountId)
    ..type = 'transfer'
    ..amountDeltaFen = amountDeltaFen
    ..transferAmountFen = amountDeltaFen.replaceFirst('-', '')
    ..counterpartySs58Address = 'counterparty'
    ..fromSs58Address = ss58Address
    ..toSs58Address = 'counterparty'
    ..status = status
    ..source = 'test'
    ..createdAtMillis = recordKey.hashCode;
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('交易页顶栏显示链状态，入口只剩多签账户卡片，扫码收进收款地址框', (tester) async {
    ContactPickMode? openedContactMode;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: TransactionTabPage(
          currentWalletLoader: () async => null,
          localRecordsLoader: (_, {limit = 100}) async => const [],
          balanceLoader: (_) async => 0,
          contactPageBuilder: (mode) {
            openedContactMode = mode;
            return const Scaffold(body: Text('通讯录测试页'));
          },
        ),
      ),
    );
    await tester.pump();

    // 个人多签账户列表已经迁入交易页入口，机构多签不在这里展示。
    // 链上支付主体字段(收款地址 / 金额 / 签名交易)由 `OnchainPaymentPanel`
    // 在选中钱包后渲染,本测试只校验顶层入口结构。
    expect(find.text('交易'), findsNothing);
    expect(find.byTooltip('我的通讯录'), findsOneWidget);
    expect(find.byTooltip('选择交易钱包'), findsOneWidget);
    expect(find.byType(ChainProgressBanner), findsOneWidget);
    expect(find.text('公民链'), findsOneWidget);
    expect(find.text('最终区块 —'), findsOneWidget);
    final chainLabel = tester.widget<Text>(find.text('公民链'));
    final finalizedLabel = tester.widget<Text>(find.text('最终区块 —'));
    expect(chainLabel.style?.color, AppTheme.info);
    expect(finalizedLabel.style?.color, AppTheme.info);
    expect(find.textContaining('已更新'), findsNothing);
    expect(find.textContaining('更新中'), findsNothing);
    expect(find.textContaining('连接失败'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('transaction-chain-status-inline')),
      findsOneWidget,
    );
    final centerGap = tester.getRect(
      find.byKey(const ValueKey<String>('transaction-chain-status-center-gap')),
    );
    final screenWidth = tester.getSize(find.byType(Scaffold).first).width;
    expect(centerGap.center.dx, closeTo(screenWidth / 2, 0.01));
    // 交易顶栏状态不再使用原卡片中的竖线。
    expect(
      find.byKey(const ValueKey<String>('transaction-chain-status-divider')),
      findsNothing,
    );
    // 顶部入口只剩多签账户一张独立卡片：不再是双入口，故也不再有中间竖线。
    expect(find.byType(PersonalAccountEntryCard), findsOneWidget);
    expect(find.text('多签账户'), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PersonalAccountEntryCard),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
    expect(find.text('个人多签'), findsNothing);
    expect(find.text('机构多签'), findsNothing);

    // 扫一扫入口已撤销，扫码收进收款地址框内；签名请求改由「聊天 → 扫一扫」承接。
    expect(find.text('扫一扫'), findsNothing);
    expect(find.byTooltip('扫码填入收款地址'), findsOneWidget);

    await tester.tap(find.byTooltip('我的通讯录'));
    await _pumpUntilFound(tester, find.text('通讯录测试页'));
    // 交易入口只声明“选择收款人”意图，页面不再接收当前付款钱包账户。
    expect(openedContactMode, ContactPickMode.pickForTransfer);
    Navigator.of(tester.element(find.text('通讯录测试页'))).pop();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('链上交易状态跟随交易钱包切换刷新且只统计转出', (tester) async {
    final walletA = _wallet(
      index: 1,
      name: '钱包A',
      address: 'wallet_a',
      accountId: _walletAAccountId,
    );
    final walletB = _wallet(
      index: 2,
      name: '钱包B',
      address: 'wallet_b',
      accountId: _walletBAccountId,
    );
    var currentWallet = walletA;
    final records = [
      _tx(
        recordKey: 'a:pending',
        ss58Address: 'wallet_a',
        accountId: _walletAAccountId,
        amountDeltaFen: '-101',
        status: LocalTxStore.statusPending,
      ),
      _tx(
        recordKey: 'a:inBlock',
        ss58Address: 'wallet_a',
        accountId: _walletAAccountId,
        amountDeltaFen: '-202',
        status: LocalTxStore.statusInBlock,
      ),
      _tx(
        recordKey: 'a:finalized',
        ss58Address: 'wallet_a',
        accountId: _walletAAccountId,
        amountDeltaFen: '-303',
        status: LocalTxStore.statusFinalized,
      ),
      _tx(
        recordKey: 'a:failed',
        ss58Address: 'wallet_a',
        accountId: _walletAAccountId,
        amountDeltaFen: '-404',
        status: LocalTxStore.statusFailed,
      ),
      _tx(
        recordKey: 'b:incoming',
        ss58Address: 'wallet_b',
        accountId: _walletBAccountId,
        amountDeltaFen: '404',
        status: LocalTxStore.statusFinalized,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: OnchainPaymentPanel(
          title: '交易',
          currentWalletLoader: () async => currentWallet,
          balanceLoader: (_) async => 100,
          localRecordsLoader: (accountId, {limit = 100}) async {
            final normalizedAccountId = LocalTxStore.requireAccountId(
              accountId,
            );
            return records
                .where((record) => record.accountId == normalizedAccountId)
                .take(limit)
                .toList();
          },
          walletPicker: () async {
            currentWallet = walletB;
            return true;
          },
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('待确认 2'));

    expect(find.text('待确认 2'), findsOneWidget);
    expect(find.textContaining('已出块'), findsNothing);
    expect(find.textContaining('已提交'), findsNothing);
    expect(find.text('已确认 1'), findsOneWidget);
    expect(find.text('失败 1'), findsOneWidget);

    await tester.tap(find.byTooltip('选择交易钱包'));
    await _pumpUntilFound(tester, find.text('待确认 0'));

    expect(find.text('待确认 0'), findsOneWidget);
    expect(find.text('已确认 0'), findsOneWidget);
    expect(find.text('失败 0'), findsOneWidget);
  });

  testWidgets('通讯录转账只预填收款地址且不改变付款钱包', (tester) async {
    final payer = _wallet(
      index: 2,
      name: '付款钱包B',
      address: 'wallet_b',
      accountId: _walletBAccountId,
    );
    const recipient = 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: OnchainPaymentPanel(
          title: '交易',
          initialToAddress: recipient,
          currentWalletLoader: () async => payer,
          balanceLoader: (_) async => 100,
          localRecordsLoader: (_, {limit = 100}) async => const [],
        ),
      ),
    );
    await _pumpUntilFound(tester, find.textContaining('钱包可用余额：100'));

    final addressField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '请输入账户',
      ),
    );
    expect(addressField.controller?.text, recipient);
    expect(find.textContaining('钱包可用余额：100'), findsOneWidget);
    expect(find.text('GMB'), findsOneWidget);
    final gmbMark = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/icons/gmb-mark.png',
      ),
    );
    expect(gmbMark.width, 18);
    expect(gmbMark.height, 18);
    expect(gmbMark.color, AppTheme.primary);
    expect(gmbMark.colorBlendMode, BlendMode.srcIn);
    expect(find.text('CNY'), findsNothing);
    expect(find.textContaining('钱包可用余额：100.00 GMB'), findsOneWidget);
  });

  testWidgets('独立链上支付下拉刷新重载数据且保留后台链状态读取', (tester) async {
    var walletLoads = 0;
    var recordLoads = 0;
    final payer = _wallet(
      index: 1,
      name: '付款钱包',
      address: 'wallet_a',
      accountId: _walletAAccountId,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: OnchainPaymentPanel(
          title: '交易',
          currentWalletLoader: () async {
            walletLoads++;
            return payer;
          },
          balanceLoader: (_) async => 100,
          localRecordsLoader: (_, {limit = 100}) async {
            recordLoads++;
            return const [];
          },
        ),
      ),
    );
    await _pumpUntilFound(tester, find.textContaining('钱包可用余额：100'));

    // 独立链上支付页只保留后台状态读取；下拉刷新组件仍就位。
    expect(find.byType(ChainProgressBanner), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('transaction-chain-status-inline')),
      findsNothing,
    );
    expect(find.text('公民链'), findsNothing);
    expect(find.textContaining('最终区块'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    final walletLoadsAfterInit = walletLoads;
    final recordLoadsAfterInit = recordLoads;
    expect(walletLoadsAfterInit, greaterThanOrEqualTo(1));
    expect(recordLoadsAfterInit, greaterThanOrEqualTo(1));

    // 下拉触发刷新：余额（currentWalletLoader）+ 本地记录（localRecordsLoader）重载。
    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    for (
      var i = 0;
      i < 40 &&
          (walletLoads <= walletLoadsAfterInit ||
              recordLoads <= recordLoadsAfterInit);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(walletLoads, greaterThan(walletLoadsAfterInit));
    expect(recordLoads, greaterThan(recordLoadsAfterInit));
  });
}
