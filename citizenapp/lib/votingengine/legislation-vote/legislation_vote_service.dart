import 'dart:convert';

import 'package:citizenapp/citizen/shared/pallet_registry.dart';

import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/scale_codec.dart' show ByteOutput;

import 'package:citizenapp/votingengine/legislation-vote/legislation_vote_query_service.dart';

/// 立法投票/签署提交服务(LegislationVote sub-pallet,pallet_index=26)。
///
/// 代表机构表决/行政签署/三人会签/护宪终审四个动作都是**纯 extrinsic**
/// (signer=origin=动作人本人,零 op_tag)，业务层只编码 RuntimeCall，
/// 交易准备、冷热签名和最终执行由 CitizenSDK 完成。提交后回读 legislation-vote storage 确认
/// runtime 已记账,txHash 不代表已执行。特别案公投(referendum/snapshot)带 CID
/// 凭证,另见 legislation_referendum_service。
///
/// 代表机构表决额外携带 `voter_role_code`；其余签署调用保持
/// `[26][call_index][proposal_id:u64_le][approve:bool]`。
class LegislationVoteService {
  LegislationVoteService({
    required CitizenChain chain,
    required CitizenTransactions transactions,
  }) : _transactions = transactions,
       _query = LegislationVoteQueryService(chain: chain);

  final CitizenTransactions _transactions;
  final LegislationVoteQueryService _query;

  /// LegislationVote runtime pallet_index。
  static const int legislationVotePallet = PalletRegistry.legislationVotePallet;

  static const int callCastRepresentativeVote =
      PalletRegistry.castRepresentativeVoteCall;
  static const int callExecutiveSign = PalletRegistry.executiveSignCall;
  static const int callOverrideSign = PalletRegistry.overrideSignCall;
  static const int callGuardVote = PalletRegistry.guardVoteCall;

  // ──── 公开 API ────

