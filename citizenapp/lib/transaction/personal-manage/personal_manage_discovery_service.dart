// 个人多签反向索引发现:后处理(ADR-018 §九)。
//
// 从 AdminAccounts 单次扫描结果(AdminAccountsScanService)里筛出个人多签
// (kind=Personal,且管理员含本地钱包),反查发起人 / 账户名后 upsert
// `PersonalAccountEntity`。机构账户登记与展示不走本服务。

import 'package:citizenapp/log/app_log.dart';
import 'package:isar_community/isar.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/admin_account_storage_codec.dart';
import 'package:citizenapp/citizen/shared/admin_accounts_scan_service.dart';
import 'package:citizenapp/isar/wallet_isar.dart';

import 'personal_manage_service.dart';

/// 个人多签后处理统计。
class PersonalManageDiscoveryStats {
  const PersonalManageDiscoveryStats({
    required this.subjectsScanned,
    required this.matchedPersonals,
    required this.newlyAdded,
    required this.orphansRemoved,
    required this.elapsed,
    this.partialFailure = false,
  });

  final int subjectsScanned;
  final int matchedPersonals;
  final int newlyAdded;
  final int orphansRemoved;
  final Duration elapsed;
  final bool partialFailure;

  static const empty = PersonalManageDiscoveryStats(
    subjectsScanned: 0,
    matchedPersonals: 0,
    newlyAdded: 0,
    orphansRemoved: 0,
    elapsed: Duration.zero,
  );
}

class PersonalManageDiscoveryService {
  PersonalManageDiscoveryService({
    required PersonalManageService personalManageService,
  }) : _personalManage = personalManageService;

  final PersonalManageService _personalManage;

  /// 处理一次共享扫描结果:筛出我的个人多签 → 批量反查发起人/账户名 → upsert Isar + 孤儿校验。
  Future<PersonalManageDiscoveryStats> processScanned(
    AdminAccountsScanResult scan, {
    required Set<String> myAccountIds,
  }) async {
    final start = DateTime.now();

    final mine = AdminAccountsScanService.filterMine(
      scan,
      myAccountIds: myAccountIds,
      kind: AdminAccountStorageCodec.kindPersonal,
      codeWhitelist: const {'PMUL'},
    );

    // 批量反查发起人/账户名(PersonalAccounts 精确整键)。
    Map<String, ({String creatorAccountId, String accountName})?> metas;
    try {
      metas = await _personalManage.fetchPersonalMetasBatch(
        mine.map((a) => a.personalAccountId!),
      );
    } catch (e) {
      AppLog.d('[PersonalManageDiscovery] 批量反查个人多签元数据失败: $e');
      // 反查整体失败时不做孤儿状态变更,避免把瞬时 RPC 失败误判为注销。
      return PersonalManageDiscoveryStats(
        subjectsScanned: scan.totalKeys,
        matchedPersonals: mine.length,
        newlyAdded: 0,
        orphansRemoved: 0,
        elapsed: DateTime.now().difference(start),
        partialFailure: true,
      );
    }

    final scannedAccountIds = <String>{};
    var newlyAdded = 0;

    for (final acc in mine) {
      final personalAccountId = acc.personalAccountId!;
      final meta = metas[personalAccountId];
      if (meta == null) continue;
      scannedAccountIds.add(personalAccountId);
      final added = await _upsertPersonal(
        accountId: personalAccountId,
        name: meta.accountName,
        creatorAccountId: meta.creatorAccountId,
        matchedAdminAccountIds: acc.admins
            .map((admin) => admin.account_id)
            .where(myAccountIds.contains)
            .toList(growable: false),
      );
      if (added) newlyAdded++;
    }

    final orphans = await _reverseValidateAndDelete(scannedAccountIds);

    return PersonalManageDiscoveryStats(
      subjectsScanned: scan.totalKeys,
      matchedPersonals: mine.length,
      newlyAdded: newlyAdded,
      orphansRemoved: orphans,
      elapsed: DateTime.now().difference(start),
      partialFailure: scan.partialFailure,
    );
  }

  Future<bool> _upsertPersonal({
    required String accountId,
    required String name,
    required String creatorAccountId,
    required List<String> matchedAdminAccountIds,
  }) async {
    final normalizedCreatorAccountId = _requireAccountId(creatorAccountId);
    final personalAccountId = _requireAccountId(accountId);

    return WalletIsar.instance.writeTxn((isar) async {
      final exists = await isar.personalAccountEntitys
          .filter()
          .accountIdEqualTo(personalAccountId)
          .findFirst();

      if (exists != null) {
        if (!exists.discoveredViaAdmin) return false;
        exists.matchedAdminAccountIds = matchedAdminAccountIds;
        await isar.personalAccountEntitys.put(exists);
        await PersonalMultisigLocalState.putStatusInTxn(
          isar,
          accountId,
          PersonalMultisigLocalState.statusActive,
        );
        return false;
      }

      final entity = PersonalAccountEntity()
        ..accountId = personalAccountId
        ..accountName = name
        ..creatorAccountId = normalizedCreatorAccountId
        ..addedAtMillis = DateTime.now().millisecondsSinceEpoch
        ..discoveredViaAdmin = true
        ..matchedAdminAccountIds = matchedAdminAccountIds;
      await isar.personalAccountEntitys.put(entity);
      await PersonalMultisigLocalState.putStatusInTxn(
        isar,
        accountId,
        PersonalMultisigLocalState.statusActive,
      );
      return true;
    });
  }

  Future<int> _reverseValidateAndDelete(Set<String> scannedAccountIds) async {
    var closed = 0;
    await WalletIsar.instance.writeTxn((isar) async {
      final stalePersonals = await isar.personalAccountEntitys
          .filter()
          .discoveredViaAdminEqualTo(true)
          .findAll();
      for (final p in stalePersonals) {
        if (!scannedAccountIds.contains(_requireAccountId(p.accountId))) {
          // 链上注销后仍保留本地账户入口，只把状态标成已注销；
          // 用户在详情页点“删除”时才真正清空本机数据。
          await PersonalMultisigLocalState.putStatusInTxn(
            isar,
            p.accountId,
            PersonalMultisigLocalState.statusClosed,
          );
          closed++;
        }
      }
    });
    return closed;
  }

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }
}
