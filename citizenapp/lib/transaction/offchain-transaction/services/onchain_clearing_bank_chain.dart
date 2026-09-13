import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/citizen/shared/pallet_registry.dart';

import 'package:polkadart/scale_codec.dart' show CompactBigIntCodec, ByteOutput;


/// 扫码支付清算体系中清算行(L2)业务的链上 RuntimeCall 与执行入口。
///
///
/// - 对应 `offchain-transaction` pallet 的 4 个 call(call_index 30/31/32/33):
///   `bind_clearing_bank` / `deposit` / `withdraw` / `switch_bank`。原省储行
///   `bind_clearing_institution` (call_index 9) 已在 Step 2b-iv-b 随老 pallet
///   删除。
/// - CitizenApp 只保留 RuntimeCall SCALE 编码；nonce、era、tip、sr25519、
///   extrinsic 和 finalized execution 全部由 CitizenSDK 负责。
/// - 所有金额参数以**分**为单位的整数进入 SCALE 编码,与链上 `u128` 对齐。
class OnchainClearingBankChain {
  const OnchainClearingBankChain({required CitizenTransactions transactions})
      : _transactions = transactions;

  final CitizenTransactions _transactions;

  /// `OffchainTransaction` pallet index(citizenchain runtime 定义)。
  static const int _palletIndex = PalletRegistry.offchainTransactionPallet;

  /// 4 个 call_index(对应 lib.rs call_index 30~33)。
  static const int _bindClearingBankCallIndex = PalletRegistry.bindClearingBankCall;
  static const int _depositCallIndex = PalletRegistry.depositCall;
  static const int _withdrawCallIndex = PalletRegistry.withdrawCall;
  static const int _switchBankCallIndex = PalletRegistry.switchBankCall;

  // ──────────── 公开接口:4 个新 extrinsic ────────────

  /// `bind_clearing_bank(bank_main_account_id)`:L3 绑定清算行(绑定即开户,无预存)。
  ///
  /// [signerPublicKey]     L3 用户公钥(32 字节)
  /// [bankMainAccountId]  目标清算行**主账户**地址(32 字节,从 CID API 拿到 hex 后解码)
  /// [externalSigning]  冷账户展示 SDK QR_V1 后返回的扫描原文
  Future<({String txHash, int usedNonce})> bindClearingBank({
    required Uint8List signerPublicKey,
    required Uint8List bankMainAccountId,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) {
    final callData = _buildBindClearingBankCall(bankMainAccountId);
    return _executeFinalized(
      signerPublicKey: signerPublicKey,
      callData: callData,
      externalSigning: externalSigning,
    );
  }

  /// `deposit(amount)`:L3 自持账户 → 清算行主账户充值。
  ///
  /// [amountFen] 充值金额(分,u128 范围内的正整数)。
  Future<({String txHash, int usedNonce})> deposit({
    required Uint8List signerPublicKey,
    required BigInt amountFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) {
    final callData = _buildAmountOnlyCall(_depositCallIndex, amountFen);
    return _executeFinalized(
      signerPublicKey: signerPublicKey,
      callData: callData,
      externalSigning: externalSigning,
    );
  }

  /// `withdraw(amount)`:清算行主账户 → L3 自持账户提现。
  Future<({String txHash, int usedNonce})> withdraw({
    required Uint8List signerPublicKey,
    required BigInt amountFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) {
    final callData = _buildAmountOnlyCall(_withdrawCallIndex, amountFen);
    return _executeFinalized(
      signerPublicKey: signerPublicKey,
      callData: callData,
      externalSigning: externalSigning,
    );
  }

  /// `switch_bank(new_bank)`:切换清算行(前置:旧清算行余额必须为 0)。
  Future<({String txHash, int usedNonce})> switchBank({
    required Uint8List signerPublicKey,
    required Uint8List newBankMainAccountId,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) {
    final callData = _buildAccountIdCall(
      _switchBankCallIndex,
      newBankMainAccountId,
    );
    return _executeFinalized(
      signerPublicKey: signerPublicKey,
      callData: callData,
      externalSigning: externalSigning,
    );
  }

  // ──────────── 内部：业务 RuntimeCall 编码 ────────────

  /// `bind_clearing_bank` 与 `switch_bank` 都是接受单个 AccountId 参数,统一编码。
  ///
  /// 格式:`[pallet_index=19] [call_index] [account_id: [u8;32]]`。
  Uint8List _buildBindClearingBankCall(Uint8List bankMainAccountId) {
    return _buildAccountIdCall(_bindClearingBankCallIndex, bankMainAccountId);
  }

  Uint8List _buildAccountIdCall(int callIndex, Uint8List accountId) {
    if (accountId.length != 32) {
      throw ArgumentError('account_id 必须是 32 字节,实际 ${accountId.length}');
    }
    final output = ByteOutput()
      ..pushByte(_palletIndex)
      ..pushByte(callIndex)
      ..write(accountId);
    return output.toBytes();
  }

  /// 仅含 amount 参数的 RuntimeCall（deposit/withdraw 共用）。
  ///
  /// 格式:`[pallet_index=19] [call_index] [Compact<u128>(amount_fen)]`
  /// 与链上 `pub fn deposit(origin, amount: u128)` 严格对齐。
  Uint8List _buildAmountOnlyCall(int callIndex, BigInt amountFen) {
    if (amountFen <= BigInt.zero) {
      throw ArgumentError('amount 必须大于 0(分),实际 $amountFen');
    }
    final output = ByteOutput()
      ..pushByte(_palletIndex)
      ..pushByte(callIndex)
      ..write(CompactBigIntCodec.codec.encode(amountFen));
    return output.toBytes();
  }

  /// 把 App 业务 callData 直接交给 CitizenSDK；nonce、era、签名、
  /// extrinsic、提交、观察与 finalized Runtime 终态均不在本类实现。
  Future<({String txHash, int usedNonce})> _executeFinalized({
    required Uint8List signerPublicKey,
    required Uint8List callData,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final prepared = await _transactions.prepareTransaction(
      signerPublicKey,
      callData,
    );
    final started = await _transactions.executePreparedTransaction(
      prepared.preparationId,
    );
    CitizenTransactionExecutionCompleted completed;
    if (started is CitizenTransactionExternalSigningPending) {
      final response = await externalSigning(started);
      if (response == null) {
        await _transactions.cancelPreparedTransactionExecution(
          started.executionId,
        );
        throw StateError('清算行链上交易签名已取消');
      }
      completed = await _transactions.consumePreparedTransactionQrResponse(
        started.executionId,
        response,
      );
    } else {
      completed = started as CitizenTransactionExecutionCompleted;
    }
    if (completed.resolution != CitizenTransactionResolution.finalizedSuccess) {
      throw StateError(completed.poolRejectionReason ?? '清算行链上交易执行失败');
    }
    return (
      txHash: '0x${_hex(completed.transactionHash)}',
      usedNonce: prepared.nonce.toInt(),
    );
  }

  // ──────────── 通用工具 ────────────

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
