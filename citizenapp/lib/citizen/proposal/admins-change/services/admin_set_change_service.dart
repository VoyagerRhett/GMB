import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/citizen/proposal/admins-change/codec/admin_set_change_call_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/codec/account_id_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_set_change_result.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_set_validation.dart';

/// 本服务校验并编码管理员集合变更业务 RuntimeCall，再委托 CitizenSDK 准备和执行通用交易；
/// 热签、QR_V1 冷签和链上终态观察均由 SDK 提供，不在 CitizenApp 业务层重复实现。
class AdminsChangeService {
  const AdminsChangeService({required CitizenTransactions transactions})
      : _transactions = transactions;

  final CitizenTransactions _transactions;

  Uint8List buildCallData({
    required AdminAccountState account,
    required String proposerAccountId,
    required List<AdminPerson> admins,
    required int newThreshold,
  }) {
    final normalized = AdminSetValidation.validate(
      account: account,
      proposerAccountId: proposerAccountId,
      admins: admins,
      newThreshold: newThreshold,
    );
    return PersonalAdminsChangeCallCodec.build(
      institutionCode: account.institutionCode,
      adminKind: account.kind,
      accountId:
          AdminAccountIdCodec.fromAccountIdText(account.personalAccountId!),
      admins: normalized.admins,
      newThreshold: normalized.threshold,
    );
  }

  Future<AdminsChangeSubmitResult> submit({
    required AdminAccountState account,
    required List<AdminPerson> admins,
    required int newThreshold,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final callData = buildCallData(
      account: account,
      proposerAccountId: '0x${AdminAccountIdCodec.hexEncode(signerPublicKey)}',
      admins: admins,
      newThreshold: newThreshold,
    );
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
        throw StateError('管理员更换签名已取消');
      }
      completed = await _transactions.consumePreparedTransactionQrResponse(
        started.executionId,
        response,
      );
    } else {
      completed = started as CitizenTransactionExecutionCompleted;
    }
    if (completed.resolution != CitizenTransactionResolution.finalizedSuccess) {
      throw StateError(completed.poolRejectionReason ?? '管理员更换交易执行失败');
    }
    return AdminsChangeSubmitResult(
      txHash: '0x${AdminAccountIdCodec.hexEncode(completed.transactionHash)}',
      usedNonce: prepared.nonce.toInt(),
    );
  }
}
