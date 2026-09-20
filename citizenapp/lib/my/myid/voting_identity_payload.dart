// 公民链上身份确认载荷独立解码器。
//
// 两色识别模型:签名前必须能从字节独立解码出全部字段并展示给公民,解不开一律拒签。
// 公民签名覆盖完整授权字节:
//   genesis_hash(32) ++ payload ++ expected_identity_version(8) ++ expires_at(8)
// SCALE 布局与链端结构体逐字节一致,字段变更四处必须同步:
//   citizenchain/runtime/misc/citizen-identity/src/lib.rs
//     (CitizenIdentityAuthorization / VotingIdentityPayload / CandidateIdentityPayload)
//   citizenchain/onchina/src/domains/citizens/chain_identity.rs
//     (build_citizen_identity_authorization_bytes)
//   citizenwallet/lib/signer/payload_decoder.dart(_readCandidateIdentityPayload)
//   本文件
// 注:链上「已存储」的 CandidateIdentity(含 birth_date)另由
//   citizenapp/lib/my/myid/myid_service.dart(_decodeCandidateIdentity)解码。
import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// CitizenChain SS58 前缀。

enum CitizenIdentityConsentLevel { voting, candidate }

class VotingIdentityConsentPayload {
  const VotingIdentityConsentPayload({
    required this.identityLevel,
    required this.cidNumber,
    required this.accountId,
    required this.ss58Address,
    required this.validFrom,
    required this.validUntil,
    required this.statusNormal,
    required this.provinceCode,
    required this.cityCode,
    required this.townCode,
    this.birthProvinceCode,
    this.birthCityCode,
    this.birthTownCode,
    this.familyName,
    this.givenName,
    this.citizenSexLabel,
    this.birthDate,
    this.genesisHashHex,
    this.expectedIdentityVersion,
    this.authorizationExpiresAt,
  });

  /// 附加授权字段；只有整段授权字节解码成功才会带上。
  VotingIdentityConsentPayload withAuthorization({
    required String genesisHashHex,
    required int expectedIdentityVersion,
    required int authorizationExpiresAt,
  }) {
    return VotingIdentityConsentPayload(
      identityLevel: identityLevel,
      cidNumber: cidNumber,
      accountId: accountId,
      ss58Address: ss58Address,
      validFrom: validFrom,
      validUntil: validUntil,
      statusNormal: statusNormal,
      provinceCode: provinceCode,
      cityCode: cityCode,
      townCode: townCode,
      birthProvinceCode: birthProvinceCode,
      birthCityCode: birthCityCode,
      birthTownCode: birthTownCode,
      familyName: familyName,
      givenName: givenName,
      citizenSexLabel: citizenSexLabel,
      birthDate: birthDate,
      genesisHashHex: genesisHashHex,
      expectedIdentityVersion: expectedIdentityVersion,
      authorizationExpiresAt: authorizationExpiresAt,
    );
  }

  /// 0x 小写 hex 创世哈希;锁定本次授权只对该链有效。
  final String? genesisHashHex;

  /// 授权声明的身份版本;须等于链上当前值。
  final int? expectedIdentityVersion;

  /// 授权失效时间(Unix 秒)。
  final int? authorizationExpiresAt;

  final CitizenIdentityConsentLevel identityLevel;
  final String cidNumber;

  /// 0x 小写 hex,32 字节公民钱包公钥。
  final String accountId;

  /// SS58(prefix 走 kGmbSs58Prefix 单源)展示地址。
  final String ss58Address;

  /// YYYYMMDD 整数。
  final int validFrom;
  final int validUntil;

  /// true=NORMAL,false=REVOKED。
  final bool statusNormal;

  final String provinceCode;
  final String cityCode;
  final String townCode;
  final String? birthProvinceCode;
  final String? birthCityCode;
  final String? birthTownCode;
  final String? familyName;
  final String? givenName;
  final String? citizenSexLabel;

  /// 出生日期(YYYYMMDD 整数),仅竞选身份携带。
  final int? birthDate;

  bool get isCandidate =>
      identityLevel == CitizenIdentityConsentLevel.candidate;

