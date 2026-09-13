import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// 清算行节点链上声明。
///
/// 该结构直接解码 finalized 链状态
/// `OffchainTransaction::ClearingBankNodes[cid_number]`。
class ClearingBankNodeEndpoint {
  const ClearingBankNodeEndpoint({
    required this.cidNumber,
    required this.peerId,
    required this.rpcDomain,
    required this.rpcPort,
    required this.registeredAt,
    required this.registeredBy,
  });

  final String cidNumber;
  final String peerId;
  final String rpcDomain;
  final int rpcPort;
  final int registeredAt;
  final String registeredBy;

  String get wssUrl {
    final isLocal = rpcDomain == '127.0.0.1' || rpcDomain == 'localhost';
    final scheme = isLocal ? 'ws' : 'wss';
    return '$scheme://$rpcDomain:$rpcPort';
  }
}

/// 链上清算行声明与 finalized 机构快照的组合结果。
class ClearingBankCandidate {
  const ClearingBankCandidate({
    required this.cidNumber,
    required this.cidFullName,
    required this.cidShortName,
    required this.areaPath,
    required this.endpoint,
  });

  final String cidNumber;
  final String cidFullName;
  final String? cidShortName;
  final String areaPath;
  final ClearingBankNodeEndpoint endpoint;

  String get displayTitle {
    final shortName = cidShortName?.trim() ?? '';
    if (shortName.isNotEmpty) return shortName;
    final fullName = cidFullName.trim();
    return fullName.isEmpty ? cidNumber : fullName;
  }

  /// 机构账户由链统一派生规则确定。
  String get mainAccountId =>
      accountIdText(deriveInstitutionMainAccountId(cidNumber));

  String get feeAccountId =>
      accountIdText(deriveInstitutionFeeAccountId(cidNumber));
}

/// CitizenApp 清算行目录服务。
///
/// 搜索、端点和用户绑定状态全部来自 finalized 链状态；机构目录只补充名称与行政区
/// 展示，不参与清算行资格判断。关键操作每次重新读链，不保留长 TTL 权限缓存。
class ClearingBankDirectory {
  ClearingBankDirectory({
    required CitizenChain chain,
    InstitutionRepository? institutionRepository,
  })  : _chain = chain,
        _institutionRepository =
            institutionRepository ?? InstitutionRepository();

  final CitizenChain _chain;
  final InstitutionRepository _institutionRepository;

  static const int _pageSize = 256;
  static const int _batchSize = 100;

  Future<List<ClearingBankCandidate>> search(String query) async {
    await _institutionRepository.directory.ensureSynced();
    final endpoints = await _fetchAllEndpoints();
    final keyword = query.trim().toLowerCase();
    final candidates = <ClearingBankCandidate>[];

    for (final endpoint in endpoints) {
      final institution =
          await _institutionRepository.getByCid(endpoint.cidNumber);
      final candidate = await _candidate(endpoint, institution);
      if (keyword.isEmpty ||
          candidate.cidNumber.toLowerCase().contains(keyword) ||
          candidate.cidFullName.toLowerCase().contains(keyword) ||
          (candidate.cidShortName?.toLowerCase().contains(keyword) ?? false)) {
        candidates.add(candidate);
      }
    }

    candidates.sort((a, b) => a.cidNumber.compareTo(b.cidNumber));
    return candidates.take(20).toList(growable: false);
  }

  Future<ClearingBankCandidate> _candidate(
    ClearingBankNodeEndpoint endpoint,
    Institution? institution,
  ) async {
    var areaPath = '';
    if (institution != null) {
      try {
        areaPath =
            await _institutionRepository.institutionAreaPath(institution);
      } on Exception {
        areaPath = '';
      }
    }
    return ClearingBankCandidate(
      cidNumber: endpoint.cidNumber,
      cidFullName: institution?.cidFullName ?? endpoint.cidNumber,
      cidShortName: institution?.cidShortName,
      areaPath: areaPath,
      endpoint: endpoint,
    );
  }

  /// 精确读取单个清算行声明。绑定和付款前调用本方法重新校验链状态。
  Future<ClearingBankNodeEndpoint?> fetchEndpoint(String cidNumber) async {
    final finalized = await _chain.getFinalizedHead();
    final raw = await _chain.getStorage(
      finalized,
      _clearingBankNodesKey(cidNumber),
    );
    if (raw == null || raw.isEmpty) return null;
    return _decodeEndpoint(cidNumber, raw);
  }

  /// 查询 finalized `UserBank[user]`，返回当前绑定清算行主账户 SS58。
  Future<String?> fetchUserBank(String userAddress) async {
    final account = Uint8List.fromList(Keyring().decodeAddress(userAddress));
    final finalized = await _chain.getFinalizedHead();
    final raw = await _chain.getStorage(finalized, _userBankKey(account));
    if (raw == null || raw.length != 32) return null;
    return Keyring().encodeAddress(raw.toList(), kGmbSs58Prefix);
  }

