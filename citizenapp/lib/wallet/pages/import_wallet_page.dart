import 'dart:async';

import 'package:flutter/material.dart';
import 'package:citizenapp/ui/widgets/bip39_input.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/wallet/pages/create_wallet_flow.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/widgets/wallet_password.dart';

/// 导入热钱包页：输入助记词 → 验证 → 落库。
///
/// **fail-closed**：`importWallet` 保证钱包本地落库成功才返回，此时 `pop(true)`
/// 交由调用方（钱包页 / 首启门禁）决定进入；失败按SDK真实终态抛出，弹窗提示后停留
/// 本页、助记词保留在输入框（仅成功路径 clear），用户可直接重试。设备子钥不在导入时
/// 注册；已有子钥直接使用，实际业务确认缺钥时才鉴权一次生成，不增加页面授权流程。
class ImportWalletPage extends StatefulWidget {
  const ImportWalletPage({super.key});

  @override
  State<ImportWalletPage> createState() => _ImportWalletPageState();
}

class _ImportWalletPageState extends State<ImportWalletPage> {
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isImporting = false;
  String? _error;
  CitizenSdkOperation<CitizenWalletProfile>? _operation;

  @override
  void initState() {
    super.initState();
    // 本页始终承载助记词与可选钱包密码，进入即持有进程级截屏保护。
    unawaited(ScreenshotGuard.enable());
  }

  Future<void> _import() async {
    setState(() {
      _error = null;
      _isImporting = true;
    });
    try {
      final password = _passwordController.text;
      await validateWalletPasswordInput(context, password);
      if (!mounted) return;
      if (!await confirmWalletPasswordUse(context, password) || !mounted) {
        return;
      }
      final mnemonic = _mnemonicController.text;
      final operation = context.read<CitizenSdk>().wallet.importWallet(
        mnemonic: mnemonic,
        password: password,
      );
      _operation = operation;
      await operation.result;
      if (!mounted) return;
      // 钱包名是本机标签，导入后保留本机默认值；公开昵称由 cid_number 对应的
      // display_name 独立恢复，本流程不得联网改写钱包标签。
      _mnemonicController.clear();
      _passwordController.clear();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = walletOperationErrorMessage(e);
      });
      // fail-closed：钱包失败与恢复事实由SDK维护。弹窗提示后停留导入页，
      // 助记词保留在输入框（仅成功路径 clear），用户可直接重试。
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入失败'),
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
      _operation = null;
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final operation = _operation;
    if (operation != null) unawaited(operation.cancel().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    unawaited(ScreenshotGuard.disable());
    _mnemonicController.clear();
    _passwordController.clear();
    _mnemonicController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('输入助记词')),
      body: ListView(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        children: [
          Bip39InputField(controller: _mnemonicController, wordCount: 0),
          SizedBox(height: AppLayout.scaled(context, 12)),
          WalletPasswordField(controller: _passwordController),
          SizedBox(height: AppLayout.scaled(context, 12)),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.danger),
            ),
          FilledButton(
            onPressed: _isImporting ? null : _import,
            child: Text(_isImporting ? '导入中...' : '确认导入'),
          ),
        ],
      ),
    );
  }
}
