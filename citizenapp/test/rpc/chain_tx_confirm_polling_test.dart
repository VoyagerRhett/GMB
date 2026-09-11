import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/rpc/chain_event_subscription.dart';
import 'package:citizenapp/rpc/chain_rpc.dart';
import 'package:citizenapp/transaction/history/chain/wallet_transaction_history_sync.dart';
import 'package:citizenapp/transaction/history/data/local_tx_store.dart';

import '../support/isar_test_env.dart';

/// 交易记录「待确认 → 已确认」必须**不依赖出块**。
///
/// 本链空块不出块：一笔交易只有它自己那个块这一次 finalized 事件，也就是只有
/// 一次确认机会。这一次里任何一步慢了或失败了（轻节点还没把该块应用完、账户
/// nonce 快照还是旧值、事件被 `_syncInflight` 合并丢掉），就再也没有第二次，
/// 记录永久停在待确认，只能手动刷新——2026-08-07 真机复现的正是这个。
///
/// 连发多笔时后一笔的块给前一笔当了重试机会，所以联测看起来是好的；单发一笔必卡。
/// 因此断言必须是：**没有任何区块事件，确认也要被反复重试**。
class _SilentSubscription extends ChainEventSubscription {
  final StreamController<ChainEvent> _events =
      StreamController<ChainEvent>.broadcast();
  final StreamController<void> _dropped = StreamController<void>.broadcast();

  @override
  Stream<ChainEvent> get events => _events.stream;

  @override
  Stream<void> get dropped => _dropped.stream;

  /// 订阅永远连不上：坐实"确认不靠订阅、不靠出块"。
  @override
  Future<bool> connect() async => false;

  @override
  void disconnect() {}

  Future<void> close() async {
    await _events.close();
    await _dropped.close();
  }
}

/// 数确认尝试次数。`_confirmOpenSubmits()` 第一行就读 finalized 头，
/// 因此这个计数即"确认被尝试了几次"。
class _CountingChainRpc implements ChainRpc {
  int finalizedReads = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchFinalizedBlock) {
      finalizedReads += 1;
    }
    return Future<Never>.error(StateError('offline'));
  }
}

void main() {
  useIsolatedIsar();

  const accountId =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const ss58Address = 'from-wallet';
  const pollInterval = Duration(milliseconds: 20);

  late _SilentSubscription subscription;
  late _CountingChainRpc rpc;
  late ChainTxMonitor monitor;

  setUp(() {
    subscription = _SilentSubscription();
    rpc = _CountingChainRpc();
    monitor = ChainTxMonitor.forTesting(
      subscription: subscription,
      chainRpc: rpc,
      confirmPollInterval: pollInterval,
    );
  });

  tearDown(() async {
    monitor.stop();
    await subscription.close();
  });

  Future<void> seedPendingTransfer() {
    return LocalTxStore.upsertLocalSubmitTransfer(
      ss58Address: ss58Address,
      accountId: accountId,
      txHash: '0xfeed',
      amountDeltaFen: '-101',
      transferAmountFen: '100',
      feeFen: '1',
      counterpartySs58Address: 'to-wallet',
      fromSs58Address: ss58Address,
      toSs58Address: 'to-wallet',
      usedNonce: 1,
      createdAtMillis: 1,
    );
  }

  test('有待确认记录时，没有任何区块事件也会反复重试确认', () async {
    await seedPendingTransfer();
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: ss58Address,
    });
    await monitor.start();

    // 全程不发任何 ChainEvent，订阅也永远连不上。
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(rpc.finalizedReads, greaterThanOrEqualTo(5),
        reason: '确认必须由轮询驱动；只靠出块事件的话这里会停在个位数甚至 1 次');
  });

  test('确认尝试持续推进，不会跑一次就停', () async {
    await seedPendingTransfer();
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: ss58Address,
    });
    await monitor.start();

    await Future<void>.delayed(const Duration(milliseconds: 120));
    final firstWindow = rpc.finalizedReads;

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(rpc.finalizedReads, greaterThan(firstWindow),
        reason: '第二个窗口必须继续有新的确认尝试');
  });

  test('没有待确认记录时不打链，空闲零开销', () async {
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: ss58Address,
    });
    await monitor.start();

    await Future<void>.delayed(const Duration(milliseconds: 220));

    // start() 自身的 _syncToLatest 会读一次 finalized；轮询不得在此之上继续打链。
    expect(rpc.finalizedReads, lessThanOrEqualTo(2),
        reason: '空闲期每 3 秒白读一次 finalized 是不可接受的');
  });

  test('stop() 之后不再重试', () async {
    await seedPendingTransfer();
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: ss58Address,
    });
    await monitor.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    monitor.stop();
    final afterStop = rpc.finalizedReads;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(rpc.finalizedReads, afterStop, reason: '已停止的监控器不得继续打链');
  });
}
