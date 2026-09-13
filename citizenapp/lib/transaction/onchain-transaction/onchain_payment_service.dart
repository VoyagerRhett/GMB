import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_models.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_transfer_call.dart';

class OnchainPaymentService {
  OnchainPaymentService({
    required CitizenSdkWallet wallet,
    required CitizenTransactions transactions,
  })  : _wallet = wallet,
        _transactions = transactions;

  final CitizenSdkWallet _wallet;
  final CitizenTransactions _transactions;

  Future<CitizenWalletStateAccount?> getCurrentWallet() async =>
      (await _wallet.getState()).defaultAccount;

  /// 校验 CitizenApp 转账表单、编码 opaque RuntimeCall，然后直接
  /// 交给 CitizenSDK 准备。签名、广播和最终执行不在 App 业务服务内实现。
  Future<CitizenPreparedTransaction> prepareTransfer(
    OnchainPaymentDraft draft,
  ) async {
    final toSs58Address = draft.toSs58Address.trim();
    final symbol = draft.symbol.trim().toUpperCase();
    final remarkBytes = utf8.encode(draft.remark).length;
    if (toSs58Address.isEmpty || symbol.isEmpty || draft.amount <= 0) {
      throw const OnchainPaymentException(
        OnchainPaymentErrorCode.invalidDraft,
        '交易草稿不合法，请检查收款地址、数量和币种',
      );
    }
    if (remarkBytes > OnchainTransferCall.maxTransferRemarkBytes) {
      throw const OnchainPaymentException(
        OnchainPaymentErrorCode.invalidDraft,
        '转账备注超过链上长度上限',
      );
    }

    final wallet = (await _wallet.getState()).defaultAccount;
    if (wallet == null) {
      throw const OnchainPaymentException(
        OnchainPaymentErrorCode.walletMissing,
        '请先创建或导入钱包，再进行链上交易',
      );
    }

    final sourceAccountId = _hexToBytes(wallet.accountId);
    final callData = OnchainTransferCall.encode(
      destinationSs58Address: toSs58Address,
      amountYuan: draft.amount,
      remark: draft.remark,
    );
    try {
      return await _transactions.prepareTransaction(
        Uint8List.fromList(sourceAccountId),
        callData,
      );
    } catch (e) {
      if (e is OnchainPaymentException) rethrow;
      throw OnchainPaymentException(
        OnchainPaymentErrorCode.broadcastFailed,
        '交易提交失败: $e',
      );
    }
  }

  List<int> _hexToBytes(String input) {
    final text = input.startsWith('0x') ? input.substring(2) : input;
    if (text.isEmpty || text.length.isOdd) return const <int>[];
    final out = <int>[];
    for (var i = 0; i < text.length; i += 2) {
      out.add(int.parse(text.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
