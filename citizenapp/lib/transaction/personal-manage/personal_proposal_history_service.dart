// 个人多签提案历史聚合服务(req 5)。
//
// 双轨制数据源:
// 1. 链上 `votingengine.ActiveProposalsBySubject[PersonalAccount(personal_account_id)]`
//    返回当前活跃(STATUS_VOTING)的提案 ID 列表。
// 2. 本机 Isar `PersonalAccountProposalEntity` 永久保留所有历史快照,覆盖
//    链上 90 天后已清理的终态提案。
//
// `fetchAll` 把两条数据合并去重(以 proposalId 为 key),并把链上活跃提案的
// 最新状态 upsert 到 Isar(同步缓存,防止其他设备发起的提案漏记)。

import 'dart:convert';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:polkadart/polkadart.dart' show Hasher;

import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';

/// 提案动作类型常量(对齐 Isar entity action 字段)。
class PersonalProposalAction {
  static const String create = 'create';
  static const String transfer = 'transfer';
  static const String close = 'close';
}

/// 提案状态字符串(对齐 votingengine 链上枚举,但用人类可读字符串持久化)。
class PersonalProposalStatus {
  static const String voting = 'voting';
  static const String passed = 'passed';
  static const String rejected = 'rejected';
  static const String executed = 'executed';
  static const String executionFailed = 'execution_failed';
}

/// 链上 votingengine status u8 → Isar 字符串。
String mapChainStatus(int? chainStatus) {
  switch (chainStatus) {
    case 0:
      return PersonalProposalStatus.voting;
    case 1:
      return PersonalProposalStatus.passed;
    case 2:
      return PersonalProposalStatus.rejected;
    case 3:
      return PersonalProposalStatus.executed;
    case 4:
      return PersonalProposalStatus.executionFailed;
    default:
      return PersonalProposalStatus.voting;
  }
}

/// 详情页提案列表渲染所需的视图模型。
class PersonalAccountProposalView {
  const PersonalAccountProposalView({
    required this.proposalId,
    required this.action,
    required this.status,
    required this.yesVotes,
    required this.noVotes,
    required this.createdAtMillis,
    this.finalStatusAtMillis,
    this.snapshot,
  });

  final int proposalId;
  final String action;
  final String status;
  final int yesVotes;
  final int noVotes;
  final int createdAtMillis;
  final int? finalStatusAtMillis;
  final Map<String, dynamic>? snapshot;

  bool get isActive => status == PersonalProposalStatus.voting;
  bool get isFinal => !isActive;
}

class PersonalProposalHistoryService {
  PersonalProposalHistoryService({
    required CitizenChain chain,
    ProposalQueryService? proposalService,
  }) : _chain = chain,
       _proposalService = proposalService ?? ProposalQueryService(chain: chain);

  final CitizenChain _chain;
  final ProposalQueryService _proposalService;

  /// 拉取该多签的全部提案(活跃 + 历史),按 createdAt desc 排序。
  ///
  /// 容错:链上失败仅回退 Isar;Isar 失败仅回退链上;两者都失败返回空列表。
  ///
  /// 状态新鲜度策略:
  /// 1. 链上 ActiveProposalsBySubject 同步活跃提案到 Isar(防其他设备漏记)
  /// 2. **额外**:遍历 Isar 中本机已知 status='voting' 的 entity,挨个查链上
  ///    Proposals[id] 拿最新 status + tally。这步必须独立于 active 列表,
  ///    因为提案一旦终态(passed/executed/rejected)就从 active 列表移除,
  ///    本机 Isar 永远停在 voting 状态,UI 卡片显示"投票中"是假数据。
  Future<List<PersonalAccountProposalView>> fetchAll(
    String personalAccountId,
  ) async {
    final activeIds = await _safeFetchActiveProposalIds(personalAccountId);

    // 链可达性正向探针:只有确认链已同步可达时,才允许把「链上查不到」判为幽灵
    // 并清理本机记录;离线/未同步一律保留本机 Isar 历史(容错回退→仅返回 Isar)。
    final chainReachable = (await _chain.getSyncStatus()).isUsable;

    // Step 1: 链上活跃提案逐个同步到 Isar(防止其他设备发起的提案在本机无记录)。
    for (final pid in activeIds) {
      await _syncActiveProposalToIsar(personalAccountId, pid);
    }

    // Step 2: 重查本机 Isar 中 status='voting' 的 entity,即使它们已不在 active 列表
    // (提案终态后就从 active 列表移除,但本机 entity 还停在 voting)。
    await _refreshLocalVotingEntities(personalAccountId, chainReachable);

    return _readAllFromIsar(personalAccountId);
  }

