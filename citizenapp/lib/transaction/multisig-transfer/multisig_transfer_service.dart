import 'dart:convert';

import 'package:citizenapp/citizen/shared/pallet_registry.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:polkadart/scale_codec.dart' show CompactBigIntCodec, ByteOutput;
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/institution/institution_models.dart'
    as institution_models;
import 'package:citizenapp/citizen/institution/institution_chain_service.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_models.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_service.dart';

import 'package:citizenapp/citizen/shared/institution_code_label.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_cache.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_cache.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_models.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_query_service.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// 固定治理机构资金业务的默认岗位码；普通机构必须由任职人明确填写动态岗位码。
String defaultInstitutionProposerRoleCode(InstitutionInfo institution) {
  switch (institution.orgType) {
    case OrgType.nrc:
    case OrgType.prc:
      return 'COMMITTEE_MEMBER';
    case OrgType.prb:
      return 'DIRECTOR';
    default:
      return '';
  }
}

/// 机构转账提案链上交互服务。
///
/// 负责 extrinsic 编码/提交 和 storage 查询。
class MultisigTransferService {
  MultisigTransferService({
    required CitizenChain chain,
    required CitizenTransactions transactions,
  })  : _chain = chain,
        _transactions = transactions,
        _internalVoteQuery = InternalVoteQueryService(chain: chain),
        _proposalQuery = ProposalQueryService(chain: chain);

  final CitizenChain _chain;
  final CitizenTransactions _transactions;
  final InternalVoteQueryService _internalVoteQuery;
  final ProposalQueryService _proposalQuery;

  // ──── 常量 ────

  /// MultisigTransfer pallet index（runtime pallet_index=17）。
  ///
  /// 本 pallet 只保留 propose_X(0/1/2)；机构岗位选民/个人多签管理员投票一律走
  /// InternalVote(20).cast(0)，手动重试走 VotingEngine(9).retry_passed_proposal(4)。
  static const _palletIndex = PalletRegistry.multisigTransferPallet;

  /// propose_transfer call_index=0。
  static const _proposeCallIndex = 0;

  /// propose_safety_fund_transfer call_index=1。
  static const _proposeSafetyFundCallIndex = 1;

  /// propose_sweep_to_main call_index=2。
  static const _proposeSweepCallIndex = 2;

  /// MultisigTransfer::TransferProposed event_index=0。
  static const _transferProposedEventIndex = 0;

  /// MultisigTransfer::SafetyFundTransferProposed event_index=3。
  /// Event enum 按声明顺序编号（无显式 codec index），顺序为
  /// TransferProposed(0)/ExecutionFailed(1)/Executed(2)/SafetyFundTransferProposed(3)/
  /// …/SweepToMainProposed(6)，与 runtime lib.rs 严格一致。
  static const _safetyFundProposedEventIndex = 3;

  /// MultisigTransfer::SweepToMainProposed event_index=6。
  static const _sweepProposedEventIndex = 6;

  /// 与 runtime `multisig::MODULE_TAG` 唯一对齐的提案数据标签。
  static const _moduleTag = 'multisig';

  // ──── Extrinsic 提交 ────

