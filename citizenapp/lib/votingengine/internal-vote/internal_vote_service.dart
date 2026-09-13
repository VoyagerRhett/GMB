import 'dart:convert';

import 'package:citizenapp/citizen/shared/pallet_registry.dart';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/scale_codec.dart' show ByteOutput;

import 'package:citizenapp/votingengine/internal-vote/internal_vote_query_service.dart';

/// 投票引擎统一投票入口服务。
///
/// - 所有业务 pallet(admins_change / resolution_destroy /
///   grandpakey_change / institution_multisig / transaction 业务)的
///   管理员一人一票一律走
///   `InternalVote::cast(proposal_id, ticket_claim, approve)` 一条路径。
/// - 业务 service(InstitutionChainService 等)
///   只负责发起提案(propose_X)；执行重试统一走 VotingEngine.retry_passed_proposal,
///   投票动作统一
///   委托本服务,避免多处构造相同的 call。
///
/// Runtime 位置: `pallet_index=20, call_index=0`(InternalVote sub-pallet)。
/// Call 编码: `[0x14][0x00][proposal_id:u64_le][ticket_claim][approve:bool]`。
class InternalVoteService {
  const InternalVoteService({
    required CitizenChain chain,
    required CitizenTransactions transactions,
  })  : _chain = chain,
        _transactions = transactions;

  final CitizenChain _chain;
  final CitizenTransactions _transactions;

  // ──── 常量 ────

  /// InternalVote sub-pallet。runtime pallet_index=20。
  static const int internalVotePallet = PalletRegistry.internalVotePallet;

  /// InternalVote::cast call_index=0。
  static const int internalVoteCallIndex = PalletRegistry.internalVoteCastCall;

  // ──── 公开 API ────

  /// 提交 `InternalVote::cast(proposal_id, approve)` extrinsic(pallet 20.0)。
  ///
  /// 投票提交必须等待交易进入区块。txHash 只代表交易已提交，
  /// 不能代表 runtime 已执行 `InternalVote::cast`。
  ///
  /// 返回交易哈希、runtime nonce 和入块哈希。业务模块无需感知提案所属
  /// pallet/MODULE_TAG，投票引擎会按 ProposalData 前缀自动分派到对应
  /// `InternalVoteExecutor`；最终投票状态仍以投票引擎 storage 为准。
  Future<({String txHash, int usedNonce, String blockHashHex})> submit({
    required int proposalId,
    required bool approve,
    String? actorCidNumber,
    String? voterRoleCode,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final callData = buildCallData(
      proposalId: proposalId,
      voterRoleCode: voterRoleCode,
      approve: approve,
    );
    final result = await _executeFinalized(
      callData: callData,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    await _confirmRuntimeVote(
      proposalId: proposalId,
      actorCidNumber: actorCidNumber,
      voterRoleCode: voterRoleCode,
      approve: approve,
      signerPublicKey: signerPublicKey,
    );
    return result;
  }

  /// 构造 InternalVote::cast call data(对外公开,便于冷钱包/热钱包复用)。
  ///
  /// `voterRoleCode == null` 编码个人票据声明 0；机构岗位编码声明 1 + RoleCode。
  static Uint8List buildCallData({
    required int proposalId,
    String? voterRoleCode,
    required bool approve,
  }) {
    final output = ByteOutput();
    output.pushByte(internalVotePallet);
    output.pushByte(internalVoteCallIndex);
    output.write(_u64ToLeBytes(proposalId));
    final roleCode = voterRoleCode?.trim();
    if (roleCode == null || roleCode.isEmpty) {
      output.pushByte(0); // InternalVoteTicketClaim::Personal
    } else {
      final roleBytes = Uint8List.fromList(utf8.encode(roleCode));
      if (roleBytes.length > 64) {
        throw ArgumentError('voter_role_code 超过 64 字节');
      }
      output.pushByte(1); // InternalVoteTicketClaim::InstitutionRole
      output.write(_encodeCompact(roleBytes.length));
      output.write(roleBytes);
    }
    output.pushByte(approve ? 1 : 0);
    return output.toBytes();
  }

  // ──── 内部：签名提交 ────

  Future<({String txHash, int usedNonce, String blockHashHex})> _executeFinalized({
    required Uint8List callData,
    required Uint8List signerPublicKey,
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
        throw StateError('投票签名已取消');
      }
      completed = await _transactions.consumePreparedTransactionQrResponse(
        started.executionId,
        response,
      );
    } else {
      completed = started as CitizenTransactionExecutionCompleted;
    }
    if (completed.resolution !=
            CitizenTransactionResolution.finalizedSuccess ||
        completed.execution == null) {
      throw StateError(completed.poolRejectionReason ?? '投票交易执行失败');
    }
    return (
      txHash: '0x${_hexEncode(completed.transactionHash)}',
      usedNonce: prepared.nonce.toInt(),
      blockHashHex: completed.execution!.block.hash,
    );
  }

  /// SDK finalized execution 成功后回读 runtime 投票引擎 storage，
  /// 确认管理员投票已经真正写入。
  ///
  /// 这里是 citizenapp 的投票确认边界。txHash、交易池状态和
  /// 客户端 pending 记录都不能替代 runtime `InternalVotesByTicket`。
  Future<void> _confirmRuntimeVote({
    required int proposalId,
    required String? actorCidNumber,
    required String? voterRoleCode,
    required bool approve,
    required Uint8List signerPublicKey,
  }) async {
    final publicKey = _hexEncode(signerPublicKey);
    final query = InternalVoteQueryService(chain: _chain);
    for (var attempt = 0; attempt < 6; attempt++) {
      final chainVote = actorCidNumber == null
          ? await query.fetchAdminVote(proposalId, publicKey)
          : await query.fetchInstitutionTicketVote(
              proposalId,
              actorCidNumber,
              voterRoleCode!,
              publicKey,
            );
      if (chainVote == approve) return;
      if (chainVote != null && chainVote != approve) {
        throw StateError('runtime 投票记录与本次投票方向不一致');
      }
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    throw StateError('交易已成功执行，但 runtime 投票记录未收敛');
  }

  static Uint8List _encodeCompact(int value) {
    if (value < 0 || value >= 1 << 14) {
      throw ArgumentError('岗位码长度超出 SCALE Compact 两字节范围');
    }
    if (value < 1 << 6) return Uint8List.fromList([value << 2]);
    final encoded = (value << 2) | 1;
    return Uint8List.fromList([encoded & 0xff, encoded >> 8]);
  }

  // ──── 内部：编码工具 ────

  static Uint8List _u64ToLeBytes(int value) {
    final bytes = Uint8List(8);
    final bd = ByteData.sublistView(bytes);
    bd.setUint64(0, value, Endian.little);
    return bytes;
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
