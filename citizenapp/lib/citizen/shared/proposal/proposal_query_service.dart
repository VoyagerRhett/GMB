import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/shared/institution_code_label.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/institution/institution_role_models.dart';
import 'package:citizenapp/citizen/institution/institution_role_storage_codec.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_query_service.dart';

/// VotingEngine / InternalVote 通用查询服务。
///
/// 提案状态、投票计数、快照和 NextProposalId 都是投票引擎
/// 通用状态，不能借用具体业务 service 暴露给其他模块。
class ProposalQueryService {
  ProposalQueryService({required CitizenChain chain})
    : _chain = chain,
      _internalVoteQuery = InternalVoteQueryService(chain: chain);

  final CitizenChain _chain;
  final InternalVoteQueryService _internalVoteQuery;

  /// 与 runtime `MaxActiveProposals = 10` 对齐的提案主体上限。
  static const maxActiveProposalsPerSubject = 10;

  /// 查询 NextProposalId（投票引擎全局递增 ID）。
  Future<int> fetchNextProposalId() async {
    final key = _buildStorageValueKey('VotingEngine', 'NextProposalId');
    final data = await _readStorage(key);
    if (data == null || data.length != 8) return 0;
    return _decodeU64(data);
  }

  /// 查询提案状态。返回 status（0=voting, 1=passed, 2=rejected），null 表示不存在。
  Future<int?> fetchProposalStatus(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'Proposals',
      _u64ToLeBytes(proposalId),
    );
    final data = await _readStorage(key);
    if (data == null) return null;
    return decodeProposalMeta(proposalId, data)?.status;
  }

  /// 查询并严格解码投票引擎提案元数据。
  Future<ProposalMeta?> fetchProposalMeta(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'Proposals',
      _u64ToLeBytes(proposalId),
    );
    final data = await _readStorage(key);
    if (data == null) return null;
    return decodeProposalMeta(proposalId, data);
  }

  /// 读取 `VotingEngine::ProposalData` 的 opaque 业务字节。
  ///
  /// 具体 PersonalManage／机构治理语义仍由各 App 业务解码器负责；本服务仅统一
  /// App 侧 storage key，底层 finalized 读取继续由 CitizenSDK 执行。
  Future<Uint8List?> fetchProposalData(int proposalId) {
    return _readStorage(
      _buildStorageKey(
        'VotingEngine',
        'ProposalData',
        _u64ToLeBytes(proposalId),
      ),
    );
  }

  /// 查询并严格解码提案绑定的 VotePlan。
  Future<VotePlan?> fetchVotePlan(int proposalId) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'ProposalVotePlans',
      _u64ToLeBytes(proposalId),
    );
    final data = await _readStorage(key);
    return data == null
        ? null
        : InstitutionRoleStorageCodec.decodeVotePlan(data);
  }

  /// `VotingEngine::Proposal` SCALE 解码唯一真源。
  ///
  /// 任何业务服务需要提案元数据时必须调用本方法，禁止复制字段布局。
  static ProposalMeta? decodeProposalMeta(int proposalId, Uint8List data) {
    try {
      // Proposal = kind + stage + status + internal_code Option
      //   + actor_cid_number Option + execution_account_id Option
      //   + subject CID 集合 + start(u32) + end(u32)。
      // 公民分母属于投票引擎按 proposal_id 保存的独立人口快照，不在 Proposal 重复存储。
      if (data.length < 3 + 3 + 1 + 4 + 4) return null;
      final kind = data[0];
      final stage = data[1];
      final status = data[2];
      var offset = 3;

      String? internalCode;
      final internalCodeTag = data[offset++];
      if (internalCodeTag == 1) {
        if (offset + 4 > data.length) return null;
        internalCode = InstitutionCodeLabel.codeToString(
          data.sublist(offset, offset + 4),
        );
        offset += 4;
      } else if (internalCodeTag != 0) {
        return null;
      }

      String? actorCidNumber;
      if (offset >= data.length) return null;
      final actorCidTag = data[offset++];
      if (actorCidTag == 1) {
        final decoded = _readCidNumber(data, offset);
        if (decoded == null) return null;
        actorCidNumber = decoded.$1;
        offset = decoded.$2;
      } else if (actorCidTag != 0) {
        return null;
      }

      Uint8List? executionAccountId;
      if (offset >= data.length) return null;
      final executionAccountIdTag = data[offset++];
      if (executionAccountIdTag == 1) {
        if (offset + 32 > data.length) return null;
        executionAccountId = Uint8List.fromList(
          data.sublist(offset, offset + 32),
        );
        offset += 32;
      } else if (executionAccountIdTag != 0) {
        return null;
      }

      final subjectCids = _decodeSubjectCidNumbers(data, offset);
      if (subjectCids == null) return null;
      if (subjectCids.$2 + 4 + 4 != data.length) return null;

      return ProposalMeta(
        proposalId: proposalId,
        kind: kind,
        stage: stage,
        status: status,
        internalCode: internalCode,
        actorCidNumber: actorCidNumber,
        executionAccountId: executionAccountId,
        subjectCidNumbers: subjectCids.$1,
      );
    } catch (_) {
      return null;
    }
  }

  /// 查询投票计数。
  Future<({int yes, int no})> fetchVoteTally(int proposalId) async {
    final key = _buildStorageKey(
      'InternalVote',
      'InternalTallies',
      _u64ToLeBytes(proposalId),
    );
    final data = await _readStorage(key);
    if (data == null || data.length != 8) return (yes: 0, no: 0);
    return (yes: _decodeU32(data, 0), no: _decodeU32(data, 4));
  }

  /// 查询内部投票阈值快照。
  Future<int?> fetchInternalThresholdSnapshot(int proposalId) async {
    final key = _buildStorageKey(
      'InternalVote',
      'InternalThresholdSnapshot',
      _u64ToLeBytes(proposalId),
    );
    final data = await _readStorage(key);
    if (data == null || data.length != 4) return null;
    return _decodeU32(data, 0);
  }

  /// 查询提案创建时锁定的管理员快照。
  Future<List<String>> fetchAdminSnapshot(
    int proposalId,
    InstitutionInfo institution,
  ) async {
    final key = _buildDoubleStorageKey(
      'VotingEngine',
      'AdminSnapshot',
      _u64ToLeBytes(proposalId),
      proposalSubjectKey(institution),
    );
    final data = await _readStorage(key);
    if (data == null) {
      throw StateError('提案 $proposalId 缺少 VotingEngine::AdminSnapshot');
    }
    final decoded = decodeAdminSnapshot(data);
    if (decoded == null || decoded.isEmpty) {
      throw const FormatException('VotingEngine::AdminSnapshot SCALE 数据无效');
    }
    return decoded;
  }

  /// 查询提案创建时锁定的实际投票账户快照。
  ///
  /// 个人多签读取 `AdminSnapshot`；机构提案必须按完整岗位主体读取
  /// `VoterSnapshot`。禁止把多个岗位按钱包合并，也禁止回落当前 admins。
  Future<List<String>> fetchEligibleVoterSnapshot(
    int proposalId,
    InstitutionInfo institution,
  ) async {
    if (isPersonalAccountIdentity(institution.cidNumber)) {
      return fetchAdminSnapshot(proposalId, institution);
    }
    throw StateError('机构提案必须按明确岗位调用 fetchRoleVoterSnapshot');
  }

  /// 查询一个完整机构岗位主体在提案创建时冻结的任职钱包。
  Future<List<String>> fetchRoleVoterSnapshot(
    int proposalId,
    String cidNumber,
    String voterRoleCode,
  ) async {
    final subject = BytesBuilder(copy: false)
      ..addByte(0) // AuthorizationSubject::Institution
      ..add(_encodeBoundedText(cidNumber, 32, 'cid_number'))
      ..add(_encodeBoundedText(voterRoleCode, 64, 'voter_role_code'));
    final key = _buildDoubleStorageKey(
      'VotingEngine',
      'VoterSnapshot',
      _u64ToLeBytes(proposalId),
      subject.toBytes(),
    );
    final data = await _readStorage(key);
    if (data == null) {
      throw StateError('提案 $proposalId 缺少岗位 $voterRoleCode 的 VoterSnapshot');
    }
    final decoded = decodeAdminSnapshot(data);
    if (decoded == null || decoded.isEmpty) {
      throw const FormatException('VotingEngine::VoterSnapshot SCALE 数据无效');
    }
    return decoded;
  }

  /// 返回提案全部冻结票据；同一钱包在多个岗位中会出现多次，禁止按账户去重。
  Future<List<EligibleVoterTicket>> fetchEligibleVoterTickets(
    int proposalId,
    InstitutionInfo institution,
  ) async {
    if (isPersonalAccountIdentity(institution.cidNumber)) {
      final accountIds = await fetchAdminSnapshot(proposalId, institution);
      return accountIds
          .map((accountId) => EligibleVoterTicket(voterAccountId: accountId))
          .toList(growable: false);
    }
    final plan = await fetchVotePlan(proposalId);
    if (plan == null) {
      throw StateError('提案 $proposalId 缺少有效 VotePlan');
    }
    final tickets = <EligibleVoterTicket>[];
    for (final subject in plan.voterSubjects) {
      final role = subject.roleSubject;
      if (role == null || role.cidNumber != institution.cidNumber) continue;
      final accountIds = await fetchRoleVoterSnapshot(
        proposalId,
        role.cidNumber,
        role.roleCode,
      );
      for (final accountId in accountIds) {
        tickets.add(
          EligibleVoterTicket(
            voterAccountId: accountId,
            cidNumber: role.cidNumber,
            voterRoleCode: role.roleCode,
          ),
        );
      }
    }
    if (tickets.isEmpty) {
      throw StateError('提案 $proposalId 没有当前机构的冻结岗位票据');
    }
    return tickets;
  }

  Uint8List _encodeBoundedText(String value, int maxBytes, String field) {
    final bytes = utf8.encode(value.trim());
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('$field 长度不合法');
    }
    final length = bytes.length;
    final prefix = length < 64
        ? <int>[length << 2]
        : <int>[(length << 2 | 1) & 0xff, (length << 2 | 1) >> 8];
    return Uint8List.fromList([...prefix, ...bytes]);
  }

  /// 查询某个提案主体当前的活跃提案 ID。
  Future<List<int>> fetchActiveProposalIds(InstitutionInfo institution) async {
    return _fetchActiveProposalIdsBySubjectKey(proposalSubjectKey(institution));
  }

  /// 个人多签历史同步入口；个人多签没有 CID，只能以 AccountId 为主体。
  Future<List<int>> fetchActivePersonalProposalIds(String personalAccountId) {
    return _fetchActiveProposalIdsBySubjectKey(
      personalAccountSubjectKey(personalAccountId),
    );
  }

  Future<List<int>> _fetchActiveProposalIdsBySubjectKey(
    Uint8List subjectKey,
  ) async {
    final key = _buildStorageKey(
      'VotingEngine',
      'ActiveProposalsBySubject',
      subjectKey,
    );
    final data = await _readStorage(key);
    if (data == null) return const [];
    final decoded = decodeActiveProposalIds(data);
    if (decoded == null) {
      throw const FormatException(
        'VotingEngine::ActiveProposalsBySubject SCALE 数据无效',
      );
    }
    return decoded;
  }

  /// 查询某管理员对某提案的投票记录。
  Future<bool?> fetchAdminVote(int proposalId, String accountId) {
    return _internalVoteQuery.fetchAdminVote(proposalId, accountId);
  }

  /// 批量查询内部投票管理员记录。
  ///
  /// 详情页和待投票红点通过本方法合并 storage 读取，避免
  /// 按管理员逐条访问轻节点。
  Future<Map<String, bool?>> fetchAdminVotesBatch(
    int proposalId,
    Iterable<String> accountIds,
  ) {
    return _internalVoteQuery.fetchAdminVotesBatch(proposalId, accountIds);
  }

  Future<Map<String, bool?>> fetchTicketVotesBatch(
    int proposalId,
    Iterable<EligibleVoterTicket> tickets,
  ) {
    return _internalVoteQuery.fetchTicketVotesBatch(proposalId, tickets);
  }

  /// 每个公开查询都先锁定一个 SDK 验证的 finalized 块，业务 key 仍由
  /// VotingEngine 模块生成，不将 pallet 语义下沉到 CitizenSDK。
  Future<Uint8List?> _readStorage(Uint8List key) async {
    final finalized = await _chain.getFinalizedHead();
    return _chain.getStorage(finalized, key);
  }

  Uint8List _buildStorageValueKey(String palletName, String storageName) {
    final palletHash = Hasher.twoxx128.hashString(palletName);
    final storageHash = Hasher.twoxx128.hashString(storageName);
    final key = Uint8List(palletHash.length + storageHash.length);
    key.setAll(0, palletHash);
    key.setAll(palletHash.length, storageHash);
    return key;
  }

  Uint8List _buildStorageKey(
    String palletName,
    String storageName,
    Uint8List keyData,
  ) {
    final palletHash = Hasher.twoxx128.hashString(palletName);
    final storageHash = Hasher.twoxx128.hashString(storageName);
    final keyHash = _blake2128Concat(keyData);
    final result = Uint8List(
      palletHash.length + storageHash.length + keyHash.length,
    );
    var offset = 0;
    result.setAll(offset, palletHash);
    offset += palletHash.length;
    result.setAll(offset, storageHash);
    offset += storageHash.length;
    result.setAll(offset, keyHash);
    return result;
  }

  Uint8List _buildDoubleStorageKey(
    String palletName,
    String storageName,
    Uint8List key1Data,
    Uint8List key2Data,
  ) {
    final palletHash = Hasher.twoxx128.hashString(palletName);
    final storageHash = Hasher.twoxx128.hashString(storageName);
    final key1Hash = _blake2128Concat(key1Data);
    final key2Hash = _blake2128Concat(key2Data);
    final result = Uint8List(
      palletHash.length +
          storageHash.length +
          key1Hash.length +
          key2Hash.length,
    );
    var offset = 0;
    result.setAll(offset, palletHash);
    offset += palletHash.length;
    result.setAll(offset, storageHash);
    offset += storageHash.length;
    result.setAll(offset, key1Hash);
    offset += key1Hash.length;
    result.setAll(offset, key2Hash);
    return result;
  }

  Uint8List _blake2128Concat(Uint8List data) {
    final hash = Hasher.blake2b128.hash(data);
    final result = Uint8List(hash.length + data.length);
    result.setAll(0, hash);
    result.setAll(hash.length, data);
    return result;
  }

  /// `VotingEngine::ProposalSubject` 的唯一 SCALE 编码真源。
  ///
  /// 机构主体固定为 `InstitutionCid(cid_number)`；只有个人多签使用
  /// `PersonalAccount(account_id)`，机构账户绝不能替代机构 CID。
  static Uint8List proposalSubjectKey(InstitutionInfo institution) {
    if (isPersonalAccountIdentity(institution.cidNumber)) {
      return personalAccountSubjectKey(institution.personalAccountId);
    }

    return institutionCidSubjectKey(institution.cidNumber);
  }

  /// `ProposalSubject::InstitutionCid` 编码；只接受机构 CID。
  static Uint8List institutionCidSubjectKey(String cidNumber) {
    final normalized = cidNumber.trim();
    if (isPersonalAccountIdentity(normalized)) {
      throw ArgumentError('个人多签身份不得编码为 InstitutionCid');
    }
    final cidBytes = Uint8List.fromList(utf8.encode(normalized));
    if (cidBytes.isEmpty || cidBytes.length > 32) {
      throw ArgumentError('机构 CID 的 UTF-8 长度必须为 1..32 字节');
    }
    final length = _encodeCompactInt(cidBytes.length);
    return Uint8List.fromList([0, ...length, ...cidBytes]);
  }

  /// `ProposalSubject::PersonalAccount` 编码；AccountId 必须恰好 32 字节。
  static Uint8List personalAccountSubjectKey(String personalAccountId) {
    return Uint8List.fromList([1, ...accountIdBytes(personalAccountId)]);
  }

  /// 严格解码 `BoundedVec<AccountId32>` 管理员快照。
  static List<String>? decodeAdminSnapshot(Uint8List data) {
    try {
      final (count, lenSize) = _decodeCompact(data, 0);
      if (lenSize + count * 32 != data.length) return null;
      return List<String>.unmodifiable([
        for (var offset = lenSize; offset < data.length; offset += 32)
          '0x${_hexEncode(Uint8List.fromList(data.sublist(offset, offset + 32)))}',
      ]);
    } catch (_) {
      return null;
    }
  }

  /// 严格解码 `BoundedVec<u64, MaxActiveProposals>`。
  static List<int>? decodeActiveProposalIds(Uint8List data) {
    try {
      final (count, lenSize) = _decodeCompact(data, 0);
      if (count > maxActiveProposalsPerSubject ||
          lenSize + count * 8 != data.length) {
        return null;
      }
      return List<int>.unmodifiable([
        for (var offset = lenSize; offset < data.length; offset += 8)
          ByteData.sublistView(
            data,
            offset,
            offset + 8,
          ).getUint64(0, Endian.little),
      ]);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _encodeCompactInt(int value) {
    if (value < 1 << 6) return Uint8List.fromList([value << 2]);
    if (value < 1 << 14) {
      final encoded = (value << 2) | 1;
      return Uint8List.fromList([encoded & 0xff, encoded >> 8]);
    }
    final encoded = (value << 2) | 2;
    return Uint8List.fromList([
      encoded & 0xff,
      (encoded >> 8) & 0xff,
      (encoded >> 16) & 0xff,
      (encoded >> 24) & 0xff,
    ]);
  }

  static (int, int) _decodeCompact(Uint8List data, int offset) {
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
      final val = (data[offset] | (data[offset + 1] << 8)) >> 2;
      return (val, 2);
    }
    if (mode == 2) {
      if (offset + 3 >= data.length) {
        throw const FormatException('Compact<u32> mode2 长度不足');
      }
      final val =
          (data[offset] |
              (data[offset + 1] << 8) |
              (data[offset + 2] << 16) |
              (data[offset + 3] << 24)) >>
          2;
      return (val, 4);
    }
    throw const FormatException('Compact<u32> big-integer 模式不支持');
  }

  static (String, int)? _readCidNumber(Uint8List data, int offset) {
    final (length, compactSize) = _decodeCompact(data, offset);
    final start = offset + compactSize;
    final end = start + length;
    if (length <= 0 || length > 32 || end > data.length) return null;
    try {
      return (
        utf8.decode(data.sublist(start, end), allowMalformed: false),
        end,
      );
    } on FormatException {
      return null;
    }
  }

  static (List<String>, int)? _decodeSubjectCidNumbers(
    Uint8List data,
    int offset,
  ) {
    final (count, lenSize) = _decodeCompact(data, offset);
    if (count > 256) return null;
    var cursor = offset + lenSize;
    final result = <String>[];
    for (var i = 0; i < count; i++) {
      final decoded = _readCidNumber(data, cursor);
      if (decoded == null) return null;
      result.add(decoded.$1);
      cursor = decoded.$2;
    }
    return (List.unmodifiable(result), cursor);
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

  int _decodeU32(Uint8List data, int offset) {
    final bd = ByteData.sublistView(data);
    return bd.getUint32(offset, Endian.little);
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
