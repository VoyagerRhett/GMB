import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/rpc/chain_event_subscription.dart';
import 'package:citizenapp/rpc/chain_rpc.dart';
import 'package:citizenapp/transaction/history/chain/wallet_transaction_history_sync.dart';

import '../support/isar_test_env.dart';

/// 自动确认**只有一条**通路：finalized 订阅推事件 → `_syncThrough` →
/// `_confirmOpenSubmits`。订阅一旦断开而不重连，自动确认就永久失效，交易卡片
/// 只能靠手动刷新（走 `_syncToLatest()`，不经订阅）才翻已确认。
///
/// 2026-08-07 iOS/Android 两端同时复现的正是这个：`onDone` 不对外发信号，
/// `_subscriptionConnected` 只在 `stop()` 里才置 false，于是断开后
/// `_ensureSubscription()` 每次从第一行早退，没有任何重连路径。
///
/// 本文件钉死断开→重连这条自愈链路。断言必须落在**真的重新订阅了**
/// （`connectCount`）上：只断言标志位翻转会漏掉「标志翻了但没人去连」的回归。
///
/// 用真实定时器而非 `fakeAsync`：`start()` 里有 Isar 真 I/O，拨假表会卡在真实
/// 事件循环上；退避改为构造注入，缩到毫秒级。
class _FakeSubscription extends ChainEventSubscription {
  _FakeSubscription();

  final StreamController<ChainEvent> _events =
      StreamController<ChainEvent>.broadcast();
  final StreamController<void> _dropped = StreamController<void>.broadcast();

  int connectCount = 0;

  /// 下一次 `connect()` 的返回值；置 false 模拟轻节点尚未就绪。
  bool connectResult = true;

  @override
  Stream<ChainEvent> get events => _events.stream;

  @override
  Stream<void> get dropped => _dropped.stream;

  @override
  Future<bool> connect() async {
    connectCount += 1;
    return connectResult;
  }

  @override
  void disconnect() {}

  /// 模拟底层 smoldot 流结束（原生 chain 被释放）。
  void emitDrop() => _dropped.add(null);

  Future<void> close() async {
    await _events.close();
    await _dropped.close();
  }
}

/// 离线 RPC：`start()` 里的 metadata 预热是 `unawaited` 的，真 [ChainRpc] 会去
/// 拉起 smoldot，单测必须注入立即失败的 fake，否则用例随机 flaky。
class _OfflineChainRpc implements ChainRpc {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

/// 第一笔 finalized 读取由测试精确控制，后续代次保持离线。
///
/// 这样可以稳定制造“旧 start 卡在外部 RPC，stop 后新代次或 Wallet 擦除先完成”的
/// 逆序，而不依赖计时器或真实轻节点时序。
class _ControlledFinalizedChainRpc implements ChainRpc {
  final Completer<({Uint8List blockHash, int blockNumber})> firstFinalized =
      Completer<({Uint8List blockHash, int blockNumber})>();

  int finalizedReadCount = 0;

