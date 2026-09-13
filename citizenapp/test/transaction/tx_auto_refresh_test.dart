import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';

import '../support/isar_test_env.dart';

// 响应式刷新的核心机制:`LocalTxStore.listenAccountChanges` 在该账户记录被写库
// 时发出事件。UI 侧 [TxAutoRefreshMixin] 订阅它并去抖重刷。
//
// 说明:mixin→页面「自动翻已确认」的整链路无法在 flutter_test 里稳定断言 ——
// Isar 原生 watcher 的通知走真实事件循环,而 widget 的 initState 订阅在 fake-async
// 区,两个 zone 对不上(store 级测试把 listen/写/断言全放进同一个 runAsync 才通)。
// 该整链路由装机端到端验收(发一笔,盯其从待确认自动翻已确认)。
void main() {
  useIsolatedIsar();

  tearDown(() {
    LocalTxAccountChangeSubscription.debugCancelSubscription = null;
  });

  const fromAccountId =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fromSs58Address = 'from-wallet';
  const toSs58Address = 'to-wallet';

  testWidgets('listenAccountChanges 在记录 pending→finalized 写库时发出事件',
      (tester) async {
    await tester.runAsync(() async {
      await LocalTxStore.upsertLocalSubmitTransfer(
        ss58Address: fromSs58Address,
        accountId: fromAccountId,
        txHash: '0xfeed',
        amountDeltaFen: '-101',
        transferAmountFen: '100',
        feeFen: '1',
        counterpartySs58Address: toSs58Address,
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        executionId: 'execution-refresh',
        callDataHash: '0x${'11' * 32}',
        usedNonce: 1,
        createdAtMillis: 1,
      );

      final seen = <void>[];
      final sub = LocalTxStore.listenAccountChanges(
        fromAccountId,
        () => seen.add(null),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150)); // 订阅生效

      // 模拟 SDK history 把记录投影为 finalized。
      await LocalTxStore.markLocalSubmitFinalized(
        accountId: fromAccountId,
        txHash: '0xfeed',
        executionId: 'execution-refresh',
        callDataHash: '0x${'11' * 32}',
        blockHash: '0x22',
        blockNumber: 9,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200)); // 通知送达

      expect(seen, isNotEmpty, reason: 'finalized 写库应触发 watch 事件驱动 UI 重刷');
      await sub.cancel();
    });
  }, timeout: const Timeout(Duration(seconds: 40)));

  testWidgets('WalletIsar 擦除会等待已登记 watcher 真实取消', (tester) async {
    await tester.runAsync(() async {
      final sub = LocalTxStore.listenAccountChanges(fromAccountId, () {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await WalletIsar.instance.closeAndDeleteFromDisk();

      // close 已取得同一个 single-flight 取消任务，调用方随后重复取消仍应幂等完成。
      await sub.cancel();
      expect(
        () => WalletIsar.instance.db(),
        throwsA(isA<StateError>()),
      );
    });
  }, timeout: const Timeout(Duration(seconds: 40)));

  testWidgets('关闭命中 watcher 启动窗口时不会晚到挂回数据库', (tester) async {
    await tester.runAsync(() async {
      final sub = LocalTxStore.listenAccountChanges(fromAccountId, () {});

      // 不等待 db() 和原生 subscription 建立，直接同步发出关闭意图。
      await WalletIsar.instance.closeAndDeleteFromDisk();
      await sub.cancel();

      expect(
        WalletIsar.instance.db,
        throwsA(isA<StateError>()),
      );
    });
  }, timeout: const Timeout(Duration(seconds: 40)));

  testWidgets('Widget dispose 后全局擦除会确定性等待 fake-async watcher', (tester) async {
    await tester.pumpWidget(const _TxWatcherHost(accountId: fromAccountId));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    for (var attempt = 0;
        attempt < 20 && WalletIsar.instance.hasActiveOperation;
        attempt++) {
      // 原生 Future 先在真实事件循环前进，再回 widget fake-async Zone 收尾；打开、
      // 查询是两个异步阶段，不能用一次固定延迟假定都已经完成。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(WalletIsar.instance.hasActiveOperation, isFalse);
    await tester.runAsync(WalletIsar.instance.closeAndDeleteFromDisk);
  }, timeout: const Timeout(Duration(seconds: 40)));

  testWidgets('外部消费者取消失败会使擦除可见失败并允许重试', (tester) async {
    await tester.runAsync(() async {
      var shouldFail = true;
      late WalletIsarConsumerLease lease;
      lease = WalletIsar.instance.registerExternalConsumer(() async {
        if (shouldFail) {
          throw StateError('模拟 watcher 取消失败');
        }
        lease.release();
      });

      await expectLater(
        WalletIsar.instance.closeAndDeleteFromDisk(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('取消 Wallet 外部消费者失败'),
          ),
        ),
      );
      expect(WalletIsar.instance.db, throwsA(isA<StateError>()));

      shouldFail = false;
      await WalletIsar.instance.closeAndDeleteFromDisk();
    });
  }, timeout: const Timeout(Duration(seconds: 40)));

  testWidgets('原生 watcher 取消失败由调用方观察且 root Zone 不泄漏', (tester) async {
    await tester.runAsync(() async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final sub = LocalTxStore.listenAccountChanges(fromAccountId, () {});
        await Future<void>.delayed(const Duration(milliseconds: 100));

        var shouldFail = true;
        LocalTxAccountChangeSubscription.debugCancelSubscription =
            (subscription) async {
          if (shouldFail) throw StateError('模拟原生 watcher 取消失败');
          await subscription.cancel();
        };

        await expectLater(
          sub.cancel(),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('模拟原生 watcher 取消失败'),
            ),
          ),
        );

        // 失败保留 lease/subscription；同一句柄可在原生边界恢复后重试并真实释放。
        shouldFail = false;
        await sub.cancel();
        await WalletIsar.instance.closeAndDeleteFromDisk();
      }, (error, _) {
        uncaught.add(error);
      });
      expect(uncaught, isEmpty);
    });
  }, timeout: const Timeout(Duration(seconds: 40)));
}

class _TxWatcherHost extends StatefulWidget {
  const _TxWatcherHost({required this.accountId});

  final String accountId;

  @override
  State<_TxWatcherHost> createState() => _TxWatcherHostState();
}

class _TxWatcherHostState extends State<_TxWatcherHost>
    with TxAutoRefreshMixin<_TxWatcherHost> {
  @override
  void initState() {
    super.initState();
    unawaited(LocalTxStore.queryRecentByAccountId(widget.accountId));
    startTxAutoRefresh(widget.accountId);
  }

  @override
  Future<void> onTxRecordsChanged() async {}

  @override
  void dispose() {
    unawaited(stopTxAutoRefresh().catchError((Object _, StackTrace __) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
