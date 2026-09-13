import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';

import '../ui/app_theme.dart';
import 'app_lock_service.dart';
import 'account_security_service.dart';
import 'emergency_wipe_platform.dart';

import 'package:citizenapp/ui/app_layout.dart';

/// 在设置页内输入并确认独立的防共匪密码。
Future<bool> showDuressModeSetupDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _DuressModeSetupDialog(),
      ) ??
      false;
}

class _DuressModeSetupDialog extends StatefulWidget {
  const _DuressModeSetupDialog();

  @override
  State<_DuressModeSetupDialog> createState() => _DuressModeSetupDialogState();
}

class _DuressModeSetupDialogState extends State<_DuressModeSetupDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text;
    if (!RegExp(r'^\d{6}$').hasMatch(pin) ||
        !RegExp(r'^\d{6}$').hasMatch(_confirmController.text)) {
      setState(() => _error = '请输入两次 6 位数字密码');
      return;
    }
    if (pin != _confirmController.text) {
      setState(() => _error = '两次输入不一致');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await AppLockService.setDuressModePin(pin);
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _saving = false;
          _error = '防共匪密码不能与应用锁密码相同';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatters = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('设置防共匪密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pinController,
              enabled: !_saving,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: formatters,
              decoration: const InputDecoration(labelText: '输入 6 位数字密码'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              enabled: !_saving,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: formatters,
              decoration: const InputDecoration(labelText: '再次输入密码'),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

/// PIN 输入模式。
enum PinInputMode {
  /// 设置新 PIN：输入两次。
  setup,

  /// 验证 PIN：输入一次。
  verify,

  /// 关闭 PIN：输入一次验证后删除。
  remove,
}

/// 6 位 PIN 输入页面。
///
/// [mode] 决定行为：
/// - [PinInputMode.setup]：输入两次设置 PIN，成功 pop(true)
/// - [PinInputMode.verify]：输入一次验证，成功 pop(true)
/// - [PinInputMode.remove]：输入一次验证后删除 PIN，成功 pop(true)
class PinInputPage extends StatefulWidget {
  const PinInputPage({super.key, required this.mode});

  final PinInputMode mode;

  @override
  State<PinInputPage> createState() => _PinInputPageState();
}

class _PinInputPageState extends State<PinInputPage> {
  static const int pinLength = 6;

  String _pin = '';
  String? _firstPin; // setup 模式下第一次输入的 PIN
  String _title = '';
  String _subtitle = '';
  String? _error;
  bool _locked = false;
  bool _submitting = false;
  bool _wipeTerminal = false;
  int _remainingSeconds = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _initState() async {
    // 先检查是否被锁定
    if (widget.mode == PinInputMode.verify) {
      final locked = await AppLockService.isLocked();
      if (!mounted) return;
      if (locked) {
        await _startLockCountdown();
        return;
      }
    }
    if (!mounted) return;
    _updateTitle();
  }

  void _updateTitle() {
    switch (widget.mode) {
      case PinInputMode.setup:
        setState(() {
          _title = _firstPin == null ? '设置应用密码' : '请再次输入';
          _subtitle = _firstPin == null ? '请输入 6 位数字密码' : '确认您的密码';
        });
      case PinInputMode.verify:
        setState(() {
          _title = '输入应用密码';
          _subtitle = '请输入 6 位数字密码';
        });
      case PinInputMode.remove:
        setState(() {
          _title = '关闭应用锁';
          _subtitle = '请输入当前密码以关闭';
        });
    }
  }

  Future<void> _startLockCountdown() async {
    final remaining = await AppLockService.getRemainingLockSeconds();
    if (!mounted) return;
    if (remaining <= 0) {
      _updateTitle();
      return;
    }
    setState(() {
      _locked = true;
      _remainingSeconds = remaining;
    });
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final r = await AppLockService.getRemainingLockSeconds();
      if (!mounted) return;
      if (r <= 0) {
        _lockTimer?.cancel();
        setState(() {
          _locked = false;
          _remainingSeconds = 0;
        });
        _updateTitle();
      } else {
        setState(() => _remainingSeconds = r);
      }
    });
  }

  void _onDigit(int digit) {
    if (_pin.length >= pinLength || _locked || _submitting || _wipeTerminal) {
      return;
    }
    setState(() {
      _pin += digit.toString();
      _error = null;
    });
    // 数字必须先进入本地状态；触觉反馈走平台通道，不得阻塞快速连续输入。
    unawaited(HapticFeedback.lightImpact());
    if (_pin.length == pinLength) {
      unawaited(_onPinComplete());
    }
  }

  void _onDelete() {
    if (_pin.isEmpty || _locked || _submitting || _wipeTerminal) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _onPinComplete() async {
    if (_submitting || _wipeTerminal) return;
    setState(() => _submitting = true);
    try {
      switch (widget.mode) {
        case PinInputMode.setup:
          await _handleSetup();
        case PinInputMode.verify:
          await _handleVerify();
        case PinInputMode.remove:
          await _handleRemove();
      }
    } on AppDataWipeException {
      await _showWipeFailureTerminal();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _error = '操作未完成，请稍后重试';
      });
    } finally {
      if (mounted && !_wipeTerminal) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _handleSetup() async {
    if (_firstPin == null) {
      // 第一次输入
      _firstPin = _pin;
      setState(() => _pin = '');
      _updateTitle();
    } else {
      // 第二次输入
      if (_pin == _firstPin) {
        await AppLockService.setPin(_pin);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        _firstPin = null;
        setState(() {
          _pin = '';
          _error = '两次输入不一致，请重新设置';
        });
        _updateTitle();
      }
    }
  }

  Future<void> _handleVerify() async {
    final result = await AppLockService.verifyPin(
      _pin,
      wallet: context.read<CitizenSdk?>()?.wallet,
      accountSecurity: context.read<AccountSecurityService?>(),
    );
    if (!mounted) return;

    switch (result) {
      case AppPinVerificationResult.verified:
        Navigator.of(context).pop(true);
      case AppPinVerificationResult.duressMode:
        // 独立六位防共匪密码单次命中即进入不可逆擦除，不保留内存中间态。
        await _triggerDuressModeWipe();
      case AppPinVerificationResult.dataWiped:
        await _showDataWipedTerminal();
      case AppPinVerificationResult.locked:
        setState(() => _pin = '');
        await _startLockCountdown();
      case AppPinVerificationResult.rejected:
        await _showRejectedPin();
    }
  }

  Future<void> _handleRemove() async {
    final result = await AppLockService.verifyNormalPin(
      _pin,
      wallet: context.read<CitizenSdk?>()?.wallet,
      accountSecurity: context.read<AccountSecurityService?>(),
    );
    if (!mounted) return;

    switch (result) {
      case AppPinVerificationResult.verified:
        await AppLockService.removePin();
        if (!mounted) return;
        Navigator.of(context).pop(true);
      case AppPinVerificationResult.duressMode:
        await _showRejectedPin();
      case AppPinVerificationResult.dataWiped:
        await _showDataWipedTerminal();
      case AppPinVerificationResult.locked:
        setState(() => _pin = '');
        await _startLockCountdown();
      case AppPinVerificationResult.rejected:
        await _showRejectedPin();
    }
  }

  Future<void> _triggerDuressModeWipe() async {
    final wallet = context.read<CitizenSdk?>()?.wallet;
    final accountSecurity = context.read<AccountSecurityService?>();
    // 必须先持久化擦除意图；只有门闩落盘成功才允许隐藏真实界面。
    await AppLockService.latchPersistentWipe();
    if (!mounted) return;
    _wipeTerminal = true;
    setState(() {
      _submitting = true;
      _pin = '';
      _error = null;
    });
    // 先让不可返回的中性页面完成绘制，再请求 Android 退到后台；禁止继续暴露密码页。
    await Future.any<void>(<Future<void>>[
      WidgetsBinding.instance.endOfFrame,
      // 某些嵌入器在当前帧之后不再回报 endOfFrame；短兜底不能阻塞擦除启动。
      Future<void>.delayed(const Duration(milliseconds: 50)),
    ]);
    await EmergencyWipePlatform.beginProtectedExecution();
    while (mounted) {
      try {
        await AppLockService.wipeAllData(
          wallet: wallet,
          accountSecurity: accountSecurity,
        );
        await EmergencyWipePlatform.finishProtectedExecution();
        await SystemNavigator.pop();
        return;
      } catch (_) {
        // 不可逆状态下不再询问或允许退出；当前进程自动重试，进程被杀后由启动门闩恢复。
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _showRejectedPin() async {
    final failCount = await AppLockService.getFailCount();
    if (!mounted) return;
    final remaining = (AppLockService.maxFailAttempts - failCount).clamp(
      0,
      999,
    );
    setState(() {
      _pin = '';
      _error = '密码错误，还可尝试 $remaining 次';
    });
  }

  Future<void> _showDataWipedTerminal() async {
    if (!mounted) return;
    _wipeTerminal = true;
    setState(() {
      _submitting = true;
      _pin = '';
      _error = null;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('数据已清空'),
          content: const Text('应用数据已全部清空。请退出并重新启动应用。'),
          actions: [
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('退出'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWipeFailureTerminal() async {
    if (!mounted) return;
    _wipeTerminal = true;
    setState(() {
      _submitting = false;
      _pin = '';
      _error = null;
    });
    while (true) {
      if (!mounted) return;
      var choiceMade = false;
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('数据清理未完成'),
            content: const Text('为保护本机数据，只能重试擦除或退出应用。'),
            actions: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        if (choiceMade) return;
                        choiceMade = true;
                        Navigator.of(dialogContext).pop(false);
                      },
                child: const Text('退出'),
              ),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () {
                        if (choiceMade) return;
                        choiceMade = true;
                        Navigator.of(dialogContext).pop(true);
                      },
                child: const Text('重试擦除'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (retry != true) {
        await SystemNavigator.pop();
        return;
      }
      setState(() => _submitting = true);
      try {
        await AppLockService.wipeAllData(
          wallet: context.read<CitizenSdk?>()?.wallet,
          accountSecurity: context.read<AccountSecurityService?>(),
        );
        if (!mounted) return;
        await _showDataWipedTerminal();
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _submitting = false);
        // 不展示底层数据域或文件路径，回到同一终态对话继续重试。
      }
    }
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours 小时 $minutes 分 $seconds 秒';
    }
    if (minutes > 0) {
      return '$minutes 分 $seconds 秒';
    }
    return '$seconds 秒';
  }

  @override
  Widget build(BuildContext context) {
    if (_wipeTerminal) {
      return const PopScope(
        canPop: false,
        child: ColoredBox(color: Colors.black),
      );
    }
    return Scaffold(
      appBar: widget.mode != PinInputMode.verify
          ? AppBar(title: Text(_title), centerTitle: true)
          : null,
      body: SafeArea(child: _locked ? _buildLockedView() : _buildPinView()),
    );
  }

  Widget _buildLockedView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppLayout.scaledValue(80),
              height: AppLayout.scaledValue(80),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.danger.withAlpha(20),
              ),
              child: Icon(
                Icons.lock_clock,
                size: AppLayout.scaledValue(44),
                color: AppTheme.danger,
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(24)),
            Text(
              '应用已锁定',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(20),
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(12)),
            Text(
              '连续验证错误次数过多\n请在 ${_formatDuration(_remainingSeconds)} 后重试',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(14),
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinView() {
    return Column(
      children: [
        const Spacer(flex: 2),
        if (widget.mode == PinInputMode.verify) ...[
          Container(
            width: AppLayout.scaledValue(72),
            height: AppLayout.scaledValue(72),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.primaryGradient,
            ),
            child: Icon(
              Icons.lock_outline,
              size: AppLayout.scaledValue(36),
              color: AppTheme.textOnPrimary,
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
        ],
        Text(
          widget.mode == PinInputMode.verify ? _title : _subtitle,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(16),
            color: AppTheme.textSecondary,
          ),
        ),
        if (widget.mode == PinInputMode.setup && _firstPin == null) ...[
          SizedBox(height: AppLayout.scaledValue(8)),
          Container(
            margin: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(48)),
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaledValue(12),
              vertical: AppLayout.scaledValue(8),
            ),
            decoration: AppTheme.bannerDecoration(AppTheme.warning),
            child: Text(
              '请牢记密码。忘记密码将清空所有数据。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(12),
                color: AppTheme.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        SizedBox(height: AppLayout.scaledValue(32)),
        // PIN 圆点指示器
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pinLength, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(8),
              ),
              width: AppLayout.scaledValue(filled ? 18 : 16),
              height: AppLayout.scaledValue(filled ? 18 : 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: filled ? AppTheme.primary : AppTheme.border,
                  width: 2,
                ),
                boxShadow: filled
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(40),
                          blurRadius: AppLayout.scaledValue(8),
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),
        if (_error != null) ...[
          SizedBox(height: AppLayout.scaledValue(12)),
          Text(
            _error!,
            style: TextStyle(
              color: AppTheme.danger,
              fontSize: AppLayout.scaledValue(13),
            ),
          ),
        ],
        if (_submitting && !_wipeTerminal) ...[
          SizedBox(height: AppLayout.scaledValue(12)),
          const CircularProgressIndicator(),
        ],
        const Spacer(flex: 1),
        // 数字键盘
        _buildKeypad(),
        SizedBox(height: AppLayout.scaledValue(32)),
      ],
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(48)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_key(1), _key(2), _key(3)],
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_key(4), _key(5), _key(6)],
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_key(7), _key(8), _key(9)],
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 空白占位
              SizedBox(
                width: AppLayout.scaledValue(72),
                height: AppLayout.scaledValue(72),
              ),
              _key(0),
              // 删除键
              SizedBox(
                width: AppLayout.scaledValue(72),
                height: AppLayout.scaledValue(72),
                child: IconButton(
                  onPressed: _submitting || _wipeTerminal ? null : _onDelete,
                  icon: Icon(
                    Icons.backspace_outlined,
                    size: AppLayout.scaledValue(24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(int digit) {
    final enabled = !_submitting && !_wipeTerminal;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '数字 $digit',
      onTap: enabled ? () => _onDigit(digit) : null,
      excludeSemantics: true,
      child: SizedBox(
        width: AppLayout.scaledValue(72),
        height: AppLayout.scaledValue(72),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(
            side: BorderSide(color: AppTheme.borderLight, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            // 固定键盘在按下时立即登记；读屏点击由外层 Semantics 单独处理。
            onTapDown: enabled ? (_) => _onDigit(digit) : null,
            onTap: enabled ? () {} : null,
            customBorder: const CircleBorder(),
            splashColor: AppTheme.primary.withAlpha(30),
            child: Center(
              child: Text(
                '$digit',
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(28),
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
