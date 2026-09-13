import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// CitizenApp 全局唯一的通用安全存储实例。
///
/// 这里只保存已经受业务层保护的密文 blob、PIN 哈希和短期令牌，不保存或解封
/// 钱包账户秘密。若在这里启用通用生物门禁，会让后台会话和设备锁状态读取错误弹窗。
///
/// - Android：插件 10.x 默认使用 RSA-OAEP 包装 AES-GCM 数据密钥；开启算法变更
///   迁移及迁移备份，避免升级过程中断造成既有密文不可读。
/// - iOS：仅允许本机在首次解锁后访问，不随 iCloud/换机迁移；钱包秘密和设备认证
///   由 CitizenSDK 自有安全存储实现。
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  ),
);
