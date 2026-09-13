import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';

LocalTxEntity _record({
  String status = LocalTxStore.statusFinalized,
}) {
  return LocalTxEntity()
    ..recordKey = 'pub:0xblock:1'
    ..ss58Address = 'wallet_addr'
    ..accountId = 'pub'
    ..type = 'transfer'
    ..amountDeltaFen = '120'
    ..transferAmountFen = '120'
    ..counterpartySs58Address = 'from_addr'
    ..fromSs58Address = 'from_addr'
    ..toSs58Address = 'wallet_addr'
    ..status = status
    ..source = 'chain_event'
    ..blockNumber = 10
    ..blockHash = '0xblock'
    ..eventIndex = 1
    ..createdAtMillis = DateTime(2026, 5, 20, 12).millisecondsSinceEpoch
    ..confirmedAtMillis = status == LocalTxStore.statusFinalized
        ? DateTime(2026, 5, 20, 12, 1).millisecondsSinceEpoch
        : null;
}

void main() {
  testWidgets('交易记录条目显示 finalized 状态标签', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTxRecordTile(record: _record()),
        ),
      ),
    );

    expect(find.text('转账'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('+1.20'), findsOneWidget);
  });

  testWidgets('钱包详情最近记录可显示进入详情箭头', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTxRecordTile(
            record: _record(),
            showChevron: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('点击交易记录条目进入交易详情页', (tester) async {
    final record = _record(status: LocalTxStore.statusInBlock);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => LocalTxRecordTile(
              record: record,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LocalTxRecordDetailPage(record: record),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    expect(find.text('交易详情'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('已出块'), findsNothing);
    expect(find.text('区块号'), findsOneWidget);
  });
}
