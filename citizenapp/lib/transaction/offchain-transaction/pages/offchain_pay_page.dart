import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/transaction/offchain-transaction/rpc/offchain_clearing_rpc.dart';
import 'package:citizenapp/transaction/offchain-transaction/models/payment_intent.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_directory.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/signer/signing.dart' show kOpSignL3Pay;
import 'package:citizenapp/ui/app_layout.dart';

/// 扫码支付清算体系付款确认页。
///
///
/// - 入口:`offchain_scan_flow.dart` 扫商户码成功后跳转过来
///   (商户码 `UserTransferBody` 的 `bank` 字段是收款方清算行 `cid_number`)。
/// - Step 3 范围:同行 / 跨行都提交到**收款方清算行节点**,与 runtime
///   `submit_offchain_batch` 的收款方主导模型对齐。
/// - 流程:
///   1. 连清算行节点 RPC,查 `offchain_queryUserBank(user)` 得付款方清算行
///      `payer_bank` SS58(未绑定 → 结束);
///   2. 重读 finalized `ClearingBankNodes[cid_number]`，再按链统一派生规则计算
///      `recipient_bank` 主账户 hex;
///   3. 同行校验(`payer_bank` == `recipient_bank` hex → SS58 对比);
///   4. 查 `offchain_queryFeeRate(payer_bank)` 得 `(rate_bp, min_fee_fen)`,本地
///      计算 `fee_fen`(与 runtime 一致的四舍五入);
///   5. 展示确认 UI(金额 / 手续费 / 合计 / 收款方地址 / 备注);
///   6. 用户点确认 → 查 `offchain_queryNextNonce(user)` → 构造
///      `NodePaymentIntent`(随机 tx_id + `expires_at = currentBlock + 100`) →
///      `signingHash()` → 热钱包 `signWithWallet` → 提交
///      `offchain_submitPayment(intent_hex, sig_hex)` → 显示结果。
class OffchainClearingPayPage extends StatefulWidget {
  const OffchainClearingPayPage({
    super.key,
    required this.wallet,
    required this.toSs58Address,
    required this.recipientBankCidNumber,
    required this.clearingNodeWssUrl,
    this.initialAmountYuan,
    this.memo,
  });

  /// 付款方当前钱包(仅支持热钱包)。
  final CitizenWalletStateAccount wallet;

  /// 商户 QR `UserTransferBody.ss58Address` 收款方 SS58 展示地址。
  final String toSs58Address;

  /// 商户 QR `UserTransferBody.bank` 收款方清算行 `cid_number`。
  final String recipientBankCidNumber;

  /// 收款方清算行节点 WSS URL。
  final String clearingNodeWssUrl;

  /// 商户 QR 预填金额(元,字符串)。空 → 由用户输入。
  final String? initialAmountYuan;

  final String? memo;

  @override
  State<OffchainClearingPayPage> createState() =>
      _OffchainClearingPayPageState();
}

enum _PageState { loading, ready, submitting, done, error }

class _OffchainClearingPayPageState extends State<OffchainClearingPayPage> {
  static const int _expiresInBlocks = 100; // ≈ 10 分钟(6s/block),签名离提交留足余量

  _PageState _state = _PageState.loading;
  String _errorMessage = '';

  // 预取:付款方绑定的清算行主账户 SS58
  String? _payerBankCid;
  // 预取:QR 收款方 cid_number 解析出的清算行主账户 hex
  String? _recipientBankCid;
  // 预取:费率
  int _rateBp = 0;
  int _minFeeFen = 1;
  // 预取:当前最新块高(用于 expires_at)
  int _currentBlockNumber = 0;

  // 金额输入(元,字符串)
  final TextEditingController _amountCtrl = TextEditingController();

  // 提交结果
  String? _resultTxId;

