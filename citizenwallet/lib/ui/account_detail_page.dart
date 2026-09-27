import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/screenshot_guard.dart';
import '../wallet/wallet_manager.dart';
import 'app_theme.dart';
import 'widgets/wallet_qr_dialog.dart';

/// Lv3 账户详情：某钱包(master)下单个账户的公钥、ss58、私钥（账户名可点击改名）。
///
/// model B 全 `//index`：每账户私钥（child mini-secret）独立、单向,导出单账户只
/// 暴露该账户,不牵连根/兄弟。私钥展示前需生物识别 + 防截屏 + 纯文本不可复制。
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({
    super.key,
    required this.account,
    required this.walletName,
  });

  final Account account;
  final String walletName;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  final WalletManager _walletManager = WalletManager();

  late String _accountName;

  String? _privateKey;
  bool _privateKeyVisible = false;
  bool _screenshotGuardActive = false;
  Future<void>? _screenshotGuardOpening;
  int _securityEpoch = 0;

  @override
  void initState() {
    super.initState();
    _accountName = widget.account.accountName;
  }

  @override
  void dispose() {
    if (_screenshotGuardActive) {
      unawaited(ScreenshotGuard.disable(_onSecurityEvent));
    }
    super.dispose();
  }

  Future<void> _enableScreenshotGuard() {
    if (_screenshotGuardActive) return Future<void>.value();
    return _screenshotGuardOpening ??= _openScreenshotGuard();
  }

  Future<void> _openScreenshotGuard() async {
    try {
      await ScreenshotGuard.enable(_onSecurityEvent);
      if (!mounted) {
        await ScreenshotGuard.disable(_onSecurityEvent);
        return;
      }
      _screenshotGuardActive = true;
    } finally {
      _screenshotGuardOpening = null;
    }
  }

  void _onSecurityEvent(String event) {
    if (!mounted) return;
    if (event == 'screenshot_taken' ||
        event == 'screen_recording_started' ||
        event == 'protection_failed') {
      _securityEpoch++;
      if (event == 'protection_failed' && _screenshotGuardActive) {
        _screenshotGuardActive = false;
        unawaited(ScreenshotGuard.disable(_onSecurityEvent));
      }
      setState(() {
        _privateKeyVisible = false;
        _privateKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            event == 'protection_failed'
                ? '屏幕保护不可用，私钥已隐藏'
                : event == 'screenshot_taken'
                ? '检测到截屏，私钥已隐藏。请勿截屏保存私钥。'
                : '检测到屏幕录制，私钥已隐藏',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
    if (confirmed != true) return;
    try {
      final epoch = _securityEpoch;
      // 确认原生保护成功后才进行私钥派生和页面展示。
      await _enableScreenshotGuard();
      if (!mounted ||
          !_screenshotGuardActive ||
          !ScreenshotGuard.canDisplaySensitiveContent ||
          epoch != _securityEpoch)
        return;
      final key = await _walletManager.getAccountPrivateKey(
        widget.account.accountId,
      );
      // 派生期间若保护失效，丢弃这次结果而不是重新显示私钥。
      if (!mounted ||
          !_screenshotGuardActive ||
          !ScreenshotGuard.canDisplaySensitiveContent ||
          epoch != _securityEpoch)
        return;
      setState(() {
        _privateKey = key;
        _privateKeyVisible = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('验证失败：${walletErrorMessage(e)}')));
    }
  }

  Future<void> _renameAccount() async {
    final controller = TextEditingController(text: _accountName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名账户'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: WalletManager.maxAccountNameLength,
          decoration: const InputDecoration(
            hintText: '请输入新名称',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await _walletManager.renameAccount(widget.account.accountId, newName);
      if (!mounted) return;
      setState(() => _accountName = newName.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账户'),
        content: Text(
          '确定删除「$_accountName」？\n'
          '该账户可用钱包助记词重新派生找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _walletManager.deleteAccount(widget.account.accountId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
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

  void _showWalletQr() {
    // 与钱包详情页账户列表共用同一份弹窗与载荷,禁止各造一份。
    showWalletQrDialog(
      context,
      accountId: widget.account.accountId,
      accountName: _accountName,
      ss58Address: widget.account.ss58Address,
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(title: const Text('账户详情'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 账户名可点击改名（编辑图标示意）。
                      Semantics(
                        button: true,
                        label: '重命名账户',
                        onTap: _renameAccount,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _renameAccount,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _accountName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.edit_outlined,
                                    size: 15,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.walletName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: '显示账户码',
                  child: IconButton(
                    tooltip: '显示账户码',
                    onPressed: _showWalletQr,
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.qr_code_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 公开信息 + 私钥（默认隐藏，验证后显示该账户 child mini-secret）
          Container(
            decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
            child: Column(
              children: [
                _infoTile('公钥', '（给电脑看的）', account.accountId),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _infoTile('账户地址', '（给人看的）', account.ss58Address),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildPrivateKeyTile(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (account.accountIndex != 0)
            OutlinedButton.icon(
              onPressed: _confirmDeleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除该账户'),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivateKeyTile() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text.rich(
            TextSpan(
              text: '私钥',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              children: [
                // 与公钥、账户地址的括号副标题使用同一视觉层级。
                TextSpan(
                  text: '（只能自己悄悄看）',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!_privateKeyVisible)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _revealPrivateKey,
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
                        '点击查看私钥',
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
                _privateKey ?? '无数据',
                style: const TextStyle(
                  fontSize: 13,
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
                    '请手抄备份，不支持复制；导出即等于该账户控制权',
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _privateKeyVisible = false;
                    _privateKey = null;
                  }),
                  icon: const Icon(Icons.visibility_off_rounded, size: 16),
                  label: const Text('隐藏'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoTile(String label, String subLabel, String value) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主标签 + 括号副标签:副标签缩小减淡,与主标签形成差异。
          Text.rich(
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: subLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AppTheme.primaryLight,
                ),
                onPressed: () => _copy(value, label),
                tooltip: '复制',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
