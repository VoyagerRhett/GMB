// 分类管理员模块 `AdminAccounts` 链上扫描。
//
// 管理员身份和个人多签发现都依赖链上 `AdminAccounts` 反向索引。本服务把
// "翻页 getKeysPaged + 批量 fetchStorageBatch + 解码 + 提取账户"收敛为一次扫描,
// 产出已解码条目。调用方必须显式选择要扫描的分类管理员 pallet，个人多签只扫
// `PersonalAdmins`，钱包管理员标签则扫描公权、私权和个人三类。
//
// 扫描直接调用 CitizenChain 的 finalized **短前缀分页**
// (prefix = twox128(pallet) || twox128(storage),
// 无嵌长 K1)。

import 'package:flutter/foundation.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/shared/admin_account_storage_codec.dart';

/// 单条已解码的 AdminAccount 记录(地址 + 过滤所需字段)。
@immutable
class ScannedAdminAccount {
  const ScannedAdminAccount({
    this.cidNumber,
    this.personalAccountId,
    required this.institutionCode,
    required this.kind,
    required this.admins,
  }) : assert((cidNumber == null) != (personalAccountId == null));

  /// 机构管理员表的唯一主键。
  final String? cidNumber;

  /// 个人多签管理员表的唯一主键。
  final String? personalAccountId;

  /// 4 字节机构码字符串（"NRC"/"PRC"/"PRB"/"PMUL"/"CGOV" 等）。
  final String institutionCode;

  /// 管理员账户类型(0=Public,1=Private,2=Personal)。
  final int kind;

  /// 完整管理员人员集合；账户使用规范 AccountId，姓、名只用于展示。
  final List<AdminPerson> admins;
}

/// 一次全表扫描的结果。
@immutable
class AdminAccountsScanResult {
  const AdminAccountsScanResult({
    required this.accounts,
    required this.totalKeys,
    required this.partialFailure,
  });

  /// 全部成功解码的条目(未过滤)。
  final List<ScannedAdminAccount> accounts;

  /// 扫描到的 storage key 总数(含未能解码者),用于统计。
  final int totalKeys;

  /// 翻页或批量读取过程中出现过失败(结果可能不完整)。
  final bool partialFailure;

  static const empty = AdminAccountsScanResult(
    accounts: <ScannedAdminAccount>[],
    totalKeys: 0,
    partialFailure: false,
  );
}

/// 分类管理员 `AdminAccounts` 单次扫描服务。
class AdminAccountsScanService {
  AdminAccountsScanService({
    required CitizenChain chain,
    this.palletNames = const ['PersonalAdmins'],
  }) : _chain = chain {
    if (palletNames.isEmpty) {
      throw ArgumentError.value(palletNames, 'palletNames', '不能为空');
    }
  }

  final CitizenChain _chain;

  /// 本次扫描的分类管理员 pallet；只允许当前链上三张管理员表。
  final List<String> palletNames;

  static const Set<String> _allowedPalletNames = {
    'PublicAdmins',
    'PrivateAdmins',
    'PersonalAdmins',
  };

  /// 翻页大小。
  static const _pageSize = 256;

  /// 单批 storage 读取上限(防 RPC 超时)。
  static const _batchSize = 100;