  /// 提交 propose_transfer extrinsic。
  ///
  /// 返回真实创建出的 proposal_id、交易哈希、nonce 和入块哈希。
  Future<
      ({
        String txHash,
        int usedNonce,
        int proposalId,
        String blockHashHex,
      })> submitProposeTransfer({
    required InstitutionInfo institution,
    required String? proposerRoleCode,
    required String beneficiaryAddress,
    required double amountYuan,
    required String remark,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final amountFen = BigInt.from((amountYuan * 100).round());
    final actorCidNumber = isPersonalAccountIdentity(institution.cidNumber)
        ? null
        : institution.cidNumber;
    final normalizedRoleCode = actorCidNumber == null
        ? null
        : _requireProposerRoleCode(proposerRoleCode);
    final beneficiaryPublicKey =
        _ss58AddressToAccountId(beneficiaryAddress, '收款地址');
    // InstitutionInfo.mainAccountId 是 App 内部 AccountId hex，
    // 不能按 SS58/Base58 解码，否则 hex 中的 0 会被当成非法 Base58 字符。
    final fromPublicKey =
        _accountIdToAccountId(institution.mainAccountId, '转出主账户');
    final callData = _buildProposeTransferCall(
      actorCidNumber: actorCidNumber,
      proposerRoleCode: normalizedRoleCode,
      fundingAccountId: institution.mainAccountId,
      beneficiaryAddress: beneficiaryAddress,
      amountFen: amountFen,
      remark: remark,
    );
    final submitResult = await _executeFinalized(
      callData: callData,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    final proposalId = await _confirmTransferProposedEvent(
      finalizedBlock: submitResult.block,
      institutionCode: institution.adminAccountCode ?? 'PMUL',
      actorCidNumber: actorCidNumber,
      proposerPublicKey: signerPublicKey,
      fromPublicKey: fromPublicKey,
      beneficiaryPublicKey: beneficiaryPublicKey,
      amountFen: amountFen,
    );
    return (
      txHash: submitResult.txHash,
      usedNonce: submitResult.usedNonce,
      proposalId: proposalId,
      blockHashHex: submitResult.block.hash,
    );
  }

  /// 提交 propose_safety_fund_transfer extrinsic（安全基金转账提案）。
  ///
  /// 提案创建类交易必须等真正入块并核对事件后才算业务成功
  /// （与 submitProposeTransfer 同标准），返回事件中的 proposal_id
  /// 供后续投票跟踪；submit-only 给不出 proposal_id，也无法区分
  /// "已接受"与"已上链"。
  Future<({String txHash, int usedNonce, int proposalId, String blockHashHex})>
      submitProposeSafetyFund({
    required InstitutionInfo institution,
    required String proposerRoleCode,
    required String beneficiaryAddress,
    required double amountYuan,
    required String remark,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final amountFen = BigInt.from((amountYuan * 100).round());
    final actorCidNumber = institution.cidNumber;
    final safetyFundAccountId = institution.accounts?.safetyFundAccountId ??
        (throw StateError('国家储委会缺少安全基金账户'));
    final safetyFundAccountIdBytes =
        Uint8List.fromList(accountIdBytes(safetyFundAccountId));
    final beneficiaryPublicKey =
        _ss58AddressToAccountId(beneficiaryAddress, '收款地址');
    final callData = _buildProposeSafetyFundCall(
      actorCidNumber: actorCidNumber,
      proposerRoleCode: _requireProposerRoleCode(proposerRoleCode),
      institutionAccountId: safetyFundAccountId,
      beneficiaryAddress: beneficiaryAddress,
      amountYuan: amountYuan,
      remark: remark,
    );
    final submitResult = await _executeFinalized(
      callData: callData,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    final proposalId = await _confirmProposalEvent(
      finalizedBlock: submitResult.block,
      eventLabel: 'SafetyFundTransferProposed',
      eventIndex: _safetyFundProposedEventIndex,
      decode: (data, offset) => _decodeSafetyFundProposedEvent(
        data,
        offset,
        actorCidNumber: actorCidNumber,
        institutionAccountId: safetyFundAccountIdBytes,
        proposerPublicKey: signerPublicKey,
        beneficiaryPublicKey: beneficiaryPublicKey,
        amountFen: amountFen,
      ),
    );
    return (
      txHash: submitResult.txHash,
      usedNonce: submitResult.usedNonce,
      proposalId: proposalId,
      blockHashHex: submitResult.block.hash,
    );
  }

  /// 提交 propose_sweep_to_main extrinsic（手续费划转提案）。
  ///
  /// 同 submitProposeSafetyFund，提案类必须入块+核对事件。
  Future<({String txHash, int usedNonce, int proposalId, String blockHashHex})>
      submitProposeSweep({
    required InstitutionInfo institution,
    required String proposerRoleCode,
    required double amountYuan,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final amountFen = BigInt.from((amountYuan * 100).round());
    final feeAccountId =
        institution.accounts?.feeAccountId ?? (throw StateError('机构缺少费用账户'));
    final institutionAccountId =
        Uint8List.fromList(accountIdBytes(feeAccountId));
    final toPublicKey =
        _accountIdToAccountId(institution.mainAccountId, '机构主账户');
    final callData = _buildProposeSweepCall(
      actorCidNumber: institution.cidNumber,
      proposerRoleCode: _requireProposerRoleCode(proposerRoleCode),
      institutionAccountId: feeAccountId,
      amountYuan: amountYuan,
    );
    final submitResult = await _executeFinalized(
      callData: callData,
      signerPublicKey: signerPublicKey,
      externalSigning: externalSigning,
    );
    final proposalId = await _confirmProposalEvent(
      finalizedBlock: submitResult.block,
      eventLabel: 'SweepToMainProposed',
      eventIndex: _sweepProposedEventIndex,
      decode: (data, offset) => _decodeSweepProposedEvent(
        data,
        offset,
        institutionAccountId: institutionAccountId,
        actorCidNumber: institution.cidNumber,
        proposerPublicKey: signerPublicKey,
        toPublicKey: toPublicKey,
        amountFen: amountFen,
      ),
    );
    return (
      txHash: submitResult.txHash,
      usedNonce: submitResult.usedNonce,
      proposalId: proposalId,
      blockHashHex: submitResult.block.hash,
    );
  }

  // ──── 链上查询 ────

  /// 查询转出主账户的 finalized 可用余额（元）。
  ///
  /// 治理机构按主账户、费用账户、安全基金、永久质押分别建模，转账提案固定从主账户支出；
  /// 个人/注册多签账户通过 InstitutionInfo.mainAccountId 继续映射到账户。
  Future<double> fetchInstitutionBalance(InstitutionInfo institution) async {
    final balance = await _chain.getAccountBalance(institution.mainAccountId);
    return balance.freeFen.toDouble() / 100;
  }

  // ──── 双层 ID 与反向索引 ────

  /// 查询提案展示号:`ProposalDisplayId[proposal_id] = ProposalDisplayMeta { year, seq_in_year }`。
  ///
  /// 返回 null 表示链上不存在该展示号(理论上不应该发生 — 创建提案时
  /// 同事务一定写入)。
  Future<ProposalDisplayMeta?> fetchProposalDisplayId(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'ProposalDisplayId',
      _u64ToLeBytes(proposalId),
    );
    final data = await _fetchStorage('0x${_hexEncode(key)}');
    if (data == null || data.length != 6) return null;
    // SCALE: u16 LE (year) + u32 LE (seq_in_year) = 6 bytes
    final bd = ByteData.sublistView(data);
    return ProposalDisplayMeta(
      year: bd.getUint16(0, Endian.little),
      seqInYear: bd.getUint32(2, Endian.little),
    );
  }

  /// 批量查询展示号(列表页一次性 batch fetch,避免 N 次 RPC)。
  Future<Map<int, ProposalDisplayMeta>> fetchProposalDisplayIdBatch(
      List<int> proposalIds) async {
    if (proposalIds.isEmpty) return const {};
    final keyHexList = proposalIds
        .map((id) => '0x${_hexEncode(_buildStorageKey(
              'VotingEngine',
              'ProposalDisplayId',
              _u64ToLeBytes(id),
            ))}')
        .toList();
    final batchResult = await _fetchStorageBatch(keyHexList);
    final result = <int, ProposalDisplayMeta>{};
    for (var i = 0; i < proposalIds.length; i++) {
      final data = batchResult[keyHexList[i]];
      if (data == null || data.length != 6) continue;
      final bd = ByteData.sublistView(data);
      result[proposalIds[i]] = ProposalDisplayMeta(
        year: bd.getUint16(0, Endian.little),
        seqInYear: bd.getUint32(2, Endian.little),
      );
    }
    return result;
  }

  // 提案查询统一走按年取 + 客户端过滤:code 过滤(filterGovernanceIds)、
  // CID 过滤(filterInstitutionVisible)。链端归属真源是 Proposal.subject_cid_numbers,
  // `ProposalsByYear` 是全量短 key 入口,列表页只从已解码 CID 集合筛选。

  /// 通用反向索引迭代器。
  ///
  /// `StorageDoubleMap<_, Twox64Concat, K1, Twox64Concat, u64, ()>` 的 key 结构:
  ///   `twox128(pallet) ++ twox128(storage) ++ twox64(K1)(8B) ++ K1(原值) ++ twox64(u64)(8B) ++ u64(8B LE)`
  ///
  /// 取所有 key 的前缀:
  ///   `twox128(pallet) ++ twox128(storage) ++ twox64(K1) ++ K1`
  ///
  /// `state_getKeysPaged(prefix, count, startKey)` 返回前缀下所有完整 key,
  /// 每个 key 末 8 字节 = u64 LE = proposal_id。
  Future<List<int>> _fetchProposalIdsByDoubleMap(
      String storageName, Uint8List firstKeyRaw) async {
    final palletHash = _twoxx128String('VotingEngine');
    final storageHash = _twoxx128String(storageName);
    final firstKeyHashed = Hasher.twoxx64.hash(firstKeyRaw);
    final prefixLen = palletHash.length +
        storageHash.length +
        firstKeyHashed.length +
        firstKeyRaw.length;
    final prefix = Uint8List(prefixLen);
    var off = 0;
    prefix.setAll(off, palletHash);
    off += palletHash.length;
    prefix.setAll(off, storageHash);
    off += storageHash.length;
    prefix.setAll(off, firstKeyHashed);
    off += firstKeyHashed.length;
    prefix.setAll(off, firstKeyRaw);
    final finalized = await _chain.getFinalizedHead();
    final keys = await _chain.getStorageKeysPaged(finalized, prefix);
    if (keys.isEmpty) return const [];

    // 每条 key 末 8 字节 = proposal_id u64 LE(twox64_concat 的 raw 部分)
    final ids = <int>[];
    for (final keyBytes in keys) {
      if (keyBytes.length < 8) continue;
      final tail = keyBytes.sublist(keyBytes.length - 8);
      ids.add(_decodeU64(tail));
    }
    return ids;
  }

  /// 查询主体活跃提案；机构按 CID，个人多签按 AccountId。
  Future<List<int>> fetchActiveProposalIds(InstitutionInfo institution) {
    return _proposalQuery.fetchActiveProposalIds(institution);
  }

  /// 查询投票计数。
  Future<({int yes, int no})> fetchVoteTally(int proposalId) {
    return _proposalQuery.fetchVoteTally(proposalId);
  }

  /// 查询内部投票阈值快照。
  ///
  /// 个人多签创建提案的创建阈值是提案级快照，
  /// 不能使用 InstitutionInfo.internalThreshold 的多签默认值。
  Future<int?> fetchInternalThresholdSnapshot(int proposalId) {
    return _proposalQuery.fetchInternalThresholdSnapshot(proposalId);
  }

  /// 查询提案创建时锁定的实际投票账户快照。
  ///
  /// 机构按岗位有效任职快照，个人多签按管理员快照；详情页展示和
  /// 可投钱包筛选必须使用同一份创建时快照。
  Future<List<EligibleVoterTicket>> fetchEligibleVoterTickets(
    int proposalId,
    InstitutionInfo institution,
  ) {
    return _proposalQuery.fetchEligibleVoterTickets(
      proposalId,
      institution,
    );
  }

  /// 查询提案状态。返回 status（0=voting, 1=passed, 2=rejected），null 表示不存在。
  Future<int?> fetchProposalStatus(int proposalId) {
    return _proposalQuery.fetchProposalStatus(proposalId);
  }

  /// 查询提案完整元数据（actor CID + execution account + subject CIDs）。
  /// 返回 null 表示提案不存在。
  Future<ProposalMeta?> fetchProposalMeta(int proposalId) async {
    final decoded = await _proposalQuery.fetchProposalMeta(proposalId);
    if (decoded == null) return null;

    // 双层 ID：同时查 ProposalDisplayId 反查表（失败不阻塞，fallback null）。
    ProposalDisplayMeta? displayMeta;
    try {
      displayMeta = await fetchProposalDisplayId(proposalId);
    } catch (e) {
      // 展示号缺失不阻断主流程，但必须留痕，否则 RPC 故障会伪装成"无展示号"。
      AppLog.d('[MultisigTransfer] fetchProposalDisplayId($proposalId) 失败: $e');
    }

    return ProposalMeta(
      proposalId: proposalId,
      kind: decoded.kind,
      stage: decoded.stage,
      status: decoded.status,
      internalCode: decoded.internalCode,
      actorCidNumber: decoded.actorCidNumber,
      executionAccountId: decoded.executionAccountId,
      subjectCidNumbers: decoded.subjectCidNumbers,
      displayMeta: displayMeta,
    );
  }

  // ──── 分页 + 缓存 + 批量查询 ────

  /// 给定一组 proposal_id,batch 查 meta + 业务详情 + 展示号,
  /// 返回 `ProposalWithDetail` 列表(顺序按 ids 入参,不重排)。
  ///
  /// 双层 ID 模式下,客户端先通过反向索引拿 ID 列表,再调本方法取详情。
  /// 多签管理提案(ACTION_CREATE_PERSONAL / ACTION_CLOSE)按既有规则过滤掉。
  Future<List<ProposalWithDetail>> fetchProposalsByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    return _fetchProposalsForIds(ids);
  }

  /// 分页查询提案:从 [startId] 往前(含 startId)加载 [count] 个。
  ///
  /// 优先读缓存,未命中的用 [fetchStorageBatch] 批量查询。
  /// 返回结果按 ID 倒序。
  Future<List<ProposalWithDetail>> fetchProposalPage(
      int startId, int count) async {
    // 把范围转成显式 ids 列表,然后委派给 _fetchProposalsForIds。
    final ids = <int>[
      for (var id = startId; id > startId - count && id >= 0; id--) id,
    ];
    return _fetchProposalsForIds(ids);
  }

  /// 给定 [ids] 一组提案 ID,batch 拉 meta + 业务详情 + 展示号,
  /// 返回 `ProposalWithDetail` 列表,**顺序与入参一致**。
  /// 多签管理类提案(ACTION_CREATE_PERSONAL / ACTION_CLOSE)在装配阶段过滤掉。
  Future<List<ProposalWithDetail>> _fetchProposalsForIds(List<int> ids) async {
    final results = <ProposalWithDetail>[];
    final uncachedMetaKeys = <String>[];
    final uncachedMetaIds = <int>[];
    final cachedMetas = <int, ProposalMeta>{};
    final runtimeUpgradeService = RuntimeUpgradeService(
      chain: _chain,
      transactions: _transactions,
    );

    for (final id in ids) {
      final cached = ProposalCache.getMeta(id);
      if (cached != null) {
        cachedMetas[id] = cached;
      } else {
        final keyBytes =
            _buildStorageKey('VotingEngine', 'Proposals', _u64ToLeBytes(id));
        uncachedMetaKeys.add('0x${_hexEncode(keyBytes)}');
        uncachedMetaIds.add(id);
      }
    }

    // 批量查询未命中的 meta
    if (uncachedMetaKeys.isNotEmpty) {
      final batchResult = await _fetchStorageBatch(uncachedMetaKeys);
      for (var i = 0; i < uncachedMetaIds.length; i++) {
        final id = uncachedMetaIds[i];
        final data = batchResult[uncachedMetaKeys[i]];
        if (data != null) {
          final meta = _decodeProposalMeta(id, data);
          if (meta != null) {
            cachedMetas[id] = meta;
            ProposalCache.putMeta(id, meta);
          }
        }
      }
      // 双层 ID：为这一批 meta 同步批量读取 ProposalDisplayId 并回填。
      final displayMap = await fetchProposalDisplayIdBatch(uncachedMetaIds);
      for (final id in uncachedMetaIds) {
        final meta = cachedMetas[id];
        final dm = displayMap[id];
        if (meta != null && dm != null) {
          final patched = ProposalMeta(
            proposalId: meta.proposalId,
            kind: meta.kind,
            stage: meta.stage,
            status: meta.status,
            internalCode: meta.internalCode,
            actorCidNumber: meta.actorCidNumber,
            executionAccountId: meta.executionAccountId,
            subjectCidNumbers: meta.subjectCidNumbers,
            displayMeta: dm,
          );
          cachedMetas[id] = patched;
          ProposalCache.putMeta(id, patched);
        }
      }
    }

    // 对有 meta 的提案，批量查询 ProposalData（先查缓存）。
    // 联合投票提案不能再走“统一按转账解码”的旧逻辑，
    // 否则 runtime 升级这类提案会被漏掉或误判类型。
    final uncachedDetailKeys = <String>[];
    final uncachedDetailIds = <int>[];
    final cachedTransferDetails = <int, TransferProposalInfo>{};
    final cachedRuntimeUpgradeDetails = <int, RuntimeUpgradeProposalInfo>{};
    final cachedCreateMultisigDetails = <int, CreateProposalInfo>{};
    final cachedCloseMultisigDetails = <int, CloseProposalInfo>{};
    final institutionCloseIds = <int>{};

    for (final entry in cachedMetas.entries) {
      final meta = entry.value;
      if (meta.kind == 1) {
        final cachedDetail = ProposalCache.getRuntimeUpgradeDetail(entry.key);
        if (cachedDetail != null) {
          cachedRuntimeUpgradeDetails[entry.key] = cachedDetail;
          continue;
        }
      } else {
        // 内部投票提案：先查转账缓存，再查管理缓存
        final cachedTransfer =
            MultisigTransferCache.getTransferDetail(entry.key);
        if (cachedTransfer != null) {
          cachedTransferDetails[entry.key] = cachedTransfer;
          continue;
        }
        final cachedCreate = ProposalCache.getCreateMultisigDetail(entry.key);
        if (cachedCreate != null) {
          cachedCreateMultisigDetails[entry.key] = cachedCreate;
          continue;
        }
        final cachedClose = ProposalCache.getCloseMultisigDetail(entry.key);
        if (cachedClose != null) {
          cachedCloseMultisigDetails[entry.key] = cachedClose;
          continue;
        }
      }
      final keyBytes = _buildStorageKey(
          'VotingEngine', 'ProposalData', _u64ToLeBytes(entry.key));
      uncachedDetailKeys.add('0x${_hexEncode(keyBytes)}');
      uncachedDetailIds.add(entry.key);
    }

    if (uncachedDetailKeys.isNotEmpty) {
      final manageService = InstitutionChainService();
      final personalManageService = PersonalManageService(
        chain: _chain,
        transactions: _transactions,
      );
      final batchResult = await _fetchStorageBatch(uncachedDetailKeys);
      for (var i = 0; i < uncachedDetailIds.length; i++) {
        final id = uncachedDetailIds[i];
        final meta = cachedMetas[id];
        final raw = batchResult[uncachedDetailKeys[i]];
        if (meta == null || raw == null || raw.isEmpty) {
          continue;
        }
        if (meta.kind == 1) {
          final runtimeDetail =
              runtimeUpgradeService.decodeRuntimeUpgradeStorageValue(id, raw);
          if (runtimeDetail != null) {
            cachedRuntimeUpgradeDetails[id] = runtimeDetail;
            ProposalCache.putRuntimeUpgradeDetail(id, runtimeDetail);
          }
          continue;
        }

        // 内部投票提案：先按 PersonalAdmins 解码，再按机构管理(公权/私权)解码，
        // 失败后才尝试普通多签转账提案。
        final personalDetail =
            personalManageService.decodePersonalProposalData(id, raw);
        if (personalDetail is CreateProposalInfo) {
          cachedCreateMultisigDetails[id] = personalDetail;
          ProposalCache.putCreateMultisigDetail(id, personalDetail);
          continue;
        }
        if (personalDetail is CloseProposalInfo) {
          cachedCloseMultisigDetails[id] = personalDetail;
          ProposalCache.putCloseMultisigDetail(id, personalDetail);
          continue;
        }
        final orgManageDetail = manageService.decodeManageProposalData(id, raw);
        if (orgManageDetail is institution_models.CloseProposalInfo) {
          // 机构关闭与个人多签关闭是两种不同协议主体；
          // 只在当前查询中标记跳过，不得转换或写入个人多签缓存。
          institutionCloseIds.add(id);
          continue;
        }

        final transferDetail = _decodeProposalData(id, raw);
        if (transferDetail != null) {
          cachedTransferDetails[id] = transferDetail;
          MultisigTransferCache.putTransferDetail(id, transferDetail);
        }
      }
    }

    // 组装结果(跳过多签管理提案,这些在多签账户详情页单独展示)
    for (final id in ids) {
      final meta = cachedMetas[id];
      if (meta == null) continue;
      // 多签管理提案不在治理列表中显示
      if (cachedCreateMultisigDetails.containsKey(id) ||
          cachedCloseMultisigDetails.containsKey(id) ||
          institutionCloseIds.contains(id)) {
        continue;
      }
      final transferDetail = cachedTransferDetails[id];
      final runtimeUpgradeDetail = cachedRuntimeUpgradeDetails[id];
      final createMultisigDetail = cachedCreateMultisigDetails[id];
      final closeMultisigDetail = cachedCloseMultisigDetails[id];
      // 如果都没匹配到，尝试安全基金 / 手续费划转提案。
      SafetyFundProposalInfo? safetyFundDetail;
      SweepProposalInfo? sweepDetail;
      if (transferDetail == null &&
          runtimeUpgradeDetail == null &&
          createMultisigDetail == null &&
          closeMultisigDetail == null &&
          meta.kind == 0) {
        try {
          safetyFundDetail = await fetchSafetyFundAction(id);
        } catch (e) {
          // 查询失败必须留痕，否则与"确实不是安全基金提案"无法区分。
          AppLog.d('[MultisigTransfer] fetchSafetyFundAction($id) 失败: $e');
        }
        if (safetyFundDetail == null) {
          try {
            sweepDetail = await fetchSweepAction(id);
          } catch (e) {
            AppLog.d('[MultisigTransfer] fetchSweepAction($id) 失败: $e');
          }
        }
      }
      // 联合提案且不是 runtime 升级，尝试检测决议发行/销毁
      String? resIssuanceSummary;
      String? resDestroySummary;
      if (meta.kind == 1 && runtimeUpgradeDetail == null) {
        try {
          final raw = await fetchProposalDataRaw(id);
          if (raw != null) {
            final tag = _detectJointProposalTag(raw);
            if (tag == 'res-iss') {
              resIssuanceSummary = '决议发行提案';
            } else if (tag == 'res-dst') {
              resDestroySummary = '决议销毁提案';
            }
          }
        } catch (e) {
          AppLog.d('[MultisigTransfer] 联合提案类型检测($id) 失败: $e');
        }
      }
      results.add(ProposalWithDetail(
        meta: meta,
        runtimeUpgradeDetail: runtimeUpgradeDetail,
        createMultisigDetail: createMultisigDetail?.copyWithStatus(meta.status),
        closeMultisigDetail: closeMultisigDetail?.copyWithStatus(meta.status),
        businessDetails: {
          if (transferDetail != null)
            MultisigTransferProposalDetailKeys.transfer:
                transferDetail.copyWithStatus(meta.status),
          if (safetyFundDetail != null)
            MultisigTransferProposalDetailKeys.safetyFund: safetyFundDetail,
          if (sweepDetail != null)
            MultisigTransferProposalDetailKeys.sweep: sweepDetail,
        },
        resolutionIssuanceSummary: resIssuanceSummary,
        resolutionDestroySummary: resDestroySummary,
      ));
    }

    return results;
  }

  /// ADR-018 统一提案查询:按年取当前年全部提案一次。
  ///
  /// `ProposalsByYear[year]` 是短 key 索引,轻节点可正常前缀扫描;
  /// 链端对每个提案无条件写入该索引、终态清理时移除,所以按年取得到的就是
  /// "全部存活提案"。公民-提案 / 机构详情 / 个人多签统一从这一份结果客户端按
  /// 已解码 `subject_cid_numbers` 过滤,替代旧的账户归属过滤。
  /// 长前缀扫描,并让多页面共用一次查询(见 ProposalFeedCache,降全节点负载)。
  Future<List<ProposalWithDetail>> fetchCurrentYearProposals() async {
    final currentYear = await _resolveCurrentYear();
    if (currentYear == null) return const [];
    final ids = await _fetchProposalIdsByYearTwox(currentYear);
    return _fetchProposalsForIds(ids);
  }

  /// 从当前年提案全集过滤出指定机构页可见的提案(纯客户端,不联网):
  /// 本机构关联提案(`subject_cid_numbers` 包含机构 CID)。
  List<ProposalWithDetail> filterInstitutionVisible(
    List<ProposalWithDetail> all,
    InstitutionInfo institution,
  ) {
    final cidNumber = institution.cidNumber;
    final visible = all.where((p) {
      return p.meta.subjectCidNumbers.contains(cidNumber);
    }).toList();
    visible.sort((a, b) => b.meta.proposalId.compareTo(a.meta.proposalId));
    return visible;
  }

  /// 从当前年提案全集过滤出指定治理类型(机构码)的提案 id(广场用,纯客户端)。
  List<int> filterGovernanceIds(
    List<ProposalWithDetail> all,
    Set<String> codes,
  ) {
    final ids = all
        .where((p) =>
            p.meta.internalCode != null && codes.contains(p.meta.internalCode))
        .map((p) => p.meta.proposalId)
        .toList();
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  /// 公民 tab「提案」统一流:默认公共机构码 ∪ 当前钱包订阅机构 CID。
  ///
  /// 默认范围按机构码命中(如 NRC/NLG/PRS),订阅范围必须按机构
  /// CID 精确命中,不能按机构码放大,否则会把同类所有省/市机构全部塞进用户提案流。
  List<int> filterCitizenProposalFeedIds(
    List<ProposalWithDetail> all, {
    required Set<String> defaultCodes,
    required Set<String> subscribedInstitutionCidNumbers,
  }) {
    final normalizedDefaultCodes =
        defaultCodes.map((code) => code.toUpperCase()).toSet();
    final normalizedSubscribedCidNumbers = subscribedInstitutionCidNumbers
        .map((cid) => cid.trim())
        .where((cid) => cid.isNotEmpty)
        .toSet();
    final ids = all
        .where((p) {
          final code = p.meta.internalCode?.toUpperCase();
          if (code != null && normalizedDefaultCodes.contains(code)) {
            return true;
          }
          return p.meta.subjectCidNumbers
              .any(normalizedSubscribedCidNumbers.contains);
        })
        .map((p) => p.meta.proposalId)
        .toSet()
        .toList();
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  /// 查询对指定机构用户可见的提案事件(ADR-018:按年取 + 客户端过滤)。
  Future<List<ProposalWithDetail>> fetchInstitutionVisibleProposals(
      InstitutionInfo institution) async {
    final all = await fetchCurrentYearProposals();
    return filterInstitutionVisible(all, institution);
  }

  /// 从 `CurrentProposalYear` 拿当前提案分配年份(用于反向索引按年迭代)。
  Future<int?> _resolveCurrentYear() async {
    final palletHash = _twoxx128String('VotingEngine');
    final storageHash = _twoxx128String('CurrentProposalYear');
    final key = Uint8List(palletHash.length + storageHash.length);
    key.setAll(0, palletHash);
    key.setAll(palletHash.length, storageHash);
    final data = await _fetchStorage('0x${_hexEncode(key)}');
    if (data == null || data.length < 2) return null;
    return ByteData.sublistView(data).getUint16(0, Endian.little);
  }

  /// `ProposalsByYear[year]` 反向索引迭代(year 是 u16,内部不暴露给业务层)。
  Future<List<int>> _fetchProposalIdsByYearTwox(int year) async {
    final yearBytes = Uint8List(2);
    ByteData.sublistView(yearBytes).setUint16(0, year, Endian.little);
    return _fetchProposalIdsByDoubleMap('ProposalsByYear', yearBytes);
  }

  /// 查询指定机构的所有转账提案（包括已完成的），按 ID 倒序。
  Future<List<TransferProposalInfo>> fetchAllInstitutionProposals(
      InstitutionInfo institution) async {
    final visibleProposals =
        await fetchInstitutionVisibleProposals(institution);
    final proposals = <TransferProposalInfo>[];

    for (final proposal in visibleProposals) {
      final detailObject =
          proposal.businessDetails[MultisigTransferProposalDetailKeys.transfer];
      if (detailObject is! TransferProposalInfo) {
        continue;
      }
      if (detailObject.actorCidNumber == institution.cidNumber) {
        proposals.add(detailObject.copyWithStatus(proposal.meta.status));
      }
    }

    proposals.sort((a, b) => b.proposalId.compareTo(a.proposalId));
    return proposals;
  }

  /// 从原始 SCALE 字节解码 ProposalMeta（与 fetchProposalMeta 相同逻辑）。
  ProposalMeta? _decodeProposalMeta(int proposalId, Uint8List data) {
    return ProposalQueryService.decodeProposalMeta(proposalId, data);
  }

  /// 读取原始 ProposalData 存储字节。
  Future<Uint8List?> fetchProposalDataRaw(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'ProposalData',
      _u64ToLeBytes(proposalId),
    );
    return _fetchStorage('0x${_hexEncode(key)}');
  }

  /// 检测联合提案 ProposalData 的 MODULE_TAG 前缀。
  /// 返回 'rt-upg'、'res-iss'、'res-dst' 或 null。
  static String? _detectJointProposalTag(Uint8List raw) {
    if (raw.length < 2) return null;
    // BoundedVec<u8>：Compact<len> + bytes
    final first = raw[0];
    final mode = first & 0x03;
    int offset;
    if (mode == 0) {
      offset = 1;
    } else if (mode == 1) {
      offset = 2;
    } else if (mode == 2) {
      offset = 4;
    } else {
      return null;
    }
    if (offset + 7 > raw.length) return null;
    final tag = String.fromCharCodes(raw.sublist(offset, offset + 7));
    if (tag == 'res-iss') return 'res-iss';
    if (tag == 'res-dst') return 'res-dst';
    if (offset + 6 <= raw.length) {
      final tag6 = String.fromCharCodes(raw.sublist(offset, offset + 6));
      if (tag6 == 'rt-upg') return 'rt-upg';
    }
    return null;
  }

  /// 测试入口：暴露批量解码路径（_decodeProposalData），用链上真实
  /// payload 字节做布局回归，防止"守卫长度与链端布局漂移"导致提案静默消失。
  @visibleForTesting
  TransferProposalInfo? debugDecodeProposalData(int proposalId, Uint8List raw) {
    return _decodeProposalData(proposalId, raw);
  }

  /// 测试入口：锁定 VotingEngine::Proposal 当前完整 SCALE 布局。
  @visibleForTesting
  ProposalMeta? debugDecodeProposalMeta(int proposalId, Uint8List raw) {
    return _decodeProposalMeta(proposalId, raw);
  }

  /// 从原始 SCALE 字节解码 ProposalData（BoundedVec<u8> → TransferAction）。
  TransferProposalInfo? _decodeProposalData(int proposalId, Uint8List raw) {
    try {
      int offset = 0;
      final (vecLen, lenBytes) = _decodeCompact(raw, offset);
      offset += lenBytes;
      // storage value 必须恰好是一段完整 BoundedVec，拒绝截断或尾随脏字节。
      if (offset + vecLen != raw.length) return null;
      final data = raw.sublist(offset, offset + vecLen);
      // 跳过 MODULE_TAG 前缀。
      final tag = _moduleTag.codeUnits;
      // 个人多签最小长度 = tag + actor Option(1) + funding account(32)
      // + beneficiary(32) + amount(16) + empty remark Compact(1) + proposer(32)。
      // 机构转账还必须在 actor Option 后携带 CID 的 Compact 长度和正文。
      if (data.length < tag.length + 1 + 32 + 32 + 16 + 1 + 32) {
        return null;
      }
      for (var i = 0; i < tag.length; i++) {
        if (data[i] != tag[i]) return null;
      }
      return _decodeTransferAction(proposalId, data.sublist(tag.length));
    } catch (e) {
      // SCALE 解码失败必须留痕：runtime 升级布局变更时提案会"凭空消失"，
      // 没有日志就无从排查。
      AppLog.d('[MultisigTransfer] 提案 $proposalId ProposalData 解码失败: $e');
      return null;
    }
  }

  /// 查询某快照选民对提案的投票记录。null=未投票，true=赞成，false=反对。
  Future<bool?> fetchAdminVote(int proposalId, String publicKey) async {
    return _internalVoteQuery.fetchAdminVote(proposalId, publicKey);
  }

  /// 批量查询某提案下多名快照选民的投票记录。
  ///
  /// 转账/多签管理详情页展示全部合格选民投票时走批量读取，
  /// 避免逐个产生 storage RPC。
  Future<Map<String, bool?>> fetchAdminVotesBatch(
    int proposalId,
    Iterable<String> publicKeysHex,
  ) {
    return _internalVoteQuery.fetchAdminVotesBatch(proposalId, publicKeysHex);
  }

  Future<Map<String, bool?>> fetchTicketVotesBatch(
    int proposalId,
    Iterable<EligibleVoterTicket> tickets,
  ) {
    return _internalVoteQuery.fetchTicketVotesBatch(proposalId, tickets);
  }

  /// 查询 NextProposalId（投票引擎全局递增 ID）。
  Future<int> fetchNextProposalId() {
    return _proposalQuery.fetchNextProposalId();
  }

  /// 查询单个转账提案详情。返回 null 表示不存在。
  ///
  /// ProposalData 是 BoundedVec<u8>，SCALE 编码为 Compact 长度前缀 + 原始字节。
  /// 原始字节为 TransferAction SCALE 布局：
  ///   actor_cid_number:Option<CidNumber> + funding_account_id:AccountId32
  ///   + beneficiary: AccountId32(32) + amount: u128(16)
  ///   + remark: Vec<u8>(Compact len + bytes) + proposer: AccountId32(32)
  Future<TransferProposalInfo?> fetchProposalAction(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'ProposalData',
      _u64ToLeBytes(proposalId),
    );
    final raw = await _fetchStorage('0x${_hexEncode(key)}');
    if (raw == null || raw.isEmpty) return null;
    // 单笔与批量读取统一消费同一严格解码入口，禁止标签或布局双轨漂移。
    return _decodeProposalData(proposalId, raw);
  }

  /// 解码 TransferAction SCALE 数据。
  TransferProposalInfo? _decodeTransferAction(int proposalId, Uint8List data) {
    try {
      var offset = 0;
      if (data.isEmpty) return null;

      String? actorCidNumber;
      final actorOption = data[offset++];
      if (actorOption == 1) {
        final actorCid = _readCidNumber(data, offset);
        if (actorCid == null) return null;
        actorCidNumber = actorCid.$1;
        offset = actorCid.$2;
      } else if (actorOption != 0) {
        return null;
      }

      // funding_account_id: AccountId32
      if (offset + 32 > data.length) return null;
      final institutionAccountId = data.sublist(offset, offset + 32);
      offset += 32;

      // beneficiary: AccountId32 (32 bytes)
      if (offset + 32 > data.length) return null;
      final beneficiaryBytes = data.sublist(offset, offset + 32);
      offset += 32;

      // amount: u128 little-endian (16 bytes)
      if (offset + 16 > data.length) return null;
      final amountBytes = data.sublist(offset, offset + 16);
      var amountBig = BigInt.zero;
      for (var i = 15; i >= 0; i--) {
        amountBig = (amountBig << 8) | BigInt.from(amountBytes[i]);
      }
      offset += 16;

      // remark: Vec<u8> (Compact length + bytes)
      final (remarkLen, remarkLenSize) = _decodeCompact(data, offset);
      offset += remarkLenSize;
      // remark 后必须只剩固定 32 字节 proposer，拒绝截断和尾随字段。
      if (offset + remarkLen + 32 != data.length) return null;
      final remarkBytes = data.sublist(offset, offset + remarkLen);
      final remark = utf8.decode(remarkBytes, allowMalformed: true);
      offset += remarkLen;

      // proposer: AccountId32 (32 bytes)
      final proposerBytes = data.sublist(offset, offset + 32);

      final beneficiarySs58 = Keyring()
          .encodeAddress(Uint8List.fromList(beneficiaryBytes), kGmbSs58Prefix);
      final proposerSs58 = Keyring()
          .encodeAddress(Uint8List.fromList(proposerBytes), kGmbSs58Prefix);

      return TransferProposalInfo(
        proposalId: proposalId,
        actorCidNumber: actorCidNumber,
        institutionAccountId: Uint8List.fromList(institutionAccountId),
        beneficiary: beneficiarySs58,
        amountFen: amountBig,
        remark: remark,
        proposer: proposerSs58,
      );
    } catch (e) {
      // 字段级解码失败同样要留痕，与上层"提案不存在"区分开。
      AppLog.d('[MultisigTransfer] 提案 $proposalId TransferAction 解码失败: $e');
      return null;
    }
  }

  /// 解码 SCALE Compact<u32>，返回 (value, bytesConsumed)。
  (int, int) _decodeCompact(Uint8List data, int offset) {
    final first = data[offset];
    final mode = first & 0x03;
    if (mode == 0) {
      return (first >> 2, 1);
    } else if (mode == 1) {
      final val = (data[offset] | (data[offset + 1] << 8)) >> 2;
      return (val, 2);
    } else if (mode == 2) {
      final val = (data[offset] |
              (data[offset + 1] << 8) |
              (data[offset + 2] << 16) |
              (data[offset + 3] << 24)) >>
          2;
      return (val, 4);
    } else {
      // big integer mode — 简单处理，假设不超过 256
      final lenBytes = (first >> 2) + 4;
      var val = 0;
      for (var i = lenBytes - 1; i >= 0; i--) {
        val = (val << 8) | data[offset + 1 + i];
      }
      return (val, 1 + lenBytes);
    }
  }

  (String, int)? _readCidNumber(Uint8List data, int offset) {
    if (offset >= data.length) return null;
    final (length, compactSize) = _decodeCompact(data, offset);
    final start = offset + compactSize;
    final end = start + length;
    if (length <= 0 || length > 32 || end > data.length) return null;
    try {
      return (
        utf8.decode(data.sublist(start, end), allowMalformed: false),
        end
      );
    } catch (_) {
      return null;
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ──── 内部：extrinsic 编码 ────

  /// 构造 propose_transfer call data。
  ///
  /// 格式：[0x11][0x00][actor_cid_number:Option<CidNumber>]
  /// [proposer_role_code:Option<RoleCode>][funding_account_id:AccountId32]
  /// [beneficiary:AccountId32][amount:u128][remark:Vec<u8>]。
  Uint8List _buildProposeTransferCall({
    required String? actorCidNumber,
    required String? proposerRoleCode,
    required String fundingAccountId,
    required String beneficiaryAddress,
    required BigInt amountFen,
    required String remark,
  }) {
    final output = ByteOutput();
    output.pushByte(_palletIndex);
    output.pushByte(_proposeCallIndex);

    if (actorCidNumber == null) {
      if (proposerRoleCode != null) {
        throw StateError('个人多签不得携带机构岗位码');
      }
      output.pushByte(0);
      output.pushByte(0);
    } else {
      final roleCode = _requireProposerRoleCode(proposerRoleCode);
      output.pushByte(1);
      _writeCidNumber(output, actorCidNumber);
      output.pushByte(1);
      _writeRoleCode(output, roleCode);
    }
    output.write(Uint8List.fromList(accountIdBytes(fundingAccountId)));

    // beneficiary: AccountId32 = 32 bytes（不是 MultiAddress，无 0x00 前缀）
    final beneficiaryId = _ss58AddressToAccountId(beneficiaryAddress, '收款地址');
    output.write(beneficiaryId);

    // amount: u128 little-endian（16 字节，非 Compact）
    output.write(_u128ToLeBytes(amountFen));

    // remark: Vec<u8> = Compact<u32> length + bytes
    final remarkBytes = utf8.encode(remark);
    output.write(
        CompactBigIntCodec.codec.encode(BigInt.from(remarkBytes.length)));
    if (remarkBytes.isNotEmpty) {
      output.write(Uint8List.fromList(remarkBytes));
    }

    return output.toBytes();
  }

  /// 构造 propose_sweep_to_main call data。
  ///
  /// 格式：[0x11][0x02][actor_cid_number:CidNumber][proposer_role_code:RoleCode]
  /// [institution_account_id:AccountId32][amount:u128_le]。
  Uint8List _buildProposeSweepCall({
    required String actorCidNumber,
    required String proposerRoleCode,
    required String institutionAccountId,
    required double amountYuan,
  }) {
    final output = ByteOutput();
    output.pushByte(_palletIndex);
    output.pushByte(_proposeSweepCallIndex);
    _writeCidNumber(output, actorCidNumber);
    _writeRoleCode(output, proposerRoleCode);
    output.write(Uint8List.fromList(accountIdBytes(institutionAccountId)));
    final amountFen = BigInt.from((amountYuan * 100).round());
    final amountBytes = Uint8List(16);
    var rem = amountFen;
    for (var i = 0; i < 16; i++) {
      amountBytes[i] = (rem & BigInt.from(0xFF)).toInt();
      rem = rem >> 8;
    }
    output.write(amountBytes);
    return output.toBytes();
  }

  /// 构造 propose_safety_fund_transfer call data。
  ///
  /// 格式：[0x11][0x01][actor_cid_number:CidNumber][proposer_role_code:RoleCode]
  /// [institution_account_id:AccountId32][beneficiary:32][amount:u128][remark:Vec<u8>]。
  Uint8List _buildProposeSafetyFundCall({
    required String actorCidNumber,
    required String proposerRoleCode,
    required String institutionAccountId,
    required String beneficiaryAddress,
    required double amountYuan,
    required String remark,
  }) {
    final output = ByteOutput();
    output.pushByte(_palletIndex);
    output.pushByte(_proposeSafetyFundCallIndex);

    _writeCidNumber(output, actorCidNumber);
    _writeRoleCode(output, proposerRoleCode);
    output.write(Uint8List.fromList(accountIdBytes(institutionAccountId)));

    // beneficiary: 32 bytes
    final beneficiaryId = _ss58AddressToAccountId(beneficiaryAddress, '收款地址');
    output.write(beneficiaryId);

    // amount: u128 LE
    final amountFen = BigInt.from((amountYuan * 100).round());
    final amountBytes = Uint8List(16);
    var rem = amountFen;
    for (var i = 0; i < 16; i++) {
      amountBytes[i] = (rem & BigInt.from(0xFF)).toInt();
      rem = rem >> 8;
    }
    output.write(amountBytes);

    // remark: Vec<u8>
    final remarkBytes = utf8.encode(remark);
    output.write(
        CompactBigIntCodec.codec.encode(BigInt.from(remarkBytes.length)));
    if (remarkBytes.isNotEmpty) {
      output.write(Uint8List.fromList(remarkBytes));
    }

    return output.toBytes();
  }

  /// 从链上 SafetyFundProposalActions 存储查询安全基金转账提案详情。
  Future<SafetyFundProposalInfo?> fetchSafetyFundAction(int proposalId) async {
    final key = _buildStorageKey(
      'MultisigTransfer',
      'SafetyFundProposalActions',
      _u64ToLeBytes(proposalId),
    );
    final raw = await _fetchStorage('0x${_hexEncode(key)}');
    // SafetyFundAction: actor CID + institution_account_id + beneficiary + amount + remark + proposer。
    if (raw == null || raw.length < 1 + 32 + 32 + 16 + 1 + 32) {
      return null;
    }
    try {
      var offset = 0;
      final actorCid = _readCidNumber(raw, offset);
      if (actorCid == null) return null;
      offset = actorCid.$2;
      final institutionAccountId =
          Uint8List.fromList(raw.sublist(offset, offset + 32));
      offset += 32;
      final beneficiaryBytes = raw.sublist(offset, offset + 32);
      offset += 32;
      var amountBig = BigInt.zero;
      for (var i = 15; i >= 0; i--) {
        amountBig = (amountBig << 8) | BigInt.from(raw[offset + i]);
      }
      offset += 16;
      final (remarkLen, remarkLenSize) = _decodeCompact(raw, offset);
      offset += remarkLenSize;
      if (offset + remarkLen + 32 != raw.length) return null;
      final remark = utf8.decode(
        raw.sublist(offset, offset + remarkLen),
        allowMalformed: true,
      );
      offset += remarkLen;
      final proposerBytes = raw.sublist(offset, offset + 32);
      return SafetyFundProposalInfo(
        proposalId: proposalId,
        actorCidNumber: actorCid.$1,
        institutionAccountId: institutionAccountId,
        beneficiary: Keyring().encodeAddress(
            Uint8List.fromList(beneficiaryBytes), kGmbSs58Prefix),
        amountFen: amountBig,
        remark: remark,
        proposer: Keyring()
            .encodeAddress(Uint8List.fromList(proposerBytes), kGmbSs58Prefix),
      );
    } catch (e) {
      // SCALE 解码失败必须留痕，与"确实不是安全基金提案"区分开。
      AppLog.d('[MultisigTransfer] 提案 $proposalId SafetyFundAction 解码失败: $e');
      return null;
    }
  }

  /// 从链上 SweepProposalActions 存储查询手续费划转提案详情。
  Future<SweepProposalInfo?> fetchSweepAction(int proposalId) async {
    final key = _buildStorageKey(
      'MultisigTransfer',
      'SweepProposalActions',
      _u64ToLeBytes(proposalId),
    );
    final raw = await _fetchStorage('0x${_hexEncode(key)}');
    // SweepAction: actor CID + institution_account_id + amount + proposer。
    if (raw == null || raw.length < 1 + 32 + 16 + 32) return null;
    try {
      final actorCid = _readCidNumber(raw, 0);
      if (actorCid == null) return null;
      final institutionOffset = actorCid.$2;
      if (institutionOffset + 32 + 16 + 32 != raw.length) return null;
      final institutionAccountId = Uint8List.fromList(
        raw.sublist(institutionOffset, institutionOffset + 32),
      );
      var amountBig = BigInt.zero;
      for (var i = 15; i >= 0; i--) {
        amountBig =
            (amountBig << 8) | BigInt.from(raw[institutionOffset + 32 + i]);
      }
      final proposerOffset = institutionOffset + 32 + 16;
      final proposerBytes =
          Uint8List.fromList(raw.sublist(proposerOffset, proposerOffset + 32));
      return SweepProposalInfo(
        proposalId: proposalId,
        actorCidNumber: actorCid.$1,
        institutionAccountId: institutionAccountId,
        amountFen: amountBig,
        proposer: Keyring().encodeAddress(proposerBytes, kGmbSs58Prefix),
      );
    } catch (e) {
      // SCALE 解码失败必须留痕，与"确实不是手续费划转提案"区分开。
      AppLog.d('[MultisigTransfer] 提案 $proposalId SweepAction 解码失败: $e');
      return null;
    }
  }

  Future<Uint8List?> _fetchStorage(String keyHex) async {
    final finalized = await _chain.getFinalizedHead();
    return _chain.getStorage(finalized, _hexDecode(keyHex));
  }

  Future<Map<String, Uint8List?>> _fetchStorageBatch(
    List<String> keyHexes,
  ) async {
    if (keyHexes.isEmpty) return const <String, Uint8List?>{};
    final finalized = await _chain.getFinalizedHead();
    final values = await _chain.getStorageBatch(
      finalized,
      keyHexes.map(_hexDecode).toList(growable: false),
    );
    return <String, Uint8List?>{
      for (var index = 0; index < keyHexes.length; index++)
        keyHexes[index]: values[index],
    };
  }

  Future<({String txHash, int usedNonce, CitizenBlockRef block})>
      _executeFinalized({
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
        throw StateError('多签提案交易签名已取消');
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
      throw StateError(completed.poolRejectionReason ?? '多签提案交易执行失败');
    }
    return (
      txHash: '0x${_hexEncode(completed.transactionHash)}',
      usedNonce: prepared.nonce.toInt(),
      block: completed.execution!.block,
    );
  }

  Future<int> _confirmTransferProposedEvent({
    required CitizenBlockRef finalizedBlock,
    required String institutionCode,
    required String? actorCidNumber,
    required Uint8List proposerPublicKey,
    required Uint8List fromPublicKey,
    required Uint8List beneficiaryPublicKey,
    required BigInt amountFen,
  }) {
    return _confirmProposalEvent(
      finalizedBlock: finalizedBlock,
      eventLabel: 'TransferProposed',
      eventIndex: _transferProposedEventIndex,
      decode: (data, offset) => _decodeTransferProposedEvent(
        data,
        offset,
        institutionCode: institutionCode,
        actorCidNumber: actorCidNumber,
        proposerPublicKey: proposerPublicKey,
        fromPublicKey: fromPublicKey,
        beneficiaryPublicKey: beneficiaryPublicKey,
        amountFen: amountFen,
      ),
    );
  }

  /// 入块后读取 System.Events 核对提案事件并提取 proposal_id。
  ///
  /// 三类提案（转账/安全基金/手续费划转）共用本入口，
  /// 事件不存在=业务失败，必须抛错而不是静默放过。
  Future<int> _confirmProposalEvent({
    required CitizenBlockRef finalizedBlock,
    required String eventLabel,
    required int eventIndex,
    required ({int proposalId, bool matches})? Function(
      Uint8List data,
      int offset,
    ) decode,
  }) async {
    final events = await _chain.getSystemEvents(finalizedBlock);
    if (events == null || events.isEmpty) {
      throw StateError('交易已入块，但未读取到 System.Events，不能确认提案创建成功');
    }
    final proposalId = _findProposalIdInEvents(
      events,
      eventIndex: eventIndex,
      decode: decode,
    );
    if (proposalId == null) {
      throw StateError(
        '交易已入块，但未找到 MultisigTransfer.$eventLabel 事件，提案创建失败',
      );
    }
    return proposalId;
  }

  /// 在 System.Events 原始字节中扫描本 pallet 指定事件并提取 proposal_id。
  ///
  /// 三类提案共用扫描骨架，事件字段解码与匹配由 decode 回调完成。
  int? _findProposalIdInEvents(
    Uint8List data, {
    required int eventIndex,
    required ({int proposalId, bool matches})? Function(
      Uint8List data,
      int offset,
    ) decode,
  }) {
    final (_, countSize) = _decodeCompact(data, 0);
    if (countSize <= 0) return null;
    for (var scanOffset = countSize; scanOffset < data.length; scanOffset++) {
      var offset = scanOffset;
      final phase = data[offset];
      offset += 1;
      if (phase == 0x00) {
        if (offset + 4 > data.length) continue;
        offset += 4;
      } else if (phase != 0x01 && phase != 0x02) {
        continue;
      }

      if (offset + 2 > data.length) continue;
      final palletIndex = data[offset];
      final evtIndex = data[offset + 1];
      offset += 2;

      if (palletIndex == _palletIndex && evtIndex == eventIndex) {
        final decoded = decode(data, offset);
        if (decoded == null) continue;
        if (decoded.matches) return decoded.proposalId;
      }
    }
    return null;
  }

  ({
    int proposalId,
    bool matches,
  })? _decodeTransferProposedEvent(
    Uint8List data,
    int offset, {
    required String institutionCode,
    required String? actorCidNumber,
    required Uint8List proposerPublicKey,
    required Uint8List fromPublicKey,
    required Uint8List beneficiaryPublicKey,
    required BigInt amountFen,
  }) {
    // TransferProposed 事件字段顺序必须与 runtime Event enum 完全一致。
    // 字段：proposal_id + institution_code + actor_cid_number:Option<CidNumber>
    //      + proposer + funding_account_id + beneficiary + amount
    //      + remark(Vec) + expires_at(u32) + topics
    const fixedBytes = 8 + 4 + 1 + 32 + 32 + 32 + 16;
    if (offset + fixedBytes > data.length) return null;
    var pos = offset;
    final proposalId = _readU64LE(data, pos);
    pos += 8;
    // institution_code: [u8;4]
    final eventCodeBytes = data.sublist(pos, pos + 4);
    final eventCode = InstitutionCodeLabel.codeToString(eventCodeBytes);
    pos += 4;
    final actorOption = data[pos++];
    String? eventActorCidNumber;
    if (actorOption == 1) {
      final decoded = _readCidNumber(data, pos);
      if (decoded == null) return null;
      eventActorCidNumber = decoded.$1;
      pos = decoded.$2;
    } else if (actorOption != 0) {
      return null;
    }
    final eventProposer = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventFrom = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventBeneficiary = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventAmount = _readU128LE(data, pos);
    pos += 16;

    final (remarkLen, remarkLenSize) = _decodeCompact(data, pos);
    if (remarkLenSize <= 0 || pos + remarkLenSize + remarkLen > data.length) {
      return null;
    }
    pos += remarkLenSize + remarkLen;

    // runtime BlockNumber = u32，expires_at 紧跟 remark 之后。
    if (pos + 4 > data.length) return null;
    pos += 4;

    if (_skipTopics(data, pos) == null) return null;
    final matches = eventCode == institutionCode &&
        eventActorCidNumber == actorCidNumber &&
        _bytesEqual(eventProposer, proposerPublicKey) &&
        _bytesEqual(eventFrom, fromPublicKey) &&
        _bytesEqual(eventBeneficiary, beneficiaryPublicKey) &&
        eventAmount == amountFen;
    return (
      proposalId: proposalId,
      matches: matches,
    );
  }

  ({
    int proposalId,
    bool matches,
  })? _decodeSafetyFundProposedEvent(
    Uint8List data,
    int offset, {
    required String actorCidNumber,
    required Uint8List institutionAccountId,
    required Uint8List proposerPublicKey,
    required Uint8List beneficiaryPublicKey,
    required BigInt amountFen,
  }) {
    // SafetyFundTransferProposed 字段顺序必须与 runtime Event enum
    // 完全一致：proposal_id u64 | actor_cid_number | proposer 32B |
    // institution_account_id 32B | beneficiary 32B
    // | amount u128 | remark Compact+bytes | expires_at u32 | topics。
    const fixedBytes = 8 + 1 + 32 + 32 + 32 + 16;
    if (offset + fixedBytes > data.length) return null;
    var pos = offset;
    final proposalId = _readU64LE(data, pos);
    pos += 8;
    final actorCid = _readCidNumber(data, pos);
    if (actorCid == null) return null;
    pos = actorCid.$2;
    if (pos + 32 + 32 + 32 + 16 > data.length) return null;
    final eventProposer = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventInstitutionAccount =
        Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventBeneficiary = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventAmount = _readU128LE(data, pos);
    pos += 16;

    final (remarkLen, remarkLenSize) = _decodeCompact(data, pos);
    if (remarkLenSize <= 0 || pos + remarkLenSize + remarkLen > data.length) {
      return null;
    }
    pos += remarkLenSize + remarkLen;

    // runtime BlockNumber = u32，expires_at 紧跟 remark 之后。
    if (pos + 4 > data.length) return null;
    pos += 4;

    if (_skipTopics(data, pos) == null) return null;
    final matches = actorCid.$1 == actorCidNumber &&
        _bytesEqual(eventInstitutionAccount, institutionAccountId) &&
        _bytesEqual(eventProposer, proposerPublicKey) &&
        _bytesEqual(eventBeneficiary, beneficiaryPublicKey) &&
        eventAmount == amountFen;
    return (
      proposalId: proposalId,
      matches: matches,
    );
  }

  ({
    int proposalId,
    bool matches,
  })? _decodeSweepProposedEvent(
    Uint8List data,
    int offset, {
    required Uint8List institutionAccountId,
    required String actorCidNumber,
    required Uint8List proposerPublicKey,
    required Uint8List toPublicKey,
    required BigInt amountFen,
  }) {
    // SweepToMainProposed 字段顺序必须与 runtime Event enum 完全
    // 一致：proposal_id | actor_cid_number | proposer | institution_account_id
    // | main_account_id | amount | expires_at | topics（无 remark 字段）。
    const fixedBytes = 8 + 1 + 32 + 32 + 32 + 16 + 4;
    if (offset + fixedBytes > data.length) return null;
    var pos = offset;
    final proposalId = _readU64LE(data, pos);
    pos += 8;
    final actorCid = _readCidNumber(data, pos);
    if (actorCid == null) return null;
    pos = actorCid.$2;
    final eventProposer = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventInstitutionAccount =
        Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventTo = Uint8List.fromList(data.sublist(pos, pos + 32));
    pos += 32;
    final eventAmount = _readU128LE(data, pos);
    pos += 16;
    // expires_at: u32。
    pos += 4;

    if (_skipTopics(data, pos) == null) return null;
    final matches = _bytesEqual(eventProposer, proposerPublicKey) &&
        actorCid.$1 == actorCidNumber &&
        _bytesEqual(institutionAccountId, eventInstitutionAccount) &&
        _bytesEqual(eventTo, toPublicKey) &&
        eventAmount == amountFen;
    return (
      proposalId: proposalId,
      matches: matches,
    );
  }


  // ──── 内部：storage key 构造 ────

  /// 构造 storage key：twox128(pallet) + twox128(storage) + blake2_128_concat(keyData)。
  Uint8List _buildStorageKey(
    String palletName,
    String storageName,
    Uint8List keyData,
  ) {
    final palletHash = _twoxx128String(palletName);
    final storageHash = _twoxx128String(storageName);
    final keyHash = _blake2128Concat(keyData);

    final result =
        Uint8List(palletHash.length + storageHash.length + keyHash.length);
    var offset = 0;
    result.setAll(offset, palletHash);
    offset += palletHash.length;
    result.setAll(offset, storageHash);
    offset += storageHash.length;
    result.setAll(offset, keyHash);
    return result;
  }

  // ──── 内部：编码工具 ────

  void _writeCidNumber(ByteOutput output, String cidNumber) {
    final bytes = utf8.encode(cidNumber);
    if (bytes.isEmpty || bytes.length > 32) {
      throw ArgumentError('actor_cid_number 必须为 1..32 字节');
    }
    output.write(CompactBigIntCodec.codec.encode(BigInt.from(bytes.length)));
    output.write(Uint8List.fromList(bytes));
  }

  String _requireProposerRoleCode(String? proposerRoleCode) {
    final value = proposerRoleCode?.trim() ?? '';
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > 64) {
      throw ArgumentError('proposer_role_code 必须为 1..64 字节');
    }
    return value;
  }

  void _writeRoleCode(ByteOutput output, String proposerRoleCode) {
    final value = _requireProposerRoleCode(proposerRoleCode);
    final bytes = utf8.encode(value);
    output.write(CompactBigIntCodec.codec.encode(BigInt.from(bytes.length)));
    output.write(Uint8List.fromList(bytes));
  }

  /// 将 BigInt 编码为 u128 little-endian（16 字节）。
  Uint8List _u128ToLeBytes(BigInt value) {
    final bytes = Uint8List(16);
    var v = value;
    for (var i = 0; i < 16; i++) {
      bytes[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return bytes;
  }

  Uint8List _u64ToLeBytes(int value) {
    final bytes = Uint8List(8);
    final bd = ByteData.sublistView(bytes);
    bd.setUint64(0, value, Endian.little);
    return bytes;
  }

  int _decodeU64(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return bd.getUint64(0, Endian.little);
  }

  int _readU64LE(Uint8List data, int offset) {
    final bd = ByteData.sublistView(data, offset, offset + 8);
    return bd.getUint64(0, Endian.little);
  }

  BigInt _readU128LE(Uint8List data, int offset) {
    var value = BigInt.zero;
    for (var i = 15; i >= 0; i--) {
      value = (value << 8) | BigInt.from(data[offset + i]);
    }
    return value;
  }

  int? _skipTopics(Uint8List data, int offset) {
    if (offset >= data.length) return null;
    final (count, size) = _decodeCompact(data, offset);
    if (size <= 0) return null;
    final next = offset + size + count * 32;
    return next <= data.length ? next : null;
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexDecode(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  Uint8List _accountIdToAccountId(String hex, String fieldName) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
      throw FormatException('$fieldName必须是32字节账户hex');
    }
    return _hexDecode(clean);
  }

  Uint8List _ss58AddressToAccountId(String address, String fieldName) {
    try {
      return Uint8List.fromList(Keyring().decodeAddress(address));
    } catch (_) {
      throw FormatException('$fieldName必须是SS58地址');
    }
  }

  // ──── 内部：哈希（直接使用 polkadart Hasher）────

  Uint8List _twoxx128String(String input) {
    return Hasher.twoxx128.hashString(input);
  }

  Uint8List _blake2128Concat(Uint8List data) {
    final hash = Hasher.blake2b128.hash(data);
    final result = Uint8List(hash.length + data.length);
    result.setAll(0, hash);
    result.setAll(hash.length, data);
    return result;
  }
}
