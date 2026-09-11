import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizenapp/transaction/history/data/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/core/wallet_manager.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';
import 'package:citizenapp/wallet/widgets/wallet_action_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_qr_dialog.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 账户详情（Lv3）：单个 `//index` 账户 = 单钱包多账户下「以前的钱包详情」。
///
/// 承载该账户的全部钱包功能，一律按 `account_id` 键控：
/// - 充值 / 提现 / 零钱包（[WalletActionCard]，链下清算行零钱包按账户独立绑定）；
/// - 清算行菜单当前只显示“暂未上线，敬请期待”，不进入尚未完成的设置页；
/// - 交易记录（[TransactionHistoryPage]，按账户 `account_id` 查询）；
/// - 顶部完整 SS58 地址与该账户的账户码（`k=5`，只声明账户；身份码在用户主页）；
/// - AppBar 菜单中的私钥（child mini-secret 独立、单向；展示前生物识别 +
///   防截屏 + 纯文本不可复制）。
///
/// 追加账户不在本页：收在「我的钱包」列表右上角「＋」的「添加下一个账户 / 添加指定账户」。
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key, required this.account});

  final Account account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage>
    with TxAutoRefreshMixin<AccountDetailPage> {
  final WalletManager _walletManager = WalletManager();

  /// 充值/提现/零钱包动作卡:下拉刷新时通过此 key 触发清算行余额重查。
  final GlobalKey<WalletActionCardState> _actionCardKey =
      GlobalKey<WalletActionCardState>();

  bool _screenshotGuardActive = false;

  /// 该账户最近交易记录(最多 5 条),按 `account_id` 查询。
  List<LocalTxEntity> _recentRecords = const [];

  @override
  void initState() {
    super.initState();
    // 初始化加载最近交易记录;之后由 ChainTxMonitor 后台写库触发响应式重刷
    // (不重复启动监听、不劫持全局回调)。
    _loadRecentRecords();
    startTxAutoRefresh(widget.account.accountId);
  }

  @override
  Future<void> onTxRecordsChanged() => _loadRecentRecords();

  @override
  void dispose() {
    unawaited(
      stopTxAutoRefresh().catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[Wallet] 账户详情 watcher 停止失败: $error\n$stackTrace');
      }),
    );
    if (_screenshotGuardActive) ScreenshotGuard.disable();
    super.dispose();
  }

  Future<void> _loadRecentRecords() async {
    try {
      final records = await LocalTxStore.queryRecentByAccountId(
        widget.account.accountId,
        limit: 5,
      );
      if (!mounted) return;
      setState(() => _recentRecords = records);
    } catch (_) {
      // 加载失败静默忽略,账户详情其余功能不受影响。
    }
  }

  /// 下拉刷新:清算行余额卡 + 最近交易记录。
  Future<void> _onPullRefresh() async {
    await Future.wait<void>([
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

  Future<void> _revealPrivateKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查看私钥'),
        content: const Text('私钥泄露将导致该账户资产被盗（仅该账户，不影响本钱包其他账户）。\n\n确认要查看吗？'),
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
    String? key;
    try {
      key = await _walletManager.getAccountPrivateKey(widget.account.accountId);
      if (!mounted) return;
      if (!_screenshotGuardActive) {
        _screenshotGuardActive = true;
        await ScreenshotGuard.enable();
        if (!mounted) return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('私钥'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppLayout.scaledValue(14)),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withAlpha(15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.danger.withAlpha(40)),
                ),
                // 普通 Text 不提供选择/复制菜单，避免私钥进入剪贴板。
                child: Text(
                  key!,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(13),
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                    height: 1.6,
                  ),
                ),
              ),
              SizedBox(height: AppLayout.scaledValue(10)),
              Text(
                '请手抄备份，不支持复制；导出即等于该账户控制权',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: AppLayout.scaledValue(12),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('验证失败：$e')));
    } finally {
      // 私钥弹窗关闭后立即释放页面引用并恢复截屏策略，不把敏感信息留在详情页状态中。
      key = null;
      if (_screenshotGuardActive) {
        _screenshotGuardActive = false;
        await ScreenshotGuard.disable();
      }
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label已复制'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 清算行设置尚未上线；入口保留产品位置，但不得进入未完成页面。
  void _showClearingBankUnavailable() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂未上线，敬请期待')));
  }

  /// 账户详情统一出固定账户码（`k=5`）：这里表达的是「账户」，身份由用户主页的用户码表达。
  Future<void> _openWalletQr() async {
    await showWalletQrDialog(
      context,
      accountId: widget.account.accountId,
      accountName: widget.account.accountName,
    );
  }

  Future<void> _onMenuAction(String action) async {
    switch (action) {
      case 'clearing_bank':
        _showClearingBankUnavailable();
      case 'private_key':
        await _revealPrivateKey();
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    // 普通详情页交给路由自身处理返回，保留 iOS 左边缘交互式返回手势。
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户详情'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            tooltip: '账户操作',
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clearing_bank',
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_outlined,
                      size: AppLayout.scaled(context, 18),
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: AppLayout.scaled(context, 10)),
                    const Text('清算行'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'private_key',
                child: Row(
                  children: [
                    Icon(
                      Icons.key_outlined,
                      size: AppLayout.scaled(context, 18),
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: AppLayout.scaled(context, 10)),
                    const Text('查看私钥'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onPullRefresh,
        child: ListView(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildHeader(),
            SizedBox(height: AppLayout.scaled(context, 16)),
            // 充值 / 提现 / 零钱包(按 account_id,链下清算行零钱包按账户独立绑定)。
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
              child: WalletActionCard(
                key: _actionCardKey,
                accountId: account.accountId,
                ss58Address: account.ss58Address,
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            _buildTransactionHistoryCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final account = widget.account;
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(AppLayout.scaledValue(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: AppLayout.scaledValue(44),
                      height: AppLayout.scaledValue(44),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Text(
                        '#${account.accountIndex}',
                        style: TextStyle(
                          fontSize: AppLayout.scaledValue(14),
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: AppLayout.scaledValue(14)),
                    Expanded(
                      // 二维码覆盖卡片右上角，账户名只在首行避让它。
                      child: Padding(
                        padding:
                            EdgeInsets.only(right: AppLayout.scaledValue(36)),
                        child: Text(
                          account.accountName,
                          style: TextStyle(
                            fontSize: AppLayout.scaledValue(18),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppLayout.scaledValue(4)),
                Padding(
                  // 地址独占第二行，不再为上方二维码预留宽度；复制按钮贴齐内容右边界。
                  padding: EdgeInsets.only(left: AppLayout.scaledValue(58)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          account.ss58Address,
                          style: TextStyle(
                            fontSize: AppLayout.scaledValue(11),
                            fontFamily: 'monospace',
                            color: Colors.white.withAlpha(210),
                            height: 1.35,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '复制 SS58 地址',
                        visualDensity: VisualDensity.compact,
                        constraints: BoxConstraints(
                          minWidth: AppLayout.scaledValue(44),
                          minHeight: AppLayout.scaledValue(44),
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => _copy(account.ss58Address, 'SS58 地址'),
                        icon: Icon(
                          Icons.copy_rounded,
                          size: AppLayout.scaledValue(16),
                          color: Colors.white.withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            // Stack 覆盖整张卡片，避免被内容区 20dp padding 再向内挤。
            top: AppLayout.scaledValue(8),
            right: AppLayout.scaledValue(8),
            child: IconButton(
              tooltip: '账户二维码',
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints(
                  minWidth: AppLayout.scaledValue(44),
                  minHeight: AppLayout.scaledValue(44)),
              padding: EdgeInsets.zero,
              onPressed: _openWalletQr,
              icon: Icon(
                Icons.qr_code_rounded,
                size: AppLayout.scaledValue(20),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 交易记录卡片:标题跳转完整列表 + 最近 5 条。
  Widget _buildTransactionHistoryCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
      child: Column(children: _buildTransactionHistorySection()),
    );
  }

  List<Widget> _buildTransactionHistorySection() {
    return [
      InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionHistoryPage(
                ss58Address: widget.account.ss58Address,
                accountId: widget.account.accountId,
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