  /// 全表扫描 AdminAccounts,返回全部已解码条目。
  ///
  /// [onProgress] 进度回调:(已扫描 key 数, 已知总数或 null, 已解码条目数)。
  Future<AdminAccountsScanResult> scanAll({
    void Function(int scanned, int? total, int decoded)? onProgress,
  }) async {
    final finalized = await _chain.getFinalizedHead();
    final allKeys = <Uint8List>[];
    final kinds = <int>[];
    var partialFailure = false;

    for (final entry in _adminAccountsPrefixes()) {
      Uint8List? startKey;
      while (true) {
        List<Uint8List> page;
        try {
          page = await _chain.getStorageKeysPaged(
            finalized,
            entry.prefix,
            startKey: startKey,
            limit: _pageSize,
          );
        } catch (e) {
          AppLog.d('[AdminAccountsScan] getKeysPaged 失败: $e');
          partialFailure = true;
          break;
        }
        if (page.isEmpty) break;
        allKeys.addAll(page);
        kinds.addAll(List<int>.filled(page.length, entry.kind));
        onProgress?.call(allKeys.length, null, 0);
        if (page.length < _pageSize) break;
        startKey = page.last;
      }
    }

    final accounts = <ScannedAdminAccount>[];
    for (var start = 0; start < allKeys.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, allKeys.length);
      final batchKeys = allKeys.sublist(start, end);

      List<Uint8List?> values;
      try {
        values = await _chain.getStorageBatch(finalized, batchKeys);
      } catch (e) {
        AppLog.d('[AdminAccountsScan] fetchStorageBatch 失败: $e');
        partialFailure = true;
        continue;
      }

      for (var index = 0; index < batchKeys.length; index++) {
        final keyBytes = batchKeys[index];
        final value = values[index];
        if (value == null) continue;
        final kind = kinds[start + index];
        final decoded = AdminAccountStorageCodec.tryDecode(value, kind: kind);
        if (decoded == null) continue;
        if (kind == AdminAccountStorageCodec.kindPersonal) {
          final accountIdBytes =
              AdminAccountStorageCodec.extractPersonalAccountFromKey(keyBytes);
          if (accountIdBytes == null) continue;
          final accountId =
              AdminAccountStorageCodec.accountIdText(accountIdBytes);
          if (accountId == null) continue;
          accounts.add(ScannedAdminAccount(
            personalAccountId: accountId,
            institutionCode: decoded.institutionCode,
            kind: decoded.kind,
            admins: decoded.admins,
          ));
        } else {
          final cidNumber =
              AdminAccountStorageCodec.extractCidNumberFromKey(keyBytes);
          if (cidNumber == null) continue;
          accounts.add(ScannedAdminAccount(
            cidNumber: cidNumber,
            institutionCode: decoded.institutionCode,
            kind: decoded.kind,
            admins: decoded.admins,
          ));
        }
      }
      onProgress?.call(allKeys.length, allKeys.length, accounts.length);
    }

    return AdminAccountsScanResult(
      accounts: accounts,
      totalKeys: allKeys.length,
      partialFailure: partialFailure,
    );
  }

  /// 纯函数:从扫描结果里筛出"我的"账户(指定 kind,可选机构码白名单,
  /// 且管理员集合含本地任一钱包账户 ID)。供个人多签发现复用,便于单测。
  static List<ScannedAdminAccount> filterMine(
    AdminAccountsScanResult scan, {
    required Set<String> myAccountIds,
    int? kind,
    Set<int>? kinds,
    Set<String>? codeWhitelist,
  }) {
    final acceptedKinds = kinds ?? (kind == null ? const <int>{} : {kind});
    return scan.accounts
        .where(
          (a) =>
              acceptedKinds.contains(a.kind) &&
              (codeWhitelist == null ||
                  codeWhitelist.contains(a.institutionCode)) &&
              a.admins.any(
                (admin) => myAccountIds.contains(admin.account_id),
              ),
        )
        .toList(growable: false);
  }

  /// 每个短 prefix 同时携带 pallet 决定的主体类型，禁止再从 value 猜 kind。
  List<({Uint8List prefix, int kind})> _adminAccountsPrefixes() {
    final invalid =
        palletNames.where((name) => !_allowedPalletNames.contains(name));
    if (invalid.isNotEmpty) {
      throw ArgumentError.value(
        invalid.join(','),
        'palletNames',
        '包含未知分类管理员 pallet',
      );
    }
    return palletNames
        .toSet()
        .map((palletName) => (
              prefix: _adminAccountsPrefix(palletName),
              kind: switch (palletName) {
                'PublicAdmins' =>
                  AdminAccountStorageCodec.kindPublicInstitution,
                'PrivateAdmins' =>
                  AdminAccountStorageCodec.kindPrivateInstitution,
                'PersonalAdmins' => AdminAccountStorageCodec.kindPersonal,
                _ => throw StateError('未知管理员 pallet'),
              },
            ))
        .toList(growable: false);
  }

  Uint8List _adminAccountsPrefix(String palletName) {
    final palletHash = Hasher.twoxx128.hashString(palletName);
    final storageHash = Hasher.twoxx128.hashString('AdminAccounts');
    final prefix = Uint8List(palletHash.length + storageHash.length);
    prefix.setAll(0, palletHash);
    prefix.setAll(palletHash.length, storageHash);
    return prefix;
  }
}
