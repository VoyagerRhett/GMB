import 'dart:async';

import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/qr/bodies/user_contact_body.dart';
import 'package:citizenapp/qr/bodies/user_transfer_body.dart';
import 'package:citizenapp/qr/bodies/account_id_code_body.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_router.dart';
import 'package:citizenapp/qr/scan_dispatch_flow.dart';
import 'package:citizenapp/signer/qr_signer.dart';
import 'package:citizenapp/rpc/chain_rpc.dart';
import 'package:citizenapp/rpc/smoldot_client.dart';
import 'package:citizenapp/transaction/history/data/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/ui/widgets/shimmer_loading.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/wallet/core/wallet_manager.dart';
import 'package:citizenapp/wallet/core/default_account_service.dart';
import 'package:citizenapp/wallet/pages/account_detail_page.dart';
import 'package:citizenapp/wallet/pages/create_wallet_flow.dart';
import 'package:citizenapp/wallet/widgets/add_account_sheet.dart';
import 'package:citizenapp/wallet/widgets/wallet_action_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_identity_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_onchain_balance_card.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';
import 'package:citizenapp/transaction/history/chain/wallet_transaction_history_sync.dart';
import 'package:citizenapp/ui/app_layout.dart';

class WalletTab extends StatefulWidget {
  const WalletTab({
    super.key,
    this.selectForTrade = false,
    this.snapshotLoader,
    this.afterSnapshotLoaded,
    this.finalizedBalancesLoader,
    this.balanceWriter,
    this.onBalanceRefreshingChanged,
    this.defaultAccountReorderCommitter,
    this.deleteWalletAction,
    this.deleteAccountAction,
    this.signAndDeleteWalletAction,
    this.clearingBankClearer,
    this.walletCleanupPlanRetrier,
    this.walletCleanupPlanAcknowledger,
    this.pendingWalletCleanupPlansLoader,
  });

  final bool selectForTrade;

  /// Widget 测试专用的本地钱包快照读取入口；生产环境固定为空并读取真实钱包仓库。
  @visibleForTesting
  final Future<WalletPageSnapshot> Function()? snapshotLoader;

  /// Widget 测试专用的成功后回调；未注入余额读取器时用于隔离身份和轻节点后台刷新。
  @visibleForTesting
  final Future<void> Function(List<WalletProfile> wallets)? afterSnapshotLoaded;

  /// Widget 测试专用的 finalized 余额读取器，用可控 Future 验证刷新所有权交接。
  @visibleForTesting
  final Future<Map<String, double>> Function(List<String> accountIds)?
      finalizedBalancesLoader;

  /// Widget 测试专用的余额写入器，避免并发测试改动真实钱包仓库。
  @visibleForTesting
  final Future<bool> Function(
    int walletIndex,
    String accountId,
    int walletsRevision,
    double balance,
  )? balanceWriter;

  /// Widget 测试专用的刷新状态观察器，用于证明旧 owner 无权清理新 owner 的状态。
  @visibleForTesting
  final ValueChanged<bool>? onBalanceRefreshingChanged;

  /// Widget 测试专用的默认账户提交器，用可控 Future 制造冷签等待与快照交错。
  @visibleForTesting
  final Future<void> Function(
    List<DefaultAccount> before,
    List<DefaultAccount> target,
  )? defaultAccountReorderCommitter;

  /// Widget 测试专用的钱包删除入口；生产环境固定调用 [WalletManager.deleteWallet]。
  @visibleForTesting
  final Future<WalletDeletionResult> Function(
    int walletIndex,
    String expectedAccountId,
  )? deleteWalletAction;

  /// Widget 测试专用的账户删除入口；生产环境固定调用 [WalletManager.deleteAccount]。
  @visibleForTesting
  final Future<WalletDeletionResult> Function(String accountId)?
      deleteAccountAction;

  /// Widget 测试专用的热钱包签名删除入口。
  @visibleForTesting
  final Future<WalletDeletionResult> Function({
    required int walletIndex,
    required String accountId,
  })? signAndDeleteWalletAction;

  /// Widget 测试专用的清算行缓存清理入口；生产环境固定调用
  /// [ClearingBankPrefs.clear]。
  @visibleForTesting
  final Future<void> Function(String accountId)? clearingBankClearer;

  @visibleForTesting
  final Future<void> Function(WalletCleanupPlan plan)? walletCleanupPlanRetrier;

  @visibleForTesting
  final Future<void> Function(String planId)? walletCleanupPlanAcknowledger;

  @visibleForTesting
  final Future<List<WalletCleanupPlan>> Function()?
      pendingWalletCleanupPlansLoader;

  @override
  State<WalletTab> createState() => _WalletTabState();
}

/// 钱包页一次完整、可提交的本地快照。
///
/// 三份数据必须全部读取成功才替换页面现有快照，避免刷新中途失败时把已展示的钱包
/// 误清成空列表。该类型也让 Widget 测试可以精确控制首次加载和刷新时序。
@visibleForTesting
class WalletPageSnapshot {
  WalletPageSnapshot({
    required List<WalletProfile> wallets,
    required List<Account> accounts,
    required List<DefaultAccount> defaultAccounts,
    required this.walletsRevision,
    required this.usableHotWalletAccountId,
  })  : wallets = List<WalletProfile>.unmodifiable(wallets),
        accounts = List<Account>.unmodifiable(accounts),
        defaultAccounts = List<DefaultAccount>.unmodifiable(defaultAccounts),
        monitoredAccounts = WalletManager.transactionMonitorAccountsForFacts(
          wallets,
          accounts,
        );

  final List<WalletProfile> wallets;
  final List<Account> accounts;
  final List<DefaultAccount> defaultAccounts;
  final int walletsRevision;
  final String? usableHotWalletAccountId;
  final Map<String, String> monitoredAccounts;
}

const int _walletSnapshotReadMaxAttempts = 3;

/// 在同一个钱包数据版本内读取钱包、热账户、默认账户三段事实。
///
/// 三段读取之间发生钱包增删、改名或默认账户变更时，本轮结果可能混入两代数据，必须
/// 整体丢弃并重读；重试次数有上限，避免持续写入时让页面加载永久占住异步队列。
@visibleForTesting
Future<WalletPageSnapshot> readConsistentWalletPageSnapshot({
  required int Function() revisionReader,
  bool Function()? mutationActiveReader,
  Future<void> Function()? mutationSettledWaiter,
  required Future<List<WalletProfile>> Function() walletsLoader,
  required Future<List<Account>> Function(List<WalletProfile> wallets)
      accountsLoader,
  required Future<List<DefaultAccount>> Function() defaultAccountsLoader,
  required Future<String?> Function(
    List<WalletProfile> wallets,
    List<Account> accounts,
  ) usableHotWalletAccountIdLoader,
  int maxAttempts = _walletSnapshotReadMaxAttempts,
}) async {
  if (maxAttempts <= 0) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', '必须大于 0');
  }
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    // 事实变更门禁开启时，Isar 可能已写但硬件钥仍未完成或正准备回滚；本轮连读
    // 都不能开始，更不能因为首尾 revision 暂时相同而提交中间态。
    if (mutationActiveReader?.call() ?? false) {
      final waiter = mutationSettledWaiter;
      if (waiter != null) await waiter();
      if (mutationActiveReader?.call() ?? false) continue;
    }
    final revisionBefore = revisionReader();
    final wallets = await walletsLoader();
    final accounts = await accountsLoader(wallets);
    final defaultAccounts = await defaultAccountsLoader();
    final usableHotWalletAccountId =
        await usableHotWalletAccountIdLoader(wallets, accounts);
    final revisionAfter = revisionReader();
    if (!(mutationActiveReader?.call() ?? false) &&
        revisionBefore == revisionAfter) {
      return WalletPageSnapshot(
        wallets: wallets,
        accounts: accounts,
        defaultAccounts: defaultAccounts,
        walletsRevision: revisionAfter,
        usableHotWalletAccountId: usableHotWalletAccountId,
      );
    }
  }
  throw StateError('钱包数据在读取期间持续变化，请重试');
}

/// 钱包页本地快照的四个互斥状态。
///
/// 刷新失败与首次失败必须分开：前者仍有可信的上次成功快照，后者没有任何数据可供
/// “＋”入口判断能力，绝不能把未知状态伪装成“没有热钱包”。
enum _WalletLoadState {
  initialLoading,
  success,
  initialFailure,
  refreshFailure,
}

/// 钱包列表异常行单源判定。
///
/// 非法 `signMode` 过去既不算热钱包也不算冷钱包，会被列表过滤，却仍会参与重复检查，
/// 形成“提示已存在但页面看不到”。现在账户、地址、冷热类型任一异常都必须显示为异常行。
@visibleForTesting
bool isBrokenWalletProfile(WalletProfile wallet) {
  if (!isAccountIdText(wallet.accountId)) return true;
  if (!wallet.isHotWallet && !wallet.isColdWallet) return true;
  return wallet.ss58Address != ss58FromAccountIdText(wallet.accountId);
}

