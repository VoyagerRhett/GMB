import 'dart:async';

import 'package:flutter/material.dart';
import 'package:citizenapp/my/myid/myid_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/wallet/pages/create_wallet_flow.dart';
import 'package:citizenapp/wallet/pages/create_wallet_onboarding_page.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 原门禁UI由App承载；SDK的真实目录决定empty/ready/recovering，冷热同权。
/// 初始化页面仍等待原备份/导入交互结束，再切换页面；不弹SDK窗口。
class WalletGate extends StatefulWidget {
  const WalletGate({
    super.key,
    required this.child,
    this.walletStateLoader,
    this.onInitialized,
    this.loadTimeout = const Duration(seconds: 5),
  });

  final Widget child;

  /// SDK状态加载测试接线，不复制钱包状态或判定规则。
  final Future<CitizenWalletState> Function()? walletStateLoader;

  /// 首次初始化(本次会话从 onboarding 新建/导入钱包)后的一次性引导,测试注入用;默认把
  /// 用户带到身份页 [MyIdPage] 去注册身份(决策③:不改动主界面 5-tab 结构,返回即回落)。
  /// **冷启动即有钱包的老用户不经此路径**,不打扰。
  final void Function(BuildContext context)? onInitialized;

  /// 只限制一次本地钱包事实读取的等待时间；超时继续 fail-closed 并显示重试，
  /// 绝不能把未知状态当作“没有钱包”或直接放行。
  @visibleForTesting
  final Duration loadTimeout;

  @override
  State<WalletGate> createState() => _WalletGateState();
}

enum _GateStatus { checking, needsWallet, ready }

class _WalletGateState extends State<WalletGate> {
  _GateStatus _status = _GateStatus.checking;
  String? _error;
  StreamSubscription<CitizenSdkEvent>? _walletEvents;

  @override
  void initState() {
    super.initState();
    _walletEvents = context.read<CitizenSdk>().events.listen((event) {
      if (event is CitizenSdkWalletChanged) _onWalletsChanged();
    });
    unawaited(_check());
  }

  @override
  void dispose() {
    unawaited(_walletEvents?.cancel());
    super.dispose();
  }

  Future<CitizenWalletState> _loadState() {
    final loader = widget.walletStateLoader;
    if (loader != null) return loader().timeout(widget.loadTimeout);
    final operation = context.read<CitizenSdk>().wallet.getState();
    return operation.result.timeout(widget.loadTimeout, onTimeout: () async {
      // 只限制显示等待；转发真实取消，不把超时当作底层已结束或目录为空。
      await operation.cancel();
      throw TimeoutException('本地钱包读取超时', widget.loadTimeout);
    });
  }

  _GateStatus _statusFor(CitizenWalletState state) {
    return switch (state.initializationState) {
      CitizenWalletInitializationState.empty => _GateStatus.needsWallet,
      CitizenWalletInitializationState.ready => _GateStatus.ready,
      CitizenWalletInitializationState.recovering => throw const CitizenSdkException(
        code: CitizenSdkErrorCode.notReady, message: '钱包仍有未完成的本机操作计划',
      ),
    };
  }

  Future<void> _check() async {
    try {
      final wallet = await _loadState();
      if (!mounted) return;
      setState(() {
        _error = null;
        _status = _statusFor(wallet);
      });
    } catch (e) {
      // 本地库读取失败既不能误判成「无钱包」（会把老用户锁进创建页），
      // 也不能直接放行（无身份进广场），停在错误态由用户重试。
      if (!mounted) return;
      setState(() => _error = walletLocalStoreErrorMessage(e));
    }
  }

  /// 运行期钱包增删（我的 → 钱包列表）后重判。
  /// 只在已放行状态下才需要重判——其余状态本就没进 App。
  void _onWalletsChanged() {
    if (!mounted || _status != _GateStatus.ready) return;
    unawaited(_kickOutIfNoWallet());
  }

  Future<void> _kickOutIfNoWallet() async {
    CitizenWalletState wallet;
    try {
      wallet = await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = walletLocalStoreErrorMessage(e));
      return;
    }
    if (!mounted) return;
    if (wallet.initializationState == CitizenWalletInitializationState.ready) return;
    if (wallet.initializationState == CitizenWalletInitializationState.recovering) {
      setState(() => _error = '本地钱包读取失败：钱包仍有未完成的本机操作计划');
      return;
    }
    // 踢回前必须清空 AppShell 内已 push 的页面栈：删钱包这个动作本身就发生在
    // 深层页面（我的 → 钱包列表），不清栈的话初始化页会被旧页面盖住，
    // 用户看上去仍留在 App 里。
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    setState(() => _status = _GateStatus.needsWallet);
  }

  void _retry() {
    setState(() {
      _error = null;
      _status = _GateStatus.checking;
    });
    _check();
  }

  Future<void> _afterCreated() async {
    try {
      final state = await _loadState();
      if (!mounted) return;
      if (state.initializationState != CitizenWalletInitializationState.ready) {
        throw const CitizenSdkException(code: CitizenSdkErrorCode.notReady, message: '钱包初始化尚未完成');
      }
      setState(() => _status = _GateStatus.ready);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (widget.onInitialized ?? _introduceIdentity)(context);
      });
    } catch (error) {
      if (mounted) setState(() => _error = walletLocalStoreErrorMessage(error));
    }
  }

  /// 默认初始化引导:一次性 push 身份页(返回即回落主界面,不改动 5-tab 结构)。
  void _introduceIdentity(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyIdPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
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
                    horizontal: AppLayout.scaled(context, 32)),
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
              FilledButton(
                onPressed: _retry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_status) {
      case _GateStatus.checking:
        return Scaffold(
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
        );
      case _GateStatus.needsWallet:
        return CreateWalletOnboardingPage(
          onCreated: () => unawaited(_afterCreated()),
        );
      case _GateStatus.ready:
        return widget.child;
    }
  }
}
