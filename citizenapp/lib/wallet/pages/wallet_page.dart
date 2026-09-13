import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/qr/bodies/user_contact_body.dart';
import 'package:citizenapp/qr/bodies/user_transfer_body.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_router.dart';
import 'package:citizenapp/qr/scan_dispatch_flow.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';
import 'package:citizenapp/ui/widgets/shimmer_loading.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/account_detail_page.dart';
import 'package:citizenapp/wallet/widgets/wallet_action_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_identity_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_onchain_balance_card.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';
import 'package:citizenapp/ui/app_layout.dart';

class WalletTab extends StatefulWidget {
  const WalletTab({super.key, this.selectForTrade = false});

  final bool selectForTrade;

  @override
  State<WalletTab> createState() => _WalletTabState();
}

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
bool isBrokenCitizenWalletStateAccount(CitizenWalletStateAccount wallet) {
  if (!isAccountIdText(wallet.accountId)) return true;
  if (wallet.signMode != CitizenWalletSignMode.hot &&
      wallet.signMode != CitizenWalletSignMode.cold) {
    return true;
  }
  return wallet.ss58Address != ss58FromAccountIdText(wallet.accountId);
}

/// 导入冷钱包扫码只提取 SS58 展示地址；
/// 不在这里触发导入，避免用户还没确认就写入本地钱包库。
@visibleForTesting
Future<String?> extractColdWalletImportAddress(CitizenQr qr, String raw) async {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }

  try {
    final document = await qr.parse(text);
    if (document.kind == CitizenQrKind.accountId &&
        document.accountId != null) {
      return ss58FromAccountIdText(document.accountId!);
    }
  } on Object {
    // 非 SDK 通用码继续交由 App 业务二维码路由。
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
    case QrRouteType.accountDataKeyResponse:
    case QrRouteType.unknown:
      return null;
  }
}

/// 钱包列表页（单列横向卡片）：
/// - 正常态：唯一热钱包的 `//index` 账户行 + 冷钱包行并列，点账户行进账户详情，
///   点冷钱包行进冷钱包详情；
/// - 选择交易钱包态（selectForTrade）：按钱包整只选择付款钱包，沿用 CitizenWalletStateAccount 行；
/// - 钱包/账户图标按冷热配色：热=墨绿主色 / 冷=蓝(离线签名设备调性)；
/// - 冷钱包行保留既有行为；热钱包账户行的竖三点菜单提供
///   「扫一扫 / 重命名 / 删除钱包或删除账户」，整卡点击进入账户详情。
class _WalletTabState extends State<WalletTab> {
  CitizenWalletState? _state;
  AccountSecurityService? _security;
  _WalletLoadState _loadState = _WalletLoadState.initialLoading;
  Object? _loadError;
  Map<String, double> _balances = const <String, double>{};
  String? _identityAccountId;
  bool _mutationInProgress = false;
  int _loadGeneration = 0;

  bool get _isSelectionMode => widget.selectForTrade;
  CitizenSdkWallet get _wallet => context.read<CitizenSdk>().wallet;
  AccountSecurityService get _accountSecurity =>
      context.read<AccountSecurityService>();
  List<CitizenWalletStateAccount> get _accounts =>
      _state?.accounts ?? const <CitizenWalletStateAccount>[];
  List<CitizenWalletStateAccount> get _wallets {
    final result = <CitizenWalletStateAccount>[];
    final hot = _hotWallet;
    if (hot != null) result.add(hot);
    result.addAll(
      _accounts.where(
        (account) => account.signMode == CitizenWalletSignMode.cold,
      ),
    );
    return result;
  }

  CitizenWalletStateAccount? get _hotWallet {
    for (final account in _accounts) {
      if (account.signMode == CitizenWalletSignMode.hot &&
          account.accountIndex == 0) {
        return account;
      }
    }
    return null;
  }

