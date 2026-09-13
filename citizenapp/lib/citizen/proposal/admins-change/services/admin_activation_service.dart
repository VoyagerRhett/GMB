import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/institution_code_label.dart';
import 'package:citizenapp/signer/signing.dart';
import 'package:citizenapp/isar/wallet_isar.dart';

/// 管理员激活记录。
class ActivatedAdmin {
  const ActivatedAdmin({
    required this.accountId,
    required this.cidNumber,
    required this.institutionCode,
    required this.kind,
    required this.activatedAtMs,
  });

  /// 管理员账户 ID（小写 `0x` 加 64 位十六进制）。
  final String accountId;

  /// 机构唯一主键；管理员激活不再绑定任一机构账户。
  final String cidNumber;

  /// 链上 institution_code（4 字节机构码字符串，如 "NRC"/"PMUL"/"CGOV"）。
  final String institutionCode;

  /// 链上 AdminAccountKind 编码。
  final int kind;

  /// 激活时间（毫秒时间戳）。
  final int activatedAtMs;

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'cid_number': cidNumber,
    'institution_code': institutionCode,
    'kind': kind,
    'activated_at_ms': activatedAtMs,
  };

  factory ActivatedAdmin.fromJson(Map<String, dynamic> json) => ActivatedAdmin(
    accountId: json['account_id'] as String,
    cidNumber: json['cid_number'] as String,
    institutionCode: json['institution_code'] as String,
    kind: json['kind'] as int,
    activatedAtMs: json['activated_at_ms'] as int,
  );
}

/// 管理员激活服务。App 构造并审阅业务 payload，CitizenSDK 按账户冷热模式完成签名，
/// 本服务随后复核链上管理员账户并写入本地激活记录。
class ActivationService {
  ActivationService({required InstitutionAdminService adminService})
    : _adminService = adminService;

  final InstitutionAdminService _adminService;

  /// AccountId 级管理员激活 payload 4 字节二进制前缀 = GMB || 0x18。
  ///
  /// 二进制前缀域:此前缀**内嵌在被签 payload 字节里**
  /// (冷钱包对整段 payloadHex 直接 sr25519 签名,node 按字节偏移解析),不经
  /// signingMessage 做 blake2 hash。
  /// 四方逐字节锁步:node activation.rs(build/decode)、冷钱包
  /// payload_decoder.dart、本服务。前缀单源对齐 primitives::sign::
  /// binary_domain_prefix,金标见 test/signer/fixtures/
  /// binary_prefix_domain_vectors.json。
  // 读取
  /// 加载所有激活记录。
  Future<List<ActivatedAdmin>> loadAll() async {
    final raw = await WalletIsar.instance.read((isar) async {
      return (await isar.walletAdminActivationStateEntitys.get(0))?.payloadJson;
    });
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ActivatedAdmin.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取指定管理员账户的已激活管理员，并与链上管理员列表交叉校验。
  Future<List<ActivatedAdmin>> getActivatedAdmins(
    AdminAccountIdentity identity,
  ) async {
    final cidNumber = _requireInstitutionCid(identity);
    var all = await loadAll();
    final institutionRecords = all
        .where((item) => item.cidNumber == cidNumber)
        .toList();
    if (institutionRecords.isEmpty) return [];

    // 链上交叉校验
    try {
      final chainAdmins = await _adminService.fetchAdmins(identity);
      final validAccountIds = chainAdmins
          .map((admin) => admin.account_id)
          .toSet();
      final before = all.length;
      all.removeWhere(
        (a) =>
            a.cidNumber == cidNumber && !validAccountIds.contains(a.accountId),
      );
      if (all.length != before) {
        await _saveAll(all);
      }
      return all.where((a) => a.cidNumber == cidNumber).toList();
    } catch (_) {
      // RPC 查询失败时不清除本地记录
      return institutionRecords;
    }
  }

  /// 检查指定账户 ID 是否已激活。
  Future<bool> isActivated(
    String accountId,
    AdminAccountIdentity identity,
  ) async {
    final normalizedAccountId = _normalize(accountId);
    final cidNumber = _requireInstitutionCid(identity);
    final all = await loadAll();
    return all.any(
      (a) => a.accountId == normalizedAccountId && a.cidNumber == cidNumber,
    );
  }

  /// 构建管理员激活业务 payload；账户签名与冷热分流由 CitizenSDK 完成。
  Uint8List buildActivationPayload({
    required String accountId,
    required AdminAccountIdentity identity,
  }) {
    _requireInstitutionCid(identity);
    final normalizedAccountId = _normalize(accountId);

    return _buildActivatePayload(identity, normalizedAccountId);
  }

  /// CitizenSDK 已完成账户控制证明后记录本机激活状态。
  ///
  /// [accountId] 管理员账户 ID。
  /// [identity] 管理员账户。
  Future<ActivatedAdmin> activate({
    required String accountId,
    required AdminAccountIdentity identity,
  }) async {
    final cidNumber = _requireInstitutionCid(identity);
    final normalizedAccountId = _normalize(accountId);

    // 验证是链上管理员
    final admins = await _adminService.fetchAdmins(identity);
    if (!admins.any((admin) => admin.account_id == normalizedAccountId)) {
      throw Exception('该账户 ID 不在此管理员账户的链上管理员列表中');
    }

    // 写入本地存储
    final now = DateTime.now().millisecondsSinceEpoch;
    final activation = ActivatedAdmin(
      accountId: normalizedAccountId,
      cidNumber: cidNumber,
      institutionCode: identity.institutionCode,
      kind: identity.kind,
      activatedAtMs: now,
    );

    var all = await loadAll();
    // 去重
    all.removeWhere(
      (a) => a.accountId == normalizedAccountId && a.cidNumber == cidNumber,
    );
    all.add(activation);
    await _saveAll(all);

    return activation;
  }

  // 取消激活
  /// 取消激活。
  Future<void> deactivate(
    String accountId,
    AdminAccountIdentity identity,
  ) async {
    final normalizedAccountId = _normalize(accountId);
    final cidNumber = _requireInstitutionCid(identity);
    var all = await loadAll();
    all.removeWhere(
      (a) => a.accountId == normalizedAccountId && a.cidNumber == cidNumber,
    );
    await _saveAll(all);
  }

  // 内部方法
  Uint8List _buildActivatePayload(
    AdminAccountIdentity identity,
    String accountId,
  ) {
    final signerPublicKey = _hexToBytes(accountId);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final random = Random.secure();
    return activateAdminPayload(
      cidNumber: _requireInstitutionCid(identity),
      institutionCode: InstitutionCodeLabel.codeBytes(identity.institutionCode),
      kind: identity.kind,
      signerPublicKey: signerPublicKey,
      timestamp: timestamp,
      nonce: List<int>.generate(
        kAdminNonceLength,
        (_) => random.nextInt(256),
        growable: false,
      ),
    );
  }

  static String _requireInstitutionCid(AdminAccountIdentity identity) {
    if (identity.type != AdminAccountIdentityType.institution) {
      throw ArgumentError('管理员激活只适用于机构 CID；个人多签不使用机构激活协议');
    }
    return identity.cidNumber!;
  }

  Future<void> _saveAll(List<ActivatedAdmin> all) async {
    final raw = jsonEncode(all.map((a) => a.toJson()).toList());
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.walletAdminActivationStateEntitys.put(
        WalletAdminActivationStateEntity()
          ..id = 0
          ..payloadJson = raw,
      );
    });
  }

  static String _normalize(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
