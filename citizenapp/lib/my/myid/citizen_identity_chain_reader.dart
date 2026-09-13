import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;

import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// 由永久 CID 定位的链上公民身份快照。
///
/// CID 与钱包的双向绑定、CID 登记状态均已在读取阶段闭环校验;调用方不得再把
/// 裸钱包或单向映射当作已注册 CID。
///
/// [votingIdentity] 为 `null` 表示**匿名已注册**:账户自助占了一个 CID 并双向绑定
/// (`CidRegistry` Active),但链上无 `VotingIdentityByCid`(未经注册局线下升级)。
/// 匿名态只暴露 `cidNumber`,不得据此当投票/竞选公民。非空即投票身份已闭环校验。
class CitizenIdentityChainSnapshot {
  const CitizenIdentityChainSnapshot({
    required this.cidNumber,
    required this.accountId,
    required this.bindingRevision,
    required this.votingIdentity,
    this.candidateIdentity,
  });

  /// 已注册且绑定闭环的匿名 CID(无投票身份)。
  bool get isAnonymous => votingIdentity == null;

  final String cidNumber;
  final Uint8List accountId;

  /// CID 单调绑定版本；初绑为 1，每次换绑或撤销递增。
  final int bindingRevision;
  final Uint8List? votingIdentity;
  final Uint8List? candidateIdentity;
}

/// 某 CID 在同一 finalized 区块上的有效钱包绑定。
///
/// 该快照只表达“CID 当前由哪个钱包授权”，不把钱包提升为身份主键。
class CitizenBindingChainSnapshot {
  const CitizenBindingChainSnapshot({
    required this.cidNumber,
    required this.accountId,
    required this.bindingRevision,
  });

  final String cidNumber;
  final Uint8List accountId;
  final int bindingRevision;

  String get accountIdText => CitizenIdentityChainReader.hexEncode(accountId);
}

/// `citizen-identity` 永久 CID 存储的统一读取器。
class CitizenIdentityChainReader {
  const CitizenIdentityChainReader({required CitizenChain chain})
    : _chain = chain;

  final CitizenChain _chain;

  /// 在同一个 finalized 区块批量读取 CID 的当前有效钱包绑定。
  ///
  /// 每条结果都同时验证 `AccountIdByCid`、`CidRegistry Active`、
  /// `BindingRevisionByCid` 与反向 `CidByAccountId`，任一不闭环就不返回该 CID。
  ///
  /// 任一条 `CidRegistry` 布局无法解析则整批上抛：解析器与链端结构不同步时，
  /// 整批失败让用户重试，好过静默把全部联系人判成「无有效绑定」。
  Future<Map<String, CitizenBindingChainSnapshot>> readBindingsByCidNumbers(
    Iterable<String> cidNumbers,
  ) async {
    final normalized = <String>{
      for (final cidNumber in cidNumbers) _normalizeCidNumber(cidNumber),
    };
    if (normalized.isEmpty) {
      return const <String, CitizenBindingChainSnapshot>{};
    }

    final finalized = await _chain.getFinalizedHead();
    final candidates = <String, CitizenBindingChainSnapshot>{};

    await Future.wait(
      normalized.map((cidNumber) async {
        final cidScale = encodeBoundedBytes(utf8.encode(cidNumber));
        final rows = await _chain.getStorageBatch(finalized, <Uint8List>[
          storageMapKey('CitizenIdentity', 'AccountIdByCid', cidScale),
          storageMapKey('CitizenIdentity', 'CidRegistry', cidScale),
          storageMapKey('CitizenIdentity', 'BindingRevisionByCid', cidScale),
        ]);
        final accountId = rows[0];
        final bindingRevision = _decodeU64(rows[2]);
        if (accountId == null ||
            accountId.length != 32 ||
            !cidRecordIsActive(rows[1]) ||
            bindingRevision <= 0) {
          return;
        }
        candidates[cidNumber] = CitizenBindingChainSnapshot(
          cidNumber: cidNumber,
          accountId: accountId,
          bindingRevision: bindingRevision,
        );
      }),
    );

    final verified = <String, CitizenBindingChainSnapshot>{};
    await Future.wait(
      candidates.values.map((candidate) async {
        final reverse = await _chain.getStorage(
          finalized,
          storageMapKey(
            'CitizenIdentity',
            'CidByAccountId',
            candidate.accountId,
          ),
        );
        if (decodeCidNumber(reverse) == candidate.cidNumber) {
          verified[candidate.cidNumber] = candidate;
        }
      }),
    );
    return verified;
  }

