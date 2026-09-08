import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../util/screenshot_guard.dart';
import '../wallet/wallet_manager.dart';
import 'account_detail_page.dart';
import 'app_theme.dart';
import 'scan_page.dart';
import 'widgets/wallet_qr_dialog.dart';

/// Lv2 钱包详情：钱包(master)名 + 助记词备份 + 账户列表 + 添加账户。
///
/// 冷钱包按钱包存种子/助记词;助记词是钱包级根备份,在身份卡内展示(隐藏→确认→
/// 生物识别→显示,防截屏、不可复制)。账户按 `//index` 派生,点账户进 Lv3。
class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage> {
  final WalletManager _walletManager = WalletManager();

  List<Account> _accounts = [];
  bool _loading = true;
  bool _addingAccount = false;

  String? _mnemonic;
  bool _mnemonicVisible = false;
  bool _screenshotGuardActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_screenshotGuardActive) {
      ScreenshotGuard.disable(_onSecurityEvent);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await _walletManager.getAccounts(widget.wallet.masterId);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  void _enableScreenshotGuard() {
    if (!_screenshotGuardActive) {
      _screenshotGuardActive = true;
      ScreenshotGuard.enable(_onSecurityEvent);
    }
  }

  void _onSecurityEvent(String event) {
    if (!mounted) return;
    if (event == 'screenshot_taken' || event == 'screen_recording_started') {
      setState(() {
        _mnemonicVisible = false;
        _mnemonic = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            event == 'screenshot_taken'
                ? '检测到截屏，助记词已隐藏。请勿截屏保存助记词。'
                : '检测到屏幕录制，助记词已隐藏',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _revealMnemonic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查看助记词'),
        content: const Text('助记词可恢复本钱包全部账户，泄露将导致资产被盗。\n\n确认要查看吗？'),
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
    if (confirmed != true) return;
    try {
      final mnemonic = await _walletManager.getMasterMnemonic(
        widget.wallet.masterId,
      );
      if (!mounted) return;
      _enableScreenshotGuard();
      setState(() {
        _mnemonic = mnemonic;
        _mnemonicVisible = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('验证失败：${walletErrorMessage(e)}')),
      );
    }
  }

  int get _nextIndex =>
      _accounts
          .map((e) => e.accountIndex)
          .fold<int>(-1, (m, e) => e > m ? e : m) +
      1;

  /// 混合式添加:默认"下一个" + 高级"指定序号"(恢复非连续账户 / 特定注资账户)。
  void _showAddAccountSheet() {
    if (_addingAccount) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _sheetItem(
                icon: Icons.add_circle_outline,
                label: '添加下一个账户',
                subtitle: '将派生 //$_nextIndex',
                onTap: () {
                  Navigator.pop(context);
                  _doAdd();
                },
              ),
              const SizedBox(height: 8),
              _sheetItem(
                icon: Icons.tag_rounded,
                label: '指定序号添加',
                subtitle: '填 1–${WalletManager.maxAccountIndex}（恢复特定账户）',
                onTap: () {
                  Navigator.pop(context);
                  _promptIndexAndAdd();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, color: AppTheme.primaryLight, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptIndexAndAdd() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('指定账户序号'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '1–${WalletManager.maxAccountIndex}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (raw == null) return;
    final index = int.tryParse(raw.trim());
    if (index == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效序号')));
      return;
    }
    await _doAdd(index: index);
  }

  Future<void> _doAdd({int? index}) async {
    if (_addingAccount) return;
    setState(() => _addingAccount = true);
    try {
      await _walletManager.addAccount(widget.wallet.masterId, index: index);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('添加账户失败：${walletErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _addingAccount = false);
    }
  }

  Future<void> _openAccount(Account account) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountDetailPage(
          account: account,
          walletName: widget.wallet.walletName,
        ),
      ),
    );
    await _load();
  }

  String _shortAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
  }

  Future<void> _openWalletScan() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ScanPage(wallet: widget.wallet)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('钱包详情'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '扫码签名',
            onPressed: _openWalletScan,
            icon: SvgPicture.asset(
              'resources/icons/scan-line.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppTheme.primaryLight,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildIdentityCard(),
                const SizedBox(height: 20),
                _buildAccountsSection(),
              ],
            ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上排：钱包图标 + 名称。
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 22,
                color: AppTheme.primaryLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.wallet.walletName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 下方：助记词区（隐藏→确认→生物识别→显示，样式同账户私钥区）。
          _buildMnemonicArea(),
        ],
      ),
    );
  }

  Widget _buildMnemonicArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '助记词（请绝对保密）',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (!_mnemonicVisible)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _revealMnemonic,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      color: AppTheme.textTertiary,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '点击查看助记词',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.danger.withAlpha(15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.danger.withAlpha(40)),
            ),
            // 纯 Text（非 SelectableText）→ 不可复制。
            child: Text(
              _mnemonic ?? '无数据',
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '请手抄备份；若创建时设置密码，恢复时还必须输入原密码',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _mnemonicVisible = false;
                  _mnemonic = null;
                }),
                icon: const Icon(Icons.visibility_off_rounded, size: 16),
                label: const Text('隐藏'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAccountsSection() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 8, 6),
            child: Row(
              children: [
                const Text(
                  '账户列表',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _addingAccount ? null : _showAddAccountSheet,
                  child: const Text('添加账户'),
                ),
              ],
            ),
          ),
          ..._accounts.map(_buildAccountRow),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              '提示:重装或换设备后,重导助记词只自动恢复账户0,其余账户需在此重新添加,可指定序号精确还原(离线设备无法链上探活)。',
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// 序号徽章:两位数以内 `#xx` 单行居中;三位数起 `#` 缩小减淡挪到方框左上角,
  /// 数字另起一行居中并按位数自动缩小(序号上限 //1989,整串单行会撑满方框)。
  Widget _buildIndexBadge(int index) {
    const numberStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.primaryLight,
    );
    if (index < 100) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('#$index', style: numberStyle),
      );
    }
    return SizedBox.expand(
      child: Stack(
        children: [
          const Positioned(
            top: 3,
            left: 5,
            child: Text(
              '#',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          Positioned.fill(
            top: 12,
            left: 3,
            right: 3,
            bottom: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$index', style: numberStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(Account account) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAccount(account),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                alignment: Alignment.center,
                child: _buildIndexBadge(account.accountIndex),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.accountName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortAddress(account.ss58Address),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // 二维码入口：不进账户详情就能出示该账户的账户码。
              // 独立热区，点它不触发整行的 onTap。
              Semantics(
                button: true,
                label: '显示账户码',
                child: IconButton(
                  tooltip: '显示账户码',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => showWalletQrDialog(
                    context,
                    accountId: account.accountId,
                    accountName: account.accountName,
                    ss58Address: account.ss58Address,
                  ),
                  icon: const Icon(
                    Icons.qr_code_rounded,
                    size: 20,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
