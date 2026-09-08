import 'package:flutter/material.dart';
import 'package:citizenwallet/wallet/wallet_password.dart';

import '../util/sensitive_page_mixin.dart';
import '../wallet/wallet_manager.dart';
import 'widgets/bip39_input.dart';

/// 导入钱包页面（通过助记词）。
class ImportWalletPage extends StatefulWidget {
  const ImportWalletPage({super.key});

  @override
  State<ImportWalletPage> createState() => _ImportWalletPageState();
}

class _ImportWalletPageState extends State<ImportWalletPage>
    with SensitivePageMixin {
  final WalletManager _walletManager = WalletManager();
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final mnemonic = _mnemonicController.text.trim();
    if (mnemonic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入助记词')),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final password = WalletPassword.parse(_passwordController.text);
      if (!await confirmWalletPasswordUse(context, password) || !mounted) {
        return;
      }
      final result = await _walletManager.importWallet(
        mnemonic,
        password: password.value,
      );
      _mnemonicController.clear();
      _passwordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入「${result.wallet.walletName}」')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sensitiveContentHidden) {
      return buildHiddenPlaceholder(message: '助记词输入已隐藏');
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('输入助记词'),
        centerTitle: true,
      ),
      // 候选词 Wrap 位于输入框**下方**，键盘升起时最容易被盖住。
      // 顶部留白压到最小、标题与输入框间距收紧，把输入框和候选区整体上提，
      // 让候选词落在键盘上沿之上。
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          Bip39InputField(controller: _mnemonicController, wordCount: 0),
          const SizedBox(height: 16),
          WalletPasswordField(controller: _passwordController),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _importing ? null : _import,
            child: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('导入钱包'),
          ),
        ],
      ),
    );
  }
}
