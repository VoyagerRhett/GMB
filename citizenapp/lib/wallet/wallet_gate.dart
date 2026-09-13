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
/// 创建、导入和助记词输入全部由 SDK 安全窗口承担；本页只保留 CitizenApp 的入口、
/// 加载、错误与初始化后身份引导，不保存钱包资料或秘密副本。
class WalletGate extends StatefulWidget {
  const WalletGate({
    super.key,
    required this.child,
    this.walletStateLoader,
    this.onInitialized,
    this.loadTimeout = const Duration(seconds: 5),
  });

  final Widget child;
  final Future<CitizenWalletState> Function()? walletStateLoader;
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
  }

  Future<void> _openWalletFlow({required bool importing}) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final wallet = context.read<CitizenSdk>().wallet;
      if (importing) {
        await wallet.importWallet();
      } else {
        await wallet.create();
      }
      if (!mounted) return;
      setState(() => _status = _GateStatus.ready);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (widget.onInitialized ?? _introduceIdentity)(context);
      });
    } on CitizenSdkException catch (error) {
      if (!mounted || error.code == CitizenSdkErrorCode.cancelled) return;
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
      _GateStatus.needsWallet => _walletEntry(context),
      _GateStatus.ready => widget.child,
    };
  }

  Widget _walletEntry(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppLayout.scaled(context, 420),
              ),
              child: Padding(
                padding: EdgeInsets.all(AppLayout.scaled(context, 24)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: AppLayout.scaled(context, 56),
                      height: AppLayout.scaled(context, 56),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 16)),
                    Text(
                      '创建钱包',
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 20),
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 8)),
                    const Text(
                      '钱包账户是 公民App 唯一的账户。助记词、密码和私钥只会进入公民软件包安全界面。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 24)),
                    SizedBox(
                      width: double.infinity,
                      height: AppLayout.scaled(context, 48),
                      child: FilledButton(
                        onPressed: _submitting
                            ? null
                            : () => _openWalletFlow(importing: false),
                        child: Text(_submitting ? '处理中…' : '创建钱包'),
                      ),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 8)),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => _openWalletFlow(importing: true),
                      child: const Text('已有钱包？导入助记词'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

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
