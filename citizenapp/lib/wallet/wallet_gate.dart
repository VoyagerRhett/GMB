import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/my/myid/myid_page.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

/// 应用级账户门禁：CitizenSDK 中存在任一可用热／冷账户即可放行业务页面。
///
/// 目录为空时直接启动 SDK 唯一初始化窗口；任一热／冷账户均放行。SDK 负责
/// 创建、助记词导入和账户码冷导入，本页只保留加载、错误与初始化后身份引导。
class WalletGate extends StatefulWidget {
  const WalletGate({
    super.key,
    required this.child,
    this.walletStateLoader,
    this.walletInitializer,
    this.onInitialized,
    this.loadTimeout = const Duration(seconds: 5),
  });

  final Widget child;
  final Future<CitizenWalletState> Function()? walletStateLoader;
  final Future<CitizenWalletState> Function()? walletInitializer;
  final void Function(BuildContext context)? onInitialized;

  @visibleForTesting
  final Duration loadTimeout;

  @override
  State<WalletGate> createState() => _WalletGateState();
}

enum _GateStatus { checking, needsWallet, ready }

class _WalletGateState extends State<WalletGate> {
  _GateStatus _status = _GateStatus.checking;
  AccountSecurityService? _security;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<AccountSecurityService>();
    if (identical(next, _security)) return;
    _security?.revision.removeListener(_onWalletStateMayHaveChanged);
    _security = next;
    next.revision.addListener(_onWalletStateMayHaveChanged);
  }

  @override
  void dispose() {
    _security?.revision.removeListener(_onWalletStateMayHaveChanged);
    super.dispose();
  }

  Future<CitizenWalletState> _loadState() {
    final loader =
        widget.walletStateLoader ?? context.read<CitizenSdk>().wallet.getState;
    return loader().timeout(widget.loadTimeout);
  }

  Future<void> _check() async {
    try {
      final state = await _loadState();
      if (!mounted) return;
      setState(() {
        _error = null;
        _status =
            state.accounts.isEmpty ? _GateStatus.needsWallet : _GateStatus.ready;
      });
      if (state.accounts.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_initializeWallet());
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  void _onWalletStateMayHaveChanged() {
    if (!mounted || _status != _GateStatus.ready) return;
    unawaited(_kickOutIfNoWalletAccount());
  }

  Future<void> _kickOutIfNoWalletAccount() async {
    CitizenWalletState state;
    try {
      state = await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
      return;
    }
    if (!mounted || state.accounts.isNotEmpty) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    setState(() => _status = _GateStatus.needsWallet);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeWallet());
    });
  }

  Future<void> _initializeWallet() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final state = await (widget.walletInitializer?.call() ??
          context.read<CitizenSdk>().wallet.initialize(
            content: CitizenWalletInitializationContent(
              walletAccountRoleText:
                  '钱包账户是 公民App 唯一的账户，请务必妥善保存助记词和钱包密码（如设置），若丢失或遗忘将永久无法找回。',
              walletAuthorizationText:
                  '每次动钱动权（转账/投票/发布）需通过指纹或人脸验证',
              walletCompletionText: '创建完成后进入公民广场',
              walletBackupText:
                  '公民不保存助记词，关闭本弹窗后将无法再次显示。请立即手抄备份，或在「公民钱包」中妥善保管——这是恢复钱包与追加其他账户的唯一凭证。设置过钱包密码时，还必须单独备份密码。不支持复制，不支持截屏。',
              walletColdAccountText:
                  '私钥保存在 公民钱包 签名设备上，签名请通过 公民钱包 扫码完成。',
            ),
          ));
      if (!mounted) return;
      if (state.accounts.isEmpty) {
        throw const CitizenSdkException(
          code: CitizenSdkErrorCode.integrity,
          message: '钱包初始化完成但账户目录仍为空',
        );
      }
      setState(() => _status = _GateStatus.ready);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (widget.onInitialized ?? _introduceIdentity)(context);
      });
    } on CitizenSdkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _introduceIdentity(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyIdPage()),
    );
  }

  void _retry() {
    setState(() {
      _error = null;
      _status = _GateStatus.checking;
    });
    unawaited(_check());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorPage(context);
    return switch (_status) {
      _GateStatus.checking => Scaffold(
          body: Center(
            child: SizedBox(
              width: AppLayout.scaled(context, 24),
              height: AppLayout.scaled(context, 24),
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      _GateStatus.needsWallet => Scaffold(
          body: Center(
            child: SizedBox(
              width: AppLayout.scaled(context, 24),
              height: AppLayout.scaled(context, 24),
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      _GateStatus.ready => widget.child,
    };
  }

  Widget _errorPage(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: AppLayout.scaled(context, 40),
                color: AppTheme.textTertiary,
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.scaled(context, 32),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 14),
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),
              FilledButton(onPressed: _retry, child: const Text('重试')),
            ],
          ),
        ),
      );

  static String _message(Object error) => switch (error) {
        CitizenSdkException value => value.message,
        _ => '本地钱包读取失败：$error',
      };
}
