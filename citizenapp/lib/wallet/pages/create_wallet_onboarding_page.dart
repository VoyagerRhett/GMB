import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart' show ImportColdWalletPage;
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/pages/create_wallet_flow.dart';
import 'package:citizenapp/wallet/pages/import_wallet_page.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/widgets/wallet_password.dart';

/// 首次没有冷热账户时承载原初始化UI；SDK负责真实状态与输入、持久化规则。
/// 原创建/导入布局保留，只增加已批准的18词与冷账户入口；冷入口不依赖本机热金库。
class CreateWalletOnboardingPage extends StatefulWidget {
  const CreateWalletOnboardingPage({
    super.key,
    required this.onCreated,
    this.deviceSecureProbe,
  });

  /// 钱包就绪回调（创建或导入成功后触发，WalletGate 收到翻转到主界面）。
  final VoidCallback onCreated;

  /// UI测试可注入探测；正式运行只读取SDK的系统安全能力事实。
  final Future<bool> Function()? deviceSecureProbe;

  @override
  State<CreateWalletOnboardingPage> createState() =>
      _CreateWalletOnboardingPageState();
}

class _CreateWalletOnboardingPageState extends State<CreateWalletOnboardingPage>
    with WidgetsBindingObserver {
  /// null = 检测中；createWallet 前置要求系统锁屏已开启，未开启时禁用创建。
  bool? _deviceSecure;
  bool _creating = false;
  bool _createInFlight = false;
  int _wordCount = 12;
  String? _error;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeDeviceSecure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户去系统设置开完锁屏回到前台，自动复检。
    if (state == AppLifecycleState.resumed) {
      _probeDeviceSecure();
    }
  }

  Future<void> _probeDeviceSecure() async {
    bool secure;
    try {
      final probe = widget.deviceSecureProbe;
      if (probe != null) {
        secure = await probe();
      } else {
        final capabilities = await context.read<CitizenSdk>().getCapabilities();
        secure = capabilities[CitizenCapabilityName.hardwareVault].available &&
            capabilities[CitizenCapabilityName.userAuthentication].available;
      }
    } catch (_) {
      // 探测不可用按未开锁屏处理（fail-closed），与 createWallet 的前置一致。
      secure = false;
    }
    if (!mounted) return;
    setState(() => _deviceSecure = secure);
  }

  Future<void> _create() async {
    // SDK校验是异步的；只锁住本次入口，不提前改变原按钮文案或密码确认时序。
    if (_createInFlight) return;
    _createInFlight = true;
    try {
      late final String password;
      try {
        password = _passwordController.text;
        await validateWalletPasswordInput(context, password);
        if (!mounted) return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = '$e');
        return;
      }
      if (!await confirmWalletPasswordUse(context, password) || !mounted) return;
      // 确认后立即清空可见输入；原始输入只交SDK校验和规范化，不把 password
      // 留在页面 controller、钱包数据库或安全存储。
      _passwordController.clear();
      setState(() {
        _creating = true;
        _error = null;
      });
      try {
        await runCreateWalletFlow(
          context,
          wordCount: _wordCount,
          password: password,
        );
        if (!mounted) return;
        widget.onCreated();
      } catch (e) {
        AppLog.d('onboarding wallet create failed');
        if (!mounted) return;
        setState(() => _error = walletOperationErrorMessage(e));
        // 创建失败常见原因是锁屏状态变化，顺手复检刷新警示卡。
        _probeDeviceSecure();
        // fail-closed：钱包失败及恢复事实由SDK维护，弹窗提示后停留创建页可重试。
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('创建钱包失败'),
            content: Text(walletOperationErrorMessage(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _creating = false);
        }
      }
    } finally {
      _createInFlight = false;
    }
  }

  Future<void> _openImport() async {
    // 复用 ImportWalletPage：其内部 importWallet 为 fail-closed（钱包本地落库成功才
    // pop(true)，失败弹窗并保留助记词）。设备子钥同样不在导入时注册；实际业务确认
    // 缺钥时才鉴权一次生成，页面门禁不参与。
    // 返回 true 即钱包就绪，放行进 App。
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportWalletPage()),
    );
    if (!mounted) return;
    if (imported == true) {
      widget.onCreated();
    }
  }

  Future<void> _openColdImport() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportColdWalletPage()),
    );
    if (mounted && imported == true) widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _deviceSecure == true && !_creating;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: AppLayout.scaled(context, 420)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                children: [
                  Center(
                    child: Container(
                      width: AppLayout.scaled(context, 56),
                      height: AppLayout.scaled(context, 56),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius:
                            BorderRadius.circular(AppLayout.scaledValue(14)),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.white,
                        size: AppLayout.scaled(context, 26),
                      ),
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 16)),
                  Text(
                    '创建钱包',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 20),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  Text(
                    '钱包账户是 公民App 唯一的账户，请务必妥善保存助记词和钱包密码（如设置），'
                    '若丢失或遗忘将永久无法找回。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 13),
                      height: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 24)),
                  if (_deviceSecure == false) ...[
                    _buildDeviceLockWarning(),
                    SizedBox(height: AppLayout.scaled(context, 16)),
                  ],
                  Text(
                    '助记词长度',
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  _WordCountCard(
                    wordCount: 12,
                    subtitle: '128 位熵 · 标准安全强度',
                    recommended: true,
                    selected: _wordCount == 12,
                    onTap: () => setState(() => _wordCount = 12),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 10)),
                  _WordCountCard(
                    wordCount: 18,
                    subtitle: '192 位熵 · 安全性更高',
                    recommended: false,
                    selected: _wordCount == 18,
                    onTap: () => setState(() => _wordCount = 18),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 10)),
                  _WordCountCard(
                    wordCount: 24,
                    subtitle: '256 位熵 · 安全性更高',
                    recommended: false,
                    selected: _wordCount == 24,
                    onTap: () => setState(() => _wordCount = 24),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 16)),
                  WalletPasswordField(controller: _passwordController),
                  SizedBox(height: AppLayout.scaled(context, 20)),
                  const _SecurityNoteRow(
                    icon: Icons.vpn_key_outlined,
                    text: '账户私钥经硬件加密储存在本机，本机不会保存助记词',
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  const _SecurityNoteRow(
                    icon: Icons.lock_outline,
                    text: '每次动钱动权（转账/投票/发布）需通过指纹或人脸验证',
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  const _SecurityNoteRow(
                    icon: Icons.edit_outlined,
                    text: '请手抄助记词；设置密码时还必须单独记住密码',
                  ),
                  SizedBox(height: AppLayout.scaled(context, 24)),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 12),
                        color: AppTheme.danger,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 8)),
                  ],
                  SizedBox(
                    height: AppLayout.scaled(context, 48),
                    child: FilledButton(
                      onPressed: canCreate ? _create : null,
                      child: Text(_creating ? '创建中…' : '创建钱包'),
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 10)),
                  Text(
                    _deviceSecure == false ? '开启系统锁屏后可创建' : '创建完成后进入公民广场',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 11),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  TextButton(
                    onPressed: canCreate ? _openImport : null,
                    child: const Text('已有钱包？导入助记词'),
                  ),
                  TextButton(
                    onPressed: _creating ? null : _openColdImport,
                    child: const Text('导入冷钱包'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceLockWarning() {
    return Container(
      padding: EdgeInsets.all(AppLayout.scaledValue(14)),
      decoration: AppTheme.bannerDecoration(AppTheme.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: AppLayout.scaledValue(18),
                color: AppTheme.warning,
              ),
              SizedBox(width: AppLayout.scaledValue(8)),
              Expanded(
                child: Text(
                  '未检测到系统锁屏',
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(13),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppLayout.scaledValue(6)),
          Padding(
            padding: EdgeInsets.only(left: AppLayout.scaledValue(26)),
            child: Text(
              '钱包密钥依赖系统锁屏保护。请先在系统设置中开启屏幕锁定'
              '（数字密码、图案或生物识别），再返回创建。',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(12),
                height: 1.55,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(10)),
          Padding(
            padding: EdgeInsets.only(left: AppLayout.scaledValue(26)),
            child: OutlinedButton(
              onPressed: _probeDeviceSecure,
              child: const Text('重新检测'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordCountCard extends StatelessWidget {
  const _WordCountCard({
    required this.wordCount,
    required this.subtitle,
    required this.recommended,
    required this.selected,
    required this.onTap,
  });

  final int wordCount;
  final String subtitle;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaled(context, 14),
              vertical: AppLayout.scaled(context, 12)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$wordCount 个助记词',
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 15),
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? AppTheme.primaryDark
                                : AppTheme.textPrimary,
                          ),
                        ),
                        if (recommended) ...[
                          SizedBox(width: AppLayout.scaled(context, 6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppLayout.scaled(context, 7),
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(
                                  AppLayout.scaledValue(8)),
                            ),
                            child: Text(
                              '推荐',
                              style: TextStyle(
                                fontSize: AppLayout.scaled(context, 10.5),
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: AppLayout.scaled(context, 2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 11.5),
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: AppLayout.scaled(context, 20),
                color: selected ? AppTheme.primary : AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityNoteRow extends StatelessWidget {
  const _SecurityNoteRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: AppLayout.scaled(context, 15), color: AppTheme.primary),
        SizedBox(width: AppLayout.scaled(context, 8)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 11.5),
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
