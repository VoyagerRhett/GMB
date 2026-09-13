import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';

/// InternalVote 通用查询服务。
///
/// 内部投票记录属于投票引擎通用状态，不放进具体业务模块，
/// 避免 proposal 共享层依赖业务 service。
class InternalVoteQueryService {
  const InternalVoteQueryService({required CitizenChain chain})
      : _chain = chain;

  final CitizenChain _chain;

  /// 查询某管理员对某提案的投票记录。null=未投票，true=赞成，false=反对。
  Future<bool?> fetchAdminVote(int proposalId, String accountId) async {
    final data = await _readOne(_ticketVoteKey(proposalId, accountId));
    return _decodeVote(data);
  }

  /// 查询一张机构岗位票据；CID、岗位码、钱包三者共同确定唯一票。
  Future<bool?> fetchInstitutionTicketVote(
    int proposalId,
    String cidNumber,
    String voterRoleCode,
    String accountId,
  ) async {
    final data = await _readOne(_ticketVoteKey(
      proposalId,
      accountId,
      cidNumber: cidNumber,
      voterRoleCode: voterRoleCode,
    ));
    return _decodeVote(data);
  }

  /// 批量查询管理员投票记录。
  ///
  /// 详情页和红点判断不能再按管理员逐条 RPC；这里统一拼好
  /// `InternalVotesByTicket` 的个人票据 storage key 后分块读取。
  Future<Map<String, bool?>> fetchAdminVotesBatch(
    int proposalId,
    Iterable<String> accountIds,
  ) async {
    final keyByAccountId = <String, Uint8List>{};
    for (final accountId in accountIds) {
      final normalizedAccountId = _requireAccountId(accountId);
      keyByAccountId[normalizedAccountId] =
          _ticketVoteKey(proposalId, normalizedAccountId);
    }
    if (keyByAccountId.isEmpty) return const {};

    final values = await _readBatch(keyByAccountId.values.toList());
    return {
      for (var index = 0; index < keyByAccountId.length; index++)
        keyByAccountId.keys.elementAt(index): _decodeVote(values[index]),
    };
  }

  /// 批量查询完整票据；返回键为 [EligibleVoterTicket.ticketKey]。
  Future<Map<String, bool?>> fetchTicketVotesBatch(
    int proposalId,
    Iterable<EligibleVoterTicket> tickets,
  ) async {
    final storageByTicket = <String, Uint8List>{};
    for (final ticket in tickets) {
      storageByTicket[ticket.ticketKey] = _ticketVoteKey(
        proposalId,
        ticket.voterAccountId,
        cidNumber: ticket.cidNumber,
        voterRoleCode: ticket.voterRoleCode,
      );
    }
    final values = await _readBatch(storageByTicket.values.toList());
    return {
      for (var index = 0; index < storageByTicket.length; index++)
        storageByTicket.keys.elementAt(index): _decodeVote(values[index]),
    };
  }

  /// 跨提案批量查询内部投票:输入 `{proposalId: [accountId]}`,一次链查返回
  /// `{proposalId: {accountId: vote?}}`。
  ///
  /// (ADR-018 R2):公民-提案列表原来每个提案各发一次批量 RPC(P 个提案
  /// = P 次往返),这里把所有 (proposalId, admin) 的 storage key 一次拼齐、单次
  /// 分块读取,P 次往返降为 1 次。
  Future<Map<int, Map<String, bool?>>> fetchAdminVotesForProposals(
    Map<int, List<String>> accountIdsByProposal,
  ) async {
    final keys = <Uint8List>[];
    final coordinates = <({int pid, String accountId})>[];
    for (final entry in accountIdsByProposal.entries) {
      for (final accountId in entry.value) {
        final normalizedAccountId = _requireAccountId(accountId);
        keys.add(_ticketVoteKey(entry.key, normalizedAccountId));
        coordinates.add((pid: entry.key, accountId: normalizedAccountId));
      }
    }
    if (keys.isEmpty) return const {};
    final values = await _readBatch(keys);
    final result = <int, Map<String, bool?>>{};
    for (var index = 0; index < coordinates.length; index++) {
      final coord = coordinates[index];
      (result[coord.pid] ??= <String, bool?>{})[coord.accountId] =
          _decodeVote(values[index]);
    }
    return result;
  }