  /// 解码完整授权字节,必须恰好消费完全部字节。
  ///
  /// 任何字段越界、长度非法、日期非法、状态未知都返回 null,
  /// 由调用方按"无法独立验证"拒签。
  static VotingIdentityConsentPayload? decode(Uint8List bytes) {
    const genesisHashLen = 32;
    const trailerLen = 16; // version(8) + expires_at(8)
    if (bytes.length <= genesisHashLen + trailerLen) return null;

    final inner = Uint8List.sublistView(
      bytes,
      genesisHashLen,
      bytes.length - trailerLen,
    );
    final decoded = _decodeCandidate(inner) ?? _decodeVotingRoot(inner);
    if (decoded == null) return null;

    return decoded.withAuthorization(
      genesisHashHex: _bytesToLowerHex(
        Uint8List.sublistView(bytes, 0, genesisHashLen),
      ),
      expectedIdentityVersion: _readU64Le(bytes, bytes.length - trailerLen),
      authorizationExpiresAt: _readU64Le(bytes, bytes.length - 8),
    );
  }

  /// 确认页展示条目,字段中文名与 citizenwallet 确认页一致。
  List<(String, String)> get reviewEntries => [
        ('身份类型', isCandidate ? '参选身份' : '投票身份'),
        ('CID编号', cidNumber),
        ('公民钱包账户', ss58Address),
        (
          '护照有效期',
          '${_formatDateInt(validFrom)} 至 ${_formatDateInt(validUntil)}'
        ),
        ('身份状态', statusNormal ? '正常' : '注销'),
        ('居住地', '$provinceCode / $cityCode / $townCode'),
        if (isCandidate) ...[
          (
            '出生地',
            '$birthProvinceCode / $birthCityCode / $birthTownCode',
          ),
          ('出生日期', birthDate == null ? '' : _formatDateInt(birthDate!)),
          ('公民姓名', '${familyName ?? ''}${givenName ?? ''}'),
          ('公民性别', citizenSexLabel ?? ''),
        ],
        if (authorizationExpiresAt != null)
          ('授权有效期至', _formatUnixSeconds(authorizationExpiresAt!)),
      ];

  static VotingIdentityConsentPayload? _decodeVotingRoot(Uint8List bytes) {
    final decoded = _readVotingIdentityPayload(bytes, 0);
    if (decoded == null || decoded.next != bytes.length) return null;
    return decoded.payload;
  }

  static VotingIdentityConsentPayload? _decodeCandidate(Uint8List bytes) {
    final voting = _readVotingIdentityPayload(bytes, 0);
    if (voting == null) return null;
    var offset = voting.next;

    final (birthProvinceCode, afterBirthProvince) =
        _readUtf8Vec(bytes, offset, maxLen: 16);
    if (birthProvinceCode == null) return null;
    offset = afterBirthProvince;
    final (birthCityCode, afterBirthCity) =
        _readUtf8Vec(bytes, offset, maxLen: 16);
    if (birthCityCode == null) return null;
    offset = afterBirthCity;
    final (birthTownCode, afterBirthTown) =
        _readUtf8Vec(bytes, offset, maxLen: 16);
    if (birthTownCode == null) return null;
    offset = afterBirthTown;
    final (familyName, afterFamilyName) =
        _readUtf8Vec(bytes, offset, maxLen: 128);
    if (familyName == null) return null;
    offset = afterFamilyName;
    final (givenName, afterGivenName) =
        _readUtf8Vec(bytes, offset, maxLen: 128);
    if (givenName == null) return null;
    offset = afterGivenName;
    if (offset >= bytes.length) return null;
    final sex = bytes[offset];
    offset += 1;
    final sexLabel = switch (sex) {
      0 => '男',
      1 => '女',
      _ => null,
    };
    if (sexLabel == null) return null;

    // birth_date: u32 YYYYMMDD(LE),CandidateIdentityPayload 末字段。
    if (offset + 4 > bytes.length) return null;
    final birthDate = _readU32Le(bytes, offset);
    offset += 4;
    if (!_isValidDateInt(birthDate) || offset != bytes.length) return null;

    final base = voting.payload;
    return VotingIdentityConsentPayload(
      identityLevel: CitizenIdentityConsentLevel.candidate,
      cidNumber: base.cidNumber,
      accountId: base.accountId,
      ss58Address: base.ss58Address,
      validFrom: base.validFrom,
      validUntil: base.validUntil,
      statusNormal: base.statusNormal,
      provinceCode: base.provinceCode,
      cityCode: base.cityCode,
      townCode: base.townCode,
      birthProvinceCode: birthProvinceCode,
      birthCityCode: birthCityCode,
      birthTownCode: birthTownCode,
      familyName: familyName,
      givenName: givenName,
      citizenSexLabel: sexLabel,
      birthDate: birthDate,
    );
  }