  /// 严格读取一个 CID 的当前有效钱包绑定。
  Future<CitizenBindingChainSnapshot?> readBindingByCidNumber(
    String cidNumber,
  ) async {
    final normalized = _normalizeCidNumber(cidNumber);
    return (await readBindingsByCidNumbers([normalized]))[normalized];
  }

  /// 按规范账户 ID 读取身份闭环,区分**纯访客 / 匿名已注册 / 投票 / 竞选**。
  ///
  /// 顺序固定为:`CidByAccountId` → `CidRegistry` Active → `AccountIdByCid`
  /// 反向一致(**绑定闭环**)→ `VotingIdentityByCid`;竞选再读 `CandidateIdentityByCid`。
  /// - `CidByAccountId` 无、或绑定不闭环(反向错配 / 非 Active)→ 返回 `null`
  ///   (**纯访客**,可自助占号)。
  /// - 绑定闭环但无 `VotingIdentityByCid`(或其布局损坏)→ 返回 `isAnonymous` 快照
  ///   (**匿名已注册**,只带 `cidNumber`)。布局损坏归匿名是 fail-closed 的**安全降级**
  ///   (降到匿名而非误升成投票公民)。
  /// - 绑定闭环 + 合法 `VotingIdentityByCid` → **投票**;再有合法 candidate → **竞选**。
  Future<CitizenIdentityChainSnapshot?> readByAccountId(
    String accountIdText,
  ) async {
    if (!isAccountIdText(accountIdText)) {
      throw const FormatException('account_id 必须是小写 0x 加 64 位十六进制');
    }
    final accountId = Uint8List.fromList([
      for (var i = 2; i < accountIdText.length; i += 2)
        int.parse(accountIdText.substring(i, i + 2), radix: 16),
    ]);

    // 同一次身份判断必须锚定同一个 finalized 区块，避免 CID 映射与身份值跨块混读。
    final finalized = await _chain.getFinalizedHead();

    final cidByAccountIdKey = storageMapKey(
      'CitizenIdentity',
      'CidByAccountId',
      accountId,
    );
    final cidRaw = await _chain.getStorage(finalized, cidByAccountIdKey);
    final cidNumber = decodeCidNumber(cidRaw);
    if (cidNumber == null) return null;

    final cidScale = encodeBoundedBytes(utf8.encode(cidNumber));
    final accountIdByCidKey = storageMapKey(
      'CitizenIdentity',
      'AccountIdByCid',
      cidScale,
    );
    final cidRegistryKey = storageMapKey(
      'CitizenIdentity',
      'CidRegistry',
      cidScale,
    );
    final votingKey = storageMapKey(
      'CitizenIdentity',
      'VotingIdentityByCid',
      cidScale,
    );
    final candidateKey = storageMapKey(
      'CitizenIdentity',
      'CandidateIdentityByCid',
      cidScale,
    );
    final bindingRevisionKey = storageMapKey(
      'CitizenIdentity',
      'BindingRevisionByCid',
      cidScale,
    );
    final keys = <Uint8List>[
      accountIdByCidKey,
      cidRegistryKey,
      votingKey,
      candidateKey,
      bindingRevisionKey,
    ];
    final rows = await _chain.getStorageBatch(finalized, keys);
    final boundAccountId = rows[0];
    final cidRecord = rows[1];
    final votingIdentity = rows[2];
    final candidateIdentity = rows[3];
    final bindingRevision = _decodeU64(rows[4]);
    // 绑定闭环:AccountIdByCid 反向一致 + CidRegistry Active。不闭环(反查为空/错配/
    // 非 Active)= 该账户没有有效 CID → 纯访客兜底(可重新占号,链上残留绑定占号时再拒)。
    if (boundAccountId == null ||
        boundAccountId.length != accountId.length ||
        !_sameBytes(boundAccountId, accountId) ||
        !cidRecordIsActive(cidRecord) ||
        bindingRevision <= 0) {
      return null;
    }

    // CID 闭环成立。VotingIdentity 键不存在或布局损坏 → 匿名已注册(安全降级,只暴露 CID)。
    if (votingIdentity == null ||
        !votingIdentityLayoutIsValid(votingIdentity)) {
      return CitizenIdentityChainSnapshot(
        cidNumber: cidNumber,
        accountId: accountId,
        bindingRevision: bindingRevision,
        votingIdentity: null,
        candidateIdentity: null,
      );
    }

    // 合法投票身份;竞选身份布局非法时降级为纯投票(不误升竞选)。
    return CitizenIdentityChainSnapshot(
      cidNumber: cidNumber,
      accountId: accountId,
      bindingRevision: bindingRevision,
      votingIdentity: votingIdentity,
      candidateIdentity:
          candidateIdentity != null &&
              candidateIdentityLayoutIsValid(candidateIdentity)
          ? candidateIdentity
          : null,
    );
  }

