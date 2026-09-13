import 'dart:typed_data';

import '../models/citizen_signing.dart';
import '../models/citizen_wallet.dart';

/// CitizenSDK 无根热钱包与公开冷账户控制面。
///
/// 名称显式包含 `Sdk`，避免与独立离线产品 CitizenWallet 混淆。create/import/
/// addAccounts 和私钥查看只启动 SDK 自有安全界面；Dart 不取得助记词、密码、
/// 私钥、prepared/native/result handle。
abstract interface class CitizenSdkWallet {
  Future<CitizenWalletProfile?> getProfile();

  /// 返回热／冷账户的统一公开目录；第一项是只读默认账户。
  Future<CitizenWalletState> getState();

  /// 导入独立冷账户的公开事实。`accountId` 与 `ss58Address` 必须且只能提供一个。
  Future<CitizenWalletState> importColdAccount({
    String? accountId,
    String? ss58Address,
    required String name,
  });

  /// 基于同一 revision 重排完整目录；第一项必须仍是当前默认账户。
  Future<CitizenWalletState> reorderAccountsWithoutDefaultChange({
    required BigInt expectedRevision,
    required List<String> accountIds,
  });

  /// Changes the default account only after the original default authorizes the complete order.
  Future<CitizenDefaultAccountChangeOutcome> beginDefaultAccountChange({
    required BigInt expectedRevision,
    required List<String> accountIds,
    int ttlSeconds = 90,
  });

  Future<CitizenDefaultAccountChangeCompleted> consumeDefaultAccountChange({
    required String sessionId,
    required String response,
  });

  /// 在 SDK 安全窗口查看指定账户私钥；确认、设备认证和清屏均由 SDK 管理。
  /// 只等待真实流程结束，绝不向 Dart 返回私钥、显示回调或内部句柄。
  Future<void> viewAccountPrivateKey(String accountId);

  /// 打开 SDK 安全界面；wordCount 是初始选择，用户可选 12／18／24 词。
  ///
  /// 密码选填且仅参与派生。准备阶段不持久化，确认离线备份后才提交钱包；
  /// Dart 只收到完成后的公开资料，不取得助记词、派生密码或准备句柄。
  Future<CitizenWalletProfile> create({
    CitizenWalletWordCount wordCount = CitizenWalletWordCount.words12,
  });

  /// 在 SDK 安全界面导入 12／18／24 词及选填派生密码。
  Future<CitizenWalletProfile> importWallet();

  /// indices 为指定编号模式的初始值；SDK 界面也提供明确的下一个账户选择。
  /// 空列表不是“下一个”的特殊值；提交仍由同一核心校验钱包归属和编号。
  Future<CitizenWalletProfile> addAccounts(List<int> indices);

  Future<CitizenWalletProfile> setActiveAccount(String accountId);

  Future<CitizenWalletState> renameAccount({
    required String accountId,
    required String name,
  });

  Future<CitizenWalletState> deleteAccount(String accountId);

  Future<void> delete();

  Future<CitizenWalletProfile?> reconcileCleanup();

  /// 使用指定热账户秘密执行通用 HKDF-SHA256；业务只提供 opaque salt/info。
  ///
  /// SDK 不解释、保存或登记派生用途；冷账户必须由其独立外部签名设备提供
  /// 对应材料，不能在此伪造本地秘密。
  Future<Uint8List> deriveApplicationKey({
    required String accountId,
    required Uint8List salt,
    required Uint8List info,
  });
}