  static ({
    VotingIdentityConsentPayload payload,
    int next,
  })? _readVotingIdentityPayload(Uint8List bytes, int offset) {
    final (cidNumber, afterCid) = _readUtf8Vec(bytes, offset, maxLen: 32);
    if (cidNumber == null) return null;
    offset = afterCid;
    // 投票载荷不含年龄:account_id(32) + valid_from(4) + valid_until(4) + status(1)。
    if (offset + 32 + 4 + 4 + 1 > bytes.length) return null;

    final walletBytes = bytes.sublist(offset, offset + 32);
    offset += 32;

    final validFrom = _readU32Le(bytes, offset);
    offset += 4;
    final validUntil = _readU32Le(bytes, offset);
    offset += 4;
    if (!_isValidDateInt(validFrom) || !_isValidDateInt(validUntil)) {
      return null;
    }
    if (validUntil < validFrom) return null;

    final status = bytes[offset];
    offset += 1;
    if (status > 1) return null;

    final (provinceCode, afterProvince) =
        _readUtf8Vec(bytes, offset, maxLen: 16);
    if (provinceCode == null) return null;
    offset = afterProvince;
    final (cityCode, afterCity) = _readUtf8Vec(bytes, offset, maxLen: 16);
    if (cityCode == null) return null;
    offset = afterCity;
    final (townCode, afterTown) = _readUtf8Vec(bytes, offset, maxLen: 16);
    if (townCode == null) return null;
    offset = afterTown;

    return (
      payload: VotingIdentityConsentPayload(
        identityLevel: CitizenIdentityConsentLevel.voting,
        cidNumber: cidNumber,
        accountId: _bytesToLowerHex(walletBytes),
        ss58Address:
            Keyring().encodeAddress(walletBytes.toList(), kGmbSs58Prefix),
        validFrom: validFrom,
        validUntil: validUntil,
        statusNormal: status == 0,
        provinceCode: provinceCode,
        cityCode: cityCode,
        townCode: townCode,
      ),
      next: offset,
    );
  }

  static (String?, int) _readUtf8Vec(
    Uint8List bytes,
    int offset, {
    required int maxLen,
  }) {
    if (offset >= bytes.length) return (null, offset);
    final (len, lenSize) = _decodeCompactU32(bytes, offset);
    if (lenSize == 0) return (null, offset);
    offset += lenSize;
    if (len <= 0 || len > maxLen || offset + len > bytes.length) {
      return (null, offset);
    }
    final text = utf8.decode(
      bytes.sublist(offset, offset + len),
      allowMalformed: false,
    );
    if (text.trim().isEmpty) return (null, offset);
    return (text, offset + len);
  }

  /// 解码 SCALE `Compact<u32>`,返回 (值, 消耗字节数);big-int 模式不会出现在
  /// 本载荷的长度前缀里,按非法处理。
  static (int, int) _decodeCompactU32(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return (0, 0);
    final first = bytes[offset];
    switch (first & 0x03) {
      case 0:
        return (first >> 2, 1);
      case 1:
        if (offset + 2 > bytes.length) return (0, 0);
        return ((first | (bytes[offset + 1] << 8)) >> 2, 2);
      case 2:
        if (offset + 4 > bytes.length) return (0, 0);
        final value = first |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24);
        return (value >> 2, 4);
      default:
        return (0, 0);
    }
  }

  static int _readU64Le(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | bytes[offset + i];
    }
    return value;
  }

  /// Unix 秒 → 本地时区 `YYYY-MM-DD HH:mm`。
  static String _formatUnixSeconds(int seconds) {
    final local =
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
            .toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static int _readU32Le(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static bool _isValidDateInt(int value) {
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    return year >= 1900 &&
        year <= 9999 &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= 31;
  }

  static String _formatDateInt(int value) {
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  static String _bytesToLowerHex(Uint8List bytes) {
    return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