  Future<List<ClearingBankNodeEndpoint>> _fetchAllEndpoints() async {
    final prefix = _storagePrefix('OffchainTransaction', 'ClearingBankNodes');
    final finalized = await _chain.getFinalizedHead();
    final keys = <Uint8List>[];
    Uint8List? startKey;
    while (true) {
      final page = await _chain.getStorageKeysPaged(
        finalized,
        prefix,
        startKey: startKey,
        limit: _pageSize,
      );
      if (page.isEmpty) break;
      keys.addAll(page);
      if (page.length < _pageSize) break;
      startKey = page.last;
    }

    final values = <Uint8List?>[];
    for (var offset = 0; offset < keys.length; offset += _batchSize) {
      final end = (offset + _batchSize).clamp(0, keys.length);
      values.addAll(
        await _chain.getStorageBatch(finalized, keys.sublist(offset, end)),
      );
    }
    final out = <ClearingBankNodeEndpoint>[];
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      final cidNumber = _decodeBlake2MapStringKey(key);
      final raw = values[index];
      if (cidNumber == null || raw == null) continue;
      final endpoint = _decodeEndpoint(cidNumber, raw);
      if (endpoint != null) out.add(endpoint);
    }
    return out;
  }

  static ClearingBankNodeEndpoint? _decodeEndpoint(
    String cidNumber,
    Uint8List raw,
  ) {
    var offset = 0;
    final (peerId, peerNext) = _readUtf8Vec(raw, offset, maxLength: 64);
    if (peerId == null) return null;
    offset = peerNext;
    final (domain, domainNext) = _readUtf8Vec(raw, offset, maxLength: 128);
    if (domain == null) return null;
    offset = domainNext;
    if (offset + 2 + 4 + 32 != raw.length) return null;
    final port = raw[offset] | (raw[offset + 1] << 8);
    offset += 2;
    final registeredAt = _readU32Le(raw, offset);
    offset += 4;
    final registeredBy = Keyring().encodeAddress(
      raw.sublist(offset, offset + 32).toList(),
      kGmbSs58Prefix,
    );
    return ClearingBankNodeEndpoint(
      cidNumber: cidNumber,
      peerId: peerId,
      rpcDomain: domain,
      rpcPort: port,
      registeredAt: registeredAt,
      registeredBy: registeredBy,
    );
  }

  static Uint8List _clearingBankNodesKey(String cidNumber) {
    final keyData = _encodeBytes(utf8.encode(cidNumber));
    return _mapKey('OffchainTransaction', 'ClearingBankNodes', keyData);
  }

  static Uint8List _userBankKey(Uint8List accountId) {
    return _mapKey('OffchainTransaction', 'UserBank', accountId);
  }

  static Uint8List _storagePrefix(String pallet, String storage) {
    final bytes = BytesBuilder()
      ..add(Hasher.twoxx128.hashString(pallet))
      ..add(Hasher.twoxx128.hashString(storage));
    return bytes.toBytes();
  }

  static Uint8List _mapKey(
    String pallet,
    String storage,
    Uint8List keyData,
  ) {
    final bytes = BytesBuilder()
      ..add(Hasher.twoxx128.hashString(pallet))
      ..add(Hasher.twoxx128.hashString(storage))
      ..add(Hasher.blake2b128.hash(keyData))
      ..add(keyData);
    return bytes.toBytes();
  }

  static String? _decodeBlake2MapStringKey(Uint8List bytes) {
    const valueOffset = 32 + 16;
    if (bytes.length <= valueOffset) return null;
    final (value, next) = _readUtf8Vec(bytes, valueOffset, maxLength: 32);
    return next == bytes.length ? value : null;
  }

  static Uint8List _encodeBytes(List<int> raw) {
    return Uint8List.fromList([..._compactU32(raw.length), ...raw]);
  }

  static List<int> _compactU32(int value) {
    if (value < 1 << 6) return [value << 2];
    if (value < 1 << 14) {
      final v = (value << 2) | 0x01;
      return [v & 0xff, (v >> 8) & 0xff];
    }
    final v = (value << 2) | 0x02;
    return [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  }

  static (String?, int) _readUtf8Vec(
    Uint8List bytes,
    int offset, {
    required int maxLength,
  }) {
    final (len, lenSize) = _decodeCompactU32(bytes, offset);
    if (lenSize == 0 || len <= 0 || len > maxLength) return (null, offset);
    offset += lenSize;
    if (offset + len > bytes.length) return (null, offset);
    try {
      return (
        utf8.decode(bytes.sublist(offset, offset + len)),
        offset + len,
      );
    } on FormatException {
      return (null, offset);
    }
  }

  static (int, int) _decodeCompactU32(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return (0, 0);
    final mode = bytes[offset] & 0x03;
    if (mode == 0) return (bytes[offset] >> 2, 1);
    if (mode == 1) {
      if (offset + 2 > bytes.length) return (0, 0);
      return ((((bytes[offset + 1] << 8) | bytes[offset]) >> 2), 2);
    }
    if (mode == 2) {
      if (offset + 4 > bytes.length) return (0, 0);
      final raw = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      return (raw >> 2, 4);
    }
    return (0, 0);
  }

  static int _readU32Le(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

}
