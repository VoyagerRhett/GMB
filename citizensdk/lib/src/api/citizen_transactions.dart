import '../models/citizen_transaction.dart';

/// CitizenSDK 高层公民链转账接口。
///
/// 交易构造、sr25519 签名、pending-before-broadcast、提交、监听和 Runtime 终态核验全部由
/// Rust Core 完成；Dart 不接收已签名 extrinsic。
abstract interface class CitizenTransactions {
  Future<CitizenWalletTransfer> transferWithRemark({
    required String sourceAccountId,
    required String destinationAccountId,
    required BigInt amountFen,
    String remark = '',
  });
}

/// 独立 finalized 历史门面；依赖链，不要求本地钱包或签名金库。
abstract interface class CitizenHistory {
  Future<CitizenTransactionHistory> initializeFinalizedHistory(
    List<String> accountIds,
  );

  Future<CitizenTransactionHistory> syncFinalizedHistory(
    List<String> accountIds,
  );
}