  bool get _canOpenWalletEntryChooser => _state != null && !_mutationInProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _accountSecurity;
    if (identical(next, _security)) return;
    _security?.revision.removeListener(_onSecurityRevision);
    _security = next;
    next.revision.addListener(_onSecurityRevision);
  }

  @override
  void dispose() {
    _security?.revision.removeListener(_onSecurityRevision);
    super.dispose();
  }

  void _onSecurityRevision() {
    if (mounted && !_mutationInProgress) unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    if (_state == null && mounted) {
      setState(() {
        _loadState = _WalletLoadState.initialLoading;
        _loadError = null;
      });
    }
    try {
      final state = await _wallet.getState();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _state = state;
        _loadState = _WalletLoadState.success;
        _loadError = null;
      });
      await _loadIdentity(state, generation);
      if (!mounted || generation != _loadGeneration) return;
      await _refreshBalances(state, generation);
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      AppLog.d('wallet load failed: $error\n$stackTrace');
      setState(() {
        _loadError = error;
        _loadState = _state == null
            ? _WalletLoadState.initialFailure
            : _WalletLoadState.refreshFailure;
      });
    }
  }

  Future<void> _loadIdentity(CitizenWalletState state, int generation) async {
    final account = state.defaultAccount;
    final binding = account == null
        ? null
        : await _accountSecurity.readAccountDataBindingForAccountId(
            account.accountId,
          );
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _identityAccountId = binding?.accountId);
  }

  Future<void> _refreshBalances(
    CitizenWalletState state,
    int generation,
  ) async {
    if (state.accounts.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _balances = const <String, double>{});
      }
      return;
    }
    try {
      final snapshots = await context
          .read<CitizenSdk>()
          .chain
          .getAccountBalances(
            state.accounts.map((account) => account.accountId).toList(),
          );
      final values = <String, double>{
        for (final snapshot in snapshots)
          snapshot.accountId: snapshot.freeFen.toDouble() / 100,
      };
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _balances = Map<String, double>.unmodifiable(values));
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('公民链余额暂时不可用')));
    }
  }

  Future<void> _onDefaultAccountReorder(int oldIndex, int newIndex) async {
    if (_mutationInProgress || oldIndex == newIndex || _state == null) return;
    final before = List<CitizenWalletStateAccount>.of(_accounts);
    final target = List<CitizenWalletStateAccount>.of(before);
    final moved = target.removeAt(oldIndex);
    target.insert(newIndex, moved);
    final revision = _state!.revision;
    setState(() {
      _mutationInProgress = true;
      _state = CitizenWalletState(
        revision: revision,
        hotProfile: _state!.hotProfile,
        accounts: target,
      );
    });
    try {
      await _commitAccountOrder(before, target, revision);
      _accountSecurity.notifyDefaultAccountChanged();
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = CitizenWalletState(
          revision: revision,
          hotProfile: _state!.hotProfile,
          accounts: before,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    } finally {
      if (mounted) setState(() => _mutationInProgress = false);
    }
  }

  Future<void> _commitAccountOrder(
    List<CitizenWalletStateAccount> before,
    List<CitizenWalletStateAccount> target,
    BigInt revision,
  ) async {
    final ids = target.map((account) => account.accountId).toList();
    if (before.first.accountId == target.first.accountId) {
      await _wallet.reorderAccountsWithoutDefaultChange(
        expectedRevision: revision,
        accountIds: ids,
      );
      return;
    }
    final outcome = await _wallet.beginDefaultAccountChange(
      expectedRevision: revision,
      accountIds: ids,
      ttlSeconds: 90,
    );
    if (outcome is CitizenDefaultAccountChangeCompleted) return;
    final pending = outcome as CitizenDefaultAccountChangePending;
    if (!mounted) {
      throw const AccountSecurityException('页面已关闭');
    }
    final response = await showCitizenSdkQrResponse(
      context,
      request: pending.transportRequest,
      expiresAt: pending.expiresAt,
    );
    if (response == null) {
      throw const AccountSecurityException('已取消默认账户切换');
    }
    await _wallet.consumeDefaultAccountChange(
      sessionId: pending.sessionId,
      response: response,
    );
  }

  Future<void> _renameAccount(CitizenWalletStateAccount account) async {
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
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
    if (name == null || name.isEmpty || name == account.name || !mounted) {
      return;
    }
    try {
      await _wallet.renameAccount(accountId: account.accountId, name: name);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败：${_errorMessage(error)}')));
    }
  }

  Future<void> _deleteAccount(CitizenWalletStateAccount account) async {
    if (_mutationInProgress) return;
    final deletingWholeWallet =
        account.signMode == CitizenWalletSignMode.hot &&
        account.accountIndex == 0;
    final targets = deletingWholeWallet
        ? _accounts
              .where((value) => value.signMode == CitizenWalletSignMode.hot)
              .toList(growable: false)
        : <CitizenWalletStateAccount>[account];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(deletingWholeWallet ? '删除钱包' : '删除账户'),
        content: Text(
          deletingWholeWallet
              ? '删除「${account.name}」会从本设备移除该钱包下全部 ${targets.length} 个账户、'
                    '私钥、交易记录和清算行缓存。\n\n请确认已经备份助记词，此操作无法撤销。'
              : '确认删除账户「${account.name}」？此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _mutationInProgress = true);
    try {
      await _accountSecurity.prepareAccountCleanup(
        accounts: targets,
        deleteWalletWideKey: deletingWholeWallet,
      );
      try {
        if (deletingWholeWallet) {
          await _wallet.delete();
          await _wallet.reconcileCleanup();
        } else {
          await _wallet.deleteAccount(account.accountId);
        }
      } catch (_) {
        await _accountSecurity.cancelAccountCleanup();
        rethrow;
      }
      await _accountSecurity.reconcileAccountCleanup();
      for (final target in targets) {
        await ClearingBankPrefs.clear(target.accountId);
      }
      _accountSecurity.notifyDefaultAccountChanged();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletingWholeWallet
                ? '已删除钱包「${account.name}」'
                : '已删除账户「${account.name}」',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除未完成：${_errorMessage(error)}')));
    } finally {
      if (mounted) setState(() => _mutationInProgress = false);
    }
  }

  Future<void> _openAccountDetail(CitizenWalletStateAccount account) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AccountDetailPage(account: account)),
    );
    if (mounted) await _reload();
  }

  Future<void> _scanSignForAccount(CitizenWalletStateAccount account) async {
    await openAccountScanSignFlow(context: context, account: account);
  }

  Future<void> _openImportColdWalletPage() async {
    if (_mutationInProgress) return;
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportColdWalletPage()),
    );
    if (imported == true && mounted) {
      _accountSecurity.notifyDefaultAccountChanged();
      await _reload();
    }
  }

  Future<void> _selectWallet(CitizenWalletStateAccount selected) async {
    final state = _state;
    if (state == null) return;
    final target = <CitizenWalletStateAccount>[
      selected,
      ...state.accounts.where(
        (account) => account.accountId != selected.accountId,
      ),
    ];
    setState(() => _mutationInProgress = true);
    try {
      await _commitAccountOrder(state.accounts, target, state.revision);
      _accountSecurity.notifyDefaultAccountChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    } finally {
      if (mounted) setState(() => _mutationInProgress = false);
    }
  }

  Future<void> _openWalletDetail(CitizenWalletStateAccount account) async {
    if (_isSelectionMode) {
      await _selectWallet(account);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WalletDetailPage(wallet: account),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _showWalletEntryChooser() async {
    if (!_canOpenWalletEntryChooser) return;
    final hot = _hotWallet;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => WalletEntryChooserSheet(
        canAddAccount: hot != null,
        onAddNextAccount: () {
          Navigator.of(sheetContext).pop();
          if (hot != null) unawaited(_openAddAccount(next: true));
        },
        onAddSpecifyAccount: () {
          Navigator.of(sheetContext).pop();
          if (hot != null) unawaited(_openAddAccount(next: false));
        },
        onImportCold: () {
          Navigator.of(sheetContext).pop();
          unawaited(_openImportColdWalletPage());
        },
      ),
    );
  }

  Future<void> _openAddAccount({required bool next}) async {
    if (_mutationInProgress) return;
    final profile = _state?.hotProfile;
    if (profile == null) return;
    final maximum = profile.accounts
        .map((account) => account.index)
        .fold<int>(0, (left, right) => left > right ? left : right);
    final initial = next ? maximum + 1 : 1;
    try {
      await _wallet.addAccounts(<int>[initial]);
      _accountSecurity.notifyDefaultAccountChanged();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已添加账户')));
    } catch (error) {
      if (!mounted ||
          error is CitizenSdkException &&
              error.code == CitizenSdkErrorCode.cancelled) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加账户失败：${_errorMessage(error)}')));
    }
  }

  Widget _buildEmptyWalletChoices() =>
      WalletEmptyChoices(onImportCold: _openImportColdWalletPage);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '选择交易钱包' : '我的钱包'),
        centerTitle: true,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              key: const ValueKey('wallet-add-entry'),
              tooltip: '添加账户 / 导入冷钱包',
              onPressed: _canOpenWalletEntryChooser
                  ? _showWalletEntryChooser
                  : null,
              icon: Icon(Icons.add, size: AppLayout.scaled(context, 26)),
            ),
        ],
      ),
      body: switch (_loadState) {
        _WalletLoadState.initialLoading => Padding(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          child: ListSkeleton(
            itemCount: 3,
            itemBuilder: (_, __) => const WalletCardSkeleton(),
          ),
        ),
        _WalletLoadState.initialFailure => _buildInitialLoadFailure(),
        _WalletLoadState.success || _WalletLoadState.refreshFailure => Column(
          children: [
            if (_loadState == _WalletLoadState.refreshFailure)
              _buildRefreshFailureBanner(),
            Expanded(
              child: _isSelectionMode
                  ? _buildSelectionList()
                  : _buildMyWalletList(),
            ),
          ],
        ),
      },
    );
  }

  Widget _buildInitialLoadFailure() => Center(
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
            _errorMessage(_loadError),
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

  Widget _buildRefreshFailureBanner() => Material(
    color: AppTheme.warning.withAlpha(20),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.warning),
            const SizedBox(width: 8),
            const Expanded(child: Text('钱包刷新失败，正在显示上次成功加载的数据')),
            TextButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      ),
    ),
  );

  Widget _buildSelectionList() {
    final wallets = _wallets;
    if (wallets.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: _buildEmptyWalletChoices(),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: wallets.length,
      itemBuilder: (context, index) {
        final account = wallets[index];
        return Padding(
          key: ValueKey('wallet_${account.walletIndex}'),
          padding: EdgeInsets.only(bottom: AppLayout.scaledValue(8)),
          child: WalletListTile(
            wallet: account,
            balance: _balances[account.accountId] ?? 0,
            showActions: false,
            isIdentityWallet: account.accountId == _identityAccountId,
            isBroken: false,
            onTap: () => _openWalletDetail(account),
            onRename: () => _renameAccount(account),
            onDelete: () => _deleteAccount(account),
            actionsEnabled: !_mutationInProgress,
          ),
        );
      },
    );
  }

  Widget _buildMyWalletList() {
    final accounts = _accounts;
    if (accounts.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: _buildEmptyWalletChoices(),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverReorderableList(
              itemCount: accounts.length,
              onReorderItem: _onDefaultAccountReorder,
              itemBuilder: (context, index) {
                final account = accounts[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('default_account_${account.accountId}'),
                  index: index,
                  enabled: !_mutationInProgress,
                  child: _buildAccountRow(account, isDefault: index == 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(
    CitizenWalletStateAccount account, {
    required bool isDefault,
  }) {
    final padding = EdgeInsets.only(bottom: AppLayout.scaledValue(8));
    if (account.signMode == CitizenWalletSignMode.hot) {
      return Padding(
        padding: padding,
        child: WalletAccountTile(
          account: account,
          isDefault: isDefault,
          isIdentity: account.accountId == _identityAccountId,
          onTap: () => _openAccountDetail(account),
          onScan: () => _scanSignForAccount(account),
          onRename: () => _renameAccount(account),
          onDelete: () => _deleteAccount(account),
          actionsEnabled: !_mutationInProgress,
        ),
      );
    }
    return Padding(
      padding: padding,
      child: WalletListTile(
        wallet: account,
        balance: _balances[account.accountId] ?? 0,
        showActions: true,
        isDefault: isDefault,
        isIdentityWallet: account.accountId == _identityAccountId,
        isBroken: false,
        onTap: () => _openWalletDetail(account),
        onRename: () => _renameAccount(account),
        onDelete: () => _deleteAccount(account),
        actionsEnabled: !_mutationInProgress,
      ),
    );
  }

  static String _errorMessage(Object? error) => switch (error) {
    CitizenSdkException value => value.message,
    AccountSecurityException value => value.message,
    null => '未知错误',
    _ => error.toString(),
  };
}

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
              subtitle: const Text(
                '在本钱包下派生下一个序号账户',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
              onTap: onAddNextAccount,
            ),
            ListTile(
              leading: const Icon(Icons.tag_rounded),
              title: const Text('添加指定账户'),
              subtitle: const Text(
                '指定序号恢复本钱包下的特定账户',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
              onTap: onAddSpecifyAccount,
            ),
          ],
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('导入冷钱包'),
            subtitle: const Text(
              '仅导入公钥，私钥保留在签名设备',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
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
            fontWeight: FontWeight.w600,
          ),
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
    required this.balance,
    required this.showActions,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.isIdentityWallet = false,
    this.isDefault = false,
    this.isBroken = false,
    this.actionsEnabled = true,
  });

  final CitizenWalletStateAccount wallet;
  final double balance;

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
    final isHot = wallet.signMode == CitizenWalletSignMode.hot;
    final iconBg = isHot
        ? AppTheme.primary.withAlpha(20)
        : AppTheme.info.withAlpha(20);
    final iconColor = isHot ? AppTheme.primaryDark : AppTheme.info;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          decoration: AppTheme.cardDecoration(radius: AppTheme.radiusMd),
          child: Row(
            children: [
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
                            wallet.name,
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
                          color: AppTheme.warning,
                        ),
                      )
                    else
                      Text(
                        AmountFormat.formatThousands(balance),
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
            ],
          ),
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
        vertical: AppLayout.scaled(context, 3),
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(24),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: AppLayout.scaled(context, 12),
              color: AppTheme.primaryDark,
            ),
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

  final CitizenWalletStateAccount account;
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
          child: Row(
            children: [
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
                            account.name,
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
            ],
          ),
        ),
      ),
    );
  }
}

