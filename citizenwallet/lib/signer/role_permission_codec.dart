import 'dart:convert';
import 'dart:typed_data';

/// 岗位业务权限操作，序号与 runtime SCALE 枚举一致。
enum RolePermissionOperation { propose, vote }

/// 业务模块静态指定的投票引擎，序号与 runtime SCALE 枚举一致。
enum VotingEngineKind { internal, joint, election, legislation }

/// 完整机构岗位授权主体。
class RoleSubject {
  const RoleSubject({required this.cidNumber, required this.roleCode});

  final String cidNumber;
  final String roleCode;
}

/// 业务模块与模块内动作的稳定标识。
class BusinessActionId {
  const BusinessActionId({required this.moduleTag, required this.actionCode});

  final String moduleTag;
  final int actionCode;
}

/// 一条完整岗位业务权限。
class RoleBusinessPermission {
  const RoleBusinessPermission({
    required this.roleSubject,
    required this.businessActionId,
    required this.operation,
  });

  final RoleSubject roleSubject;
  final BusinessActionId businessActionId;
  final RolePermissionOperation operation;
}

/// 机构岗位或个人多签授权主体。
class AuthorizationSubject {
  const AuthorizationSubject.institution(this.roleSubject)
    : personalAccountHex = null;

  const AuthorizationSubject.personalMultisig(this.personalAccountHex)
    : roleSubject = null;

  final RoleSubject? roleSubject;
  final String? personalAccountHex;

  bool get isInstitution => roleSubject != null;
}

/// 业务模块在创建提案时绑定的完整投票计划。
class VotePlan {
  const VotePlan({
    required this.businessActionId,
    required this.proposalOwner,
    required this.proposerSubject,
    required this.voterSubjects,
    required this.votingEngine,
    required this.businessObjectHash,
  });

  final BusinessActionId businessActionId;
  final String proposalOwner;
  final AuthorizationSubject proposerSubject;
  final List<AuthorizationSubject> voterSubjects;
  final VotingEngineKind votingEngine;
  final String businessObjectHash;
}

/// 岗位权限与 VotePlan 的严格 SCALE 解码器。
///
/// 任一未知枚举、畸形 UTF-8、重复主体、机构/个人混用或尾随字节都返回 `null`，
/// 公民钱包不得猜测或忽略未知载荷。
class RolePermissionCodec {
  RolePermissionCodec._();

  static RoleSubject? decodeRoleSubject(Uint8List data) {
    final decoded = _decodeRoleSubjectAt(data, 0);
    return decoded != null && decoded.$2 == data.length ? decoded.$1 : null;
  }

  static BusinessActionId? decodeBusinessActionId(Uint8List data) {
    final decoded = _decodeBusinessActionIdAt(data, 0);
    return decoded != null && decoded.$2 == data.length ? decoded.$1 : null;
  }

  static RoleBusinessPermission? decodeRoleBusinessPermission(Uint8List data) {
    final role = _decodeRoleSubjectAt(data, 0);
    if (role == null) return null;
    final action = _decodeBusinessActionIdAt(data, role.$2);
    if (action == null || action.$2 >= data.length) return null;
    final operation = data[action.$2];
    if (operation >= RolePermissionOperation.values.length ||
        action.$2 + 1 != data.length) {
      return null;
    }
    return RoleBusinessPermission(
      roleSubject: role.$1,
      businessActionId: action.$1,
      operation: RolePermissionOperation.values[operation],
    );
  }

  static AuthorizationSubject? decodeAuthorizationSubject(Uint8List data) {
    final decoded = _decodeAuthorizationSubjectAt(data, 0);
    return decoded != null && decoded.$2 == data.length ? decoded.$1 : null;
  }

