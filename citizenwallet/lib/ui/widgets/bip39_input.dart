import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39m;
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// BIP39 助记词输入组件，支持单词自动补全。
///
/// 用户输入字母时，自动展示匹配的 BIP39 单词供选择。
/// 选中后自动补全并跳到下一个单词。
class Bip39InputField extends StatefulWidget {
  const Bip39InputField({
    super.key,
    required this.controller,
    this.wordCount = 12,
  });

  final TextEditingController controller;

  /// 期望的助记词单词数量（12、18 或 24；0 表示导入时不预选数量）。
  final int wordCount;

  @override
  State<Bip39InputField> createState() => _Bip39InputFieldState();
}

class _Bip39InputFieldState extends State<Bip39InputField> {
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final currentWord = _currentWord(text);

    if (currentWord.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }

    final prefix = currentWord.toLowerCase();
    final matches = bip39m.Language.english.list
        .where((w) => w.startsWith(prefix))
        .take(6)
        .toList(growable: false);
    setState(() => _suggestions = matches);
  }

  /// 提取光标处正在输入的（最后一个不完整的）单词。
  String _currentWord(String text) {
    if (text.isEmpty) return '';
    // 如果末尾是空格，说明上一个单词已输完
    if (text.endsWith(' ')) return '';
    final parts = text.split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  void _selectWord(String word) {
    final text = widget.controller.text;
    final trimmed = text.trimRight();
    final parts = trimmed.split(RegExp(r'\s+'));

    // 替换最后一个不完整的单词
    if (parts.isNotEmpty) {
      parts[parts.length - 1] = word;
    } else {
      parts.add(word);
    }

    final newText = '${parts.join(' ')} ';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() => _suggestions = []);
  }

  int get _enteredWordCount {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: 4,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: AppTheme.textPrimary,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            hintText: '输入助记词，选择匹配的单词',
            counterText:
                '$_enteredWordCount / ${widget.wordCount > 0 ? widget.wordCount : "12、18 或 24"} 个单词',
          ),
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _suggestions.map((word) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: () => _selectWord(word),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.primary.withAlpha(40)),
                    ),
                    child: Text(
                      word,
                      style: const TextStyle(
                        color: AppTheme.primaryLight,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ],
    );
  }
}