/// 导入冷钱包扫码只提取 SS58 展示地址；
/// 不在这里触发导入，避免用户还没确认就写入本地钱包库。
@visibleForTesting
String? extractColdWalletImportAddress(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }

  final result = QrRouter().route(text);
  switch (result.type) {
    // 三种码都只声明 account_id;SS58 是展示形态,一律在本机派生。
    case QrRouteType.userContact:
      final body = result.envelope!.body as UserContactBody;
      return ss58FromAccountIdText(body.accountId);
    case QrRouteType.userTransfer:
      final body = result.envelope!.body as UserTransferBody;
      return ss58FromAccountIdText(body.accountId);
    case QrRouteType.accountIdCode:
      // 冷钱包账户详情出的就是账户码：只含 account_id。
      final body = result.envelope!.body as AccountIdCodeBody;
      return ss58FromAccountIdText(body.accountId);
    case QrRouteType.signRequest:
    case QrRouteType.signResponse:
    case QrRouteType.accountDataKeyResponse:
    case QrRouteType.unknown:
      return null;
  }
}
/// 钱包列表页（单列横向卡片）：
/// - 正常态：唯一热钱包的 `//index` 账户行 + 冷钱包行并列，点账户行进账户详情，
///   点冷钱包行进冷钱包详情；
/// - 选择交易钱包态（selectForTrade）：按钱包整只选择付款钱包，沿用 WalletProfile 行；
/// - 钱包/账户图标按冷热配色：热=墨绿主色 / 冷=蓝(离线签名设备调性)；
/// - 冷钱包行保留既有行为；热钱包账户行的竖三点菜单提供
///   「扫一扫 / 重命名 / 删除钱包或删除账户」，整卡点击进入账户详情。
class _WalletTabState extends State<WalletTab> {
  final WalletManager _walletService = WalletManager();
  late final DefaultAccountService _defaultAccountService =
      DefaultAccountService(walletManager: _walletService);
  final ChainRpc _chainRpc = ChainRpc();

  /// 拖拽要求同步可控的列表，FutureBuilder 异步流不便参与重排，
  /// 因此把钱包列表常驻在 state 上，加载完成后再 setState 触发渲染。
  List<WalletProfile>? _wallets;

  /// 唯一热钱包（masterId = 账户0.accountId）下的全部 `//index` 账户（含账户0）。
  /// 「我的钱包」正常态把它们逐个成行展示，与冷钱包 WalletProfile 行并列。
  List<Account> _accounts = const <Account>[];
  List<DefaultAccount> _defaultAccounts = const <DefaultAccount>[];
  int _walletsRevision = 0;
  String? _usableHotWalletAccountId;
  _WalletLoadState _walletLoadState = _WalletLoadState.initialLoading;
  Object? _walletLoadError;
  int _walletLoadGeneration = 0;
  int _walletSnapshotCommitSequence = 0;
  int _defaultAccountMutationSequence = 0;
  int? _defaultAccountMutationOwner;
  int _balanceRefreshOwnerSequence = 0;
  int? _balanceRefreshOwner;
  ({
    int generation,
    int walletsRevision,
    List<WalletProfile>? wallets,
  })? _pendingBalanceRefresh;
  bool _balanceRefreshing = false;
  bool _accountMutationInProgress = false;
  Map<String, WalletCleanupPlan> _pendingWalletCleanupPlans =
      const <String, WalletCleanupPlan>{};
  bool _pendingWalletCleanupInProgress = false;
  int _walletCleanupSequence = 0;
  String? _identityAccountId;
  DateTime? _lastWalletStoreSnackAt;

  bool get _isSelectionMode => widget.selectForTrade;

  /// 只有至少成功读取过一次本地快照，才能根据真实热钱包事实打开入口菜单。
  bool get _canOpenWalletEntryChooser =>
      _wallets != null && !_accountMutationInProgress;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  /// 每个主动重载领取独立代次；只有最新代次可以提交快照、错误态或后续副作用。
  int _nextWalletLoadGeneration() => ++_walletLoadGeneration;

  bool _isCurrentWalletLoad(int generation) =>
      mounted && generation == _walletLoadGeneration;

  Future<List<WalletProfile>?> _loadWallets({
    required int generation,
    bool showSnack = true,
  }) async {
    if (!_isCurrentWalletLoad(generation)) return null;
    final hadSuccessfulSnapshot = _wallets != null;
    if (!hadSuccessfulSnapshot &&
        _walletLoadState != _WalletLoadState.initialLoading) {
      setState(() {
        _walletLoadState = _WalletLoadState.initialLoading;
        _walletLoadError = null;
      });
    }
    try {
      final snapshot =
          await (widget.snapshotLoader?.call() ?? _readWalletPageSnapshot());
      // 较旧请求即使后完成也必须成为完全无副作用的空操作。
      if (!_isCurrentWalletLoad(generation)) return null;
      setState(() {
        _wallets = snapshot.wallets;
        _accounts = snapshot.accounts;
        _defaultAccounts = snapshot.defaultAccounts;
        _walletsRevision = snapshot.walletsRevision;
        _usableHotWalletAccountId = snapshot.usableHotWalletAccountId;
        _walletSnapshotCommitSequence += 1;
        _walletLoadState = _WalletLoadState.success;
        _walletLoadError = null;
      });
      if (widget.snapshotLoader == null) {
        unawaited(_startWalletMonitoring(snapshot));
      }
      unawaited(_retryPendingWalletCleanup());
      return snapshot.wallets;
    } catch (e, st) {
      // 新请求已经开始后，旧失败不能覆盖新快照或把页面降级为失败态。
      if (!_isCurrentWalletLoad(generation)) return null;
      if (!WalletIsar.instance.isBusyError(e)) {
        AppLog.d('wallet local load failed: $e\n$st');
      }
      // 并发刷新中即使较早请求失败，也必须以当前是否已有成功快照判断故障类型。
      final hasSuccessfulSnapshot = _wallets != null;
      setState(() {
        _walletLoadError = e;
        _walletLoadState = hasSuccessfulSnapshot
            ? _WalletLoadState.refreshFailure
            : _WalletLoadState.initialFailure;
      });
      // 首次失败由整页错误态承载；已有数据刷新失败时保留页面并补一次轻提示。
      if (showSnack && hasSuccessfulSnapshot) {
        _showWalletStoreErrorOnce(
          e,
          message: '钱包刷新失败，已保留上次成功加载的数据',
        );
      }
      return null;
    }
  }

  /// 读取钱包、热钱包账户和统一默认账户顺序；任一环节失败都不产生半份快照。
  Future<WalletPageSnapshot> _readWalletPageSnapshot() async {
    return readConsistentWalletPageSnapshot(
      revisionReader: () => WalletManager.walletsRevision.value,
      mutationActiveReader: () => WalletManager.walletFactsMutationActive,
      mutationSettledWaiter: WalletManager.waitForWalletFactsMutationToSettle,
      walletsLoader: _walletService.getWallets,
      accountsLoader: (_) => _walletService.getAllAccounts(),
      defaultAccountsLoader: _defaultAccountService.getAccounts,
      usableHotWalletAccountIdLoader:
          _walletService.usableHotWalletAccountIdForFacts,
    );
  }

  /// 本地快照已经提交后再登记低优先级链监控；监控失败不得反向改变钱包加载状态。
  Future<void> _startWalletMonitoring(WalletPageSnapshot snapshot) async {
    try {
      await ChainTxMonitor.instance.replaceWatchedAccounts(
        snapshot.monitoredAccounts,
      );
      if (snapshot.monitoredAccounts.isNotEmpty) {
        await ChainTxMonitor.instance.start();
      }
    } on Object catch (error, stackTrace) {
      AppLog.d('[Wallet] 交易监控启动失败: $error\n$stackTrace');
    }
  }

