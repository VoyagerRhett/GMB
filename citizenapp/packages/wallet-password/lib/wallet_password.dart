import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Substrate BIP-39 [password] 的统一校验结果。
final class WalletPassword {
  const WalletPassword._(this.value);

  /// NFKD 后传给 `substrate-bip39` 的唯一值；空字符串表示沿用无 password 钱包。
  final String value;

  bool get isEmpty => value.isEmpty;

  static const int minLength = 6;
  static const int maxLength = 30;

  static final RegExp _ascii = RegExp(
    r'''^[A-Za-z0-9!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~]$''',
  );
  static final RegExp _han = RegExp(r'^\p{Script=Han}$', unicode: true);

  /// 校验原文后执行 BIP-39 要求的 NFKD；绝不 trim、改大小写或修复非法字符。
  static WalletPassword parse(String raw) {
    if (raw.isEmpty) return const WalletPassword._('');
    final length = raw.characters.length;
    if (length < minLength || length > maxLength) {
      throw const WalletPasswordException('密码长度必须为 6–30 位');
    }
    if (!_allAllowed(raw)) {
      throw const WalletPasswordException('密码只能使用大写字母、小写字母、数字、指定符号或汉字');
    }
    final normalized = unorm.nfkd(raw);
    if (normalized.characters.length < minLength ||
        normalized.characters.length > maxLength ||
        !_allAllowed(normalized)) {
      throw const WalletPasswordException('密码包含规范化后无法安全恢复的字符');
    }
    return WalletPassword._(normalized);
  }

  static bool _allAllowed(String value) => value.characters.every(
        (character) => _ascii.hasMatch(character) || _han.hasMatch(character),
      );
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
  WalletPassword password,
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