  @override
  Future<({Uint8List blockHash, int blockNumber})> fetchFinalizedBlock() {
    finalizedReadCount += 1;
    if (finalizedReadCount == 1) return firstFinalized.future;
    return Future<({Uint8List blockHash, int blockNumber})>.error(
      StateError('new generation offline'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

void main() {
  useIsolatedIsar();

  const retryDelay = Duration(milliseconds: 20);
  // 退避到点后还要跑 connect 的微任务，等三倍留足余量。
  const pastRetry = Duration(milliseconds: 60);

  // `start()` 不等订阅连上就返回（连接走 fire-and-forget，是刻意的非阻塞启动），
  // 断言前必须先让那条 future 落定，否则读到的还是初始的未连接态。
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<void> waitUntil(bool Function() predicate) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('等待受控异步阶段超时');
  }

  late _FakeSubscription subscription;
  late ChainTxMonitor monitor;

  setUp(() {
    subscription = _FakeSubscription();
    monitor = ChainTxMonitor.forTesting(
      subscription: subscription,
      chainRpc: _OfflineChainRpc(),
      subscriptionRetryDelay: retryDelay,
    );
  });

  tearDown(() async {
    await monitor.stop();
    await subscription.close();
  });

  test('订阅断开后按退避重连，并真的重新建立订阅', () async {
    await monitor.start();
    await settle();
    expect(subscription.connectCount, 1, reason: '启动时应连接一次');
    expect(monitor.subscriptionConnectedForTesting, isTrue);

    subscription.emitDrop();
    await Future<void>.delayed(Duration.zero);

    expect(monitor.subscriptionConnectedForTesting, isFalse,
        reason: '断开后必须立刻落回未连接，否则 _ensureSubscription 会一直早退');
    expect(subscription.connectCount, 1, reason: '不得立即重连（会退化成热循环）');

    await Future<void>.delayed(pastRetry);
    expect(subscription.connectCount, 2, reason: '退避到点后必须真的重新 connect');
    expect(monitor.subscriptionConnectedForTesting, isTrue);
  });

  test('两条子订阅先后结束只触发一次重连', () async {
    await monitor.start();
    await settle();
    expect(subscription.connectCount, 1);

    subscription.emitDrop();
    subscription.emitDrop();
    await Future<void>.delayed(pastRetry);

    expect(subscription.connectCount, 2, reason: '第二次断开信号必须被忽略');
  });

  test('重连失败后继续退避重试，不放弃', () async {
    await monitor.start();
    await settle();
    expect(subscription.connectCount, 1);

    subscription.connectResult = false;
    subscription.emitDrop();
    await Future<void>.delayed(pastRetry);

    // 退避窗口内可能已重试多次，只断言"至少重连过"，不钉死次数（会随退避抖动飘）。
    final afterFirstRetries = subscription.connectCount;
    expect(afterFirstRetries, greaterThanOrEqualTo(2));
    expect(monitor.subscriptionConnectedForTesting, isFalse);

    await Future<void>.delayed(pastRetry);
    expect(subscription.connectCount, greaterThan(afterFirstRetries),
        reason: '连接失败必须继续退避重试，不能停在第一次失败');

    subscription.connectResult = true;
    await Future<void>.delayed(pastRetry);
    expect(monitor.subscriptionConnectedForTesting, isTrue,
        reason: '轻节点恢复后必须自动连回来');
  });

  test('stop() 之后的断开信号不得唤醒重连', () async {
    await monitor.start();
    await settle();
    expect(subscription.connectCount, 1);

    await monitor.stop();
    subscription.emitDrop();
    await Future<void>.delayed(pastRetry);

    expect(subscription.connectCount, 1, reason: '已停止的监控器不得再连接');
  });

  test('stop 后旧 finalized RPC 晚到不得在 Wallet 复位后重开数据库', () async {
    final controlledRpc = _ControlledFinalizedChainRpc();
    monitor = ChainTxMonitor.forTesting(
      subscription: subscription,
      chainRpc: controlledRpc,
      subscriptionRetryDelay: retryDelay,
    );
    final accountId = '0x${List<String>.filled(32, '11').join()}';
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: 'test-ss58',
    });

    await monitor.start();
    await waitUntil(() => controlledRpc.finalizedReadCount == 1);

    // stop 先同步废止旧 owner，但故意不等 drain；随后模拟 AppLock 的 Wallet 复位。
    final oldDrain = monitor.stop();
    await WalletIsar.instance.resetForTest();
    expect(Isar.getInstance('citizenapp_wallet'), isNull);

    controlledRpc.firstFinalized.complete((
      blockHash: Uint8List(32),
      blockNumber: 17,
    ));
    await oldDrain.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);

    expect(Isar.getInstance('citizenapp_wallet'), isNull,
        reason: '旧代次 RPC 晚到后不得进入游标查询并重开 Wallet 数据库');
    expect(WalletIsar.instance.hasActiveOperation, isFalse);
  });

  test('旧同步卡住时替换为空集合，放行后零游标晚写', () async {
    final controlledRpc = _ControlledFinalizedChainRpc();
    monitor = ChainTxMonitor.forTesting(
      subscription: subscription,
      chainRpc: controlledRpc,
      subscriptionRetryDelay: retryDelay,
    );
    final accountId = '0x${List<String>.filled(32, '33').join()}';
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: 'test-ss58',
    });
    await monitor.start();
    await waitUntil(() => controlledRpc.finalizedReadCount == 1);

    await monitor.replaceWatchedAccounts(const <String, String>{}).timeout(
        const Duration(seconds: 2));
    controlledRpc.firstFinalized.complete((
      blockHash: Uint8List(32),
      blockNumber: 31,
    ));
    await Future<void>.delayed(Duration.zero);

    final cursors = await WalletIsar.instance.read(
      (isar) => isar.walletTxSyncCursorEntitys.where().findAll(),
    );
    expect(cursors, isEmpty);
    expect(monitor.watchedAccountsForTesting, isEmpty);
  });

  test('旧 finalized RPC 晚完成不得清掉 stop 后启动的新代次', () async {
    final controlledRpc = _ControlledFinalizedChainRpc();
    monitor = ChainTxMonitor.forTesting(
      subscription: subscription,
      chainRpc: controlledRpc,
      subscriptionRetryDelay: retryDelay,
    );
    final accountId = '0x${List<String>.filled(32, '22').join()}';
    await monitor.replaceWatchedAccounts(<String, String>{
      accountId: 'test-ss58',
    });

    await monitor.start();
    await waitUntil(() => controlledRpc.finalizedReadCount == 1);
    expect(subscription.connectCount, 1);

    final oldDrain = monitor.stop();
    await monitor.start();
    await settle();
    expect(subscription.connectCount, 2);
    expect(monitor.subscriptionConnectedForTesting, isTrue);

    // 旧 RPC 和旧 drain 都在新代次之后完成；它们只能清旧 owner 自己的字段。
    controlledRpc.firstFinalized.complete((
      blockHash: Uint8List(32),
      blockNumber: 23,
    ));
    await oldDrain.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);

    expect(monitor.subscriptionConnectedForTesting, isTrue,
        reason: '旧代次 finally/drain 不得覆盖新代次连接态');
    expect(subscription.connectCount, 2, reason: '旧代次结束不得额外重连或断开后唤醒重连');
  });
}