  /// 拖动离手后按第一项是否变化选择授权路径。第一项不变时立即持久化；第一项变化
  /// 时只允许变化前的原默认账户签名，取消或失败均恢复原顺序。
  Future<void> _onDefaultAccountReorder(int oldIndex, int newIndex) async {
    if (_accountMutationInProgress || oldIndex == newIndex) return;
    final before = List<DefaultAccount>.of(_defaultAccounts);
    final target = List<DefaultAccount>.of(before);
    final moved = target.removeAt(oldIndex);
    target.insert(newIndex, moved);
    final beforeIds = before.map((account) => account.accountId).toList();
    final targetIds = target.map((account) => account.accountId).toList();

    // 本地拖拽已经产生比在途读取更新的页面事实，先废止旧请求，避免其在 revision
    // 最终提交前恰好返回并把乐观顺序覆盖回去。
    _nextWalletLoadGeneration();
    final mutationOwner = ++_defaultAccountMutationSequence;
    final snapshotCommitAtStart = _walletSnapshotCommitSequence;
    _defaultAccountMutationOwner = mutationOwner;
    setState(() {
      _accountMutationInProgress = true;
      _defaultAccounts = target;
    });
    var factsCommitted = false;
    try {
      final testCommitter = widget.defaultAccountReorderCommitter;
      if (testCommitter != null) {
        await testCommitter(before, target);
      } else {
        if (beforeIds.first == targetIds.first) {
          await _defaultAccountService
              .persistOrderWithoutDefaultChange(targetIds);
        } else {
          final genesisHash = await _chainRpc.fetchGenesisHash();
          final authorization = await _defaultAccountService.prepareSwitch(
            genesisHash: genesisHash,
            orderedAccountIds: targetIds,
          );
          if (authorization.currentDefaultAccount.isHotAccount) {
            await _defaultAccountService.authorizeHotAndPersist(authorization);
          } else {
            final request =
                _defaultAccountService.buildColdRequest(authorization);
            if (!mounted) return;
            final response =
                await Navigator.of(context).push<SignResponseEnvelope>(
              MaterialPageRoute(
                builder: (_) => QrSignSessionPage(
                  request: request,
                  requestJson: QrSigner().encodeRequest(request),
                  expectedSignerPublicKey:
                      authorization.currentDefaultAccount.accountId,
                ),
              ),
            );
            if (response == null) {
              throw const WalletAuthException('已取消默认账户切换');
            }
            await _defaultAccountService.authorizeColdAndPersist(
              authorization,
              response,
            );
          }
        }
      }
      factsCommitted = true;
      // 授权等待期间可能已有更新代次提交。成功路径不能继续保留任何乐观或插入的
      // 快照，必须从真实持久化事实再读完整三段后才结束 mutation。
      final reloaded = await _reloadLocalSnapshot(showSnack: false);
      if (reloaded == null) {
        throw StateError('默认账户顺序已提交，但钱包事实刷新失败，请重试刷新');
      }
      // 注入快照的 Widget 测试只验证钱包事实时序，不得旁路打开真实身份库；生产
      // 路径仍在最终持久化快照提交后重读身份标记。
      if (widget.snapshotLoader == null) {
        await _loadIdentityWallet();
      }
    } catch (error) {
      if (mounted) {
        // 只有当前 mutation 且期间没有更新快照提交时才能回滚；否则旧 before 会
        // 覆盖 reload 已提交的新账户事实。
        if (!factsCommitted &&
            _defaultAccountMutationOwner == mutationOwner &&
            _walletSnapshotCommitSequence == snapshotCommitAtStart) {
          setState(() => _defaultAccounts = before);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted && _defaultAccountMutationOwner == mutationOwner) {
        setState(() {
          _defaultAccountMutationOwner = null;
          _accountMutationInProgress = false;
        });
      }
    }
  }

  /// 与 WalletGate 同一代快照已验证的热钱包能力。build 不得根据字符串
  /// 重新猜测；重复 Hot、缺账户0、有壳无钥均必须返回 null。
  WalletProfile? _hotWallet(List<WalletProfile> wallets) {
    final accountId = _usableHotWalletAccountId;
    if (accountId == null) return null;
    final matches = wallets
        .where(
          (wallet) =>
              wallet.isHotWallet &&
              wallet.accountId == accountId &&
              !isBrokenWalletProfile(wallet),
        )
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> _reload() async {
    final generation = _nextWalletLoadGeneration();
    final wallets = await _loadWallets(generation: generation);
    // 本地快照失败时立即停下，禁止紧接着用身份/链读取再次探库并污染明确错误态。
    if (wallets == null ||
        !_isCurrentWalletLoad(generation) ||
        _isSelectionMode) {
      return;
    }
    final afterSnapshotLoaded = widget.afterSnapshotLoaded;
    if (afterSnapshotLoaded != null) {
      await afterSnapshotLoaded(wallets);
      // 普通 Widget 测试到此为止；余额并发测试注入读取器后继续走真实所有权流程。
      if (widget.finalizedBalancesLoader == null) return;
    } else {
      await _loadIdentityWallet(generation: generation);
    }
    if (!_isCurrentWalletLoad(generation)) return;
    await _refreshBalancesFromChain(
      wallets: wallets,
      generation: generation,
      walletsRevision: _walletsRevision,
    );
  }

  /// 只刷新本地快照的操作也必须领取新代次，用来废止仍在途的更早整页重载。
  Future<List<WalletProfile>?> _reloadLocalSnapshot({
    bool showSnack = true,
  }) {
    final generation = _nextWalletLoadGeneration();
    return _loadWallets(generation: generation, showSnack: showSnack);
  }

  Future<void> _loadIdentityWallet({int? generation}) async {
    try {
      final identity = await MyIdService(
        walletManager: _walletService,
      ).getState();
      if (!mounted ||
          (generation != null && !_isCurrentWalletLoad(generation))) {
        return;
      }
      setState(() {
        // 身份钱包标记 = CID 绑定账户(公民档取 votingAccountId);非公民不标记。
        _identityAccountId =
            identity.isCitizen ? identity.votingAccountId : null;
      });
    } catch (e) {
      if (!mounted ||
          (generation != null && !_isCurrentWalletLoad(generation))) {
        return;
      }
      AppLog.d('wallet identity marker load failed: $e');
      setState(() {
        _identityAccountId = null;
      });
    }
  }

  void _showWalletStoreErrorOnce(Object? error, {String? message}) {
    final now = DateTime.now();
    final last = _lastWalletStoreSnackAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastWalletStoreSnackAt = now;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message ?? walletLocalStoreErrorMessage(error))),
    );
  }

  Future<void> _refreshBalancesFromChain({
    List<WalletProfile>? wallets,
    required int generation,
    required int walletsRevision,
  }) async {
    if (!_isCurrentWalletLoad(generation)) return;
    final request = (
      generation: generation,
      walletsRevision: walletsRevision,
      wallets: wallets,
    );
    if (_balanceRefreshing) {
      assert(_balanceRefreshOwner != null);
      // RPC 不可取消；只保留最新页面代次的接管请求，旧 owner 完成后原子移交。
      final pending = _pendingBalanceRefresh;
      if (pending == null || generation >= pending.generation) {
        _pendingBalanceRefresh = request;
      }
      return;
    }

    final owner = ++_balanceRefreshOwnerSequence;
    setState(() {
      _balanceRefreshOwner = owner;
      _balanceRefreshing = true;
    });
    widget.onBalanceRefreshingChanged?.call(true);
    await _runBalanceRefresh(request: request, owner: owner);
  }

  bool _ownsBalanceRefresh({
    required int owner,
    required int generation,
    required int walletsRevision,
  }) {
    return mounted &&
        _balanceRefreshOwner == owner &&
        _walletLoadGeneration == generation &&
        _walletsRevision == walletsRevision;
  }

  Future<void> _runBalanceRefresh({
    required ({
      int generation,
      int walletsRevision,
      List<WalletProfile>? wallets,
    }) request,
    required int owner,
  }) async {
    final generation = request.generation;
    final walletsRevision = request.walletsRevision;
    Object? refreshError;
    try {
      // 生产环境先打印轻节点诊断；测试注入读取器时不启动真实轻节点。
      if (widget.finalizedBalancesLoader == null) {
        await SmoldotClientManager.instance.printDiagnostics();
      }

      var targetWallets = request.wallets ?? const <WalletProfile>[];
      bool updated = false;
      bool hasError = false;
      if (request.wallets == null) {
        try {
          targetWallets = await _walletService.getWallets();
        } catch (e, st) {
          if (!_ownsBalanceRefresh(
            owner: owner,
            generation: generation,
            walletsRevision: walletsRevision,
          )) {
            return;
          }
          if (!WalletIsar.instance.isBusyError(e)) {
            AppLog.d(
              'wallet local read before balance refresh failed: $e\n$st',
            );
          }
          refreshError = e;
          hasError = true;
        }
      }

      if (targetWallets.isEmpty) {
        // 无钱包，跳过
      } else {
        try {
          // 批量查询所有钱包 finalized 余额（一次网络请求）
          final accountIds = targetWallets.map((w) => w.accountId).toList();
          final balances = await (widget.finalizedBalancesLoader?.call(
                accountIds,
              ) ??
              _chainRpc.fetchFinalizedBalances(accountIds));
          // 新页面代次已经排队接管时，旧 RPC 结果不得开始任何本地写入。
          if (!_ownsBalanceRefresh(
            owner: owner,
            generation: generation,
            walletsRevision: walletsRevision,
          )) {
            return;
          }
          for (final wallet in targetWallets) {
            if (!_ownsBalanceRefresh(
              owner: owner,
              generation: generation,
              walletsRevision: walletsRevision,
            )) {
              return;
            }
            final balance = balances[wallet.accountId] ?? 0.0;
            if (balance != wallet.balance) {
              final committed = await (widget.balanceWriter?.call(
                    wallet.walletIndex,
                    wallet.accountId,
                    walletsRevision,
                    balance,
                  ) ??
                  _walletService.setWalletBalance(
                    walletIndex: wallet.walletIndex,
                    accountId: wallet.accountId,
                    expectedWalletsRevision: walletsRevision,
                    balance: balance,
                  ));
              if (!_ownsBalanceRefresh(
                owner: owner,
                generation: generation,
                walletsRevision: walletsRevision,
              )) {
                return;
              }
              updated = updated || committed;
            }
          }
        } catch (e) {
          if (!_ownsBalanceRefresh(
            owner: owner,
            generation: generation,
            walletsRevision: walletsRevision,
          )) {
            return;
          }
          AppLog.d('wallet batch balance refresh failed: $e');
          hasError = true;
          refreshError = e;
        }
      }
      if (!mounted ||
          _balanceRefreshOwner != owner ||
          _walletLoadGeneration != generation ||
          _walletsRevision != walletsRevision) {
        return;
      }
      if (updated) {
        await _loadWallets(generation: generation, showSnack: false);
        if (!mounted ||
            _balanceRefreshOwner != owner ||
            _walletLoadGeneration != generation ||
            _walletsRevision != walletsRevision) {
          return;
        }
      }
      if (hasError) {
        final msg = isWalletLocalStoreError(refreshError)
            ? walletLocalStoreErrorMessage(refreshError)
            : SmoldotClientManager.instance.buildUserFacingError(refreshError);
        if (isWalletLocalStoreError(refreshError)) {
          _showWalletStoreErrorOnce(refreshError);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } finally {
      _finishBalanceRefresh(owner);
    }
  }

  /// 只有当前 owner 可以结束刷新；若有更新代次等待，则保持 refreshing=true 原子交接。
  void _finishBalanceRefresh(int owner) {
    if (_balanceRefreshOwner != owner) return;
    final pending = _pendingBalanceRefresh;
    _pendingBalanceRefresh = null;
    if (mounted &&
        pending != null &&
        pending.generation == _walletLoadGeneration &&
        pending.walletsRevision == _walletsRevision) {
      final nextOwner = ++_balanceRefreshOwnerSequence;
      _balanceRefreshOwner = nextOwner;
      unawaited(_runBalanceRefresh(request: pending, owner: nextOwner));
      return;
    }

    _balanceRefreshOwner = null;
    if (mounted) {
      setState(() {
        _balanceRefreshing = false;
      });
      widget.onBalanceRefreshingChanged?.call(false);
    } else {
      _balanceRefreshing = false;
    }
  }

  /// 非法签名模式不能进入任何签名路径。用户可用本机受保护私钥验证为热钱包；
  /// 冷钱包必须从“导入冷钱包”重新扫描同一账户，不能仅凭缺少本机私钥猜测。
  Future<void> _repairBrokenWallet(WalletProfile wallet) async {
    if (_accountMutationInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('验证热钱包'),
        content: const Text(
          '仅当该账户私钥保存在本机时才能验证为热钱包。'
          '如果这是冷钱包，请取消并从“导入冷钱包”重新扫描同一账户。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('验证'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _nextWalletLoadGeneration();
    setState(() => _accountMutationInProgress = true);
    try {
      final genesisHash = await _chainRpc.fetchGenesisHash();
      await _walletService.repairHotSignMode(
        walletIndex: wallet.walletIndex,
        accountId: wallet.accountId,
        genesisHash: genesisHash,
      );
      await _reloadLocalSnapshot(showSnack: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已验证为热钱包')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('热钱包验证失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _accountMutationInProgress = false);
      }
    }
  }

  /// 删除确认后的统一互斥门禁。立即废止旧 load generation、余额 owner 和等待接管，
  /// 使删除前启动的异步结果失去所有页面写权限；三条删除路径只能有一条进入。
  Future<bool> _beginConfirmedWalletMutation() async {
    if (!mounted || _accountMutationInProgress) return false;
    _nextWalletLoadGeneration();
    _pendingBalanceRefresh = null;
    _balanceRefreshOwnerSequence += 1;
    _balanceRefreshOwner = null;
    final wasBalanceRefreshing = _balanceRefreshing;
    setState(() {
      _accountMutationInProgress = true;
      _balanceRefreshing = false;
    });
    if (wasBalanceRefreshing) {
      widget.onBalanceRefreshingChanged?.call(false);
    }
    try {
      // token 先在 replace 内同步废止，再等待旧任务全部 drain。删除事务
      // 只能在此后开始，因此旧任务已排队的写入要么先完成后被删，要么被 token 拒绝。
      await ChainTxMonitor.instance.replaceWatchedAccounts(
        const <String, String>{},
      );
    } on Object catch (error, stackTrace) {
      AppLog.d('[Wallet] 删除前交易监控排空失败: $error\n$stackTrace');
      _finishConfirmedWalletMutation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除未开始：交易监控尚未安全停止，$error')),
        );
      }
      return false;
    }
    return true;
  }

  void _finishConfirmedWalletMutation() {
    if (!mounted || !_accountMutationInProgress) return;
    setState(() => _accountMutationInProgress = false);
  }

  /// 钱包事实确认删除后，按事务内持久计划重试全部安全材料与清算行缓存。只有计划中
  /// 每一项都完成并回读不存在后才 ack；任一失败都保留整项计划供新页面继续重试。
  Future<Object?> _completeWalletCleanupPlans({
    required Iterable<WalletCleanupPlan> plans,
    required Object? existingError,
    WalletDeletionResult? deletionResult,
  }) async {
    final failures = <String>[];
    var cleanupFailed = false;
    final targets = <String, WalletCleanupPlan>{
      for (final plan in plans) plan.planId: plan,
    };
    if (mounted && targets.isNotEmpty) {
      setState(() {
        _walletCleanupSequence += 1;
        _pendingWalletCleanupPlans = <String, WalletCleanupPlan>{
          ..._pendingWalletCleanupPlans,
          ...targets,
        };
      });
    }
    for (final plan in targets.values) {
      var planReady = true;
      try {
        await (widget.walletCleanupPlanRetrier?.call(plan) ??
            _walletService.retryWalletCleanupPlan(plan));
      } on Object catch (error) {
        planReady = false;
        cleanupFailed = true;
        failures.add('钱包安全清理(${plan.planId})：$error');
      }

      // 核心安全清理未完成时，账户 ID 仍被计划占用且可能随后重现；此时绝不能清
      // 同 accountId 的清算行缓存。保留整项计划，下次从持久真源重新执行。
      if (!planReady) continue;

      for (final accountId in plan.accountIds) {
        try {
          await (widget.clearingBankClearer?.call(accountId) ??
              ClearingBankPrefs.clear(accountId));
        } on Object catch (error) {
          planReady = false;
          cleanupFailed = true;
          failures.add('清算行缓存($accountId)：$error');
        }
      }

      if (!planReady) continue;
      try {
        await (widget.walletCleanupPlanAcknowledger?.call(plan.planId) ??
            _walletService.acknowledgeWalletCleanupPlan(plan.planId));
        if (mounted) {
          setState(() {
            _walletCleanupSequence += 1;
            _pendingWalletCleanupPlans =
                Map<String, WalletCleanupPlan>.of(_pendingWalletCleanupPlans)
                  ..remove(plan.planId);
          });
        }
      } on Object catch (error) {
        cleanupFailed = true;
        failures.add('确认钱包清理计划(${plan.planId})：$error');
      }
    }
    if (!cleanupFailed) {
      return existingError is WalletLocalCleanupException
          ? null
          : existingError;
    }
    if (existingError != null &&
        existingError is! WalletLocalCleanupException) {
      failures.insert(0, '钱包后续清理：$existingError');
    }
    return WalletLocalCleanupException(
      List<String>.unmodifiable(failures),
      deletionResult: deletionResult,
    );
  }

  /// 页面加载与显式按钮共用的持久计划重试；页面销毁/重建后仍以 Wallet typed 状态恢复。
  Future<void> _retryPendingWalletCleanup({bool explicit = false}) async {
    if (_pendingWalletCleanupInProgress) return;
    _pendingWalletCleanupInProgress = true;
    final loadOwner = _walletCleanupSequence;
    Object? error;
    try {
      final pending = await (widget.pendingWalletCleanupPlansLoader?.call() ??
          _walletService.getPendingWalletCleanupPlans());
      if (!mounted) return;
      setState(() {
        final loaded = <String, WalletCleanupPlan>{
          for (final plan in pending) plan.planId: plan,
        };
        // 较早读取不能用空结果覆盖其等待期间刚由删除事务提交的新计划。
        _pendingWalletCleanupPlans = loadOwner == _walletCleanupSequence
            ? loaded
            : <String, WalletCleanupPlan>{
                ..._pendingWalletCleanupPlans,
                ...loaded,
              };
      });
      if (pending.isNotEmpty) {
        error = await _completeWalletCleanupPlans(
          plans: pending,
          existingError: null,
        );
      }
    } on Object catch (caught, stackTrace) {
      error = caught;
      AppLog.d('[Wallet] 读取/重试待清理缓存失败: $caught\n$stackTrace');
    } finally {
      _pendingWalletCleanupInProgress = false;
    }
    if (!mounted || !explicit) return;
    final message = error == null ? '待清理缓存已全部处理' : '部分后续清理仍未完成：$error';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 删除调用返回后，以一致快照中的事实决定文案；异常类型只能解释原因，不能替代事实确认。
  void _showDeleteOutcome({
    required ScaffoldMessengerState messenger,
    required String factLabel,
    required String successMessage,
    required Object? error,
    required bool? factRemoved,
  }) {
    late final String message;
    if (factRemoved == null) {
      final loadMessage = walletLocalStoreErrorMessage(_walletLoadError);
      message = error == null
          ? '删除结果暂时无法确认：$loadMessage，请重试刷新'
          : '删除出现异常且本地事实暂时无法确认：$error；$loadMessage';
    } else if (error == null) {
      message = factRemoved ? successMessage : '删除未完成：$factLabel仍存在';
    } else if (!factRemoved) {
      message = '删除未完成：$error';
    } else if (error is WalletLocalCleanupException) {
      message = '$factLabel事实已移除，但本机安全清理未完成：'
          '${error.failures.join('；')}';
    } else {
      message = '$factLabel事实已移除，但后续本机清理未完成：$error';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 删除钱包：二次确认 + 调用 WalletManager.deleteWallet + 重新加载列表。
  Future<void> _deleteWallet(WalletProfile wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除钱包'),
        content: Text('确认删除「${wallet.walletName}」？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _beginConfirmedWalletMutation()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      Object? deleteError;
      WalletDeletionResult? deletionResult;
      try {
        deletionResult = await (widget.deleteWalletAction?.call(
              wallet.walletIndex,
              wallet.accountId,
            ) ??
            _walletService.deleteWallet(
              walletIndex: wallet.walletIndex,
              expectedAccountId: wallet.accountId,
            ));
      } catch (error) {
        deleteError = error;
        if (error is WalletLocalCleanupException) {
          deletionResult = error.deletionResult;
        }
      }
      if (!mounted) return;
      if (deletionResult?.factCommitted == true) {
        deleteError = await _completeWalletCleanupPlans(
          plans: deletionResult!.cleanupPlans,
          existingError: deleteError,
          deletionResult: deletionResult,
        );
      }
      await _reloadLocalSnapshot(showSnack: false);
      if (!mounted) return;
      _showDeleteOutcome(
        messenger: messenger,
        factLabel: '钱包「${wallet.walletName}」',
        successMessage: '已删除「${wallet.walletName}」',
        error: deleteError,
        factRemoved: deletionResult?.factCommitted ?? false,
      );
    } finally {
      _finishConfirmedWalletMutation();
    }
  }

  /// 重命名钱包：弹 AlertDialog + TextField，确认后落盘并重新加载列表。
  Future<void> _renameWallet(WalletProfile wallet) async {
    final controller = TextEditingController(text: wallet.walletName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名钱包'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '输入新的钱包名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == wallet.walletName) {
      return;
    }
    try {
      // 钱包名是纯本机标签，不发布为公开昵称，也不读取资料服务。
      await _walletService.renameWallet(wallet.walletIndex, newName);
      if (!mounted) return;
      await _reloadLocalSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  /// 点账户行或菜单“账户详情”进入同一页面。
  Future<void> _openAccountDetail(Account account) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AccountDetailPage(account: account)),
    );
    if (changed == true) {
      await _reload();
    }
  }

  /// 账户标签只写 AccountEntity.accountName，不联动钱包名或链上昵称。
  Future<void> _renameAccount(Account account) async {
    final controller = TextEditingController(text: account.accountName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名账户'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '输入新的账户名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null ||
        newName.isEmpty ||
        newName == account.accountName ||
        !mounted) {
      return;
    }
    try {
      await _walletService.renameAccount(account.accountId, newName);
      if (!mounted) return;
      await _reloadLocalSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  /// 账户卡扫码只接受签名请求，并把签名账户钉死为当前卡片 account_id。
  Future<void> _scanSignForAccount(Account account) async {
    await openAccountScanSignFlow(context: context, account: account);
  }

  /// 菜单删除唯一入口：账户0签名后删整钱包；其它账户不弹窗直接删除。
  Future<void> _deleteAccountFromMenu(
    Account account,
    WalletProfile hotWallet,
  ) async {
    if (_accountMutationInProgress) return;
    if (account.accountIndex == 0) {
      await _confirmAndDeleteHotWallet(account, hotWallet);
      return;
    }

    if (!await _beginConfirmedWalletMutation()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      Object? deleteError;
      WalletDeletionResult? deletionResult;
      try {
        deletionResult = await (widget.deleteAccountAction?.call(
              account.accountId,
            ) ??
            _walletService.deleteAccount(account.accountId));
      } catch (e) {
        deleteError = e;
        if (e is WalletLocalCleanupException) {
          deletionResult = e.deletionResult;
        }
      }
      if (!mounted) return;
      if (deletionResult?.factCommitted == true) {
        deleteError = await _completeWalletCleanupPlans(
          plans: deletionResult!.cleanupPlans,
          existingError: deleteError,
          deletionResult: deletionResult,
        );
      }
      await _reloadLocalSnapshot(showSnack: false);
      if (!mounted) return;
      _showDeleteOutcome(
        messenger: messenger,
        factLabel: '账户「${account.accountName}」',
        successMessage: '已删除账户「${account.accountName}」',
        error: deleteError,
        factRemoved: deletionResult?.factCommitted ?? false,
      );
    } finally {
      _finishConfirmedWalletMutation();
    }
  }

  Future<void> _confirmAndDeleteHotWallet(
    Account anchor,
    WalletProfile hotWallet,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除钱包'),
        content: Text(
          '删除「${hotWallet.walletName}」会从本设备移除该钱包下全部 ${_accounts.length} 个账户、'
          '私钥、交易记录和清算行缓存。\n\n请确认已经备份助记词，此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('签名并删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _beginConfirmedWalletMutation()) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      Object? deleteError;
      WalletDeletionResult? deletionResult;
      try {
        final testAction = widget.signAndDeleteWalletAction;
        if (testAction != null) {
          deletionResult = await testAction(
            walletIndex: hotWallet.walletIndex,
            accountId: anchor.accountId,
          );
        } else {
          deletionResult = await _walletService.signAndDeleteWallet(
            walletIndex: hotWallet.walletIndex,
            accountId: anchor.accountId,
          );
        }
      } catch (e) {
        deleteError = e;
        if (e is WalletLocalCleanupException) {
          deletionResult = e.deletionResult;
        }
      }
      if (!mounted) return;
      if (deletionResult?.factCommitted == true) {
        deleteError = await _completeWalletCleanupPlans(
          plans: deletionResult!.cleanupPlans,
          existingError: deleteError,
          deletionResult: deletionResult,
        );
      }
      await _reloadLocalSnapshot(showSnack: false);
      if (!mounted) return;
      _showDeleteOutcome(
        messenger: messenger,
        factLabel: '钱包「${hotWallet.walletName}」',
        successMessage: '已删除钱包「${hotWallet.walletName}」',
        error: deleteError,
        factRemoved: deletionResult?.factCommitted ?? false,
      );
    } finally {
      _finishConfirmedWalletMutation();
    }
  }

  Future<void> _openImportColdWalletPage() async {
    if (_accountMutationInProgress) return;
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportColdWalletPage()),
    );
    if (imported == true) {
      await _reload();
    }
  }

  Future<void> _openWalletDetail(WalletProfile wallet) async {
    if (widget.selectForTrade) {
      await _walletService.setActiveWallet(wallet.walletIndex);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => WalletDetailPage(wallet: wallet)),
    );
    if (mounted) {
      // 返回来源无论是按钮、系统返回还是 iOS 左边缘手势都统一重读，避免通过
      // 返回值拦截原生手势，同时保证钱包名等本机修改立即回刷。
      await _reload();
    }
  }

  /// 「＋」入口三项：添加下一个账户 / 添加指定账户 / 导入冷钱包。
  ///
  /// 热钱包（创建 / 导入助记词）唯一引导在首启门禁页（[CreateWalletOnboardingPage]）
  /// 完成——一台设备一只热钱包，此处不再提供热钱包创建入口；追加账户收在本入口的两个
  /// 添加项（对齐 CitizenWallet 冷端做法）。冷钱包只存公钥、可与热钱包账户并列，保留入口。
  Future<void> _showWalletEntryChooser() async {
    // 首次加载中/失败时没有可信快照；即使被程序化调用也不得打开伪造的冷钱包菜单。
    if (!_canOpenWalletEntryChooser || _accountMutationInProgress) return;
    // 存在热钱包才提供「添加账户」两项;masterId = 热钱包账户0 的 accountId。
    final hot = _hotWallet(_wallets!);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => WalletEntryChooserSheet(
        canAddAccount: hot != null,
        onAddNextAccount: () {
          Navigator.of(context).pop();
          if (hot != null) {
            _openAddAccount(hot.accountId, AddAccountMode.next);
          }
        },
        onAddSpecifyAccount: () {
          Navigator.of(context).pop();
          if (hot != null) {
            _openAddAccount(hot.accountId, AddAccountMode.specify);
          }
        },
        onImportCold: () {
          Navigator.of(context).pop();
          _openImportColdWalletPage();
        },
      ),
    );
  }

  /// 在唯一热钱包下按 [mode] 追加账户;成功后整页刷新并提示。
  Future<void> _openAddAccount(String masterId, AddAccountMode mode) async {
    if (_accountMutationInProgress) return;
    final added = await showAddAccountSheet(
      context,
      masterId: masterId,
      mode: mode,
    );
    if (added != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _reload();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已添加账户')));
  }

  /// 空态：热钱包由首启门禁强制创建，走不到这里没有热钱包的情况；此处只提供
  /// 「导入冷钱包」入口（仅公钥、只读，可与热钱包账户并列）。
  Widget _buildEmptyWalletChoices() {
    return WalletEmptyChoices(onImportCold: _openImportColdWalletPage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectForTrade ? '选择交易钱包' : '我的钱包'),
        centerTitle: true,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              key: const ValueKey('wallet-add-entry'),
              tooltip: '添加账户 / 导入冷钱包',
              onPressed:
                  _canOpenWalletEntryChooser ? _showWalletEntryChooser : null,
              icon: Icon(Icons.add, size: AppLayout.scaled(context, 26)),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_walletLoadState == _WalletLoadState.initialLoading) {
            return Padding(
              padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
              child: ListSkeleton(
                itemCount: 3,
                itemBuilder: (_, __) => const WalletCardSkeleton(),
              ),
            );
          }
          if (_walletLoadState == _WalletLoadState.initialFailure) {
            return _buildInitialLoadFailure();
          }
          final wallets = _wallets!;
          final content = _isSelectionMode
              ? _buildSelectionList(wallets)
              : _buildMyWalletList(wallets);
          if (_walletLoadState != _WalletLoadState.refreshFailure) {
            return content;
          }
          return Column(
            children: [
              _buildRefreshFailureBanner(),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  /// 首次没有任何可信钱包快照时的失败页；重试会重新进入骨架加载态。
  Widget _buildInitialLoadFailure() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppLayout.scaledValue(24)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
            const SizedBox(height: 12),
            const Text(
              '钱包加载失败',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              walletLocalStoreErrorMessage(_walletLoadError),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('wallet-initial-load-retry'),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 已有成功快照刷新失败时保留原列表，只在顶部明确提示数据来自上次成功读取。
  Widget _buildRefreshFailureBanner() {
    return Material(
      color: AppTheme.warning.withAlpha(20),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('钱包刷新失败，正在显示上次成功加载的数据'),
              ),
              TextButton(
                key: const ValueKey('wallet-refresh-retry'),
                onPressed: _reload,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择交易钱包模式：按钱包（walletIndex）选付款钱包，沿用旧的 WalletProfile 列表
  /// （账户级付款选择不在本任务范围内）。点选即设为 active 并回传。
  Widget _buildSelectionList(List<WalletProfile> wallets) {
    if (wallets.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: _buildEmptyWalletChoices(),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: wallets.length,
      itemBuilder: (ctx, idx) {
        final wallet = wallets[idx];
        final isBroken = isBrokenWalletProfile(wallet);
        return Padding(
          key: ValueKey('wallet_${wallet.walletIndex}'),
          padding: EdgeInsets.only(bottom: AppLayout.scaledValue(8)),
          child: WalletListTile(
            wallet: wallet,
            showActions: false,
            isIdentityWallet:
                !isBroken && wallet.accountId == _identityAccountId,
            isBroken: isBroken,
            onTap: () => isBroken
                ? unawaited(_repairBrokenWallet(wallet))
                : _openWalletDetail(wallet),
            onRename: () => _renameWallet(wallet),
            onDelete: () => _deleteWallet(wallet),
            actionsEnabled: !_accountMutationInProgress,
          ),
        );
      },
    );
  }

  /// 「我的钱包」正常态：全部有效热、冷账户严格按账户级唯一顺序展示。
  ///
  /// - 账户行（含账户0）点击进 [AccountDetailPage]；身份账户 = CID 绑定的那个账户。
  /// - 冷钱包行沿用旧 [WalletListTile] 详情 / 重命名 / 删除行为，不受多账户改动影响。
  /// - 身份字段或签名模式损坏的钱包单列显示，只能验证为 Hot、重新导入为 Cold 或删除。
  Widget _buildMyWalletList(List<WalletProfile> wallets) {
    final hot = _hotWallet(wallets);
    final brokenWallets =
        wallets.where(isBrokenWalletProfile).toList(growable: false);
    if (_defaultAccounts.isEmpty &&
        brokenWallets.isEmpty &&
        _pendingWalletCleanupPlans.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: _buildEmptyWalletChoices(),
      );
    }
    return RefreshIndicator(
      // 下拉刷新先重读完整本地快照；失败时保留现有数据，再由加载状态提示重试。
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_pendingWalletCleanupPlans.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Material(
                  key: const ValueKey('wallet-pending-cleanup-banner'),
                  color: AppTheme.warning.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('钱包事实已移除，但部分后续缓存清理尚未完成'),
                        ),
                        TextButton(
                          key: const ValueKey('wallet-pending-cleanup-retry'),
                          onPressed: _pendingWalletCleanupInProgress
                              ? null
                              : () => unawaited(
                                    _retryPendingWalletCleanup(
                                      explicit: true,
                                    ),
                                  ),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverReorderableList(
              itemCount: _defaultAccounts.length,
              // Flutter 3.44 的新回调已经把向下拖动的索引按移除后列表修正，
              // 这里直接消费目标索引，禁止再次减一导致账户落到错误位置。
              onReorderItem: _onDefaultAccountReorder,
              itemBuilder: (context, index) {
                final defaultAccount = _defaultAccounts[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('default_account_${defaultAccount.accountId}'),
                  index: index,
                  enabled: !_accountMutationInProgress,
                  child: _buildDefaultAccountRow(
                    defaultAccount,
                    hot: hot,
                    isDefault: index == 0,
                  ),
                );
              },
            ),
          ),
          if (brokenWallets.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.builder(
                itemCount: brokenWallets.length,
                itemBuilder: (context, index) {
                  final broken = brokenWallets[index];
                  return Padding(
                    key: ValueKey('wallet_${broken.walletIndex}'),
                    padding: EdgeInsets.only(bottom: AppLayout.scaledValue(8)),
                    child: WalletListTile(
                      wallet: broken,
                      showActions: true,
                      isBroken: true,
                      onTap: () => unawaited(_repairBrokenWallet(broken)),
                      onRename: () => _renameWallet(broken),
                      onDelete: () => _deleteWallet(broken),
                      actionsEnabled: !_accountMutationInProgress,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultAccountRow(
    DefaultAccount defaultAccount, {
    required WalletProfile? hot,
    required bool isDefault,
  }) {
    final bottom = EdgeInsets.only(bottom: AppLayout.scaledValue(8));
    if (defaultAccount.isHotAccount) {
      Account? account;
      for (final row in _accounts) {
        if (row.accountId == defaultAccount.accountId) {
          account = row;
          break;
        }
      }
      if (account == null) return const SizedBox.shrink();
      final hotAccount = account;
      return Padding(
        padding: bottom,
        child: WalletAccountTile(
          account: hotAccount,
          isDefault: isDefault,
          isIdentity: hotAccount.accountId == _identityAccountId,
          onTap: () => _openAccountDetail(hotAccount),
          onScan: () => _scanSignForAccount(hotAccount),
          onRename: () => _renameAccount(hotAccount),
          onDelete: () {
            if (hot == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('未找到该账户所属钱包')),
              );
              return;
            }
            _deleteAccountFromMenu(hotAccount, hot);
          },
          actionsEnabled: !_accountMutationInProgress,
        ),
      );
    }
    WalletProfile? cold;
    for (final wallet in _wallets ?? const <WalletProfile>[]) {
      if (wallet.accountId == defaultAccount.accountId) {
        cold = wallet;
        break;
      }
    }
    if (cold == null) return const SizedBox.shrink();
    final coldAccount = cold;
    return Padding(
      padding: bottom,
      child: WalletListTile(
        wallet: coldAccount,
        showActions: true,
        isDefault: isDefault,
        isIdentityWallet: coldAccount.accountId == _identityAccountId,
        onTap: () => _openWalletDetail(coldAccount),
        onRename: () => _renameWallet(coldAccount),
        onDelete: () => _deleteWallet(coldAccount),
        actionsEnabled: !_accountMutationInProgress,
      ),
    );
  }
}

/// 「＋」入口底部面板：添加下一个账户 / 添加指定账户 / 导入冷钱包（导入冷钱包在最下）。
///
/// 热钱包（创建 / 导入助记词）入口不在此处——一台设备一只热钱包，其唯一引导在首启门禁页；
/// 此处不得出现「创建钱包」「导入热钱包」。存在热钱包时才提供两个添加账户项
/// （[canAddAccount]），追加走本钱包助记词校验归属，对齐 CitizenWallet 冷端做法。
///
/// 仅供 wallet_page 自己使用,通过 `@visibleForTesting` 暴露给 widget 测试。
@visibleForTesting
class WalletEntryChooserSheet extends StatelessWidget {
  const WalletEntryChooserSheet({
    super.key,
    required this.canAddAccount,
    required this.onAddNextAccount,
    required this.onAddSpecifyAccount,
    required this.onImportCold,
  });

  /// 存在热钱包时才提供「添加下一个账户 / 添加指定账户」两项。
  final bool canAddAccount;
  final VoidCallback onAddNextAccount;
  final VoidCallback onAddSpecifyAccount;
  final VoidCallback onImportCold;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canAddAccount) ...[
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('添加下一个账户'),
              subtitle: const Text('在本钱包下派生下一个序号账户',
                  style: TextStyle(color: AppTheme.textTertiary)),
              onTap: onAddNextAccount,
            ),
            ListTile(
              leading: const Icon(Icons.tag_rounded),
              title: const Text('添加指定账户'),
              subtitle: const Text('指定序号恢复本钱包下的特定账户',
                  style: TextStyle(color: AppTheme.textTertiary)),
              onTap: onAddSpecifyAccount,
            ),
          ],
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('导入冷钱包'),
            subtitle: const Text('仅导入公钥，私钥保留在签名设备',
                style: TextStyle(color: AppTheme.textTertiary)),
            onTap: onImportCold,
          ),
        ],
      ),
    );
  }
}

/// 空态选项：只提供「导入冷钱包」入口，同样不含热钱包创建 / 导入。
///
/// 仅供 wallet_page 自己使用,通过 `@visibleForTesting` 暴露给 widget 测试。
@visibleForTesting
class WalletEmptyChoices extends StatelessWidget {
  const WalletEmptyChoices({super.key, required this.onImportCold});

  final VoidCallback onImportCold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '还没有可展示的钱包。热钱包在首启时创建，这里可导入只读的冷钱包。',
          style: TextStyle(
              fontSize: AppLayout.scaled(context, 16),
              fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppLayout.scaled(context, 16)),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(18)),
            onTap: onImportCold,
            child: Ink(
              decoration: BoxDecoration(
                color: AppTheme.warning.withAlpha(15),
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(18)),
              ),
              child: Padding(
                padding: EdgeInsets.all(AppLayout.scaledValue(16)),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppTheme.warning),
                    SizedBox(width: AppLayout.scaled(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '导入冷钱包',
                            style: TextStyle(
                              fontSize: AppLayout.scaled(context, 15),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: AppLayout.scaled(context, 4)),
                          Text(
                            '仅导入公钥，签名在外部设备',
                            style: TextStyle(
                              fontSize: AppLayout.scaled(context, 12),
                              height: 1.45,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 单行钱包卡片（横向布局）：
/// 左侧 46×46 钱包图标(冷热分色) → 中间钱包名（默认标记紧邻名称右上侧）+ 千分位余额 →
/// 右侧三点菜单（重命名 / 删除）。
///
/// 整卡 InkWell 点击进入钱包详情；菜单按钮内嵌 PopupMenuButton，
/// Flutter 默认会拦截 tap 事件，不会冒泡触发整卡 onTap。
///
/// 仅供 wallet_page 自己使用,通过 `@visibleForTesting`
/// 暴露给 widget 测试。其他模块禁止直接引用。
@visibleForTesting
class WalletListTile extends StatelessWidget {
  const WalletListTile({
    super.key,
    required this.wallet,
    required this.showActions,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.isIdentityWallet = false,
    this.isDefault = false,
    this.isBroken = false,
    this.actionsEnabled = true,
  });

  final WalletProfile wallet;

  /// 选择模式下隐藏右侧菜单（避免误操作）。
  final bool showActions;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// 是否为链上唯一公民身份绑定的钱包。
  final bool isIdentityWallet;

  /// 账户级统一顺序第一项；它等于本机当前默认用户。
  final bool isDefault;

  /// accountId、SS58 或签名模式损坏：不显示余额，改显警示，点击进入严格重标确认。
  final bool isBroken;

  /// 删除/默认账户变更期间禁用菜单，禁止第二条写路径并发启动。
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context) {
    // 钱包图标按冷热区分配色 —— 热=墨绿主色(链上主用),冷=蓝(离线签名设备调性)。
    final isHot = wallet.isHotWallet;
    final iconBg =
        isHot ? AppTheme.primary.withAlpha(20) : AppTheme.info.withAlpha(20);
    final iconColor = isHot ? AppTheme.primaryDark : AppTheme.info;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          decoration: AppTheme.cardDecoration(radius: AppTheme.radiusMd),
          child: Row(children: [
            // 左：46×46 钱包图标（按冷热分色）
            Container(
              width: AppLayout.scaled(context, 46),
              height: AppLayout.scaled(context, 46),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: iconColor,
                size: AppLayout.scaled(context, 24),
              ),
            ),
            SizedBox(width: AppLayout.scaled(context, 12)),
            // 中：钱包名 + 千分位余额
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          wallet.walletName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 18),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        SizedBox(width: AppLayout.scaled(context, 4)),
                        Transform.translate(
                          offset: Offset(0, -AppLayout.scaled(context, 3)),
                          child: const _DefaultAccountLabel(),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: AppLayout.scaled(context, 4)),
                  // 坏行的余额没有意义（读不到身份就对不上链），改显警示。
                  if (isBroken)
                    Text(
                      '钱包数据异常，请验证热钱包或重新导入冷钱包',
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: AppLayout.scaled(context, 13),
                          color: AppTheme.warning),
                    )
                  else
                    Text(
                      AmountFormat.formatThousands(wallet.balance),
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 13),
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (isIdentityWallet) ...[
              SizedBox(width: AppLayout.scaled(context, 8)),
              const _WalletBadge(label: '身份钱包', icon: Icons.verified),
            ],
            // 右：三点菜单（仅非选择模式）
            if (showActions) ...[
              SizedBox(width: AppLayout.scaled(context, 4)),
              PopupMenuButton<String>(
                enabled: actionsEnabled,
                icon: Icon(
                  Icons.more_vert,
                  color: AppTheme.textTertiary,
                  size: AppLayout.scaled(context, 20),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      onRename();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除钱包',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _WalletBadge extends StatelessWidget {
  const _WalletBadge({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 8),
          vertical: AppLayout.scaled(context, 3)),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(24),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: AppLayout.scaled(context, 12),
                color: AppTheme.primaryDark),
            SizedBox(width: AppLayout.scaled(context, 3)),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 11),
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// 默认账户的纯文字标记：无人物图标、胶囊、内边距和点击占位。
class _DefaultAccountLabel extends StatelessWidget {
  const _DefaultAccountLabel();

  @override
  Widget build(BuildContext context) {
    // 标记属于名称行，只负责展示，不占用任何独立点击区域。
    return IgnorePointer(
      child: Text(
        '默认',
        maxLines: 1,
        style: TextStyle(
          fontSize: AppLayout.scaled(context, 11),
          height: 1,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryDark,
        ),
      ),
    );
  }
}

/// 单行账户卡片：唯一热钱包下某个 `//index` 账户。
///
/// 左侧序号徽标 → 账户名（默认标记紧邻名称右上侧）+ 短 SS58 → 身份徽标（如有）→
/// 竖三点。整卡点击进入账户详情；扫一扫收进菜单并锁定当前账户。
///
/// 仅供 wallet_page 自己使用，通过 `@visibleForTesting` 暴露给 widget 测试。
@visibleForTesting
class WalletAccountTile extends StatelessWidget {
  const WalletAccountTile({
    super.key,
    required this.account,
    required this.onTap,
    required this.onScan,
    required this.onRename,
    required this.onDelete,
    this.isIdentity = false,
    this.isDefault = false,
    this.actionsEnabled = true,
  });

  final Account account;
  final VoidCallback onTap;
  final VoidCallback onScan;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// 链上唯一公民身份绑定的账户。
  final bool isIdentity;

  /// 账户级统一顺序第一项；只表示当前默认用户，不表示 CID 发生换绑。
  final bool isDefault;

  /// 删除/默认账户变更期间禁用菜单，禁止扫码、重命名或另一条删除路径启动。
  final bool actionsEnabled;

  String _shortAddress(String address) {
    // 卡片固定显示前 10 位和后 8 位，中间严格使用 6 个 ASCII 句点；复制值仍是完整地址。
    if (address.length <= 18) return address;
    return '${address.substring(0, 10)}......${address.substring(address.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          decoration: AppTheme.cardDecoration(radius: AppTheme.radiusMd),
          child: Row(children: [
            Container(
              width: AppLayout.scaled(context, 46),
              height: AppLayout.scaled(context, 46),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Text(
                '#${account.accountIndex}',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            SizedBox(width: AppLayout.scaled(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          account.accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 18),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        SizedBox(width: AppLayout.scaled(context, 4)),
                        Transform.translate(
                          offset: Offset(0, -AppLayout.scaled(context, 3)),
                          child: const _DefaultAccountLabel(),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: AppLayout.scaled(context, 4)),
                  Text(
                    _shortAddress(account.ss58Address),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 13),
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (isIdentity) ...[
              SizedBox(width: AppLayout.scaled(context, 8)),
              const _WalletBadge(label: '身份钱包', icon: Icons.verified),
            ],
            PopupMenuButton<String>(
              enabled: actionsEnabled,
              tooltip: '账户操作',
              icon: Icon(
                Icons.more_vert,
                size: AppLayout.scaled(context, 20),
                color: AppTheme.textTertiary,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'scan':
                    onScan();
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'scan',
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/scan-line.svg',
                        width: AppLayout.scaled(context, 18),
                        height: AppLayout.scaled(context, 18),
                        colorFilter: const ColorFilter.mode(
                          AppTheme.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                      SizedBox(width: AppLayout.scaled(context, 10)),
                      const Text('扫一扫'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: AppLayout.scaled(context, 18),
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(width: AppLayout.scaled(context, 10)),
                      const Text('重命名'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: AppLayout.scaled(context, 18),
                        color: AppTheme.danger,
                      ),
                      SizedBox(width: AppLayout.scaled(context, 10)),
                      Text(
                        account.accountIndex == 0 ? '删除钱包' : '删除账户',
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({super.key, required this.wallet});

  final WalletProfile wallet;

  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage>
    with TxAutoRefreshMixin<WalletDetailPage> {
  final WalletManager _walletService = WalletManager();
  late final int _walletRevisionAtOpen;

  List<LocalTxEntity> _recentRecords = const [];
  bool _screenshotGuardActive = false;

  /// 外层下拉刷新通过此 key 触发链上余额卡的 refresh()。
  final GlobalKey<WalletOnchainBalanceCardState> _balanceCardKey =
      GlobalKey<WalletOnchainBalanceCardState>();
  final GlobalKey<WalletActionCardState> _actionCardKey =
      GlobalKey<WalletActionCardState>();

  /// 整页下拉刷新:
  /// - 链上余额卡:通过 GlobalKey 调 refresh()
  /// - 交易记录:复用 _loadRecentRecords()
  /// - 清算行余额:通过 WalletActionCard 读取当前绑定清算行节点余额。
  Future<void> _onPullRefresh() async {
    await Future.wait<void>([
      Future(() async {
        try {
          await _balanceCardKey.currentState?.refresh();
        } catch (_) {
          // 链上余额刷新失败已在卡片内置错误态处理,这里不打断其他刷新
        }
      }),
      Future(() async {
        try {
          await _actionCardKey.currentState?.refresh();
        } catch (_) {
          // 清算行节点可能暂不可达,动作卡内部会展示节点不可达。
        }
      }),
      _loadRecentRecords(),
    ]);
  }

  @override
  void dispose() {
    unawaited(
      stopTxAutoRefresh().catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[Wallet] 交易 watcher 停止失败: $error\n$stackTrace');
      }),
    );
    ChainTxMonitor.instance.onBalanceChanged = null;
    if (_screenshotGuardActive) ScreenshotGuard.disable();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _walletRevisionAtOpen = WalletManager.walletsRevision.value;
    _loadRecentRecords();
    startTxAutoRefresh(widget.wallet.accountId);
    // 注册余额变动回调，刷新交易记录和余额显示。
    ChainTxMonitor.instance.onBalanceChanged = (address, newBalance) {
      if (mounted && address == widget.wallet.ss58Address) {
        _loadRecentRecords();
        // 交易记录落库和余额刷新是两件事；轻节点余额读取失败时
        // ChainTxMonitor 会传 NaN，只刷新记录，不把余额误写成 0。
        if (newBalance.isFinite) {
          unawaited(
            _walletService
                .setWalletBalance(
              walletIndex: widget.wallet.walletIndex,
              accountId: widget.wallet.accountId,
              expectedWalletsRevision: _walletRevisionAtOpen,
              balance: newBalance,
            )
                .catchError((Object error, StackTrace stackTrace) {
              AppLog.d('[Wallet] 详情页余额 CAS 写入失败: $error\n$stackTrace');
              return false;
            }),
          );
        }
      }
    };
    if (ChainTxMonitor.instance.hasWatchedAccounts) {
      unawaited(
        ChainTxMonitor.instance
            .start()
            .catchError((Object error, StackTrace stackTrace) {
          AppLog.d('[Wallet] 详情页交易监控启动失败: $error\n$stackTrace');
        }),
      );
    }
  }

  Future<void> _loadRecentRecords() async {
    try {
      final records = await LocalTxStore.queryRecentByAccountId(
        widget.wallet.accountId,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _recentRecords = records;
      });
    } catch (_) {
      // 加载失败静默忽略，钱包详情页仍可正常使用
    }
  }

  @override
  Future<void> onTxRecordsChanged() => _loadRecentRecords();

  Future<void> _onMenuAction(String action) async {
    switch (action) {
      case 'scan_sign':
        final account = await _walletService.getAccountByAccountId(
          widget.wallet.accountId,
        );
        if (account == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未找到该钱包的账户0')));
          }
          return;
        }
        if (!mounted) return;
        await openScanDispatchFlow(
          context: context,
          paymentWallet: widget.wallet,
          signingAccount: account,
        );
      case 'clearing_bank':
        // 清算行设置尚未上线，冷热钱包统一只显示占位提示。
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂未上线，敬请期待')));
      case 'seed':
        await _revealSecret('私钥', () async {
          return _walletService.getAccountPrivateKey(
            widget.wallet.accountId,
          );
        });
    }
  }

  Future<void> _revealSecret(
    String label,
    Future<String?> Function() fetcher,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('查看$label'),
        content: Text('$label是核心机密信息，泄露将导致资产被盗。\n\n确认要查看吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('查看'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final value = await fetcher();
      if (!mounted) return;
      if (!_screenshotGuardActive) {
        _screenshotGuardActive = true;
        await ScreenshotGuard.enable();
        if (!mounted) return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(AppLayout.scaledValue(12)),
                decoration: AppTheme.bannerDecoration(AppTheme.danger),
                child: Text(
                  value ?? '无数据',
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(14),
                      fontFamily: 'monospace'),
                ),
              ),
              SizedBox(height: AppLayout.scaledValue(8)),
              Text(
                '请手抄备份，不支持复制',
                style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: AppLayout.scaledValue(12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on WalletAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('验证失败：${e.message}')));
    }
  }

  /// 钱包名持久化（纯本机落盘）。
  ///
  ///
  /// - 编辑态和回滚逻辑已搬到 [WalletIdentityCard]，这里只负责本机落盘。
  /// - 调用方(WalletIdentityCard)传进来的 newName 已 trim,但 updateWalletDisplay
  ///   内部再 trim 一次也无副作用,保持签名稳定。
  /// - 公开昵称、聊天联系人名均有独立真源，本方法不得触发资料或聊天同步。
  /// - 出错时重新抛出,让 WalletIdentityCard 走回滚分支。
  Future<void> _saveWalletName(String newName) async {
    try {
      await _walletService.updateWalletDisplay(
        widget.wallet.walletIndex,
        walletName: newName,
        walletIcon: widget.wallet.walletIcon,
      );
      if (!mounted) return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不拦截普通路由返回；iOS 左边缘手势、Android 系统返回和 AppBar 返回
    // 都走同一 Navigator 路径，上一页在路由完成后统一刷新钱包列表。
    return Scaffold(
      appBar: AppBar(
        title: const Text('钱包详情'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              if (widget.wallet.isHotWallet)
                const PopupMenuItem(value: 'scan_sign', child: Text('扫一扫')),
              const PopupMenuItem(value: 'clearing_bank', child: Text('清算行')),
              if (widget.wallet.isHotWallet)
                const PopupMenuItem(value: 'seed', child: Text('查看私钥')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onPullRefresh,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // 方案 2：身份与链上余额共用全宽纯色主视觉，不恢复旧渐变和卡片堆叠。
            Container(
              color: AppTheme.primary,
              child: Column(
                children: [
                  WalletIdentityCard(
                    wallet: widget.wallet,
                    onNameChanged: _saveWalletName,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppLayout.scaled(context, 20)),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withAlpha(55),
                    ),
                  ),
                  WalletOnchainBalanceCard(
                    key: _balanceCardKey,
                    wallet: widget.wallet,
                  ),
                ],
              ),
            ),
            // 三项操作紧接主视觉，保留原跳转和清算行绑定状态。
            WalletActionCard(
              key: _actionCardKey,
              accountId: widget.wallet.accountId,
              ss58Address: widget.wallet.ss58Address,
            ),
            SizedBox(height: AppLayout.scaled(context, 24)),
            // 交易区使用一张完整白色卡片；标题和单条记录入口保持不变。
            Padding(
              key: const ValueKey('wallet-transaction-section-padding'),
              padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.scaled(context, 4)),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: AppTheme.cardDecoration(radius: AppTheme.radiusMd),
                child: Column(children: _buildTransactionHistorySection()),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 24)),
          ],
        ),
      ),
    );
  }

  /// 交易记录区块:标题跳转 + 最近 5 条列表。
  List<Widget> _buildTransactionHistorySection() {
    return [
      InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionHistoryPage(
                ss58Address: widget.wallet.ss58Address,
                accountId: widget.wallet.accountId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Text(
                '交易记录',
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(16),
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: AppLayout.scaledValue(20),
                  color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
      if (_recentRecords.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: AppLayout.scaledValue(36),
          ),
          child: const Center(
            child: Text(
              '暂无交易记录',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
          ),
        )
      else
        ...List.generate(_recentRecords.length, (index) {
          final record = _recentRecords[index];
          return Column(
            children: [
              // 标题行进入完整列表；单条最近记录直接进入该笔交易详情。
              LocalTxRecordTile(
                record: record,
                showChevron: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocalTxRecordDetailPage(record: record),
                    ),
                  );
                },
              ),
              if (index < _recentRecords.length - 1) const Divider(height: 1),
            ],
          );
        }),
    ];
  }
}

class WalletIconOption {
  const WalletIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class WalletIconRegistry {
  static const List<WalletIconOption> options = [
    WalletIconOption(
      key: 'wallet',
      label: '钱包',
      icon: Icons.account_balance_wallet_outlined,
    ),
    WalletIconOption(key: 'shield', label: '盾牌', icon: Icons.shield_outlined),
    WalletIconOption(key: 'star', label: '星标', icon: Icons.star_border),
    WalletIconOption(key: 'leaf', label: '树叶', icon: Icons.eco_outlined),
    WalletIconOption(key: 'key', label: '钥匙', icon: Icons.vpn_key_outlined),
    WalletIconOption(
      key: 'safe',
      label: '保险箱',
      icon: Icons.inventory_2_outlined,
    ),
  ];

  static IconData iconFor(String key) {
    for (final option in options) {
      if (option.key == key) {
        return option.icon;
      }
    }
    return Icons.account_balance_wallet_outlined;
  }
}

/// 导入冷钱包页面：只接受本链 SS58 展示地址，不导入私钥。
class ImportColdWalletPage extends StatefulWidget {
  const ImportColdWalletPage({super.key});

  @override
  State<ImportColdWalletPage> createState() => _ImportColdWalletPageState();
}

class _ImportColdWalletPageState extends State<ImportColdWalletPage> {
  final TextEditingController _addressController = TextEditingController();
  bool _isImporting = false;
  String? _error;

  Future<void> _scanWalletAddress() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          mode: QrScanMode.accountTarget,
          customTitle: '扫描钱包二维码',
        ),
      ),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) {
      return;
    }

    final address = extractColdWalletImportAddress(raw);
    if (address == null || address.isEmpty) {
      setState(() {
        _error = '未识别到可导入的钱包账户地址';
      });
      return;
    }

    setState(() {
      _addressController.text = address;
      _addressController.selection = TextSelection.collapsed(
        offset: address.length,
      );
      _error = null;
    });
  }

  Future<void> _import() async {
    setState(() {
      _error = null;
      _isImporting = true;
    });
    try {
      await WalletManager().importColdWallet(
        ss58Address: _addressController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = walletOperationErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入冷钱包'),
        actions: [
          IconButton(
            tooltip: '扫码填入地址',
            onPressed: _isImporting ? null : _scanWalletAddress,
            icon: SvgPicture.asset(
              'assets/icons/scan-line.svg',
              width: AppLayout.scaled(context, 22),
              height: AppLayout.scaled(context, 22),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入冷钱包账户地址'),
            SizedBox(height: AppLayout.scaled(context, 8)),
            Text(
              '私钥保存在 公民钱包 签名设备上，签名请通过 公民钱包 扫码完成。',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: AppLayout.scaled(context, 13)),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            TextField(
              controller: _addressController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '请输入冷钱包账户地址',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            FilledButton(
              onPressed: _isImporting ? null : _import,
              child: Text(_isImporting ? '导入中...' : '确认导入'),
            ),
          ],
        ),
      ),
    );
  }
}
