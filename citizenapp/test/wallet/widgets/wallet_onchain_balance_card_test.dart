import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';

import '../../support/isar_test_env.dart';

import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/wallet/widgets/wallet_onchain_balance_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();
  test('恢复磁盘后各页面同步取同一状态，缺失账户失败不遮掉已有金额', () async {
    final initial = AccountBalanceSnapshotStore.forChain(_BalanceChain());
    await initial.getAccountBalance(_balanceAccount);
    final chain = _BalanceChain()..gate = Completer<void>();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final other = '0x${'bc' * 32}';
    await store.restore([_balanceAccount, other]);
    final state = store.accountState(_balanceAccount);
    expect(identical(state, store.accountState(_balanceAccount)), isTrue);
    expect(state.value, isNotNull);
    expect(chain.calls, 0);
    expect(store.accountState(other).value, isNull);
    final query = store.getAccountBalances([_balanceAccount, other]);
    final failed = expectLater(query, throwsStateError);
    await chain.started.future;
    expect(state.value!.freeFen, BigInt.parse('90071992547409931234'));
    chain.fail = true;
    chain.gate!.complete();
    await failed;
    expect(state.value, isNotNull);
    expect(store.accountState(other).hasError, isTrue);
    expect(AccountBalanceSnapshotStore.formatFen(state.value!.freeFen),
      '900,719,925,474,099,312.34');
  });

  test('显示状态合并刷新，失败保留旧值，已确认删除排空并清掉内存', () async {
    final chain = _BalanceChain();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final state = store.accountState(_balanceAccount);
    await state.load();
    final first = state.value;
    chain..gate = Completer<void>()..fail = true;
    final refresh = state.load(forceRefresh: true);
    expect(identical(refresh, state.load(forceRefresh: true)), isTrue);
    expect(state.value, first);
    chain.gate!.complete();
    await refresh;
    expect(state.hasError, isTrue);
    expect(state.value, first);
    await store.forget([_balanceAccount]);
    expect(state.value, isNull);
    expect(state.hasError, isFalse);
    expect(chain.calls, 2);
  });
  test('跨页面和新SDK实例读取同一持久快照，展示没有TTL', () async {
    final chain = _BalanceChain();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final first = await store.getAccountBalance(_balanceAccount);
    final again = await store.getAccountBalances([
      _balanceAccount,
      _balanceAccount,
    ]);
    expect(chain.calls, 1);
    expect(again.map((value) => value.totalFen), [
      first.totalFen,
      first.totalFen,
    ]);
    final nextChain = _BalanceChain();
    final restored = await AccountBalanceSnapshotStore.forChain(nextChain)
        .getAccountBalance(_balanceAccount);
    expect(nextChain.calls, 0);
    expect(restored.freeFen, BigInt.parse('90071992547409931234'));
    expect(restored.totalFen, restored.freeFen + restored.reservedFen);
  });

  test('主动刷新合并在途请求，成功后通知订阅者一次', () async {
    final chain = _BalanceChain()..gate = Completer<void>();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final notifications = <String>[];
    final subscription = store.changes.listen(notifications.add);
    final first = store.getAccountBalance(_balanceAccount, forceRefresh: true);
    final second = store.getAccountBalance(_balanceAccount, forceRefresh: true);
    await chain.started.future;
    expect(chain.calls, 1);
    chain.gate!.complete();
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, [_balanceAccount]);
    await subscription.cancel();
  });

  test('刷新失败保留持久成功余额，另一账户不能读到该余额', () async {
    final chain = _BalanceChain();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final first = await store.getAccountBalance(_balanceAccount);
    chain.fail = true;
    await expectLater(
      store.getAccountBalance(_balanceAccount, forceRefresh: true),
      throwsStateError,
    );
    expect((await store.read(_balanceAccount))!.totalFen, first.totalFen);
    expect(await store.read('0x${'bc' * 32}'), isNull);
    expect(
      (await store.getAccountBalance(_balanceAccount)).totalFen,
      first.totalFen,
    );
    expect(chain.calls, 2);
  });

  test('展示读取不等待在途刷新；最终确认只刷新落后快照', () async {
    final chain = _BalanceChain();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final first = await store.getAccountBalance(_balanceAccount);
    chain.gate = Completer<void>();
    chain.height = 2;
    final refresh = store.getAccountBalance(
      _balanceAccount,
      forceRefresh: true,
    );
    final displayed = await store.getAccountBalance(_balanceAccount);
    expect(displayed.block.number, first.block.number);
    chain.gate!.complete();
    await refresh;
    final confirmed = (await store.read(_balanceAccount))!.block;
    await store.afterFinalized(confirmed, [_balanceAccount, _balanceAccount]);
    expect(chain.calls, 2);
    chain.height = 3;
    await store.afterFinalized(
      CitizenBlockRef(
        hash: '0x${'11' * 32}',
        number: BigInt.from(3),
        finality: CitizenBlockFinality.finalized,
      ),
      [_balanceAccount],
    );
    expect(chain.calls, 3);
    expect((await store.read(_balanceAccount))!.block.number, BigInt.from(3));
  });

  test('未最终确认或总数不一致的余额不进入持久快照', () async {
    final chain = _BalanceChain()..invalidTotal = true;
    final store = AccountBalanceSnapshotStore.forChain(chain);
    await expectLater(
      store.getAccountBalance(_balanceAccount),
      throwsStateError,
    );
    expect(await store.read(_balanceAccount), isNull);
    chain
      ..invalidTotal = false
      ..finality = CitizenBlockFinality.best;
    await expectLater(
      store.getAccountBalance(_balanceAccount),
      throwsStateError,
    );
    expect(await store.read(_balanceAccount), isNull);
  });

  test('旧块不能覆盖新块，同高度不同证明和错误账户被拒绝', () async {
    final chain = _BalanceChain()..height = 20;
    final store = AccountBalanceSnapshotStore.forChain(chain);
    await store.getAccountBalance(_balanceAccount);
    chain.height = 19;
    expect(
      (await store.getAccountBalance(
        _balanceAccount,
        forceRefresh: true,
      )).block.number,
      BigInt.from(20),
    );
    chain
      ..height = 20
      ..hashByte = '22';
    await expectLater(
      store.getAccountBalance(_balanceAccount, forceRefresh: true),
      throwsStateError,
    );
    chain
      ..hashByte = '11'
      ..wrongAccount = true;
    await expectLater(
      store.getAccountBalance(_balanceAccount, forceRefresh: true),
      throwsStateError,
    );
    expect((await store.read(_balanceAccount))!.block.number, BigInt.from(20));
  });

  test('批量缺失一次读取且保留重复顺序，非法账户和明文端点先拒绝', () async {
    final chain = _BalanceChain();
    final store = AccountBalanceSnapshotStore.forChain(chain);
    final other = '0x${'bc' * 32}';
    final values = await store.getAccountBalances([
      other,
      _balanceAccount,
      other,
    ]);
    expect(values.map((value) => value.accountId), [
      other,
      _balanceAccount,
      other,
    ]);
    expect(chain.batchCalls, 1);
    await expectLater(
      store.getAccountBalance('not-an-account'),
      throwsFormatException,
    );
    await expectLater(
      store.getClearingBalance(
        accountId: _balanceAccount,
        ss58Address: 'synthetic',
        wssUrl: 'ws://example.invalid',
      ),
      throwsFormatException,
    );
  });

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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: WalletOnchainBalanceCard(
              wallet: wallet,
              balanceLoader: (_) => pending.future,
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('wallet-onchain-balance-section')))
          .height,
      123,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(await loadBalance(wallet.accountId));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次失败点击重试；total含reserved；之后失败保留原金额', (tester) async {
    final key = GlobalKey<WalletOnchainBalanceCardState>();
    var failRead = true;
    final base = await loadBalance(wallet.accountId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletOnchainBalanceCard(
            key: key,
            wallet: wallet,
            balanceLoader: (_) async {
              if (failRead) throw StateError('合成余额失败');
              return CitizenAccountBalance(
                accountId: base.accountId,
                block: base.block,
                freeFen: BigInt.from(100),
                reservedFen: BigInt.from(250),
                totalFen: BigInt.from(350),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查询失败，点击刷新'), findsOneWidget);
    failRead = false;
    await tester.tap(find.text('查询失败，点击刷新'));
    await tester.pumpAndSettle();
    expect(find.text('3.50'), findsOneWidget);
    expect(find.text('1.00'), findsNothing);
    expect(find.text('元'), findsOneWidget);
    failRead = true;
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
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

  testWidgets('切换账户后迟到的旧请求不能覆盖新账户余额', (tester) async {
    final first = Completer<CitizenAccountBalance>();
    final other = CitizenWalletStateAccount(
      signMode: wallet.signMode,
      walletIndex: wallet.walletIndex,
      accountIndex: 1,
      accountId: '0x${'bc' * 32}',
      ss58Address: wallet.ss58Address,
      name: '另一个测试账户',
      createdAtMillis: BigInt.zero,
      isDefault: false,
    );
    final key = GlobalKey<WalletOnchainBalanceCardState>();
    Future<CitizenAccountBalance> loader(String id) =>
        id == wallet.accountId ? first.future : loadBalance(id);
    Widget page(CitizenWalletStateAccount value) => MaterialApp(
      home: Scaffold(
        body: WalletOnchainBalanceCard(
          key: key,
          wallet: value,
          balanceLoader: loader,
        ),
      ),
    );
    await tester.pumpWidget(page(wallet));
    await tester.pumpWidget(page(other));
    await tester.pumpAndSettle();
    expect(find.text('1.00'), findsOneWidget);
    first.completeError(StateError('旧账户读取失败'));
    await tester.pumpAndSettle();
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('查询失败，点击刷新'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// 合成账户与余额仅用于验证隔离、精度和并发，不使用真机钱包数据。
final _balanceAccount = '0x${'ab' * 32}';

class _BalanceChain implements CitizenChain {
  int calls = 0;
  int batchCalls = 0;
  int height = 1;
  String hashByte = '11';
  bool fail = false;
  bool wrongAccount = false;
  bool invalidTotal = false;
  CitizenBlockFinality finality = CitizenBlockFinality.finalized;
  Completer<void>? gate;
  final started = Completer<void>();

  Future<void> _enter() async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (gate != null) await gate!.future;
    if (fail) throw StateError('合成读取失败');
  }

  CitizenAccountBalance _value(String accountId) => CitizenAccountBalance(
    accountId: wrongAccount ? '0x${'cd' * 32}' : accountId,
    block: CitizenBlockRef(
      hash: '0x${hashByte * 32}',
      number: BigInt.from(height),
      finality: finality,
    ),
    freeFen: BigInt.parse('90071992547409931234'),
    reservedFen: BigInt.from(250),
    totalFen: invalidTotal ? BigInt.zero : BigInt.parse('90071992547409931484'),
  );

  @override
  Future<CitizenAccountBalance> getAccountBalance(String accountId) async {
    await _enter();
    return _value(accountId);
  }

  @override
  Future<List<CitizenAccountBalance>> getAccountBalances(
    List<String> accountIds,
  ) async {
    batchCalls++;
    await _enter();
    return accountIds.map(_value).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
