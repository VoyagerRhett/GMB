import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

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

  /// 期望的助记词单词数量（12、18或24）。
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

  Future<void> _onTextChanged() async {
    final text = widget.controller.text;
    final currentWord = _currentWord(text);

    if (currentWord.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }

    final prefix = currentWord.toLowerCase();
    List<String> matches;
    try {
      matches = await context.read<CitizenSdk>().wallet.wordSuggestions(prefix);
    } catch (_) {
      matches = const [];
    }
    if (!mounted || widget.controller.text != text) return;
    setState(() => _suggestions = matches);
  }

  /// 提取末尾未完成单词；保留原交互，不按任意光标位置另算候选。
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
          SizedBox(height: AppLayout.scaled(context, 8)),
          Wrap(
            spacing: AppLayout.scaled(context, 8),
            runSpacing: AppLayout.scaled(context, 4),
            children: _suggestions.map((word) {
              return ActionChip(
                label:
                    Text(word, style: const TextStyle(color: AppTheme.primary)),
                backgroundColor: AppTheme.primary.withAlpha(15),
                side: BorderSide(color: AppTheme.primary.withAlpha(40)),
                onPressed: () => _selectWord(word),
              );
            }).toList(growable: false),
          ),
        ],
      ],
    );
  }
}
