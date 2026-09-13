import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/onchain_clearing_bank_chain.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 扫码支付清算体系 Step 1 新增:**充值** L3 自持账户 → 清算行主账户。
///
///
/// - 调链上 `deposit(amount)`(call_index 31)。
/// - 链上费按金额 0.1% 最低 0.1 元，由 runtime 唯一 `RuntimeFeeRouter` 指定签名者付款。
/// - 钱包账户由 CitizenSDK 严格分流：热账户本机签名，冷账户交给独立公民钱包扫码。
class DepositPage extends StatefulWidget {
  const DepositPage({
    super.key,
    required this.accountId,
    required this.ss58Address,
  });

  /// L3 用户链账户主键(0x+64hex):清算行绑定缓存键、按账户签名、构造 signerPublicKey。
  final String accountId;

  /// L3 用户 SS58 地址(充值 extrinsic 来源地址)。
  final String ss58Address;

  @override
  State<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends State<DepositPage> {
  final TextEditingController _amountCtrl = TextEditingController();
  bool _submitting = false;
  ClearingBankBindingSnapshot? _binding;

  @override
  void initState() {
    super.initState();
    _loadBinding();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBinding() async {
    final binding = await ClearingBankPrefs.loadSnapshot(widget.accountId);
    if (!mounted) return;
    setState(() => _binding = binding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('充值到清算行')),
      body: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _binding == null
                  ? '请先绑定清算行后再充值。'
                  : '转入 ${_binding!.displayTitle}',
              style: const TextStyle(color: Colors.grey),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '充值金额(元)',
                hintText: '例如 100.00',
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 24)),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? SizedBox(
                      width: AppLayout.scaled(context, 20),
                      height: AppLayout.scaled(context, 20),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认充值'),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            Text(
              '链上费:金额 × 0.1%(最低 0.1 元)',
              style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12), color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final amountFen = _parseAmountToFen(_amountCtrl.text);
    if (amountFen == null || amountFen <= BigInt.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的充值金额(元)')),
      );
      return;
    }

    if (_binding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先绑定清算行')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final publicKeyBytes = _hexToBytes(widget.accountId);
      if (publicKeyBytes.length != 32) {
        throw Exception('账户公钥必须是 32 字节');
      }
      final sdk = context.read<CitizenSdk>();
      final chain = OnchainClearingBankChain(transactions: sdk.transactions);
      final result = await chain.deposit(
        signerPublicKey: Uint8List.fromList(publicKeyBytes),
        amountFen: amountFen,
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('充值已提交,tx=${_short(result.txHash)}')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('充值失败:$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 把"元"字符串转为 BigInt 分。`100.5` → 10050。
  static BigInt? _parseAmountToFen(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final dotIdx = s.indexOf('.');
    String intPart;
    String fracPart;
    if (dotIdx < 0) {
      intPart = s;
      fracPart = '00';
    } else {
      intPart = s.substring(0, dotIdx);
      final raw = s.substring(dotIdx + 1);
      if (raw.isEmpty) {
        fracPart = '00';
      } else if (raw.length == 1) {
        fracPart = '${raw}0';
      } else if (raw.length == 2) {
        fracPart = raw;
      } else {
        // 超过 2 位小数:截断(不进行四舍五入,避免与链上 round_div 冲突)
        fracPart = raw.substring(0, 2);
      }
    }
    if (intPart.isEmpty) intPart = '0';
    if (!RegExp(r'^\d+$').hasMatch(intPart) ||
        !RegExp(r'^\d{2}$').hasMatch(fracPart)) {
      return null;
    }
    return BigInt.parse('$intPart$fracPart');
  }

  static List<int> _hexToBytes(String input) {
    final text = input.startsWith('0x') ? input.substring(2) : input;
    if (text.isEmpty || text.length.isOdd) return const <int>[];
    final out = <int>[];
    for (var i = 0; i < text.length; i += 2) {
      out.add(int.parse(text.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _short(String h) {
    if (h.length <= 14) return h;
    return '${h.substring(0, 8)}…${h.substring(h.length - 4)}';
  }
}
