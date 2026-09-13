import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/institution/institution_role_models.dart';
import 'package:citizenapp/citizen/institution/institution_role_storage_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/codec/account_id_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_account_service.dart';

class InstitutionAdminState {
  const InstitutionAdminState({
    required this.admins,
    this.assignments = const [],
    this.threshold,
  });

  final List<AdminPerson> admins;

  /// 机构岗位任职；个人多签不使用本字段。
  final List<InstitutionAdminAssignment> assignments;
  final int? threshold;
}

/// 管理员查询门面。
///
/// 调用方必须传入明确的 `AdminAccountIdentity`，不再把
/// `cidNumber` 当作个人多签、机构账户和治理机构共用的模糊参数。
class InstitutionAdminService {
  InstitutionAdminService({required CitizenChain chain})
      : _chain = chain,
        _accountService = AdminAccountService(chain: chain);

  final CitizenChain _chain;
  final AdminAccountService _accountService;

  Future<List<AdminPerson>> fetchAdmins(AdminAccountIdentity identity) {
    return _accountService.fetchAdmins(identity);
  }

  /// 从 entity 读取机构岗位和有效任职，并与独立 admins 钱包集合交叉校验。
  /// 管理员可以暂时不担任任何岗位，因此不要求岗位任职覆盖全部管理员。
  Future<List<InstitutionAdminAssignment>> fetchAssignments(
    AdminAccountIdentity identity,
    String cidNumber,
  ) async {
    if (identity.type == AdminAccountIdentityType.personalAccount) {
      throw ArgumentError('个人多签不属于机构岗位模型');
    }
    final adminState = await _accountService.fetchByIdentity(identity);
    if (adminState == null) return const [];
    final adminSet = adminState.admins.map((admin) => admin.account_id).toSet();
    // 非法人机构码本身不能推断公权/私权，必须按链上管理员类型路由。
    final entityPallet = identity.kind == 1 ? 'PrivateManage' : 'PublicManage';
    final roleValues =
        await _scanValues(entityPallet, 'InstitutionRoles', cidNumber);
    final assignmentValues = await _scanValues(
        entityPallet, 'InstitutionRoleAssignments', cidNumber);
    final roles = <String, InstitutionRole>{};
    for (final value in roleValues) {
      final role = InstitutionRoleStorageCodec.decodeRole(value);
      if (role != null &&
          role.cidNumber == cidNumber &&
          role.status == InstitutionRoleStatus.active) {
        roles[role.roleCode] = role;
      }
    }
    final out = <InstitutionAdminAssignment>[];
    final currentDay = DateTime.now().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    for (final value in assignmentValues) {
      final decoded = InstitutionRoleStorageCodec.decodeAssignments(value);
      if (decoded == null) continue;
      for (final assignment in decoded) {
        final role = roles[assignment.roleCode];
        if (assignment.cidNumber == cidNumber &&
            role != null &&
            adminSet.contains(assignment.account_id)) {
          final effective = assignment.withRole(role);
          if (effective.isEffectiveOnDay(currentDay)) out.add(effective);
        }
      }
    }
    return out;
  }

  /// 以管理员人员集合为主表左连接岗位任职；管理员无岗位时仍返回人员行。
  Future<List<InstitutionAdminView>> fetchAdminViews(
    AdminAccountIdentity identity,
    String cidNumber,
  ) async {
    final account = await _accountService.fetchByIdentity(identity);
    if (account == null) return const [];
    final assignments = await fetchAssignments(identity, cidNumber);
    return mergeAdminViews(account.admins, assignments);
  }

  /// 纯函数合并人员与岗位，供链读和测试共用；结果顺序严格跟随 admins 真源。
  static List<InstitutionAdminView> mergeAdminViews(
    List<AdminPerson> admins,
    List<InstitutionAdminAssignment> assignments,
  ) {
    final byAccount = <String, List<InstitutionAdminAssignment>>{};
    for (final assignment in assignments) {
      byAccount.putIfAbsent(assignment.account_id, () => []).add(assignment);
    }
    return admins
        .map(
          (admin) => InstitutionAdminView(
            admin: admin,
            assignments: List.unmodifiable(
              byAccount[admin.account_id] ?? const [],
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<int?> fetchThreshold(AdminAccountIdentity identity) {
    return _accountService.fetchThreshold(identity);
  }

  Future<bool> isAdmin(String accountId, AdminAccountIdentity identity) {
    return _accountService.isAdmin(accountId, identity);
  }

  Future<InstitutionAdminState> fetchState(
    AdminAccountIdentity identity, {
    String? cidNumber,
  }) async {
    final account = await _accountService.fetchByIdentity(identity);
    final assignments = cidNumber == null
        ? const <InstitutionAdminAssignment>[]
        : await fetchAssignments(identity, cidNumber);
    return InstitutionAdminState(
      admins: account?.admins ?? const [],
      assignments: assignments,
      threshold: account?.threshold,
    );
  }

  void clearCache([AdminAccountIdentity? identity]) {
    _accountService.clearCache(identity);
  }

  Future<List<Uint8List>> _scanValues(
      String pallet, String storage, String cidNumber) async {
    final prefix =
        _doubleMapFirstKeyPrefix(pallet, storage, utf8.encode(cidNumber));
    final finalized = await _chain.getFinalizedHead();
    final keys = <Uint8List>[];
    Uint8List? startKey;
    while (true) {
      final page = await _chain.getStorageKeysPaged(
        finalized,
        prefix,
        startKey: startKey,
        limit: 256,
      );
      if (page.isEmpty) break;
      keys.addAll(page);
      if (page.length < 256) break;
      startKey = page.last;
    }
    if (keys.isEmpty) return const [];
    final values = <Uint8List>[];
    for (var offset = 0; offset < keys.length; offset += 100) {
      final end = (offset + 100).clamp(0, keys.length);
      final rows = await _chain.getStorageBatch(
        finalized,
        keys.sublist(offset, end),
      );
      values.addAll(rows.whereType<Uint8List>());
    }
    return values;
  }

  Uint8List _doubleMapFirstKeyPrefix(
      String pallet, String storage, List<int> cidBytes) {
    final encodedCid =
        Uint8List.fromList([(cidBytes.length << 2), ...cidBytes]);
    final parts = [
      Hasher.twoxx128.hashString(pallet),
      Hasher.twoxx128.hashString(storage),
      AdminAccountIdCodec.blake2128Concat(encodedCid),
    ];
    return Uint8List.fromList(
        parts.expand((part) => part).toList(growable: false));
  }

}
