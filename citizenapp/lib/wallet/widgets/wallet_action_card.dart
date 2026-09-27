import 'dart:async';

import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/transaction/onchain-topup/onchain_topup_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';
import 'package:citizenapp/transaction/offchain-transaction/pages/petty_wallet_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/pages/withdraw_page.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

/// 账户详情的 3 列等宽操作区（充值/提现/零钱包），一律按 `account_id` 键控。
///
///
/// - 充值:进「链上充值」页(稳定币购买公民币,与清算行无关,**不需要绑定清算行**)。
/// - 提现:零钱包 → 链上账户,需已绑定清算行,否则提示先绑定。
/// - 零钱包:**可点击**进「零钱包详情页」(链下清算行零钱包),需已绑定;页内含充值到零钱包。
/// - 零钱包余额来自当前绑定清算行快照中的节点端点,通过 `offchain_queryBalance`
///   查询;失败时展示节点不可达,不再写死 0.00 元。
/// - 每个 CitizenSDK 账户独立绑定清算行，签名按精确 `account_id` 调用 SDK。
class WalletActionCard extends StatefulWidget {
  const WalletActionCard({
    super.key,
    required this.accountId,
    required this.ss58Address,
    this.finalizedBalanceLoader,
  });

  /// 该账户链账户主键(0x+64hex):充值目标、清算行绑定缓存键、按账户签名均以它为准。
  final String accountId;

  /// 该账户 SS58 地址,用于查询清算行存款余额。
  final String ss58Address;

  /// 默认复用链上余额 RPC；测试可注入稳定结果，避免把网络状态写进组件断言。
  final Future<double> Function(String accountId)? finalizedBalanceLoader;

  @override
  State<WalletActionCard> createState() => WalletActionCardState();
}

class WalletActionCardState extends State<WalletActionCard> {
  ClearingBankBindingSnapshot? _binding;
  bool _bindingLoaded = false;
  WalletBalanceState<CitizenAccountBalance>? _onchain;
  WalletBalanceState<BigInt>? _clearing;
  WalletBalanceState<BigInt>? _testBalance;

  String get _onchainBalanceText {
    final value = _onchain?.value?.totalFen ?? _testBalance?.value;
    if (value != null) {
      return '${AccountBalanceSnapshotStore.formatFen(value)} 元';
    }
    return (_onchain?.hasError ?? _testBalance?.hasError ?? false)
        ? '查询失败'
        : '读取中';
  }

  String get _balanceText {
    if (!_bindingLoaded) return '读取中';
    if (_binding == null) return '未绑定';
    final value = _clearing?.value;
    if (value != null) {
      return '${AccountBalanceSnapshotStore.formatFen(value)} 元';
    }
    return _clearing?.hasError == true ? '节点不可达' : '读取中';
  }

  @override
  void initState() {
    super.initState();
    _bindOnchain();
    unawaited(refresh(forceRefresh: false));
  }