  /// 跨提案批量查询完整票据；机构岗位票据和个人票据共用一次分块读取。
  Future<Map<int, Map<String, bool?>>> fetchTicketVotesForProposals(
    Map<int, List<EligibleVoterTicket>> ticketsByProposal,
  ) async {
    final keys = <Uint8List>[];
    final coordinates = <({int pid, String ticketKey})>[];
    for (final entry in ticketsByProposal.entries) {
      for (final ticket in entry.value) {
        final storageKey = _ticketVoteKey(
          entry.key,
          ticket.voterAccountId,
          cidNumber: ticket.cidNumber,
          voterRoleCode: ticket.voterRoleCode,
        );
        keys.add(storageKey);
        coordinates.add((
          pid: entry.key,
          ticketKey: ticket.ticketKey,
        ));
      }
    }
    if (keys.isEmpty) return const {};
    final values = await _readBatch(keys);
    final result = <int, Map<String, bool?>>{};
    for (var index = 0; index < coordinates.length; index++) {
      final coord = coordinates[index];
      (result[coord.pid] ??= <String, bool?>{})[coord.ticketKey] =
          _decodeVote(values[index]);
    }
    return result;
  }

  Uint8List _ticketVoteKey(
    int proposalId,
    String accountId, {
    String? cidNumber,
    String? voterRoleCode,
  }) {
    final proposalIdBytes = _u64ToLeBytes(proposalId);
    final accountBytes = _hexDecode(accountId);
    final ticketBytes = BytesBuilder(copy: false);
    if (cidNumber == null && voterRoleCode == null) {
      ticketBytes.addByte(0); // InternalVoteTicket::Personal
      ticketBytes.add(accountBytes);
    } else if (cidNumber != null && voterRoleCode != null) {
      ticketBytes.addByte(1); // InternalVoteTicket::Institution
      ticketBytes.add(_encodeBoundedText(cidNumber, 32, 'cid_number'));
      ticketBytes.add(_encodeBoundedText(voterRoleCode, 64, 'voter_role_code'));
      ticketBytes.add(accountBytes);
    } else {
      throw ArgumentError('机构票据查询必须同时提供 cid_number 和 voter_role_code');
    }
    final palletHash = Hasher.twoxx128.hashString('InternalVote');
    final storageHash = Hasher.twoxx128.hashString('InternalVotesByTicket');
    final key1 = _blake2128Concat(proposalIdBytes);
    final key2 = _blake2128Concat(ticketBytes.toBytes());
    final fullKey = Uint8List(
      palletHash.length + storageHash.length + key1.length + key2.length,
    );
    var offset = 0;
    fullKey.setAll(offset, palletHash);
    offset += palletHash.length;
    fullKey.setAll(offset, storageHash);
    offset += storageHash.length;
    fullKey.setAll(offset, key1);
    offset += key1.length;
    fullKey.setAll(offset, key2);
    return fullKey;
  }

  Future<Uint8List?> _readOne(Uint8List key) async {
    final finalized = await _chain.getFinalizedHead();
    return _chain.getStorage(finalized, key);
  }

  Future<List<Uint8List?>> _readBatch(List<Uint8List> keys) async {
    if (keys.isEmpty) return const <Uint8List?>[];
    final finalized = await _chain.getFinalizedHead();
    final result = <Uint8List?>[];
    for (var offset = 0; offset < keys.length; offset += 100) {
      final end = (offset + 100).clamp(0, keys.length);
      result.addAll(
        await _chain.getStorageBatch(finalized, keys.sublist(offset, end)),
      );
    }
    return result;
  }

  bool? _decodeVote(Uint8List? data) {
    if (data == null) return null;
    if (data.length != 1 || (data[0] != 0 && data[0] != 1)) {
      throw const FormatException(
        'InternalVotesByTicket 必须是严格的 SCALE bool',
      );
    }
    return data[0] == 1;
  }

  Uint8List _encodeBoundedText(String value, int maxBytes, String field) {
    final bytes = Uint8List.fromList(value.codeUnits);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('$field 长度不合法');
    }
    final length = bytes.length;
    final prefix = length < 64
        ? <int>[length << 2]
        : <int>[(length << 2 | 1) & 0xff, (length << 2 | 1) >> 8];
    return Uint8List.fromList([...prefix, ...bytes]);
  }

  Uint8List _u64ToLeBytes(int value) {
    final bytes = Uint8List(8);
    final bd = ByteData.sublistView(bytes);
    bd.setUint64(0, value, Endian.little);
    return bytes;
  }

  Uint8List _blake2128Concat(Uint8List data) {
    final hash = Hasher.blake2b128.hash(data);
    final result = Uint8List(hash.length + data.length);
    result.setAll(0, hash);
    result.setAll(hash.length, data);
    return result;
  }

  Uint8List _hexDecode(String hex) {
    final h = _requireAccountId(hex).substring(2);
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

}
