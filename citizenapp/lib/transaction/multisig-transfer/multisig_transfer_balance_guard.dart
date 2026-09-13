import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/shared/multisig_create_amount_rules.dart';

/// 多签提案和实际投票的付款账户余额检查。
class MultisigTransferBalanceGuard {
  const MultisigTransferBalanceGuard._();

  /// InternalVote::cast 固定按 1 元计费。
  static const double voteFeeYuan = 1.0;

  /// 发起提案是最低链上操作费；个人多签由签名者支付，机构由费用账户支付。
  static double get onchainOperationFeeYuan =>
      MultisigCreateAmountRules.fenToYuan(
        MultisigCreateAmountRules.minOnchainFeeFen,
      );

  /// 机构费用账户提交前的合计最低余额：外层操作费 + 后续明确支出 + ED。
  static double institutionFeeAccountRequiredYuan({
    double additionalDebitYuan = 0,
  }) {
    final additionalDebitFen = BigInt.from((additionalDebitYuan * 100).round());
    final requiredFen = MultisigCreateAmountRules.minOnchainFeeFen +
        additionalDebitFen +
        MultisigCreateAmountRules.existentialDepositFen;
    return MultisigCreateAmountRules.fenToYuan(requiredFen);
  }

  /// 检查机构费用账户能支付本次外层操作费、后续执行支出并保留 ED。
  ///
  /// 管理员钱包只签名，不能作为机构费用账户不足时的回退付款方。
  static Future<String?> checkInstitutionFeeAccountBalance({
    required String feeAccountId,
    required String actionLabel,
    double additionalDebitYuan = 0,
    required CitizenChain chain,
  }) async {
    final balance = await chain.getAccountBalance(feeAccountId);
    final balanceYuan = balance.freeFen.toDouble() / 100;
    final additionalDebitFen = BigInt.from((additionalDebitYuan * 100).round());
    final requiredYuan = institutionFeeAccountRequiredYuan(
      additionalDebitYuan: additionalDebitYuan,
    );
    if (balanceYuan >= requiredYuan) {
      return null;
    }
    return '机构费用账户余额不足，不能$actionLabel。当前余额 '
        '${AmountFormat.format(balanceYuan, symbol: '')} 元，至少需要 '
        '${AmountFormat.format(requiredYuan, symbol: '')} 元'
        '（含操作费 ${AmountFormat.format(onchainOperationFeeYuan, symbol: '')} 元'
        '${additionalDebitFen > BigInt.zero ? '、后续支出 ${AmountFormat.format(additionalDebitYuan, symbol: '')} 元' : ''}，支付后须保留 ED）。';
  }

  /// 检查签名者付款路径：个人多签提案为 0.1 元，实际 cast 投票为 1 元。
  static Future<String?> checkAdminWalletBalance({
    required CitizenWalletStateAccount wallet,
    required double requiredFeeYuan,
    required String actionLabel,
    required CitizenChain chain,
  }) async {
    final balance = await chain.getAccountBalance(wallet.accountId);
    final balanceYuan = balance.freeFen.toDouble() / 100;
    final edYuan = MultisigCreateAmountRules.fenToYuan(
      MultisigCreateAmountRules.existentialDepositFen,
    );
    final requiredBalanceYuan = requiredFeeYuan + edYuan;
    if (balanceYuan >= requiredBalanceYuan) {
      return null;
    }
    return '管理员钱包余额不足，不能$actionLabel。当前余额 '
        '${AmountFormat.format(balanceYuan, symbol: '')} 元，至少需要 '
        '${AmountFormat.format(requiredBalanceYuan, symbol: '')} 元'
        '（交易费 ${AmountFormat.format(requiredFeeYuan, symbol: '')} 元，支付后须保留 ED）。';
  }
}