  static String hexEncode(List<int> bytes) =>
      '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';

  static Uint8List storageMapKey(
    String palletName,
    String storageName,
    Uint8List keyData,
  ) {
    final palletHash = Hasher.twoxx128.hashString(palletName);
    final storageHash = Hasher.twoxx128.hashString(storageName);
    final keyHash = Hasher.blake2b128.hash(keyData);
    return Uint8List.fromList([
      ...palletHash,
      ...storageHash,
      ...keyHash,
      ...keyData,
    ]);
  }

  static Uint8List encodeBoundedBytes(List<int> value) {
    if (value.isEmpty || value.length > 32) {
      throw const FormatException('CID 长度不合法');
    }
    if (value.length >= 64) {
      throw const FormatException('CID 超出单字节 Compact 长度范围');
    }
    return Uint8List.fromList([value.length << 2, ...value]);
  }

  static String _normalizeCidNumber(String cidNumber) {
    final normalized = cidNumber.trim();
    final bytes = utf8.encode(normalized);
    if (bytes.isEmpty || bytes.length > 32) {
      throw const FormatException('CID 长度不合法');
    }
    return normalized;
  }

  static String? decodeCidNumber(Uint8List? data) {
    if (data == null) return null;
    try {
      final value = _readBoundedBytes(data, 0, 32);
      if (value.nextOffset != data.length) return null;
      final cid = utf8.decode(value.bytes, allowMalformed: false).trim();
      return cid.isEmpty ? null : cid;
    } catch (_) {
      return null;
    }
  }

  static int _decodeU64(Uint8List? data) {
    if (data == null || data.length != 8) return 0;
    var value = 0;
    for (var index = data.length - 1; index >= 0; index--) {
      value = (value << 8) | data[index];
    }
    return value;
  }

  /// 解码 `CidRecord` 到 status 字段；只接受 `Active = 0`。
  ///
  /// 严格区分「解析成功但没有有效登记」与「读不准」,绝不把后者压成未注册:
  /// - 记录不存在、状态为 `Revoked`、状态与 `revoked_at` 自相矛盾 → `false`
  ///   (结论可信:该 CID 确实没有有效登记)。
  /// - SCALE 布局无法解析(截断 / 长度非法 / 尾随字节)→ 抛 [FormatException],
  ///   交调用方按链读失败处理(门禁落 queryFailed 让用户重试)。吞成 `false` 会让
  ///   解析器与链端结构不同步时全体用户静默变访客。
  ///
  /// `residence_province_code` / `residence_city_code` 恒为空:创世
  /// `initial_cid_bindings`、`self_occupy_cid` 与注册局占号都写
  /// `AreaCodeBound::default()`,换绑只 clone 旧值。故必须 `allowEmpty: true`。
  static bool cidRecordIsActive(Uint8List? data) {
    if (data == null) return false;
    var offset = _readBoundedBytes(data, 0, 32).nextOffset;
    offset += 32; // commitment
    if (offset > data.length) {
      throw const FormatException('CidRecord commitment 越界');
    }
    offset = _readBoundedBytes(data, offset, 16, allowEmpty: true).nextOffset;
    offset = _readBoundedBytes(data, offset, 16, allowEmpty: true).nextOffset;
    // status(1) + registered_at(4) + revoked_at 标记(1) 必须齐全。
    if (offset + 1 + 4 + 1 > data.length) {
      throw const FormatException('CidRecord 尾部截断');
    }
    if (data[offset] != 0) return false; // CidRecordStatus::Revoked
    offset += 1 + 4;
    switch (data[offset]) {
      case 0: // revoked_at = None
        if (offset + 1 != data.length) {
          throw const FormatException('CidRecord 尾随字节非法');
        }
        return true;
      case 1: // revoked_at = Some(BlockNumber)
        if (offset + 1 + 4 != data.length) {
          throw const FormatException('CidRecord 尾随字节非法');
        }
        // Active 却带撤销块号:自相矛盾,fail-closed 判非 Active。
        return false;
      default:
        throw const FormatException('CidRecord revoked_at 标记非法');
    }
  }

