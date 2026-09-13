import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_directory.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/onchain_clearing_bank_chain.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 绑定**清算行**(L2)确认页。
///
///
/// - 清算行(L2)体系唯一绑定页。数据源为 finalized 链上清算行声明;
///   链上调用 `bind_clearing_bank(bank_main_account_id)`(call_index 30)。
/// - 绑定即开户,**无预存、无业务开户费**;签名者支付最低链上交易费 0.1 元/次。
/// - 本页目前无活跃入口,等「设置清算行」真实交互落地时再复用。
class BindClearingBankPage extends StatefulWidget {
  const BindClearingBankPage({
    super.key,
    required this.accountId,
    required this.ss58Address,
    required this.bank,
    this.switchMode = false,
  });

  /// L3 用户链账户主键(0x+64hex):按账户签名、构造 signerPublicKey、绑定缓存键。
  final String accountId;

  /// L3 用户 SS58 地址(绑定/切换 extrinsic 来源地址)。
  final String ss58Address;
  final ClearingBankCandidate bank;
  final bool switchMode;

  @override
  State<BindClearingBankPage> createState() => _BindClearingBankPageState();
}

class _BindClearingBankPageState extends State<BindClearingBankPage> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.bank;
    final title = b.displayTitle.isEmpty ? '(未设置全称)' : b.displayTitle;
    return Scaffold(
      appBar: AppBar(title: Text(widget.switchMode ? '切换清算行' : '绑定清算行')),
      body: ListView(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        children: [
          ListTile(
            title: const Text('清算行'),
            subtitle: Text(title),
          ),
          ListTile(
            title: const Text('所在地'),
            subtitle: Text(b.areaPath.isEmpty ? '-' : b.areaPath),
          ),
          ListTile(
            title: const Text('CID'),
            subtitle: SelectableText(b.cidNumber),
          ),
          ListTile(
            title: const Text('主账户'),
            subtitle: SelectableText('0x${b.mainAccountId}'),
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          Card(
            child: Padding(
              padding: EdgeInsets.all(AppLayout.scaledValue(12)),
              child: Text(
                '说明:\n'
                '· 绑定即开户,无需预存\n'
                '· 链上手续费 0.1 元/次\n'
                '· 同一时间只能绑定一家清算行\n'
                '· 切换前需把当前清算行存款全部提现',
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13),
                    color: Colors.grey),
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 24)),
          FilledButton(
            onPressed: _submitting ? null : _confirmBind,
            child: _submitting
                ? SizedBox(
                    width: AppLayout.scaled(context, 20),
                    height: AppLayout.scaled(context, 20),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.switchMode ? '确认切换' : '确认绑定'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBind() async {
    final mainAccountId = widget.bank.mainAccountId;

    setState(() => _submitting = true);
    try {
      final mainAccountIdBytes = _hexToBytes(mainAccountId);
      if (mainAccountIdBytes.length != 32) {
        throw Exception('主账户必须是 32 字节,实际 ${mainAccountIdBytes.length}');
      }
      final publicKeyBytes = _hexToBytes(widget.accountId);
      if (publicKeyBytes.length != 32) {
        throw Exception('账户公钥必须是 32 字节');
      }

      final sdk = context.read<CitizenSdk>();
      final chain = OnchainClearingBankChain(transactions: sdk.transactions);
      final result = widget.switchMode
          ? await chain.switchBank(
              signerPublicKey: Uint8List.fromList(publicKeyBytes),
              newBankMainAccountId: Uint8List.fromList(mainAccountIdBytes),
              externalSigning: (pending) => showCitizenSdkQrResponse(
                context,
                request: pending.qrRequest,
                expiresAt: BigInt.from(
                  pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
                ),
              ),
            )
          : await chain.bindClearingBank(
              signerPublicKey: Uint8List.fromList(publicKeyBytes),
              bankMainAccountId: Uint8List.fromList(mainAccountIdBytes),
              externalSigning: (pending) => showCitizenSdkQrResponse(
                context,
                request: pending.qrRequest,
                expiresAt: BigInt.from(
                  pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
                ),
              ),
            );

      // 绑定成功后写入完整清算行快照。链上仍是最终权威,本地快照只用于
      // 手机端页面展示、充值提现和扫码付款时快速定位清算行节点端点。
      final endpoint = widget.bank.endpoint;
      final now = DateTime.now().millisecondsSinceEpoch;
      await ClearingBankPrefs.saveSnapshot(
        widget.accountId,
        ClearingBankBindingSnapshot(
          cidNumber: widget.bank.cidNumber,
          cidFullName: widget.bank.cidFullName,
          cidShortName: widget.bank.cidShortName ?? '',
          mainAccountId: _normalizeHex(widget.bank.mainAccountId),
          feeAccountId: _normalizeHex(widget.bank.feeAccountId),
          peerId: endpoint.peerId,
          rpcDomain: endpoint.rpcDomain,
          rpcPort: endpoint.rpcPort,
          boundAtMs: now,
          lastVerifiedAtMs: now,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.switchMode ? '切换' : '绑定'}已提交,tx=${_short(result.txHash)},等待链上确认',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on AccountSecurityException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('绑定失败:$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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

  static String _normalizeHex(String input) {
    final text = input.startsWith('0x') ? input.substring(2) : input;
    return text.toLowerCase();
  }

  static String _short(String h) {
    if (h.length <= 14) return h;
    return '${h.substring(0, 8)}…${h.substring(h.length - 4)}';
  }
}
