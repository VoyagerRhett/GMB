import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'institution_models.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// 机构管理提案解码服务（公权/私权共用）。
///
/// 机构身份只能由 `cid_number` 表示；具体命名账户只是提案的
/// `institution_account_id` 参数，不反向作为机构主键。
///
/// 管理员投票一律走 `InternalVote::cast`(经 InternalVoteService),不在本服务。
class InstitutionChainService {
  // ──── 常量 ────

  /// ProposalData 中机构管理提案的 action 类型:ACTION_CLOSE=2(关闭机构多签)。
  static const actionClose = 2;

  /// 从 ProposalData 解码机构多签管理(关闭)提案,供提案列表/详情只读展示。
  ///
  /// ProposalData = `BoundedVec<u8>(Compact<len> + bytes)`;机构管理提案以 MODULE_TAG 前缀认领,
  /// 公权=`pub-mgmt`、私权=`pri-mgmt`(取代旧 `org-mgmt`),其后 ACTION_CLOSE(2):
  /// actor_cid_number + institution_account_id(32) + beneficiary(32) + proposer(32)。
  /// 个人多签提案解码在 `PersonalManageService`。
  static const _publicManageTag = [
    0x70, 0x75, 0x62, 0x2d, 0x6d, 0x67, 0x6d, 0x74, // "pub-mgmt"
  ];
  static const _privateManageTag = [
    0x70, 0x72, 0x69, 0x2d, 0x6d, 0x67, 0x6d, 0x74, // "pri-mgmt"
  ];

  Object? decodeManageProposalData(int proposalId, Uint8List raw) {
    try {
      var offset = 0;

      // BoundedVec<u8> 外层：Compact<len> + bytes
      final (vecLen, lenBytes) = _decodeCompact(raw, offset);
      offset += lenBytes;
      if (offset + vecLen != raw.length) return null;
      final data = raw.sublist(offset, offset + vecLen);

      // 公权/私权机构管理提案各自 MODULE_TAG(8 字节)。
      const tagLen = 8;
      final tag = _startsWith(data, _publicManageTag) ||
          _startsWith(data, _privateManageTag);
      if (!tag) return null;
      final actionType = data[tagLen];
      final payload = data.sublist(tagLen + 1);
      if (actionType == actionClose) {
        return _decodeCloseAction(proposalId, payload);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  CloseProposalInfo? _decodeCloseAction(int proposalId, Uint8List data) {
    var offset = 0;

    final (cidLen, cidLenBytes) = _decodeCompact(data, offset);
    offset += cidLenBytes;
    if (cidLen <= 0 || cidLen > 32 || offset + cidLen + 96 != data.length) {
      return null;
    }
    final actorCidNumber = utf8.decode(
      data.sublist(offset, offset + cidLen),
      allowMalformed: false,
    );
    offset += cidLen;

    final accountId =
        _hexEncode(Uint8List.fromList(data.sublist(offset, offset + 32)));
    offset += 32;

    final beneficiaryBytes = data.sublist(offset, offset + 32);
    final beneficiarySs58 =
        Keyring().encodeAddress(Uint8List.fromList(beneficiaryBytes), kGmbSs58Prefix);
    offset += 32;

    final proposerBytes = data.sublist(offset, offset + 32);
    final proposerSs58 =
        Keyring().encodeAddress(Uint8List.fromList(proposerBytes), kGmbSs58Prefix);

    return CloseProposalInfo(
      proposalId: proposalId,
      actorCidNumber: actorCidNumber,
      institutionAccountId: accountId,
      beneficiary: beneficiarySs58,
      proposer: proposerSs58,
    );
  }

  // ──── 内部：解码工具 ────

  bool _startsWith(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length + 1) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }

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
      final lenBytes = (first >> 2) + 4;
      var val = 0;
      for (var i = lenBytes - 1; i >= 0; i--) {
        val = (val << 8) | data[offset + 1 + i];
      }
      return (val, 1 + lenBytes);
    }
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
