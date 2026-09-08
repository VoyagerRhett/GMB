import 'package:flutter/material.dart';
import 'package:citizenwallet/wallet/wallet_password.dart';

import '../util/sensitive_page_mixin.dart';
import '../wallet/wallet_manager.dart';
import 'app_theme.dart';

/// 创建新钱包页面。
///
/// 创建成功后展示助记词，要求用户确认已备份。
class CreateWalletPage extends StatefulWidget {
  const CreateWalletPage({super.key});

  @override
  State<CreateWalletPage> createState() => _CreateWalletPageState();
}

class _CreateWalletPageState extends State<CreateWalletPage>
    with SensitivePageMixin {
  final WalletManager _walletManager = WalletManager();
  bool _creating = false;
  int _wordCount = 12;
  WalletCreationResult? _result;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    late final WalletPassword password;
    try {
      password = WalletPassword.parse(_passwordController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!await confirmWalletPasswordUse(context, password) || !mounted) return;
    // password 只参与本次派生，确认后立即清空输入框且绝不持久化。
    _passwordController.clear();
    setState(() => _creating = true);
    try {
      final result = await _walletManager.createWallet(
        wordCount: _wordCount,
        password: password.value,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _confirmBackup() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // 截屏/录屏时隐藏助记词展示
    if (sensitiveContentHidden && _result != null) {
      return buildHiddenPlaceholder(message: '助记词已隐藏');
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建钱包'),
        centerTitle: true,
      ),
      body: _result != null ? _buildMnemonicView() : _buildCreateView(),
    );
  }

  Widget _buildCreateView() {
    // 从顶部开始排布，避免内容随可用高度垂直居中后落得过低；ListView 同时保证小屏不溢出。
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
      children: [
        Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(50),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '选择助记词数量',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 12, label: Text('12 个单词')),
                ButtonSegment(value: 24, label: Text('24 个单词')),
              ],
              selected: {_wordCount},
              onSelectionChanged: (v) => setState(() => _wordCount = v.first),
            ),
            const SizedBox(height: 10),
            Text(
              _wordCount == 24 ? '256 位熵，安全性更高' : '128 位熵，标准安全强度',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 320,
              child: WalletPasswordField(controller: _passwordController),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 260,
              child: FilledButton(
                onPressed: _creating ? null : _create,
                child: _creating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('创建钱包'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMnemonicView() {
    final result = _result!;
    final words = result.mnemonic.split(' ');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 警告横幅
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: AppTheme.bannerDecoration(AppTheme.warning),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppTheme.warning, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '请安全保存助记词；设置密码时还必须单独记住密码',
                  style: TextStyle(
                    color: AppTheme.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 助记词卡片
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.key_rounded,
                      color: AppTheme.primaryLight, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '助记词（请手抄备份，不支持复制）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (i) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${i + 1}. ',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: words[i],
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 钱包信息卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    result.wallet.walletName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                result.primaryAccount.ss58Address,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontFamily: 'monospace',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _confirmBackup,
          child: const Text('已备份，完成'),
        ),
      ],
    );
  }
}
