import '../models/citizen_wallet.dart';

/// CitizenSDK 无根热钱包的公开控制面。
///
/// create/import/addAccounts 都只启动 SDK 自有安全界面。Dart API 故意没有 mnemonic 或
/// password 参数，也不会收到 prepared/native/result handle。
abstract interface class CitizenWallet {
  Future<CitizenWalletProfile?> getProfile();

  /// 在 SDK 原生安全窗口查看指定账户私钥；确认、设备认证和清屏均由 SDK 管理。
  /// 只等待真实流程结束，绝不向 Dart 返回私钥、显示回调或内部句柄。
  Future<void> viewAccountPrivateKey(String accountId);

  /// 打开 SDK 安全界面；wordCount 是初始选择，用户可选 12／18／24 词。
  ///
  /// 密码选填且仅参与派生。准备阶段不持久化，确认离线备份后才提交钱包；
  /// Dart 只收到完成后的公开资料，不取得助记词、派生密码或准备句柄。
  Future<CitizenWalletProfile> create({
    CitizenWalletWordCount wordCount = CitizenWalletWordCount.words12,
  });

  /// 在原生安全界面导入 12／18／24 词及选填派生密码。
  Future<CitizenWalletProfile> importWallet();

  /// indices 为指定编号模式的初始值；SDK 界面也提供明确的下一个账户选择。
  /// 空列表不是“下一个”的特殊值；实际提交仍由同一核心校验钱包归属和编号。
  Future<CitizenWalletProfile> addAccounts(List<int> indices);

  Future<CitizenWalletProfile> setActiveAccount(String accountId);

  Future<CitizenWalletProfile> renameAccount({
    required String accountId,
    required String name,
  });

  Future<CitizenWalletProfile?> deleteAccount(String accountId);

  Future<void> delete();

  Future<CitizenWalletProfile?> reconcileCleanup();
}
