import 'package:flutter/material.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';

/// 这里只映射原提示文案；密码校验、字符集和规范化均由SDK完成。
Future<void> validateWalletPasswordInput(BuildContext context, String raw) async {
  final result = await context.read<CitizenSdk>().wallet.validatePassword(raw);
  if (result.isValid) return;
  final message = switch (result.reason) {
    CitizenWalletInputReason.passwordLength || CitizenWalletInputReason.inputTooLong => '密码长度必须为 6–30 位',
    CitizenWalletInputReason.passwordNormalization => '密码包含规范化后无法安全恢复的字符',
    _ => '密码只能使用大写字母、小写字母、数字、指定符号或汉字',
  };
  throw WalletPasswordException(message);
}

final class WalletPasswordException implements Exception {
  const WalletPasswordException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 四端共用的单次可选 password 输入框。
class WalletPasswordField extends StatefulWidget {
  const WalletPasswordField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<WalletPasswordField> createState() => _WalletPasswordFieldState();
}

class _WalletPasswordFieldState extends State<WalletPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      decoration: InputDecoration(
        labelText: '钱包密码（选填）',
        helperText: '6–30 位；可用大小写字母、数字、符号或汉字',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _obscure ? '显示密码' : '隐藏密码',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// 非空 password 才提示风险；只确认一次，不要求用户再次输入。
Future<bool> confirmWalletPasswordUse(
  BuildContext context,
  String password,
) async {
  if (password.isEmpty) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认钱包密码', textAlign: TextAlign.center),
          content: const Text(
            '钱包密码将用于派生钱包账户，不同的密码会派生完全不同的账户，'
            '请务必牢记密码，忘记密码将无法恢复钱包。',
          ),
          actions: [
            // 两个决定具有同等布局权重，固定等宽并左右对齐，避免文字宽度影响按钮位置。
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ) ??
      false;
}