  /// 校验 `VotingIdentity<BlockNumber>` 的最终 SCALE 布局，不接受截断或尾随字节。
  static bool votingIdentityLayoutIsValid(Uint8List data) {
    try {
      if (data.length < 9) return false;
      final validFrom = _readU32Le(data, 0);
      final validUntil = _readU32Le(data, 4);
      if (!_isValidDateInt(validFrom) || !_isValidDateInt(validUntil)) {
        return false;
      }
      if (data[8] != 0 && data[8] != 1) return false;
      var offset = 9;
      offset = _readBoundedBytes(data, offset, 16, allowEmpty: true).nextOffset;
      offset = _readBoundedBytes(data, offset, 16, allowEmpty: true).nextOffset;
      offset = _readBoundedBytes(data, offset, 16, allowEmpty: true).nextOffset;
      return offset + 4 == data.length;
    } catch (_) {
      return false;
    }
  }

  /// 校验 `CandidateIdentity<BlockNumber>` 的最终 SCALE 布局。
  static bool candidateIdentityLayoutIsValid(Uint8List data) {
    try {
      var offset = 0;
      for (var index = 0; index < 3; index++) {
        offset = _readBoundedBytes(
          data,
          offset,
          16,
          allowEmpty: true,
        ).nextOffset;
      }
      final familyName = _readBoundedBytes(data, offset, 128);
      offset = familyName.nextOffset;
      final givenName = _readBoundedBytes(data, offset, 128);
      offset = givenName.nextOffset;
      if (offset + 1 + 4 + 4 != data.length) return false;
      if (data[offset] != 0 && data[offset] != 1) return false;
      final birthDate = _readU32Le(data, offset + 1);
      return _isValidDateInt(birthDate);
    } catch (_) {
      return false;
    }
  }

  static ({Uint8List bytes, int nextOffset}) _readBoundedBytes(
    Uint8List data,
    int offset,
    int maxLength, {
    bool allowEmpty = false,
  }) {
    if (offset >= data.length) throw const FormatException('Compact 越界');
    final first = data[offset];
    if ((first & 0x03) != 0) {
      throw const FormatException('当前身份键只允许短 Compact 长度');
    }
    final length = first >> 2;
    final start = offset + 1;
    final end = start + length;
    if ((!allowEmpty && length == 0) ||
        length > maxLength ||
        end > data.length) {
      throw const FormatException('BoundedVec 长度不合法');
    }
    return (bytes: Uint8List.sublistView(data, start, end), nextOffset: end);
  }

  static int _readU32Le(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);

  static bool _isValidDateInt(int value) {
    final year = value ~/ 10000;
    final month = (value % 10000) ~/ 100;
    final day = value % 100;
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return false;
    }
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// 账户边界动作使用的 `AccountId → CID` finalized 解析器。
///
/// 仅供扫码导入联系人等必须核验码内账户的动作使用；Chat 路由已经以 CID
/// 为主键，普通打开会话或主页禁止使用本类读链。
class CidByAccountIdResolver {
  CidByAccountIdResolver({required CitizenIdentityChainReader chainReader})
    : _chainReader = chainReader;

  final CitizenIdentityChainReader _chainReader;
  final Map<String, String> _cache = <String, String>{};

  Future<String> resolve(String accountId) async {
    final cached = _cache[accountId];
    if (cached != null && cached.isNotEmpty) return cached;
    final snapshot = await _chainReader.readByAccountId(accountId);
    final cidNumber = snapshot?.cidNumber ?? '';
    if (cidNumber.isEmpty) {
      throw StateError('对方尚未绑定身份（CID）');
    }
    _cache[accountId] = cidNumber;
    return cidNumber;
  }
}
