import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/wallet/core/default_account_service.dart';
import 'package:citizenapp/wallet/core/hardware_bound_seed_vault.dart';
import 'package:citizenapp/wallet/core/sign_mode.dart';
import 'package:citizenapp/wallet/core/wallet_manager.dart';
import 'package:citizenapp/wallet/pages/account_detail_page.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';
import 'package:citizenapp/wallet/widgets/add_account_sheet.dart';
import 'package:citizenapp/transaction/history/chain/wallet_transaction_history_sync.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/shimmer_loading.dart';

import '../../support/fake_secure_seed_store.dart';
import '../../support/isar_test_env.dart';

class _MemoryBlobStore implements VaultBlobStore {
  final Map<String, String> values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

Account _makeAccount({
  int index = 1,
  String name = '账户1',
  String ss58 = 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT',
}) {
  return Account(
    masterId:
        '0x0000000000000000000000000000000000000000000000000000000000000001',
    accountIndex: index,
    accountId: '0x${index.toRadixString(16).padLeft(64, '0')}',
    ss58Address: ss58,
    accountName: name,
  );
}

WalletProfile _makeColdWallet({
  int walletIndex = 2,
  String name = '冷钱包',
  double balance = 0,
}) {
  final accountId = '0x${walletIndex.toRadixString(16).padLeft(64, '0')}';
  return WalletProfile(
    walletIndex: walletIndex,
    walletName: name,
    walletIcon: 'wallet',
    balance: balance,
    ss58Address: ss58FromAccountIdText(accountId),
    accountId: accountId,
    alg: 'sr25519',
    ss58: 2027,
    createdAtMillis: 0,
    source: 'test',
    signMode: SignMode.cold,
  );
}

const _hotAccountId =
    '0x0000000000000000000000000000000000000000000000000000000000000001';

WalletProfile _makeHotWallet({String name = '热钱包'}) {
  return WalletProfile(
    walletIndex: 1,
    walletName: name,
    walletIcon: 'wallet',
    balance: 0,
    ss58Address: ss58FromAccountIdText(_hotAccountId),
    accountId: _hotAccountId,
    alg: 'sr25519',
    ss58: 2027,
    createdAtMillis: 0,
    source: 'test',
    signMode: SignMode.hot,
  );
}

WalletPageSnapshot _hotWalletSnapshot() {
  final wallet = _makeHotWallet();
  final account = Account(
    masterId: _hotAccountId,
    accountIndex: 0,
    accountId: _hotAccountId,
    ss58Address: wallet.ss58Address,
    accountName: '账户0',
  );
  return WalletPageSnapshot(
    wallets: <WalletProfile>[wallet],
    accounts: <Account>[account],
    defaultAccounts: <DefaultAccount>[
      DefaultAccount(
        accountId: account.accountId,
        ss58Address: account.ss58Address,
        accountName: account.accountName,
        signMode: SignMode.hot,
        walletIndex: wallet.walletIndex,
        masterId: account.masterId,
        accountIndex: account.accountIndex,
      ),
    ],
    walletsRevision: 1,
    usableHotWalletAccountId: wallet.accountId,
  );
}

WalletPageSnapshot _hotWalletWithSecondAccountSnapshot() {
  final wallet = _makeHotWallet();
  final anchor = Account(
    masterId: _hotAccountId,
    accountIndex: 0,
    accountId: _hotAccountId,
    ss58Address: wallet.ss58Address,
    accountName: '账户0',
  );
  const secondAccountId =
      '0x0000000000000000000000000000000000000000000000000000000000000002';
  final second = Account(
    masterId: _hotAccountId,
    accountIndex: 1,
    accountId: secondAccountId,
    ss58Address: ss58FromAccountIdText(secondAccountId),
    accountName: '账户1',
  );
  return WalletPageSnapshot(
    wallets: <WalletProfile>[wallet],
    accounts: <Account>[anchor, second],
    defaultAccounts: <DefaultAccount>[
      for (final account in <Account>[anchor, second])
        DefaultAccount(
          accountId: account.accountId,
          ss58Address: account.ss58Address,
          accountName: account.accountName,
          signMode: SignMode.hot,
          walletIndex: wallet.walletIndex,
          masterId: account.masterId,
          accountIndex: account.accountIndex,
        ),
    ],
    walletsRevision: 1,
    usableHotWalletAccountId: wallet.accountId,
  );
}

WalletPageSnapshot _coldWalletsSnapshot(List<WalletProfile> wallets) {
  return WalletPageSnapshot(
    wallets: wallets,
    accounts: const <Account>[],
    defaultAccounts: <DefaultAccount>[
      for (final wallet in wallets)
        DefaultAccount(
          accountId: wallet.accountId,
          ss58Address: wallet.ss58Address,
          accountName: wallet.walletName,
          signMode: SignMode.cold,
          walletIndex: wallet.walletIndex,
        ),
    ],
    walletsRevision: 1,
    usableHotWalletAccountId: null,
  );
}

WalletDeletionResult _testDeletionResult({
  required int? walletIndex,
  required Set<String> accountIds,
  required bool deleteAccountKeys,
  required bool deleteWalletWideKeys,
}) {
  return WalletDeletionResult(
    factCommitted: true,
    cleanupPlans: <WalletCleanupPlan>[
      WalletCleanupPlan(
        planId: 'test-plan-${accountIds.join('-')}',
        walletIndex: walletIndex,
        accountIds: accountIds,
        deleteAccountKeys: deleteAccountKeys,
        deleteWalletWideKeys: deleteWalletWideKeys,
      ),
    ],
  );
}

WalletPageSnapshot _coldWalletSnapshot({
  String name = '测试冷钱包',
  double balance = 0,
}) {
  final wallet = _makeColdWallet(name: name, balance: balance);
  return _coldWalletsSnapshot(<WalletProfile>[wallet]);
}

Widget _walletTabHost(
  Future<WalletPageSnapshot> Function() snapshotLoader, {
  Future<Map<String, double>> Function(List<String> accountIds)?
      finalizedBalancesLoader,
  Future<void> Function(int walletIndex, double balance)? balanceWriter,
  ValueChanged<bool>? onBalanceRefreshingChanged,
  Future<void> Function(
    List<DefaultAccount> before,
    List<DefaultAccount> target,
  )? defaultAccountReorderCommitter,
  Future<void> Function(int walletIndex)? deleteWalletAction,
  Future<void> Function(String accountId)? deleteAccountAction,
  Future<void> Function({
    required int walletIndex,
    required String accountId,
  })? signAndDeleteWalletAction,
  Future<void> Function(String accountId)? clearingBankClearer,
  Future<List<WalletCleanupPlan>> Function()? pendingWalletCleanupPlansLoader,
  Future<void> Function(WalletCleanupPlan plan)? walletCleanupPlanRetrier,
  Future<void> Function(String planId)? walletCleanupPlanAcknowledger,
}) {
  Future<WalletDeletionResult> runDeleteWallet(
    int walletIndex,
    String expectedAccountId,
  ) async {
    final result = _testDeletionResult(
      walletIndex: walletIndex,
      accountIds: <String>{expectedAccountId},
      deleteAccountKeys: false,
      deleteWalletWideKeys: false,
    );
    try {
      await deleteWalletAction!(walletIndex);
      return result;
    } on WalletLocalCleanupException catch (error) {
      throw WalletLocalCleanupException(
        error.failures,
        deletionResult: result,
      );
    }
  }

  Future<WalletDeletionResult> runDeleteAccount(String accountId) async {
    final result = _testDeletionResult(
      walletIndex: 1,
      accountIds: <String>{accountId},
      deleteAccountKeys: true,
      deleteWalletWideKeys: false,
    );
    try {
      await deleteAccountAction!(accountId);
      return result;
    } on WalletLocalCleanupException catch (error) {
      throw WalletLocalCleanupException(
        error.failures,
        deletionResult: result,
      );
    }
  }

  Future<WalletDeletionResult> runSignedDelete({
    required int walletIndex,
    required String accountId,
  }) async {
    const secondAccountId =
        '0x0000000000000000000000000000000000000000000000000000000000000002';
    final result = _testDeletionResult(
      walletIndex: walletIndex,
      accountIds: <String>{accountId, secondAccountId},
      deleteAccountKeys: true,
      deleteWalletWideKeys: true,
    );
    try {
      await signAndDeleteWalletAction!(
        walletIndex: walletIndex,
        accountId: accountId,
      );
      return result;
    } on WalletLocalCleanupException catch (error) {
      throw WalletLocalCleanupException(
        error.failures,
        deletionResult: result,
      );
    }
  }

  return MaterialApp(
    home: WalletTab(
      snapshotLoader: snapshotLoader,
      // 页面加载状态测试只关注本地快照，禁止启动身份和轻节点后台流程。
      afterSnapshotLoaded: (_) async {},
      finalizedBalancesLoader: finalizedBalancesLoader,
      balanceWriter: balanceWriter == null
          ? null
          : (walletIndex, _, __, balance) async {
              await balanceWriter(walletIndex, balance);
              return true;
            },
      onBalanceRefreshingChanged: onBalanceRefreshingChanged,
      defaultAccountReorderCommitter: defaultAccountReorderCommitter,
      deleteWalletAction: deleteWalletAction == null ? null : runDeleteWallet,
      deleteAccountAction:
          deleteAccountAction == null ? null : runDeleteAccount,
      signAndDeleteWalletAction:
          signAndDeleteWalletAction == null ? null : runSignedDelete,
      clearingBankClearer: clearingBankClearer,
      pendingWalletCleanupPlansLoader: pendingWalletCleanupPlansLoader ??
          () async => const <WalletCleanupPlan>[],
      walletCleanupPlanRetrier: walletCleanupPlanRetrier ?? (_) async {},
      walletCleanupPlanAcknowledger:
          walletCleanupPlanAcknowledger ?? (_) async {},
    ),
  );
}

/// 详情页会启动交易记录监听，钱包详情还会启动全局轻节点监控。严格 Isar 生命周期
/// 下，测试必须先真实销毁页面和后台消费者，再由文件级 tearDown 删除数据库；禁止
/// 依赖 Flutter 测试框架稍后的隐式卸载与删库竞态。
void _registerWalletPageDisposal(WidgetTester tester) {
  addTearDown(() async {
    // 先同步废止监控 owner，再卸载页面；随后等待旧代次全部后台任务真实结束，
    // 防止旧 finalized/RPC 返回跨过文件级 WalletIsar 擦除并重新打开数据库。
    final monitorDrain = ChainTxMonitor.instance.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // monitor 的启动任务含 Isar 原生 Future，但它的队列 continuation 属于 widget
    // fake-async Zone；交替让真实 I/O 和 fake microtask 前进，确定性等到 drain 完成。
    var monitorDrained = false;
    Object? monitorError;
    StackTrace? monitorStackTrace;
    monitorDrain.then<void>(
      (_) => monitorDrained = true,
      onError: (Object error, StackTrace stackTrace) {
        monitorError = error;
        monitorStackTrace = stackTrace;
        monitorDrained = true;
      },
    );
    for (var attempt = 0; attempt < 50 && !monitorDrained; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(monitorDrained, isTrue,
        reason: '页面销毁后 ChainTxMonitor 旧代次必须在文件级擦除前排空');
    if (monitorError != null) {
      Error.throwWithStackTrace(monitorError!, monitorStackTrace!);
    }
    await ChainTxMonitor.instance.stop();
    // TxAutoRefreshMixin.dispose 发起的取消会由 WalletIsar lease 确定性 drain；页面
    // 首次本地查询还要让“原生 I/O → fake-async Zone”逐阶段收尾，禁止固定 sleep 猜时机。
    for (var attempt = 0;
        attempt < 20 && WalletIsar.instance.hasActiveOperation;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      WalletIsar.instance.hasActiveOperation,
      isFalse,
      reason: '页面销毁后 WalletIsar 操作必须在文件级 tearDown 擦除前排空',
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 文件级唯一 Isar 生命周期(隔离临时目录)。必须在 main() 顶部调一次,不能在多个 group
  // 内各调一次——两个 group 各开一次 IsarCore 会导致第二个 setUpAll 挂死(12 分钟超时)。
  useIsolatedIsar();

  group('parseAccountIndices（空格分隔多序号解析）', () {
    test('连续 "1 2 3" → [1,2,3]', () {
      final parsed = parseAccountIndices('1 2 3');
      expect(parsed.isSuccess, isTrue);
      expect(parsed.indices, [1, 2, 3]);
    });

    test('断续 "1 5 9" → [1,5,9]', () {
      final parsed = parseAccountIndices('1 5 9');
      expect(parsed.isSuccess, isTrue);
      expect(parsed.indices, [1, 5, 9]);
    });

    test('多余空白 "  1   5  9 " 仍归一化成 [1,5,9]', () {
      final parsed = parseAccountIndices('  1   5  9 ');
      expect(parsed.indices, [1, 5, 9]);
    });

    test('空串 → 失败并给出提示', () {
      final parsed = parseAccountIndices('   ');
      expect(parsed.isSuccess, isFalse);
      expect(parsed.error, isNotNull);
    });

    test('含非数字 "1 a 3" → 失败', () {
      final parsed = parseAccountIndices('1 a 3');
      expect(parsed.isSuccess, isFalse);
      expect(parsed.error, contains('a'));
    });
  });

  group('「＋」入口三项菜单（添加下一个账户 / 添加指定账户 / 导入冷钱包）', () {
    testWidgets('有热钱包时三项齐全,导入冷钱包在最下', (tester) async {
      var next = false;
      var specify = false;
      var cold = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletEntryChooserSheet(
              canAddAccount: true,
              onAddNextAccount: () => next = true,
              onAddSpecifyAccount: () => specify = true,
              onImportCold: () => cold = true,
            ),
          ),
        ),
      );
      expect(find.text('添加下一个账户'), findsOneWidget);
      expect(find.text('添加指定账户'), findsOneWidget);
      expect(find.text('导入冷钱包'), findsOneWidget);
      // 不得出现热钱包创建 / 导入入口。
      expect(find.text('创建钱包'), findsNothing);
      expect(find.text('导入热钱包'), findsNothing);

      for (final subtitle in <String>[
        '在本钱包下派生下一个序号账户',
        '指定序号恢复本钱包下的特定账户',
        '仅导入公钥，私钥保留在签名设备',
      ]) {
        final text = tester.widget<Text>(find.text(subtitle));
        expect(text.style?.color, AppTheme.textTertiary);
      }

      await tester.tap(find.text('添加下一个账户'));
      await tester.tap(find.text('添加指定账户'));
      await tester.tap(find.text('导入冷钱包'));
      await tester.pump();
      expect(next && specify && cold, isTrue);
    });

    testWidgets('无热钱包时只有「导入冷钱包」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletEntryChooserSheet(
              canAddAccount: false,
              onAddNextAccount: () {},
              onAddSpecifyAccount: () {},
              onImportCold: () {},
            ),
          ),
        ),
      );
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('WalletEmptyChoices 空态也只有「导入冷钱包」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WalletEmptyChoices(onImportCold: () {})),
        ),
      );
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('创建钱包'), findsNothing);
      expect(find.text('导入热钱包'), findsNothing);
    });
  });

  group('钱包页三段快照一致性', () {
    test('读间 revision 变化时整段重试，不提交钱包/账户/默认账户混代快照', () async {
      var revision = 0;
      var walletReads = 0;
      var accountReads = 0;
      var defaultAccountReads = 0;
      late WalletProfile currentWallet;

      final snapshot = await readConsistentWalletPageSnapshot(
        revisionReader: () => revision,
        walletsLoader: () async {
          walletReads += 1;
          currentWallet = _makeColdWallet(
            walletIndex: walletReads,
            name: '第$walletReads代钱包',
          );
          return <WalletProfile>[currentWallet];
        },
        accountsLoader: (wallets) async {
          accountReads += 1;
          // 第一轮在钱包读取后模拟真实 mutation；三段结果必须整轮作废。
          if (accountReads == 1) revision += 1;
          final wallet = wallets.single;
          return <Account>[
            Account(
              masterId: wallet.accountId,
              accountIndex: wallet.walletIndex,
              accountId: wallet.accountId,
              ss58Address: wallet.ss58Address,
              accountName: '${wallet.walletName}-账户',
            ),
          ];
        },
        defaultAccountsLoader: () async {
          defaultAccountReads += 1;
          return <DefaultAccount>[
            DefaultAccount(
              accountId: currentWallet.accountId,
              ss58Address: currentWallet.ss58Address,
              accountName: '${currentWallet.walletName}-默认',
              signMode: SignMode.cold,
              walletIndex: currentWallet.walletIndex,
            ),
          ];
        },
        usableHotWalletAccountIdLoader: (_, __) async => null,
      );

      expect(walletReads, 2);
      expect(accountReads, 2);
      expect(defaultAccountReads, 2);
      expect(snapshot.wallets.single.walletName, '第2代钱包');
      expect(snapshot.accounts.single.accountName, '第2代钱包-账户');
      expect(snapshot.defaultAccounts.single.accountName, '第2代钱包-默认');
    });

    test('revision 持续变化时只重试指定上限并明确失败', () async {
      var revision = 0;
      var walletReads = 0;
      var accountReads = 0;
      var defaultAccountReads = 0;

      await expectLater(
        readConsistentWalletPageSnapshot(
          revisionReader: () => revision,
          walletsLoader: () async {
            walletReads += 1;
            return <WalletProfile>[_makeColdWallet()];
          },
          accountsLoader: (_) async {
            accountReads += 1;
            return const <Account>[];
          },
          defaultAccountsLoader: () async {
            defaultAccountReads += 1;
            revision += 1;
            return const <DefaultAccount>[];
          },
          usableHotWalletAccountIdLoader: (_, __) async => null,
          maxAttempts: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('持续变化'),
          ),
        ),
      );

      expect(walletReads, 3);
      expect(accountReads, 3);
      expect(defaultAccountReads, 3);
    });

    test('WalletManager 事实 mutation gate 开启时有界失败且不读取或提交中间态', () async {
      var walletReads = 0;
      var accountReads = 0;
      var defaultAccountReads = 0;

      await expectLater(
        readConsistentWalletPageSnapshot(
          revisionReader: () => 7,
          mutationActiveReader: () => true,
          walletsLoader: () async {
            walletReads += 1;
            return <WalletProfile>[_makeColdWallet()];
          },
          accountsLoader: (_) async {
            accountReads += 1;
            return const <Account>[];
          },
          defaultAccountsLoader: () async {
            defaultAccountReads += 1;
            return const <DefaultAccount>[];
          },
          usableHotWalletAccountIdLoader: (_, __) async => null,
          maxAttempts: 3,
        ),
        throwsA(isA<StateError>()),
      );

      expect(walletReads, 0);
      expect(accountReads, 0);
      expect(defaultAccountReads, 0);
    });

    test('mutation gate 解除信号完成后再有界重读并提交最新代快照', () async {
      var active = true;
      var walletReads = 0;
      final settled = Completer<void>();

      final pending = readConsistentWalletPageSnapshot(
        revisionReader: () => 8,
        mutationActiveReader: () => active,
        mutationSettledWaiter: () => settled.future,
        walletsLoader: () async {
          walletReads += 1;
          return <WalletProfile>[_makeColdWallet(name: '门禁后钱包')];
        },
        accountsLoader: (_) async => const <Account>[],
        defaultAccountsLoader: () async => const <DefaultAccount>[],
        usableHotWalletAccountIdLoader: (_, __) async => null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(walletReads, 0, reason: 'gate active 时不得读取任何中间事实');

      active = false;
      settled.complete();
      final snapshot = await pending;
      expect(walletReads, 1);
      expect(snapshot.wallets.single.walletName, '门禁后钱包');
      expect(snapshot.walletsRevision, 8);
    });

    test('完整快照监控账户0与全部 child accounts，不只监控钱包壳', () {
      final snapshot = _hotWalletWithSecondAccountSnapshot();
      expect(
        snapshot.monitoredAccounts.keys,
        <String>{
          _hotAccountId,
          '0x0000000000000000000000000000000000000000000000000000000000000002',
        },
      );
      expect(
        snapshot.monitoredAccounts[_hotAccountId],
        snapshot.accounts.first.ss58Address,
      );
    });
  });

  group('WalletTab 本地快照加载状态', () {
    testWidgets('首次加载中保持骨架且右上角＋禁用，不打开冷钱包伪菜单', (tester) async {
      final pending = Completer<WalletPageSnapshot>();
      await tester.pumpWidget(_walletTabHost(() => pending.future));
      await tester.pump();

      expect(find.byType(WalletCardSkeleton), findsNWidgets(3));
      final addButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('wallet-add-entry')),
      );
      expect(addButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('导入冷钱包'), findsNothing);

      pending.complete(_coldWalletSnapshot());
      await tester.pumpAndSettle();
    });

    testWidgets('首次失败显示重试，失败和重试加载期间＋都禁用', (tester) async {
      final retryPending = Completer<WalletPageSnapshot>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          if (calls == 1) {
            return Future<WalletPageSnapshot>.error(
              StateError('首次读取失败'),
            );
          }
          return retryPending.future;
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('钱包加载失败'), findsOneWidget);
      expect(find.textContaining('首次读取失败'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-initial-load-retry')),
          findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('wallet-initial-load-retry')));
      await tester.pump();
      expect(find.byType(WalletCardSkeleton), findsNWidgets(3));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNull,
      );

      retryPending.complete(_coldWalletSnapshot());
      await tester.pumpAndSettle();
      expect(find.text('钱包加载失败'), findsNothing);
      expect(find.text('测试冷钱包'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('首次成功且存在热钱包时右上角＋显示完整三项', (tester) async {
      await tester.pumpWidget(
        _walletTabHost(() async => _hotWalletSnapshot()),
      );
      await tester.pumpAndSettle();

      final addButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('wallet-add-entry')),
      );
      expect(addButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pumpAndSettle();

      expect(find.text('添加下一个账户'), findsOneWidget);
      expect(find.text('添加指定账户'), findsOneWidget);
      expect(find.text('导入冷钱包'), findsOneWidget);
    });

    testWidgets('首次成功且明确无热钱包时右上角＋只显示导入冷钱包', (tester) async {
      await tester.pumpWidget(
        _walletTabHost(() async => _coldWalletSnapshot()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pumpAndSettle();
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('已有成功数据刷新失败时保留列表和＋能力并显示重试提示', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          if (calls == 1) {
            return Future<WalletPageSnapshot>.value(_coldWalletSnapshot());
          }
          return Future<WalletPageSnapshot>.error(
            StateError('刷新读取失败'),
          );
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试冷钱包'), findsOneWidget);

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('测试冷钱包'), findsOneWidget);
      expect(
        find.text('钱包刷新失败，正在显示上次成功加载的数据'),
        findsOneWidget,
      );
      expect(
          find.byKey(const ValueKey('wallet-refresh-retry')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pumpAndSettle();
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('较新的刷新成功先完成时，较旧成功不得逆序覆盖最新快照', (tester) async {
      final olderRequest = Completer<WalletPageSnapshot>();
      final newerRequest = Completer<WalletPageSnapshot>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          switch (calls) {
            case 1:
              return Future<WalletPageSnapshot>.value(
                _coldWalletSnapshot(name: '基线钱包'),
              );
            case 2:
              return Future<WalletPageSnapshot>.error(
                StateError('建立刷新失败态'),
              );
            case 3:
              return olderRequest.future;
            case 4:
              return newerRequest.future;
            default:
              return Future<WalletPageSnapshot>.error(
                StateError('出现非预期的第$calls次读取'),
              );
          }
        }),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsOneWidget,
      );

      // 失败横幅在请求完成前保留，因此可以制造两次并发重试并按相反顺序完成。
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      expect(calls, 4);

      newerRequest.complete(_coldWalletSnapshot(name: '最新钱包'));
      await tester.pumpAndSettle();
      expect(find.text('最新钱包'), findsOneWidget);

      olderRequest.complete(_coldWalletSnapshot(name: '过期钱包'));
      await tester.pumpAndSettle();
      expect(find.text('最新钱包'), findsOneWidget);
      expect(find.text('过期钱包'), findsNothing);
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsNothing,
      );
    });

    testWidgets('较新的刷新成功先完成时，较旧失败不得把最新快照降级', (tester) async {
      final olderRequest = Completer<WalletPageSnapshot>();
      final newerRequest = Completer<WalletPageSnapshot>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          switch (calls) {
            case 1:
              return Future<WalletPageSnapshot>.value(
                _coldWalletSnapshot(name: '基线钱包'),
              );
            case 2:
              return Future<WalletPageSnapshot>.error(
                StateError('建立刷新失败态'),
              );
            case 3:
              return olderRequest.future;
            case 4:
              return newerRequest.future;
            default:
              return Future<WalletPageSnapshot>.error(
                StateError('出现非预期的第$calls次读取'),
              );
          }
        }),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      expect(calls, 4);

      newerRequest.complete(_coldWalletSnapshot(name: '最新钱包'));
      await tester.pumpAndSettle();
      olderRequest.completeError(StateError('过期请求失败'));
      await tester.pumpAndSettle();

      expect(find.text('最新钱包'), findsOneWidget);
      expect(find.text('钱包加载失败'), findsNothing);
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsNothing,
      );
    });

    testWidgets('旧余额 RPC 完成时原子交接新代次，旧结果不写入且不清理新 owner', (tester) async {
      final olderRpc = Completer<Map<String, double>>();
      final newerRpc = Completer<Map<String, double>>();
      final writes = <double>[];
      final refreshingStates = <bool>[];
      final accountId = _makeColdWallet().accountId;
      var storedBalance = 0.0;
      var snapshotReads = 0;
      var balanceReads = 0;

      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return _coldWalletSnapshot(
              name: snapshotReads == 1 ? '旧页面快照' : '最新页面快照',
              balance: storedBalance,
            );
          },
          finalizedBalancesLoader: (_) {
            balanceReads += 1;
            return switch (balanceReads) {
              1 => olderRpc.future,
              2 => newerRpc.future,
              _ => Future<Map<String, double>>.error(
                  StateError('出现非预期的第$balanceReads次余额读取'),
                ),
            };
          },
          balanceWriter: (_, balance) async {
            writes.add(balance);
            storedBalance = balance;
          },
          onBalanceRefreshingChanged: refreshingStates.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(balanceReads, 1);
      expect(refreshingStates, <bool>[true]);
      expect(find.text('旧页面快照'), findsOneWidget);

      // 第一代 RPC 未完成时启动第二代整页 reload；第二代余额刷新必须登记接管。
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();
      expect(snapshotReads, 2);
      expect(find.text('最新页面快照'), findsOneWidget);
      expect(balanceReads, 1);

      olderRpc.complete(<String, double>{accountId: 11});
      await tester.pumpAndSettle();

      // 旧结果因 generation 失效不得写库；finally 直接把 owner 交给第二代，期间
      // refreshing 不能出现 false，且第二代 RPC 已真正启动。
      expect(writes, isEmpty);
      expect(balanceReads, 2);
      expect(refreshingStates, <bool>[true]);
      expect(find.text('最新页面快照'), findsOneWidget);

      newerRpc.complete(<String, double>{accountId: 22});
      await tester.pumpAndSettle();

      expect(writes, <double>[22]);
      expect(storedBalance, 22);
      expect(snapshotReads, 3);
      expect(refreshingStates, <bool>[true, false]);
      expect(find.text('最新页面快照'), findsOneWidget);
      expect(find.text('旧页面快照'), findsNothing);
    });

    testWidgets('默认账户 mutation 等待失败时不回滚覆盖期间提交的新快照', (tester) async {
      final mutationPending = Completer<void>();
      final oldSnapshot = _coldWalletsSnapshot(<WalletProfile>[
        _makeColdWallet(walletIndex: 2, name: '旧账户甲'),
        _makeColdWallet(walletIndex: 3, name: '旧账户乙'),
      ]);
      final newSnapshot = _coldWalletsSnapshot(<WalletProfile>[
        _makeColdWallet(walletIndex: 4, name: '新账户丙'),
        _makeColdWallet(walletIndex: 5, name: '新账户丁'),
      ]);
      var snapshotReads = 0;
      var mutationCalls = 0;

      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return snapshotReads == 1 ? oldSnapshot : newSnapshot;
          },
          defaultAccountReorderCommitter: (_, __) {
            mutationCalls += 1;
            return mutationPending.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      final reorderable = tester.widget<SliverReorderableList>(
        find.byType(SliverReorderableList),
      );
      reorderable.onReorderItem!(0, 1);
      await tester.pump();
      expect(mutationCalls, 1);

      // mutation 仍在等待时由 reload 提交完全不同的新账户事实。
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();
      expect(snapshotReads, 2);
      expect(find.text('新账户丙'), findsOneWidget);
      expect(find.text('新账户丁'), findsOneWidget);

      mutationPending.completeError(
        const WalletAuthException('已取消默认账户切换'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('新账户丙'), findsOneWidget);
      expect(find.text('新账户丁'), findsOneWidget);
      expect(find.text('旧账户甲'), findsNothing);
      expect(find.text('旧账户乙'), findsNothing);
      expect(find.textContaining('已取消默认账户切换'), findsOneWidget);
    });

    testWidgets('默认账户 mutation 成功晚于较新 reload 时强制复读持久化最终事实', (tester) async {
      final mutationPending = Completer<void>();
      final oldSnapshot = _coldWalletsSnapshot(<WalletProfile>[
        _makeColdWallet(walletIndex: 2, name: '初始账户甲'),
        _makeColdWallet(walletIndex: 3, name: '初始账户乙'),
      ]);
      final interleavedSnapshot = _coldWalletsSnapshot(<WalletProfile>[
        _makeColdWallet(walletIndex: 4, name: '插入快照丙'),
        _makeColdWallet(walletIndex: 5, name: '插入快照丁'),
      ]);
      final persistedSnapshot = _coldWalletsSnapshot(<WalletProfile>[
        _makeColdWallet(walletIndex: 3, name: '持久化账户乙'),
        _makeColdWallet(walletIndex: 2, name: '持久化账户甲'),
      ]);
      var snapshotReads = 0;

      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return switch (snapshotReads) {
              1 => oldSnapshot,
              2 => interleavedSnapshot,
              _ => persistedSnapshot,
            };
          },
          defaultAccountReorderCommitter: (_, __) => mutationPending.future,
        ),
      );
      await tester.pumpAndSettle();

      final reorderable = tester.widget<SliverReorderableList>(
        find.byType(SliverReorderableList),
      );
      reorderable.onReorderItem!(0, 1);
      await tester.pump();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
      await tester.pumpAndSettle();
      expect(snapshotReads, 2);
      expect(find.text('插入快照丙'), findsOneWidget);

      mutationPending.complete();
      await tester.pumpAndSettle();

      expect(snapshotReads, 3, reason: 'mutation 成功后必须另起一代复读真实持久化事实');
      expect(find.text('持久化账户乙'), findsOneWidget);
      expect(find.text('持久化账户甲'), findsOneWidget);
      expect(find.text('插入快照丙'), findsNothing);
      expect(find.text('插入快照丁'), findsNothing);
    });

    testWidgets('删除确认立即废止余额 owner，并在 mutation 期间禁用＋和其它菜单', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final rpcPending = Completer<Map<String, double>>();
      final deletePending = Completer<void>();
      final writes = <double>[];
      final refreshingStates = <bool>[];
      var deleted = false;
      var balanceReads = 0;

      await tester.pumpWidget(
        _walletTabHost(
          () async => deleted
              ? _coldWalletsSnapshot(const <WalletProfile>[])
              : _coldWalletSnapshot(name: '删除竞态钱包'),
          finalizedBalancesLoader: (_) {
            balanceReads += 1;
            return rpcPending.future;
          },
          balanceWriter: (_, balance) async => writes.add(balance),
          onBalanceRefreshingChanged: refreshingStates.add,
          deleteWalletAction: (_) {
            deleted = true;
            return deletePending.future;
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(balanceReads, 1);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pump();

      final addButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('wallet-add-entry')),
      );
      expect(addButton.onPressed, isNull);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      expect(refreshingStates, <bool>[true, false]);

      deletePending.complete();
      await tester.pumpAndSettle();
      rpcPending.complete(<String, double>{_makeColdWallet().accountId: 99});
      await tester.pumpAndSettle();

      expect(writes, isEmpty, reason: '删除前 RPC 结果已经失去 owner，不能写回已删/复用索引');
      expect(find.text('删除竞态钱包'), findsNothing);
      expect(find.text('导入冷钱包'), findsOneWidget);
    });

    testWidgets('Manager 首次清理异常但页面立即重试成功时按最终状态显示删除成功', (tester) async {
      final coldAccountId = _makeColdWallet().accountId;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'clearing_bank_binding_$coldAccountId': '待清冷钱包缓存',
      });
      var deleted = false;
      var snapshotReads = 0;
      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return deleted
                ? _coldWalletsSnapshot(const <WalletProfile>[])
                : _coldWalletSnapshot(name: '待删冷钱包');
          },
          deleteWalletAction: (_) async {
            deleted = true;
            throw const WalletLocalCleanupException(<String>['测试密钥清理失败']);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(snapshotReads, 2);
      expect(find.text('待删冷钱包'), findsNothing);
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.textContaining('已删除「待删冷钱包」'), findsOneWidget);
      expect(find.textContaining('本机安全清理未完成'), findsNothing);
      expect(find.textContaining('测试密钥清理失败'), findsNothing);
      expect(find.textContaining('删除未完成'), findsNothing);
      expect(
        find.byKey(const ValueKey('wallet-pending-cleanup-banner')),
        findsNothing,
      );
      expect(
        (await SharedPreferences.getInstance())
            .getString('clearing_bank_binding_$coldAccountId'),
        isNull,
        reason: '事实已移除后，即使安全清理抛错也必须独立清交易域缓存',
      );
    });

    testWidgets('非0账户事实已删除但安全清理失败时不保留已删账户', (tester) async {
      const secondAccountId =
          '0x0000000000000000000000000000000000000000000000000000000000000002';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'clearing_bank_binding_$secondAccountId': '待清非0账户缓存',
      });
      var deleted = false;
      var snapshotReads = 0;
      var clearingBankClearCalls = 0;
      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return deleted
                ? _hotWalletSnapshot()
                : _hotWalletWithSecondAccountSnapshot();
          },
          deleteAccountAction: (accountId) async {
            expect(accountId, endsWith('2'));
            deleted = true;
            throw const WalletLocalCleanupException(<String>['账户 child 清理失败']);
          },
          walletCleanupPlanRetrier: (_) async {
            throw StateError('账户 child 清理失败');
          },
          clearingBankClearer: (_) async {
            clearingBankClearCalls += 1;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('账户操作').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除账户'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(snapshotReads, 2);
      expect(find.text('账户0'), findsOneWidget);
      expect(find.text('账户1'), findsNothing);
      expect(
        find.textContaining('账户「账户1」事实已移除，但本机安全清理未完成'),
        findsOneWidget,
      );
      expect(find.textContaining('账户 child 清理失败'), findsOneWidget);
      expect(clearingBankClearCalls, 0);
      expect(
        (await SharedPreferences.getInstance())
            .getString('clearing_bank_binding_$secondAccountId'),
        '待清非0账户缓存',
        reason: '核心计划重试失败时不得触碰可能被同 accountId 新事实复用的缓存',
      );
    });

    testWidgets('签名删热钱包事实已提交但安全清理失败时不显示删除未完成', (tester) async {
      const secondAccountId =
          '0x0000000000000000000000000000000000000000000000000000000000000002';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'clearing_bank_binding_$_hotAccountId': '待清账户0缓存',
        'clearing_bank_binding_$secondAccountId': '待清账户1缓存',
      });
      var deleted = false;
      var snapshotReads = 0;
      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            return deleted
                ? _coldWalletsSnapshot(const <WalletProfile>[])
                : _hotWalletWithSecondAccountSnapshot();
          },
          signAndDeleteWalletAction: ({
            required int walletIndex,
            required String accountId,
          }) async {
            expect(walletIndex, 1);
            expect(accountId, _hotAccountId);
            deleted = true;
            throw const WalletLocalCleanupException(<String>['钱包 KEK 清理失败']);
          },
          walletCleanupPlanRetrier: (_) async {
            throw StateError('钱包 KEK 清理失败');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('账户操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '签名并删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(snapshotReads, 2);
      expect(find.text('账户0'), findsNothing);
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(
        find.textContaining('钱包「热钱包」事实已移除，但本机安全清理未完成'),
        findsOneWidget,
      );
      expect(find.textContaining('钱包 KEK 清理失败'), findsOneWidget);
      expect(find.textContaining('删除未完成'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('clearing_bank_binding_$_hotAccountId'),
        '待清账户0缓存',
      );
      expect(
        prefs.getString('clearing_bank_binding_$secondAccountId'),
        '待清账户1缓存',
      );
    });

    testWidgets('钱包事实未删除时不得误清清算行缓存', (tester) async {
      final coldAccountId = _makeColdWallet().accountId;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'clearing_bank_binding_$coldAccountId': '必须保留的缓存',
      });

      await tester.pumpWidget(
        _walletTabHost(
          () async => _coldWalletSnapshot(name: '仍存在的钱包'),
          deleteWalletAction: (_) async {
            throw const WalletAuthException('删除授权失败');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('仍存在的钱包'), findsOneWidget);
      expect(find.textContaining('删除未完成'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance())
            .getString('clearing_bank_binding_$coldAccountId'),
        '必须保留的缓存',
      );
    });

    testWidgets('整只热钱包多个缓存清理失败仍全部尝试并聚合', (tester) async {
      const secondAccountId =
          '0x0000000000000000000000000000000000000000000000000000000000000002';
      var deleted = false;
      final clearCalls = <String>[];
      await tester.pumpWidget(
        _walletTabHost(
          () async => deleted
              ? _coldWalletsSnapshot(const <WalletProfile>[])
              : _hotWalletWithSecondAccountSnapshot(),
          signAndDeleteWalletAction: ({
            required int walletIndex,
            required String accountId,
          }) async {
            deleted = true;
            throw const WalletLocalCleanupException(<String>['硬件安全清理失败']);
          },
          clearingBankClearer: (accountId) async {
            clearCalls.add(accountId);
            throw StateError('缓存清理失败-$accountId');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('账户操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '签名并删除'));
      await tester.pumpAndSettle();

      expect(clearCalls, containsAll(<String>[_hotAccountId, secondAccountId]));
      expect(clearCalls, hasLength(2));
      expect(find.textContaining('硬件安全清理失败'), findsNothing);
      expect(find.textContaining('清算行缓存($_hotAccountId)'), findsOneWidget);
      expect(find.textContaining('清算行缓存($secondAccountId)'), findsOneWidget);
    });

    testWidgets('删除后未清即退出时，新页面从持久计划恢复并完成全部清理', (tester) async {
      final wallet = _makeColdWallet(walletIndex: 21, name: '已删除钱包');
      final plan = WalletCleanupPlan(
        planId: 'restart-plan',
        walletIndex: wallet.walletIndex,
        accountIds: <String>{wallet.accountId},
        deleteAccountKeys: false,
        deleteWalletWideKeys: false,
      );
      final pending = <WalletCleanupPlan>[plan];
      final retried = <String>[];
      final cleared = <String>[];
      final acknowledged = <String>[];

      await tester.pumpWidget(
        _walletTabHost(
          () async => _coldWalletsSnapshot(const <WalletProfile>[]),
          pendingWalletCleanupPlansLoader: () async => List.of(pending),
          walletCleanupPlanRetrier: (target) async {
            retried.add(target.planId);
          },
          clearingBankClearer: (accountId) async {
            cleared.add(accountId);
          },
          walletCleanupPlanAcknowledger: (planId) async {
            acknowledged.add(planId);
            pending.removeWhere((item) => item.planId == planId);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(retried, <String>[plan.planId]);
      expect(cleared, <String>[wallet.accountId]);
      expect(acknowledged, <String>[plan.planId]);
      expect(pending, isEmpty);
      expect(
        find.byKey(const ValueKey('wallet-pending-cleanup-banner')),
        findsNothing,
      );
    });

    testWidgets('多项持久计划部分失败时只确认成功项，显式重试后收口', (tester) async {
      final first = _makeColdWallet(walletIndex: 22, name: '计划一');
      final second = _makeColdWallet(walletIndex: 23, name: '计划二');
      final plans = <WalletCleanupPlan>[
        WalletCleanupPlan(
          planId: 'partial-plan-1',
          walletIndex: first.walletIndex,
          accountIds: <String>{first.accountId},
          deleteAccountKeys: false,
          deleteWalletWideKeys: false,
        ),
        WalletCleanupPlan(
          planId: 'partial-plan-2',
          walletIndex: second.walletIndex,
          accountIds: <String>{second.accountId},
          deleteAccountKeys: false,
          deleteWalletWideKeys: false,
        ),
      ];
      var secondCanClear = false;
      final clearCalls = <String>[];
      final acknowledged = <String>[];

      await tester.pumpWidget(
        _walletTabHost(
          () async => _coldWalletsSnapshot(const <WalletProfile>[]),
          pendingWalletCleanupPlansLoader: () async => List.of(plans),
          clearingBankClearer: (accountId) async {
            clearCalls.add(accountId);
            if (accountId == second.accountId && !secondCanClear) {
              throw StateError('第二项暂时失败');
            }
          },
          walletCleanupPlanAcknowledger: (planId) async {
            acknowledged.add(planId);
            plans.removeWhere((plan) => plan.planId == planId);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(acknowledged, <String>['partial-plan-1']);
      expect(plans.map((plan) => plan.planId), <String>['partial-plan-2']);
      expect(
        find.byKey(const ValueKey('wallet-pending-cleanup-banner')),
        findsOneWidget,
      );

      secondCanClear = true;
      await tester.tap(
        find.byKey(const ValueKey('wallet-pending-cleanup-retry')),
      );
      await tester.pumpAndSettle();

      expect(acknowledged, <String>['partial-plan-1', 'partial-plan-2']);
      expect(
        clearCalls.where((accountId) => accountId == first.accountId),
        hasLength(1),
      );
      expect(
        clearCalls.where((accountId) => accountId == second.accountId),
        hasLength(2),
      );
      expect(plans, isEmpty);
      expect(
        find.byKey(const ValueKey('wallet-pending-cleanup-banner')),
        findsNothing,
      );
    });

    testWidgets('删除结果事实已提交时即使 reload 失败仍按计划清缓存', (tester) async {
      final wallet = _makeColdWallet(walletIndex: 24, name: 'reload失败钱包');
      var deleted = false;
      var snapshotReads = 0;
      final cleared = <String>[];

      await tester.pumpWidget(
        _walletTabHost(
          () async {
            snapshotReads += 1;
            if (deleted) throw StateError('模拟 reload 失败');
            return _coldWalletsSnapshot(<WalletProfile>[wallet]);
          },
          deleteWalletAction: (_) async {
            deleted = true;
          },
          clearingBankClearer: (accountId) async {
            cleared.add(accountId);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(snapshotReads, 2);
      expect(cleared, <String>[wallet.accountId]);
      expect(find.textContaining('已删除「reload失败钱包」'), findsOneWidget);
    });

    testWidgets('钱包索引被新账户复用时仍按目标 accountId 确认旧事实已经删除', (tester) async {
      final target = _makeColdWallet(walletIndex: 2, name: '旧索引钱包');
      const replacementAccountId =
          '0x0000000000000000000000000000000000000000000000000000000000000009';
      final replacement = WalletProfile(
        walletIndex: target.walletIndex,
        walletName: '复用索引的新钱包',
        walletIcon: 'wallet',
        balance: 0,
        accountId: replacementAccountId,
        ss58Address: ss58FromAccountIdText(replacementAccountId),
        alg: 'sr25519',
        ss58: 2027,
        createdAtMillis: 1,
        source: 'test',
        signMode: SignMode.cold,
      );
      var deleted = false;
      final clearCalls = <String>[];
      await tester.pumpWidget(
        _walletTabHost(
          () async => _coldWalletsSnapshot(
            <WalletProfile>[deleted ? replacement : target],
          ),
          deleteWalletAction: (_) async => deleted = true,
          clearingBankClearer: (accountId) async => clearCalls.add(accountId),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除钱包'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('复用索引的新钱包'), findsOneWidget);
      expect(find.text('旧索引钱包'), findsNothing);
      expect(clearCalls, <String>[target.accountId]);
      expect(find.textContaining('已删除「旧索引钱包」'), findsOneWidget);
    });

    testWidgets('异常热钱包不提供追加账户入口，＋中只能导入冷钱包', (tester) async {
      final hot = _makeHotWallet(name: '异常热钱包');
      final broken = WalletProfile(
        walletIndex: hot.walletIndex,
        walletName: hot.walletName,
        walletIcon: hot.walletIcon,
        balance: hot.balance,
        accountId: hot.accountId,
        ss58Address: '损坏地址',
        alg: hot.alg,
        ss58: hot.ss58,
        createdAtMillis: hot.createdAtMillis,
        source: hot.source,
        signMode: hot.signMode,
      );
      await tester.pumpWidget(
        _walletTabHost(
          () async => WalletPageSnapshot(
            wallets: <WalletProfile>[broken],
            accounts: const <Account>[],
            defaultAccounts: const <DefaultAccount>[],
            walletsRevision: 1,
            usableHotWalletAccountId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pumpAndSettle();

      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('有壳无钥、缺账户0、重复 Hot 都不得开放追加账户', (tester) async {
      final validHot = _makeHotWallet();
      final account0 = Account(
        masterId: validHot.accountId,
        accountIndex: 0,
        accountId: validHot.accountId,
        ss58Address: validHot.ss58Address,
        accountName: '账户0',
      );
      const duplicateAccountId =
          '0x0000000000000000000000000000000000000000000000000000000000000008';
      final duplicateHot = WalletProfile(
        walletIndex: 8,
        walletName: '重复热钱包',
        walletIcon: 'wallet',
        balance: 0,
        accountId: duplicateAccountId,
        ss58Address: ss58FromAccountIdText(duplicateAccountId),
        alg: 'sr25519',
        ss58: 2027,
        createdAtMillis: 1,
        source: 'test',
        signMode: SignMode.hot,
      );
      final cases = <WalletPageSnapshot>[
        WalletPageSnapshot(
          wallets: <WalletProfile>[validHot],
          accounts: <Account>[account0],
          defaultAccounts: const <DefaultAccount>[],
          walletsRevision: 1,
          usableHotWalletAccountId: null,
        ),
        WalletPageSnapshot(
          wallets: <WalletProfile>[validHot],
          accounts: const <Account>[],
          defaultAccounts: const <DefaultAccount>[],
          walletsRevision: 2,
          usableHotWalletAccountId: null,
        ),
        WalletPageSnapshot(
          wallets: <WalletProfile>[validHot, duplicateHot],
          accounts: <Account>[account0],
          defaultAccounts: const <DefaultAccount>[],
          walletsRevision: 3,
          usableHotWalletAccountId: null,
        ),
      ];

      for (final snapshot in cases) {
        await tester.pumpWidget(_walletTabHost(() async => snapshot));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
        await tester.pumpAndSettle();
        final sheet = find.byType(WalletEntryChooserSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('导入冷钱包')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('添加下一个账户')),
          findsNothing,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('添加指定账户')),
          findsNothing,
        );
        Navigator.of(tester.element(sheet)).pop();
        await tester.pumpAndSettle();
      }
    });
  });

  group('WalletAccountTile（账户行渲染 + 冷钱包共存）', () {
    testWidgets('渲染账户名与短地址', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('账户1'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      // 长 SS58 固定展示首 10 位与末 8 位，中间严格为 6 个 ASCII 句点。
      expect(find.text('w5Bc7ma8qU......Q86xBWrT'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('点击账户行触发 onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () => tapped = true,
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('账户1'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('默认紧邻账户名称右上侧且不改变卡片高度', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const longName = '这是一个需要在窄屏省略的很长账户名称';
      Future<double> pumpDefaultTile(bool isDefault) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WalletAccountTile(
                account: _makeAccount(name: longName),
                isIdentity: true,
                isDefault: isDefault,
                onTap: () {},
                onScan: () {},
                onRename: () {},
                onDelete: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(WalletAccountTile)).height;
      }

      final normalHeight = await pumpDefaultTile(false);
      final defaultHeight = await pumpDefaultTile(true);

      expect(defaultHeight, normalHeight);
      expect(find.text('默认'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);

      final labelRect = tester.getRect(find.text('默认'));
      final nameRect = tester.getRect(find.text(longName));
      expect(labelRect.left, greaterThan(nameRect.right));
      expect(labelRect.center.dy, lessThan(nameRect.center.dy));
      expect(tester.takeException(), isNull);

      final address = tester.widget<Text>(find.textContaining('......'));
      expect(address.maxLines, 1);
      expect(address.overflow, TextOverflow.ellipsis);
    });

    testWidgets('扫一扫是三点菜单第一项且只触发当前账户扫码', (tester) async {
      var scanned = false;
      var cardTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () => cardTapped = true,
              onScan: () => scanned = true,
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      final menu = find.byTooltip('账户操作');
      expect(menu, findsOneWidget);
      // 卡片行内不再保留独立扫码按钮。
      expect(find.byTooltip('扫码签名'), findsNothing);
      expect(find.text('扫一扫'), findsNothing);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      final scan = find.text('扫一扫');
      final rename = find.text('重命名');
      expect(scan, findsOneWidget);
      expect(tester.getCenter(scan).dy, lessThan(tester.getCenter(rename).dy));

      await tester.tap(scan);
      await tester.pumpAndSettle();
      expect(scanned, isTrue);
      expect(cardTapped, isFalse);
    });

    testWidgets('账户0菜单为扫一扫/重命名/删除钱包且不再显示账户详情', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(index: 0, name: '账户0'),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('账户操作'));
      await tester.pumpAndSettle();
      expect(find.text('扫一扫'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('账户详情'), findsNothing);
      expect(find.text('删除钱包'), findsOneWidget);
      expect(find.text('删除账户'), findsNothing);
    });

    testWidgets('非0账户菜单显示删除账户而不是删除钱包', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(index: 5, name: '账户5'),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('账户操作'));
      await tester.pumpAndSettle();
      expect(find.text('删除账户'), findsOneWidget);
      expect(find.text('删除钱包'), findsNothing);
    });

    testWidgets('账户行与冷钱包行可在同一列表共存', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                WalletAccountTile(
                  account: _makeAccount(index: 0, name: '账户0'),
                  onTap: () {},
                  onScan: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
                WalletListTile(
                  wallet: _makeColdWallet(name: '我的冷钱包'),
                  showActions: true,
                  onTap: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
              ],
            ),
          ),
        ),
      );
      // 热钱包账户行与冷钱包行同列出现。
      expect(find.text('账户0'), findsOneWidget);
      expect(find.text('我的冷钱包'), findsOneWidget);
    });
  });

  group('AccountDetailPage（顶部账户资料 + AppBar 菜单 + 找回钱包功能）', () {
    // 账户详情渲染 WalletActionCard(读 ClearingBankPrefs/SharedPreferences)并加载本地
    // 交易记录(Isar,由文件级 useIsolatedIsar 提供);此处只补 SharedPreferences mock。
    setUp(() async {
      await ChainTxMonitor.instance.stop();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('顶部完整地址和卡片右上角二维码，删除/私钥/清算行不残留在正文', (tester) async {
      _registerWalletPageDisposal(tester);
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final account = _makeAccount(name: '账户1');
      await tester.pumpWidget(
        MaterialApp(home: AccountDetailPage(account: account)),
      );
      await tester.pump();
      expect(find.text('账户详情'), findsOneWidget);
      expect(find.text(account.ss58Address), findsOneWidget);
      expect(find.byTooltip('账户二维码'), findsOneWidget);
      expect(find.byTooltip('复制 SS58 地址'), findsOneWidget);
      final headerFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
        description: '账户详情渐变资料卡',
      );
      final headerRect = tester.getRect(headerFinder);
      final nameRect = tester.getRect(find.text(account.accountName));
      final qrRect = tester.getRect(find.byTooltip('账户二维码'));
      final copyRect = tester.getRect(find.byTooltip('复制 SS58 地址'));
      expect(
        qrRect.left,
        greaterThanOrEqualTo(nameRect.right),
        reason: '二维码必须位于账户名布局区之外，不能紧挨名称排版',
      );
      expect(
        qrRect.top - headerRect.top,
        lessThanOrEqualTo(12),
        reason: '二维码触控区必须贴在账户卡顶部',
      );
      expect(
        headerRect.right - qrRect.right,
        lessThanOrEqualTo(12),
        reason: '二维码触控区必须贴在账户卡右侧',
      );
      expect(
        copyRect.top,
        greaterThanOrEqualTo(qrRect.bottom),
        reason: '复制按钮必须下移到独立地址行，不能继续占用二维码旁的地址宽度',
      );
      expect(
        headerRect.right - copyRect.right,
        lessThanOrEqualTo(24),
        reason: '复制按钮必须靠齐账户卡内容右侧',
      );
      expect(find.text('点击查看私钥'), findsNothing);
      expect(find.text('删除账户'), findsNothing);
      expect(find.text('删除钱包'), findsNothing);
      expect(find.text('绑定 / 切换清算行'), findsNothing);
    });

    testWidgets('AppBar 右侧竖三点只有「清算行 / 查看私钥」', (tester) async {
      _registerWalletPageDisposal(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountDetailPage(account: _makeAccount(index: 0, name: '账户0')),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('清算行'), findsOneWidget);
      expect(find.text('查看私钥'), findsOneWidget);
      expect(find.text('删除钱包'), findsNothing);
      expect(find.text('重命名'), findsNothing);
    });

    testWidgets('账户右上角二维码打开固定账户码弹窗', (tester) async {
      _registerWalletPageDisposal(tester);
      final account = _makeAccount(index: 5, name: '日常账户');
      await tester.pumpWidget(
        MaterialApp(home: AccountDetailPage(account: account)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('账户二维码'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('日常账户')),
        findsOneWidget,
      );
      expect(find.text('账户地址'), findsNothing);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-account-qr')), findsOneWidget);
    });

    testWidgets('账户清算行入口只提示暂未上线', (tester) async {
      _registerWalletPageDisposal(tester);
      await tester.pumpWidget(
        MaterialApp(home: AccountDetailPage(account: _makeAccount(index: 0))),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清算行'));
      await tester.pump();

      expect(find.text('暂未上线，敬请期待'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '账户详情'), findsOneWidget);
    });

    testWidgets('iOS 左边缘手势可从账户详情返回上一级', (tester) async {
      _registerWalletPageDisposal(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AccountDetailPage(account: _makeAccount(index: 1)),
                  ),
                ),
                child: const Text('打开账户详情'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开账户详情'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '账户详情'), findsOneWidget);

      await tester.dragFrom(const Offset(1, 300), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text('打开账户详情'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '账户详情'), findsNothing);
    });

    testWidgets('iOS 左边缘手势可从钱包详情返回上一级', (tester) async {
      _registerWalletPageDisposal(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => WalletDetailPage(wallet: _makeColdWallet()),
                  ),
                ),
                child: const Text('打开钱包详情'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开钱包详情'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '钱包详情'), findsOneWidget);

      await tester.dragFrom(const Offset(1, 300), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text('打开钱包详情'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '钱包详情'), findsNothing);
    });

    testWidgets('冷钱包清算行入口只提示暂未上线', (tester) async {
      _registerWalletPageDisposal(tester);
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: _makeColdWallet())),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清算行'));
      await tester.pump();

      expect(find.text('暂未上线，敬请期待'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '钱包详情'), findsOneWidget);
    });
  });

  group('AddAccountSheet（重录助记词 + 多序号解析 → addAccounts）', () {
    late FakeSecureSeedStore fakeStore;
    const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      fakeStore = FakeSecureSeedStore();
      WalletManager.debugSeedStore = fakeStore;
      WalletManager.debugContactKeyStore = _MemoryBlobStore();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAuthChannel, (call) async {
        switch (call.method) {
          case 'authenticate':
            return true;
          case 'isDeviceSupported':
          case 'deviceSupportsBiometrics':
          case 'canCheckBiometrics':
            return true;
          case 'getAvailableBiometrics':
            return <String>['fingerprint'];
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAuthChannel, null);
    });

    testWidgets('指定序号模式:直接露出序号输入框,可录入多序号 "1 5 9",提交按钮在场', (tester) async {
      _registerWalletPageDisposal(tester);
      // 只验 UI 装配(指定序号模式渲染 / 多序号录入 / 提交按钮在场)。模式由入口固定,
      // 面板内不再有切换器。「1 5 9」→ [1,5,9] 解析由 parseAccountIndices 单测覆盖;
      // addAccounts([1,5,9]) 落库效果由 wallet_multi_account_test 覆盖。
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddAccountSheet(
              masterId: '0xmaster',
              mode: AddAccountMode.specify,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 指定序号模式直接露出序号输入框(面板内不再有模式切换器)。
      expect(find.text('添加指定账户'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '1 5 9');
      await tester.pump();

      expect(find.text('1 5 9'), findsOneWidget);
      expect(find.text('确认添加'), findsOneWidget);
    });
  });
}
