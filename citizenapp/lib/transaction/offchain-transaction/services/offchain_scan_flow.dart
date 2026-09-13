import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/transaction/offchain-transaction/pages/offchain_pay_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_directory.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';

/// 链下支付尾段：已拿到收款码解析结果后，校验清算行 → 查节点 → 跳付款确认页。
///
/// 扫码入口统一收口在聊天 tab「扫一扫」分发器（[openScanDispatchFlow]）：识别为收款/
/// 支付码后调本函数。真正的校验清算行、查收款方节点、跳付款确认页都留在 offchain 域。
/// 扫码结果必须携带 `UserTransferBody.bank`（收款方清算行 `cid_number`）。
Future<void> proceedOffchainPayment({
  required BuildContext context,
  required CitizenWalletStateAccount wallet,
  required QrScanTransferResult result,
}) async {
  if (result.bank == null || result.bank!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该收款码不支持扫码支付(未绑定清算行)')),
    );
    return;
  }

  final directory = ClearingBankDirectory(
    chain: context.read<CitizenSdk>().chain,
  );
  final endpoint = await directory.fetchEndpoint(result.bank!);
  if (!context.mounted) return;
  if (endpoint == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('收款方清算行尚未声明节点,无法扫码支付')),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OffchainClearingPayPage(
        wallet: wallet,
        toSs58Address: result.toSs58Address,
        recipientBankCidNumber: result.bank!,
        clearingNodeWssUrl: endpoint.wssUrl,
        initialAmountYuan: result.amount,
        memo: result.memo,
      ),
    ),
  );
}