  /// 判断本机是否存在“创建提案仍是 voting，但链上 Proposals[id] 从未存在”的快照。
  ///
  /// 这类记录通常来自旧版本把 txHash 当成功后提前落库；它不是
  /// 正常注销历史，列表页可据此删除本地幽灵多签。
  Future<bool> hasUnchainedVotingCreateProposal(
    String personalAccountId,
  ) async {
    try {
      // 离线/未同步无法确认提案是否真在链上,一律不判幽灵,避免误删本机记录。
      if (!(await _chain.getSyncStatus()).isUsable) return false;
      final entities = await WalletIsar.instance.read((isar) {
        return isar.personalAccountProposalEntitys
            .filter()
            .personalAccountIdEqualTo(personalAccountId)
            .actionEqualTo(PersonalProposalAction.create)
            .statusEqualTo(PersonalProposalStatus.voting)
            .findAll();
      });
      for (final e in entities) {
        final chainStatus = await _proposalService.fetchProposalStatus(
          e.proposalId,
        );
        if (chainStatus == null) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// 遍历本机 Isar 中所有 status='voting' 的 entity,查链上 `Proposals[id]` 拿最新状态。
  /// 链上若已终态(passed/executed/rejected/execution_failed),upsert 为终态;
  /// 链上仍 voting 则只刷新 yesVotes/noVotes;链上 storage 不存在(已被 90 天清理)
  /// 也只刷新 vote tally(取现有值)— 不强制覆盖为终态,等本机其他渠道写入历史。
  Future<void> _refreshLocalVotingEntities(
    String personalAccountId,
    bool chainReachable,
  ) async {
    try {
      final votingEntities = await WalletIsar.instance.read((isar) {
        return isar.personalAccountProposalEntitys
            .filter()
            .personalAccountIdEqualTo(personalAccountId)
            .statusEqualTo(PersonalProposalStatus.voting)
            .findAll();
      });

      for (final e in votingEntities) {
        try {
          final chainStatus = await _proposalService.fetchProposalStatus(
            e.proposalId,
          );
          if (chainStatus == null) {
            // 仅当链确认可达却查不到该提案时,才判为「本机幽灵创建提案」并清理;
            // 离线/未同步则保留本机记录,避免误删待投票提案(数据丢失)。
            if (chainReachable && e.action == PersonalProposalAction.create) {
              await _deleteProposalEntity(
                personalAccountId: personalAccountId,
                proposalId: e.proposalId,
              );
            }
            continue;
          }
          final tally = await _proposalService.fetchVoteTally(e.proposalId);
          await recordOrUpdate(
            personalAccountId: personalAccountId,
            proposalId: e.proposalId,
            action: e.action,
            status: mapChainStatus(chainStatus),
            yesVotes: tally.yes,
            noVotes: tally.no,
          );
        } catch (_) {
          // 单条刷新失败不阻断其他 entity
        }
      }
    } catch (_) {
      // 整个刷新失败也不阻断主流程
    }
  }

  Future<void> _deleteProposalEntity({
    required String personalAccountId,
    required int proposalId,
  }) async {
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(personalAccountId)
          .proposalIdEqualTo(proposalId)
          .deleteAll();
    });
  }

  /// 写入或更新 Isar 提案 entity。
  ///
  /// [snapshot] 若非空将以 JSON 形式持久化(转账金额 / beneficiary / account_name 等)。
  Future<void> recordOrUpdate({
    required String personalAccountId,
    required int proposalId,
    required String action,
    required String status,
    required int yesVotes,
    required int noVotes,
    Map<String, dynamic>? snapshot,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await WalletIsar.instance.writeTxn((isar) async {
      final existing = await isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(personalAccountId)
          .proposalIdEqualTo(proposalId)
          .findFirst();

      final isFinal = status != PersonalProposalStatus.voting;

      final entity = existing ?? PersonalAccountProposalEntity()
        ..personalAccountId = personalAccountId
        ..proposalId = proposalId
        ..createdAtMillis = existing?.createdAtMillis ?? now;

      entity.action = action;
      entity.status = status;
      entity.yesVotes = yesVotes;
      entity.noVotes = noVotes;
      entity.finalStatusAtMillis = isFinal
          ? (existing?.finalStatusAtMillis ?? now)
          : null;
      if (snapshot != null) {
        entity.snapshotJson = jsonEncode(snapshot);
      } else if (existing != null) {
        entity.snapshotJson = existing.snapshotJson;
      }

      await isar.personalAccountProposalEntitys.put(entity);
    });
  }

  // ──── 内部 ─────────────────────────────────────────────

  Future<List<int>> _safeFetchActiveProposalIds(
    String personalAccountId,
  ) async {
    try {
      return await _proposalService.fetchActivePersonalProposalIds(
        personalAccountId,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _syncActiveProposalToIsar(
    String personalAccountId,
    int proposalId,
  ) async {
    try {
      final chainStatus = await _proposalService.fetchProposalStatus(
        proposalId,
      );
      final tally = await _proposalService.fetchVoteTally(proposalId);
      final statusStr = mapChainStatus(chainStatus);

      final existing = await WalletIsar.instance.read((isar) {
        return isar.personalAccountProposalEntitys
            .filter()
            .personalAccountIdEqualTo(personalAccountId)
            .proposalIdEqualTo(proposalId)
            .findFirst();
      });

      // 本机已有记录沿用其真实动作；首次发现则必须从当前链上
      // ProposalData 严格识别，禁止把缺失/未知载荷伪装成 create。
      String? action = existing?.action;
      if (existing == null) {
        final raw = await _fetchProposalDataRaw(proposalId);
        if (raw == null) return;
        action = _decodeActionFromProposalData(raw);
        if (action == null) return;
      }

      await recordOrUpdate(
        personalAccountId: personalAccountId,
        proposalId: proposalId,
        action: action!,
        status: statusStr,
        yesVotes: tally.yes,
        noVotes: tally.no,
      );
    } catch (_) {
      // 单条同步失败不阻断其他提案同步。
    }
  }

  /// 从链上 `VotingEngine.ProposalData[id]` 原始字节解码 `PersonalProposalAction`。
  ///
  /// ProposalData 是 BoundedVec<u8>:Compact<len> + bytes。
  ///
  /// 个人多签提案能命中的映射:
  /// - per-mgmt + 0 → create (PersonalAdmins::propose_create)
  /// - per-mgmt + 1 → close  (PersonalAdmins::propose_close)
  /// - multisig → transfer (MultisigTransfer::propose_transfer)
  /// 个人多签不会触发 safety_fund/sweep,无需识别。
  String? _decodeActionFromProposalData(Uint8List raw) {
    try {
      final (length, lenSize) = _decodeCompact(raw, 0);
      if (lenSize + length != raw.length) return null;
      final data = Uint8List.sublistView(raw, lenSize);

      // per-mgmt = b"per-mgmt" 8 字节，后接 action byte。
      const perMgmt = [0x70, 0x65, 0x72, 0x2d, 0x6d, 0x67, 0x6d, 0x74];
      if (_startsWithAt(data, perMgmt, 0)) {
        if (perMgmt.length >= data.length) return null;
        final action = data[perMgmt.length];
        if (action == 0) return PersonalProposalAction.create;
        if (action == 1) return PersonalProposalAction.close;
        return null;
      }

      // 当前 multisig ProposalData 不含 action byte；tag 本身唯一表示转账。
      final multisig = 'multisig'.codeUnits;
      if (_startsWithAt(data, multisig, 0) &&
          data.length >= multisig.length + 1 + 32 + 32 + 16 + 1 + 32 &&
          (data[multisig.length] == 0 || data[multisig.length] == 1)) {
        return PersonalProposalAction.transfer;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 测试入口：锁定当前投票引擎 ProposalData 模块标签。
  @visibleForTesting
  String? debugDecodeActionFromProposalData(Uint8List raw) {
    return _decodeActionFromProposalData(raw);
  }

  bool _startsWithAt(Uint8List data, List<int> prefix, int offset) {
    if (offset + prefix.length > data.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  /// 读取 `VotingEngine.ProposalData[id]` 原始字节(BoundedVec<u8> SCALE 编码)。
  Future<Uint8List?> _fetchProposalDataRaw(int proposalId) async {
    try {
      final key = _buildStorageKey(
        'VotingEngine',
        'ProposalData',
        _u64ToLeBytes(proposalId),
      );
      final finalized = await _chain.getFinalizedHead();
      return await _chain.getStorage(finalized, key);
    } catch (_) {
      return null;
    }
  }

  Uint8List _u64ToLeBytes(int value) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint64(0, value, Endian.little);
    return bytes;
  }

  Future<List<PersonalAccountProposalView>> _readAllFromIsar(
    String personalAccountId,
  ) async {
    try {
      final entities = await WalletIsar.instance.read((isar) {
        return isar.personalAccountProposalEntitys
            .filter()
            .personalAccountIdEqualTo(personalAccountId)
            .sortByCreatedAtMillisDesc()
            .findAll();
      });
      return entities.map(_entityToView).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  PersonalAccountProposalView _entityToView(PersonalAccountProposalEntity e) {
    Map<String, dynamic>? snapshot;
    if (e.snapshotJson != null && e.snapshotJson!.isNotEmpty) {
      try {
        snapshot = jsonDecode(e.snapshotJson!) as Map<String, dynamic>;
      } catch (_) {
        snapshot = null;
      }
    }
    return PersonalAccountProposalView(
      proposalId: e.proposalId,
      action: e.action,
      status: e.status,
      yesVotes: e.yesVotes,
      noVotes: e.noVotes,
      createdAtMillis: e.createdAtMillis,
      finalStatusAtMillis: e.finalStatusAtMillis,
      snapshot: snapshot,
    );
  }

  // ──── 编码 / 哈希工具(对齐 votingengine storage key) ────

  Uint8List _buildStorageKey(String pallet, String storage, Uint8List keyData) {
    final palletHash = Hasher.twoxx128.hashString(pallet);
    final storageHash = Hasher.twoxx128.hashString(storage);
    final keyHash = Hasher.blake2b128.hash(keyData);
    final result = Uint8List(
      palletHash.length + storageHash.length + keyHash.length + keyData.length,
    );
    var offset = 0;
    result.setAll(offset, palletHash);
    offset += palletHash.length;
    result.setAll(offset, storageHash);
    offset += storageHash.length;
    result.setAll(offset, keyHash);
    offset += keyHash.length;
    result.setAll(offset, keyData);
    return result;
  }

  (int, int) _decodeCompact(Uint8List data, int offset) {
    if (offset < 0 || offset >= data.length) {
      throw const FormatException('Compact<u32> offset 越界');
    }
    final first = data[offset];
    final mode = first & 0x03;
    if (mode == 0) return (first >> 2, 1);
    if (mode == 1) {
      if (offset + 1 >= data.length) {
        throw const FormatException('Compact<u32> mode1 长度不足');
      }
      return ((first | data[offset + 1] << 8) >> 2, 2);
    }
    if (mode == 2) {
      if (offset + 3 >= data.length) {
        throw const FormatException('Compact<u32> mode2 长度不足');
      }
      return (
        (first |
                data[offset + 1] << 8 |
                data[offset + 2] << 16 |
                data[offset + 3] << 24) >>
            2,
        4,
      );
    }
    throw const FormatException('Compact<u32> big-integer 模式不支持');
  }
}