  static VotePlan? decodeVotePlan(Uint8List data) {
    final action = _decodeBusinessActionIdAt(data, 0);
    if (action == null) return null;
    final owner = _readUtf8(data, action.$2, minLength: 1, maxLength: 32);
    if (owner == null || owner.$1 != action.$1.moduleTag) return null;
    final proposer = _decodeAuthorizationSubjectAt(data, owner.$2);
    if (proposer == null) return null;
    final count = _readCompact(data, proposer.$2);
    if (count == null || count.$1 < 1 || count.$1 > 256) return null;
    var offset = proposer.$2 + count.$2;
    final voters = <AuthorizationSubject>[];
    final voterKeys = <String>{};
    for (var index = 0; index < count.$1; index++) {
      final voter = _decodeAuthorizationSubjectAt(data, offset);
      if (voter == null) return null;
      offset = voter.$2;
      final key = voter.$1.isInstitution
          ? 'i:${voter.$1.roleSubject!.cidNumber}:${voter.$1.roleSubject!.roleCode}'
          : 'p:${voter.$1.personalAccountHex}';
      if (!voterKeys.add(key)) return null;
      voters.add(voter.$1);
    }
    if (offset >= data.length) return null;
    final engine = data[offset++];
    if (engine >= VotingEngineKind.values.length ||
        offset + 32 != data.length) {
      return null;
    }
    if (proposer.$1.isInstitution) {
      if (voters.any((voter) => !voter.isInstitution)) return null;
    } else {
      if (voters.length != 1 ||
          voters.single.isInstitution ||
          voters.single.personalAccountHex != proposer.$1.personalAccountHex) {
        return null;
      }
    }
    return VotePlan(
      businessActionId: action.$1,
      proposalOwner: owner.$1,
      proposerSubject: proposer.$1,
      voterSubjects: List.unmodifiable(voters),
      votingEngine: VotingEngineKind.values[engine],
      businessObjectHash: _hex(data.sublist(offset, offset + 32)),
    );
  }

  static (RoleSubject, int)? _decodeRoleSubjectAt(Uint8List data, int offset) {
    final cid = _readUtf8(data, offset, minLength: 1, maxLength: 32);
    if (cid == null) return null;
    final roleCode = _readUtf8(data, cid.$2, minLength: 1, maxLength: 64);
    if (roleCode == null) return null;
    return (RoleSubject(cidNumber: cid.$1, roleCode: roleCode.$1), roleCode.$2);
  }

  static (BusinessActionId, int)? _decodeBusinessActionIdAt(
    Uint8List data,
    int offset,
  ) {
    final moduleTag = _readUtf8(data, offset, minLength: 1, maxLength: 32);
    if (moduleTag == null || moduleTag.$2 + 4 > data.length) return null;
    final actionCode = ByteData.sublistView(data)
        .getUint32(moduleTag.$2, Endian.little);
    return (
      BusinessActionId(moduleTag: moduleTag.$1, actionCode: actionCode),
      moduleTag.$2 + 4,
    );
  }

  static (AuthorizationSubject, int)? _decodeAuthorizationSubjectAt(
    Uint8List data,
    int offset,
  ) {
    if (offset >= data.length) return null;
    final kind = data[offset++];
    if (kind == 0) {
      final role = _decodeRoleSubjectAt(data, offset);
      return role == null
          ? null
          : (AuthorizationSubject.institution(role.$1), role.$2);
    }
    if (kind == 1 && offset + 32 <= data.length) {
      return (
        AuthorizationSubject.personalMultisig(
          _hex(data.sublist(offset, offset + 32)),
        ),
        offset + 32,
      );
    }
    return null;
  }

  static (String, int)? _readUtf8(
    Uint8List data,
    int offset, {
    required int minLength,
    required int maxLength,
  }) {
    final value = _readBytes(
      data,
      offset,
      minLength: minLength,
      maxLength: maxLength,
    );
    if (value == null) return null;
    try {
      return (utf8.decode(value.$1), value.$2);
    } on FormatException {
      return null;
    }
  }

  static (Uint8List, int)? _readBytes(
    Uint8List data,
    int offset, {
    int minLength = 0,
    required int maxLength,
  }) {
    final compact = _readCompact(data, offset);
    if (compact == null || compact.$1 < minLength || compact.$1 > maxLength) {
      return null;
    }
    final start = offset + compact.$2;
    final end = start + compact.$1;
    if (end > data.length) return null;
    return (Uint8List.sublistView(data, start, end), end);
  }

  static (int, int)? _readCompact(Uint8List data, int offset) {
    if (offset >= data.length) return null;
    final first = data[offset];
    final mode = first & 3;
    if (mode == 0) return (first >> 2, 1);
    if (mode == 1 && offset + 2 <= data.length) {
      return ((((data[offset + 1] << 8) | first) >> 2), 2);
    }
    if (mode == 2 && offset + 4 <= data.length) {
      final raw = ByteData.sublistView(data).getUint32(offset, Endian.little);
      return (raw >> 2, 4);
    }
    return null;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
