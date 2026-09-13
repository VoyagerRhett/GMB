import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/rpc/offchain_clearing_rpc.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/onchain_clearing_bank_chain.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 扫码支付清算体系 Step 1 新增:**提现** 清算行主账户 → L3 自持账户。
///
///
/// - 调链上 `withdraw(amount)`(call_index 32)。
/// - 链上费按金额 0.1% 最低 0.1 元。
/// - 可选 `wssUrl`:若提供则查清算行节点本地缓存的余额展示;不提供时只显示输入。
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({
    super.key,
    required this.accountId,
    required this.ss58Address,
    this.wssUrl,
  });

  /// L3 用户链账户主键(0x+64hex):由 CitizenSDK 分流签名并构造 signerPublicKey。
  final String accountId;

  /// L3 用户 SS58 地址(查询清算行存款余额、构造提现 extrinsic 的来源地址)。
  final String ss58Address;

  /// 清算行节点的 WebSocket URL(用于查询当前可用存款余额)。可选。
  final String? wssUrl;

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  final TextEditingController _amountCtrl = TextEditingController();
  bool _submitting = false;
  int? _balanceFen;
  String? _balanceErr;

  @override
  void initState() {
    super.initState();
    if (widget.wssUrl != null && widget.wssUrl!.isNotEmpty) {
      _loadBalance();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final chain = OffchainClearingBankRpc(widget.wssUrl!);
      final v = await chain.queryBalance(widget.ss58Address);
      if (!mounted) return;
      setState(() => _balanceFen = v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _balanceErr = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('从清算行提现')),
      body: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBalanceLine(),
            SizedBox(height: AppLayout.scaled(context, 16)),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '提现金额(元)',
                hintText: '例如 50.00',
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
                  : const Text('确认提现'),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            Text(
              '链上费:金额 × 0.1%(最低 0.1 元)',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 12),
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceLine() {
    if (widget.wssUrl == null || widget.wssUrl!.isEmpty) {
      return const Text(
        '当前清算行存款余额:未连接节点',
        style: TextStyle(color: Colors.grey),
      );
    }
    if (_balanceErr != null) {
      return Text(
        '查询余额失败:$_balanceErr',
        style: const TextStyle(color: Colors.red),
      );
    }
    if (_balanceFen == null) {
      return const Text('正在查询清算行存款余额...', style: TextStyle(color: Colors.grey));
    }
    final yuan = _balanceFen! / 100.0;
    return Text(
      '当前清算行存款余额:¥${AmountFormat.formatThousands(yuan)}',
      style: TextStyle(fontSize: AppLayout.scaledValue(14)),
    );
  }

  Future<void> _submit() async {
    final amountFen = _parseAmountToFen(_amountCtrl.text);
    if (amountFen == null || amountFen <= BigInt.zero) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入有效的提现金额(元)')));
      return;
    }

    if (widget.wssUrl == null || widget.wssUrl!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先绑定清算行')));
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
      final result = await chain.withdraw(
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
        SnackBar(content: Text('提现已提交,tx=${_short(result.txHash)}')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提现失败:$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