  late final OffchainClearingBankRpc _nodeRpc = OffchainClearingBankRpc(
    widget.clearingNodeWssUrl,
  );

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.initialAmountYuan ?? '';
    _loadPrerequisites();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrerequisites() async {
    final chain = context.read<CitizenSdk>().chain;
    try {
      // 1. 付款方绑定的清算行
      final payerBank = await _nodeRpc.queryUserBank(widget.wallet.ss58Address);
      if (payerBank == null || payerBank.isEmpty) {
        _setError('您尚未绑定清算行,请先返回"选择/绑定清算行"完成绑定');
        return;
      }

      // 2. 付款前重新确认收款方仍有链上清算行声明，主账户只按链统一原语派生。
      final endpoint = await ClearingBankDirectory(
        chain: chain,
      ).fetchEndpoint(widget.recipientBankCidNumber);
      if (endpoint == null) {
        _setError('收款方清算行未在链上声明节点,无法付款');
        return;
      }
      // 身份主键=CID:付款方 CID 来自 queryUserBank,收款方 CID 来自扫码入参。
      _payerBankCid = payerBank;
      _recipientBankCid = widget.recipientBankCidNumber;

      // 3. 费率按收款方清算行计算;同行 / 跨行都由收款方清算行拿 fee 并付 gas。
      final rate = await _nodeRpc.queryFeeRate(_recipientBankCid!);
      if (rate.rateBp <= 0) {
        _setError('清算行费率未配置(rate_bp=${rate.rateBp}),请联系清算行运维');
        return;
      }
      _rateBp = rate.rateBp;
      _minFeeFen = rate.minFeeFen;

      // 5. 当前块高
      final latest = await chain.getBestHead();
      _currentBlockNumber = latest.number.toInt();

      if (mounted) {
        setState(() => _state = _PageState.ready);
      }
    } catch (e) {
      _setError('加载支付信息失败:$e');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _PageState.error;
      _errorMessage = msg;
    });
  }

  BigInt? _parseAmountFen() {
    final txt = _amountCtrl.text.trim();
    if (txt.isEmpty) return null;
    final yuan = double.tryParse(txt);
    if (yuan == null || yuan <= 0) return null;
    final fen = BigInt.from((yuan * 100).round());
    return fen > BigInt.zero ? fen : null;
  }

  BigInt? _computeFeeFen(BigInt amountFen) {
    try {
      return NodePaymentIntent.calcFeeFen(
        amountFen: amountFen,
        rateBp: _rateBp,
        minFeeFen: _minFeeFen,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmAndSubmit() async {
    final amountFen = _parseAmountFen();
    if (amountFen == null) {
      _showSnack('请输入有效金额');
      return;
    }
    final feeFen = _computeFeeFen(amountFen);
    if (feeFen == null) {
      _showSnack('手续费计算失败');
      return;
    }

    setState(() => _state = _PageState.submitting);
    try {
      // 6. nonce
      final nonce = await _nodeRpc.queryNextNonce(widget.wallet.ss58Address);

      // 7. 构造 intent
      final payer = hexToBytes(widget.wallet.accountId);
      if (payer.length != 32) {
        throw Exception('钱包公钥长度异常:${payer.length}');
      }
      final recipient = _decodeAccount(widget.toSs58Address);
      final payerBankCidBytes = Uint8List.fromList(utf8.encode(_payerBankCid!));
      final recipientBankCidBytes = Uint8List.fromList(
        utf8.encode(_recipientBankCid!),
      );

      final intent = NodePaymentIntent(
        txId: NodePaymentIntent.randomTxId(),
        payer: payer,
        payerBankCid: payerBankCidBytes,
        recipient: recipient,
        recipientBankCid: recipientBankCidBytes,
        amount: amountFen,
        fee: feeFen,
        nonce: BigInt.from(nonce),
        expiresAt: _currentBlockNumber + _expiresInBlocks,
      );

      // 8. 签名:热钱包直签;冷钱包不能独立验证 PaymentIntent hash,必须拒绝。
      final sig = await _signSigningHash(
        signingHash: intent.signingHash(),
        amountFen: amountFen,
        feeFen: feeFen,
      );
      if (sig.length != 64) {
        throw Exception('签名长度异常:${sig.length}');
      }

      // 9. 提交
      final resp = await _nodeRpc.submitPayment(
        intentHex: bytesToHex(intent.scaleEncode()),
        payerSigHex: bytesToHex(sig),
      );

      if (!mounted) return;
      setState(() {
        _resultTxId = resp.txId;
        _state = _PageState.done;
      });
    } catch (e) {
      _setError('提交失败:$e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码付款(清算行)')),
      body: _body(),
    );
  }

  Widget _body() {
    switch (_state) {
      case _PageState.loading:
        return const Center(child: CircularProgressIndicator());
      case _PageState.error:
        return _errorView();
      case _PageState.submitting:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: AppLayout.scaledValue(12)),
              const Text('正在签名并提交到清算行...'),
            ],
          ),
        );
      case _PageState.done:
        return _doneView();
      case _PageState.ready:
        return _confirmView();
    }
  }

  Widget _errorView() {
    return Padding(
      padding: EdgeInsets.all(AppLayout.scaledValue(24)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: AppLayout.scaledValue(48),
              color: Colors.red,
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            Text(_errorMessage, textAlign: TextAlign.center),
            SizedBox(height: AppLayout.scaledValue(16)),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneView() {
    return Padding(
      padding: EdgeInsets.all(AppLayout.scaledValue(24)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: AppLayout.scaledValue(48),
              color: Colors.green,
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            const Text('支付已受理,清算行会在下一批次上链'),
            SizedBox(height: AppLayout.scaledValue(8)),
            SelectableText(
              'tx_id: ${_resultTxId ?? ''}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppLayout.scaledValue(12),
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmView() {
    final amountFen = _parseAmountFen();
    final feeFen = (amountFen != null) ? _computeFeeFen(amountFen) : null;
    final totalFen = (amountFen != null && feeFen != null)
        ? amountFen + feeFen
        : null;
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppLayout.scaledValue(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kv('收款方地址', widget.toSs58Address),
          if (_payerBankCid != null) _kv('付款方清算行', _payerBankCid!),
          _kv('收款方清算行', widget.recipientBankCidNumber),
          if (_payerBankCid != null && _recipientBankCid != null)
            _kv('清算类型', _payerBankCid == _recipientBankCid ? '同行' : '跨行'),
          if (widget.memo != null && widget.memo!.isNotEmpty)
            _kv('备注', widget.memo!),
          Divider(height: AppLayout.scaledValue(32)),
          TextField(
            controller: _amountCtrl,
            enabled:
                widget.initialAmountYuan == null ||
                widget.initialAmountYuan!.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '金额(元)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          _kv('费率', '$_rateBp bp (万分之 $_rateBp)'),
          _kv('手续费', feeFen == null ? '—' : '${_fenToYuan(feeFen)} 元'),
          _kv('合计扣款', totalFen == null ? '—' : '${_fenToYuan(totalFen)} 元'),
          SizedBox(height: AppLayout.scaledValue(24)),
          ElevatedButton(
            onPressed: (amountFen != null && feeFen != null)
                ? _confirmAndSubmit
                : null,
            child: const Text('确认并签名付款'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(4)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppLayout.scaledValue(96),
            child: Text(key, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ─── 地址编解码工具 ───

  /// 把 SS58 地址转成 32 字节。
  Uint8List _ss58ToBytes(String ss58) {
    final bytes = Keyring().decodeAddress(ss58);
    if (bytes.length != 32) {
      throw Exception('SS58 解码长度异常:${bytes.length}');
    }
    return Uint8List.fromList(bytes);
  }

  /// 热钱包 / 冷钱包统一签名入口。
  ///
  /// - 热钱包:交给 CitizenSDK 按精确 account_id 完成设备认证与签名。
  /// - 清算行付款 payload 当前是 32 字节 signing_hash,冷钱包无法从 hash 独立还原
  ///   PaymentIntent 业务字段,因此不生成离线签名二维码。
  Future<Uint8List> _signSigningHash({
    required Uint8List signingHash,
    required BigInt amountFen,
    required BigInt feeFen,
  }) async {
    final wallet = widget.wallet;
    if (wallet.signMode == CitizenWalletSignMode.hot) {
      return signCitizenPayload(
        signing: context.read<CitizenSdk>().signing,
        context: context,
        accountId: wallet.accountId,
        payload: signingHash,
        action: kOpSignL3Pay,
      );
    }

    throw Exception('清算行付款签名必须使用本机热钱包；冷钱包无法独立验证付款 hash');
  }

  /// 分转元(两位小数)。本地化展示,不参与任何链上金额计算。
  String _fenToYuan(BigInt fen) {
    // 避免 BigInt → double 丢精度(最大 9e18 分 ≈ 2^63,double 精度 2^53)。
    // 这里走字符串分隔:整数部分 / 小数部分。
    final neg = fen.isNegative;
    final abs = fen.abs();
    final yuan = abs ~/ BigInt.from(100);
    final cents = (abs % BigInt.from(100)).toInt();
    final s = '$yuan.${cents.toString().padLeft(2, '0')}';
    return neg ? '-$s' : s;
  }

  /// QR 里的 `toSs58Address` 是用户展示/扫码边界，只允许 SS58。
  Uint8List _decodeAccount(String address) {
    return _ss58ToBytes(address.trim());
  }
}