  void _bindOnchain() {
    final accountId = widget.accountId;
    final loader = widget.finalizedBalanceLoader;
    if (loader == null) {
      _onchain = AccountBalanceSnapshotStore.forChain(
        context.read<CitizenSdk>().chain,
      ).accountState(accountId)..addListener(_changed);
    } else {
      // 既有布局测试注入仍复用相同状态机；正式页面始终绑定唯一余额所有者。
      _testBalance = WalletBalanceState(
        (_) async => BigInt.from((await loader(accountId) * 100).round()),
      )..addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _unbind() {
    _onchain?.removeListener(_changed);
    _clearing?.removeListener(_changed);
    _testBalance?.removeListener(_changed);
    _onchain = null;
    _clearing = null;
    _testBalance = null;
  }

  @override
  void didUpdateWidget(covariant WalletActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.ss58Address != widget.ss58Address ||
        oldWidget.finalizedBalanceLoader != widget.finalizedBalanceLoader) {
      _unbind();
      _binding = null;
      _bindingLoaded = false;
      _bindOnchain();
      unawaited(refresh(forceRefresh: false));
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  Future<void> refresh({bool forceRefresh = true}) async {
    final accountId = widget.accountId;
    final onchainFuture =
        _onchain?.load(forceRefresh: forceRefresh) ??
        _testBalance!.load(forceRefresh: forceRefresh);
    final binding = await ClearingBankPrefs.loadSnapshot(accountId);
    if (!mounted || widget.accountId != accountId) return;
    _clearing?.removeListener(_changed);
    _binding = binding;
    _bindingLoaded = true;
    _clearing = binding == null
        ? null
        : AccountBalanceSnapshotStore.forChain(context.read<CitizenSdk>().chain)
              .clearingState(
                accountId: accountId,
                ss58Address: widget.ss58Address,
                wssUrl: binding.wssUrl,
              );
    _clearing?.addListener(_changed);
    setState(() {});
    await Future.wait([
      onchainFuture,
      if (_clearing != null) _clearing!.load(forceRefresh: forceRefresh),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('wallet-action-card'),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      padding: EdgeInsets.symmetric(
        vertical: AppLayout.scaled(context, 20),
        horizontal: AppLayout.scaled(context, 12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ClickableAction(
              icon: Icons.arrow_circle_down_outlined,
              label: '充值',
              detailText: _onchainBalanceText,
              onTap: () => _openTopup(context),
            ),
          ),
          const _ActionDivider(),
          Expanded(
            child: _ClickableAction(
              icon: Icons.arrow_circle_up_outlined,
              label: '提现',
              onTap: () => _openWithdraw(context),
            ),
          ),
          const _ActionDivider(),
          Expanded(
            child: _BalanceAction(
              balanceText: _balanceText,
              onTap: () => _openPettyWallet(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 充值 = 稳定币购买公民币,进链上充值页;不依赖清算行绑定。
  Future<void> _openTopup(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnchainTopupPage(accountId: widget.accountId),
      ),
    );
    await refresh(forceRefresh: false);
  }

  Future<void> _openWithdraw(BuildContext context) async {
    final binding = _binding;
    if (binding == null) {
      _showNeedBinding(context);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WithdrawPage(
          accountId: widget.accountId,
          ss58Address: widget.ss58Address,
          wssUrl: binding.wssUrl,
        ),
      ),
    );
    await refresh(forceRefresh: false);
  }

  /// 零钱包 = 进清算行零钱包详情页(余额 + 充值到零钱包 + 提现);需已绑定。
  Future<void> _openPettyWallet(BuildContext context) async {
    final binding = _binding;
    if (binding == null) {
      _showNeedBinding(context);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PettyWalletPage(
          accountId: widget.accountId,
          ss58Address: widget.ss58Address,
          wssUrl: binding.wssUrl,
          displayTitle: binding.displayTitle,
        ),
      ),
    );
    await refresh(forceRefresh: false);
  }

  static void _showNeedBinding(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先在“清算行”页面绑定清算行'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 三列之间的轻量分隔线，只组织视觉关系，不形成新的卡片。
class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: AppLayout.scaled(context, 88),
      color: AppTheme.divider,
    );
  }
}

/// 充值 / 提现两列共用的可点击入口：整列响应，保留 44 以上点击目标。
class _ClickableAction extends StatelessWidget {
  const _ClickableAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detailText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? detailText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppLayout.scaled(context, 96)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: AppLayout.scaled(context, 48),
                height: AppLayout.scaled(context, 48),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppLayout.scaled(context, 26),
                  color: AppTheme.primaryDark,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 8)),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryDark,
                  height: AppLayout.compactLineHeight,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 4)),
              if (detailText == null)
                // 提现列不展示金额，但保持和两侧状态行等高。
                SizedBox(height: AppLayout.scaled(context, 15))
              else
                Text(
                  detailText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    color: AppTheme.textTertiary,
                    height: AppLayout.subtitleLineHeight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 零钱包列：整列可点击进入零钱包详情页，并保留实时绑定/余额状态。
class _BalanceAction extends StatelessWidget {
  const _BalanceAction({required this.balanceText, required this.onTap});

  final String balanceText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppLayout.scaled(context, 96)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: AppLayout.scaled(context, 48),
                height: AppLayout.scaled(context, 48),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: AppLayout.scaled(context, 26),
                  color: AppTheme.primaryDark,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 8)),
              Text(
                '零钱包',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryDark,
                  height: AppLayout.compactLineHeight,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 4)),
              Text(
                balanceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12),
                  color: AppTheme.textTertiary,
                  height: AppLayout.subtitleLineHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
