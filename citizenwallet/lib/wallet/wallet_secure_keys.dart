import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenwallet/security/hardware_secretvault.dart';

import '../security/secure_storage.dart';

/// 公民钱包硬件严档的存储键与 AAD 单源。
///
/// SecureStorage 只保存不可逆推出明文的硬件信封密文；master [MiniSecretKey] 与助记词
/// 明文只以可覆写字节数组进出共享硬件金库。每个钱包以 [masterId] 独占一把硬件 KEK，
/// 两类密文再由 AAD 绑定产品、master、AccountId 与机密类型，禁止跨钱包或跨类型调换。
final class WalletSecureKeys {
  WalletSecureKeys({HardwareSecretvault? hardwareVault})
      : _hardwareVault = hardwareVault ?? HardwareSecretvault();

  static const String _product = 'citizenwallet';
  static final RegExp _masterIdPattern = RegExp(r'^0x[0-9a-f]{64}$');

  final HardwareSecretvault _hardwareVault;

  /// master [MiniSecretKey] 的硬件信封密文键。
  static String masterMiniSecretKey(String masterId) {
    _requireMasterId(masterId);
    return 'wallet.secret.$masterId.master_mini_secret_key';
  }

  /// BIP-39 助记词 UTF-8 字节的硬件信封密文键。
  static String mnemonic(String masterId) {
    _requireMasterId(masterId);
    return 'wallet.secret.$masterId.mnemonic';
  }

  Future<void> ensureAvailable() async {
    switch (await _hardwareVault.availability()) {
      case HardwareSecretvaultAvailability.available:
        return;
      case HardwareSecretvaultAvailability.noStrongBiometric:
        throw const HardwareSecretvaultException(
          'noStrongBiometric',
          '必须先在系统设置中录入强生物识别（指纹或面容）',
        );
      case HardwareSecretvaultAvailability.unsupported:
        throw const HardwareSecretvaultException(
          'hardwareUnavailable',
          '设备不支持钱包所需的硬件安全金库',
        );
    }
  }

  Future<void> writeMasterMiniSecretKey(
    String masterId,
    Uint8List miniSecretKey,
  ) async {
    if (miniSecretKey.length != 32) {
      throw ArgumentError.value(
        miniSecretKey.length,
        'miniSecretKey.length',
        'master MiniSecretKey 必须是 32 字节',
      );
    }
    await _write(
      storageKey: masterMiniSecretKey(masterId),
      context: _context(masterId, HardwareSecretType.masterMiniSecret),
      plaintext: miniSecretKey,
    );
  }

  Future<Uint8List?> readMasterMiniSecretKey(String masterId) => _read(
        storageKey: masterMiniSecretKey(masterId),
        context: _context(masterId, HardwareSecretType.masterMiniSecret),
      );

  Future<void> writeMnemonic(String masterId, Uint8List mnemonicBytes) =>
      _write(
        storageKey: mnemonic(masterId),
        context: _context(masterId, HardwareSecretType.mnemonic),
        plaintext: mnemonicBytes,
      );

  Future<Uint8List?> readMnemonic(String masterId) => _read(
        storageKey: mnemonic(masterId),
        context: _context(masterId, HardwareSecretType.mnemonic),
      );

  Future<void> deleteMasterMiniSecretKey(String masterId) =>
      appSecureStorage.delete(key: masterMiniSecretKey(masterId));

  Future<void> deleteMnemonic(String masterId) =>
      appSecureStorage.delete(key: mnemonic(masterId));

  Future<bool> containsMasterMiniSecretKey(String masterId) async =>
      await appSecureStorage.read(key: masterMiniSecretKey(masterId)) != null;

  Future<bool> containsMnemonic(String masterId) async =>
      await appSecureStorage.read(key: mnemonic(masterId)) != null;

  Future<void> deleteHardwareKey(String masterId) =>
      _hardwareVault.deleteKey(product: _product, scope: _scope(masterId));

  Future<bool> containsHardwareKey(String masterId) =>
      _hardwareVault.containsKey(product: _product, scope: _scope(masterId));

  Future<void> _write({
    required String storageKey,
    required HardwareSecretContext context,
    required Uint8List plaintext,
  }) async {
    Uint8List? ciphertext;
    try {
      ciphertext = await _hardwareVault.encrypt(context, plaintext);
      final encoded = base64Encode(ciphertext);
      await appSecureStorage.write(key: storageKey, value: encoded);
      if (await appSecureStorage.read(key: storageKey) != encoded) {
        throw const HardwareSecretvaultException(
          'storageWriteFailed',
          '钱包硬件信封密文持久化校验失败',
        );
      }
    } finally {
      if (ciphertext != null) HardwareSecretvault.clearBytes(ciphertext);
    }
  }

  Future<Uint8List?> _read({
    required String storageKey,
    required HardwareSecretContext context,
  }) async {
    final encoded = await appSecureStorage.read(key: storageKey);
    if (encoded == null) return null;
    Uint8List? ciphertext;
    try {
      try {
        ciphertext = base64Decode(encoded);
      } on FormatException {
        throw const HardwareSecretvaultException(
          'ciphertextInvalid',
          '钱包硬件信封密文格式异常',
        );
      }
      return await _hardwareVault.decrypt(context, ciphertext);
    } finally {
      if (ciphertext != null) HardwareSecretvault.clearBytes(ciphertext);
    }
  }

  static HardwareSecretContext _context(
    String masterId,
    HardwareSecretType secretType,
  ) =>
      HardwareSecretContext(
        product: _product,
        scope: _scope(masterId),
        accountId: masterId,
        secretType: secretType,
      );

  static String _scope(String masterId) {
    _requireMasterId(masterId);
    return masterId;
  }

  static void _requireMasterId(String masterId) {
    if (!_masterIdPattern.hasMatch(masterId)) {
      throw ArgumentError.value(
        masterId,
        'masterId',
        '必须是小写 0x 加 64 位十六进制 AccountId',
      );
    }
  }
}