  /// 当前代表机构表决；同一钱包在不同机构的席位分别记票。
  Future<({String txHash, int usedNonce, String blockHashHex})>
  castRepresentativeVote({
    required int proposalId,
    required String voterRoleCode,
    required bool approve,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final meta = await _query.fetchRepresentativeMeta(proposalId);
    if (meta == null) throw StateError('代表机构表决元数据不存在');
    final bodyIndex = meta.currentBody;
    final result = await _executeFinalized(
      callIndex: callCastRepresentativeVote,
      proposalId: proposalId,
      voterRoleCode: voterRoleCode,
      approve: approve,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    await _confirmRepresentativeVote(
      proposalId,
      bodyIndex,
      meta.bodies[bodyIndex].cidNumber,
      voterRoleCode,
      approve,
      signerPublicKey,
      result.blockHashHex,
    );
    return result;
  }

  /// 行政首长(机构法定代表人)签署或否决。
  Future<({String txHash, int usedNonce, String blockHashHex})> executiveSign({
    required int proposalId,
    required bool approve,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final result = await _executeFinalized(
      callIndex: callExecutiveSign,
      proposalId: proposalId,
      approve: approve,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    // 行政签署无 per-signer 账本:确认提案已离开签署阶段(进会签/已生效/已否决)。
    await _confirmStageAdvanced(proposalId, LegStage.sign, result.blockHashHex);
    return result;
  }

  /// 三人会签(立法院院长 + 参议长 + 众议长)签署或否决。
  Future<({String txHash, int usedNonce, String blockHashHex})> overrideSign({
    required int proposalId,
    required bool approve,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final result = await _executeFinalized(
      callIndex: callOverrideSign,
      proposalId: proposalId,
      approve: approve,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    await _confirmSignRecorded(
      proposalId,
      signerPublicKey,
      result.blockHashHex,
      _query.fetchOverrideSigns,
    );
    return result;
  }

  /// 护宪大法官终审表决(修宪)。
  Future<({String txHash, int usedNonce, String blockHashHex})> guardVote({
    required int proposalId,
    required bool approve,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final result = await _executeFinalized(
      callIndex: callGuardVote,
      proposalId: proposalId,
      approve: approve,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    await _confirmSignRecorded(
      proposalId,
      signerPublicKey,
      result.blockHashHex,
      _query.fetchGuardSigns,
    );
    return result;
  }

  /// 构造 `[26][call][proposal_id:u64_le][approve:bool]` call data(对外公开供冷钱包复用)。
  static Uint8List buildCallData({
    required int callIndex,
    required int proposalId,
    String? voterRoleCode,
    required bool approve,
  }) {
    final output = ByteOutput();
    output.pushByte(legislationVotePallet);
    output.pushByte(callIndex);
    output.write(_u64ToLeBytes(proposalId));
    if (callIndex == callCastRepresentativeVote) {
      final roleBytes = Uint8List.fromList(
        voterRoleCode == null ? const [] : utf8.encode(voterRoleCode.trim()),
      );
      if (roleBytes.isEmpty || roleBytes.length > 64) {
        throw ArgumentError('代表机构表决必须提供 1..64 字节 voter_role_code');
      }
      output.write(_encodeCompact(roleBytes.length));
      output.write(roleBytes);
    } else if (voterRoleCode != null) {
      throw ArgumentError('当前立法签署调用不得携带 voter_role_code');
    }
    output.pushByte(approve ? 1 : 0);
    return output.toBytes();
  }

  // ──── 内部:签名提交 ────

  Future<({String txHash, int usedNonce, String blockHashHex})>
  _executeFinalized({
    required int callIndex,
    required int proposalId,
    String? voterRoleCode,
    required bool approve,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final callData = buildCallData(
      callIndex: callIndex,
      proposalId: proposalId,
      voterRoleCode: voterRoleCode,
      approve: approve,
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
        throw StateError('立法投票签名已取消');
      }
      completed = await _transactions.consumePreparedTransactionQrResponse(
        started.executionId,
        response,
      );
    } else {
      completed = started as CitizenTransactionExecutionCompleted;
    }
    if (completed.resolution != CitizenTransactionResolution.finalizedSuccess ||
        completed.execution == null) {
      throw StateError(completed.poolRejectionReason ?? '立法投票交易执行失败');
    }
    return (
      txHash: '0x${_hexEncode(completed.transactionHash)}',
      usedNonce: prepared.nonce.toInt(),
      blockHashHex: completed.execution!.block.hash,
    );
  }

  // ──── 内部:入块后确认 ────

  Future<void> _confirmRepresentativeVote(
    int proposalId,
    int bodyIndex,
    String cidNumber,
    String voterRoleCode,
    bool approve,
    Uint8List signerPublicKey,
    String blockHashHex,
  ) async {
    final publicKey = _hexEncode(signerPublicKey);
    for (var attempt = 0; attempt < 6; attempt++) {
      final vote = await _query.fetchRepresentativeVote(
        proposalId,
        bodyIndex,
        cidNumber,
        voterRoleCode,
        publicKey,
      );
      if (vote == approve) return;
      if (vote != null && vote != approve) {
        throw StateError('runtime 投票记录与本次投票方向不一致');
      }
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('交易已成功执行，但 runtime 未记录该议员投票');
  }

  Future<void> _confirmSignRecorded(
    int proposalId,
    Uint8List signerPublicKey,
    String blockHashHex,
    Future<List<({String accountId, bool approve})>> Function(int) fetchSigns,
  ) async {
    final accountId = '0x${_hexEncode(signerPublicKey)}';
    for (var attempt = 0; attempt < 6; attempt++) {
      final signs = await fetchSigns(proposalId);
      if (signs.any((s) => s.accountId == accountId)) return;
      // 终审/会签可能一签即终态清账;若提案已离开该阶段也算成功。
      final state = await _query.fetchProposalState(proposalId);
      if (state != null && state.status != LegProposalStatus.voting) return;
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('交易已成功执行，但 runtime 未记录该签署');
  }

  Future<void> _confirmStageAdvanced(
    int proposalId,
    int fromStage,
    String blockHashHex,
  ) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final state = await _query.fetchProposalState(proposalId);
      // 签署被处理后:或已终态(passed/rejected),或推进到下一阶段(会签)。
      if (state != null &&
          (state.status != LegProposalStatus.voting ||
              state.stage != fromStage)) {
        return;
      }
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('交易已成功执行，但 runtime 未推进签署阶段');
  }

  // ──── 内部:编码工具 ────

  static Uint8List _u64ToLeBytes(int value) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint64(0, value, Endian.little);
    return bytes;
  }

  static Uint8List _encodeCompact(int value) {
    if (value < 0 || value >= 1 << 14) {
      throw ArgumentError('长度超出 SCALE Compact 两字节范围');
    }
    if (value < 1 << 6) return Uint8List.fromList([value << 2]);
    final encoded = (value << 2) | 1;
    return Uint8List.fromList([encoded & 0xff, encoded >> 8]);
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