class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({super.key, required this.wallet});

  final CitizenWalletStateAccount wallet;

  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage>
    with TxAutoRefreshMixin<WalletDetailPage> {
  List<LocalTxEntity> _recentRecords = const [];

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
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadRecentRecords();
    startTxAutoRefresh(widget.wallet.accountId);
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
        await openScanDispatchFlow(
          context: context,
          paymentWallet: widget.wallet,
          signingAccount: widget.wallet,
        );
      case 'clearing_bank':
        // 清算行设置尚未上线，冷热钱包统一只显示占位提示。
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂未上线，敬请期待')));
      case 'seed':
        await context.read<CitizenSdk>().wallet.viewAccountPrivateKey(
          widget.wallet.accountId,
        );
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
      await context.read<CitizenSdk>().wallet.renameAccount(
        accountId: widget.wallet.accountId,
        name: newName,
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
              if (widget.wallet.signMode == CitizenWalletSignMode.hot)
                const PopupMenuItem(value: 'scan_sign', child: Text('扫一扫')),
              const PopupMenuItem(value: 'clearing_bank', child: Text('清算行')),
              if (widget.wallet.signMode == CitizenWalletSignMode.hot)
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
                      horizontal: AppLayout.scaled(context, 20),
                    ),
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
                horizontal: AppLayout.scaled(context, 4),
              ),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: AppLayout.scaledValue(20),
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
      if (_recentRecords.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(36)),
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

    final address = await extractColdWalletImportAddress(
      context.read<CitizenSdk>().qr,
      raw,
    );
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
      await context.read<CitizenSdk>().wallet.importColdAccount(
        ss58Address: _addressController.text,
        name: '冷钱包',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _WalletTabState._errorMessage(error);
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
                fontSize: AppLayout.scaled(context, 13),
              ),
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
