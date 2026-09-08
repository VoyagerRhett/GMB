import 'dart:convert';

import 'package:citizenapp/security/secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gmb_hardware_secretvault/hardware_secretvault.dart';

import 'secure_seed_store.dart';

/// 硬件信封密文的静默持久化抽象。这里保存的永远只是不可解密的密文字节 Base64。
abstract interface class VaultBlobStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageBlobStore implements VaultBlobStore {
  SecureStorageBlobStore([FlutterSecureStorage? storage])
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 公民无根钱包的共享硬件严档后端。
///
/// App 只保存账户 child [MiniSecretKey]，不保存助记词或 master [MiniSecretKey]。明文
/// 以字节进入 `citizenapp/packages/hardware-secretvault`；AAD 固定绑定 `citizenapp + walletIndex +
/// accountId + account_mini_secret`。Android 必须为 StrongBox/TEE 且每次强生物识别，
/// iOS 必须为 Secure Enclave `biometryCurrentSet`。
class HardwareBoundSeedVault implements SecureSeedStore {
  HardwareBoundSeedVault({
    HardwareSecretvault? hardwareVault,
    VaultBlobStore? blobStore,
  })  : _hardwareVault = hardwareVault ?? HardwareSecretvault(),
        _blobStore = blobStore ?? SecureStorageBlobStore();

  static const String _product = 'citizenapp';
  static final RegExp _accountIdPattern = RegExp(r'^0x[0-9a-f]{64}$');

  final HardwareSecretvault _hardwareVault;
  final VaultBlobStore _blobStore;

  static String _accountBlobKey(String accountId) {
    if (!_accountIdPattern.hasMatch(accountId)) {
      throw ArgumentError.value(accountId, 'accountId', 'AccountId 格式无效');
    }
    return 'wallet.secret.$accountId.account_mini_secret';
  }

  static HardwareSecretContext _context(int walletIndex, String accountId) =>
      HardwareSecretContext(
        product: _product,
        scope: walletIndex.toString(),
        accountId: accountId,
        secretType: HardwareSecretType.accountMiniSecret,
      );

  @override
  Future<SecureAuthStatus> authStatus() async {
    switch (await _hardwareVault.availability()) {
      case HardwareSecretvaultAvailability.available:
        return SecureAuthStatus.available;
      case HardwareSecretvaultAvailability.noStrongBiometric:
        return SecureAuthStatus.noDeviceLock;
      case HardwareSecretvaultAvailability.unsupported:
        return SecureAuthStatus.unsupported;
    }
  }

  @override
  Future<void> putAccountKey({
    required int walletIndex,
    required String accountId,
    required Uint8List childMiniSecret,
  }) async {
    if (childMiniSecret.length != 32) {
      throw const SecureStoreUnavailable('账户 MiniSecretKey 必须为 32 字节');
    }
    Uint8List? encrypted;
    try {
      encrypted = await _hardwareVault.encrypt(
        _context(walletIndex, accountId),
        childMiniSecret,
      );
      await _blobStore.write(
          _accountBlobKey(accountId), base64Encode(encrypted));
    } on HardwareSecretvaultException catch (error) {
      _mapAndThrow(error);
    } on PlatformException catch (error) {
      throw SecureStoreUnavailable(error.message ?? error.code);
    } finally {
      if (encrypted != null) HardwareSecretvault.clearBytes(encrypted);
    }
  }

  @override
  Future<Uint8List?> readAccountKey({
    required int walletIndex,
    required String accountId,
  }) async {
    final stored = await _blobStore.read(_accountBlobKey(accountId));
    if (stored == null) return null;
    Uint8List? encrypted;
    try {
      encrypted = Uint8List.fromList(base64Decode(stored));
      final plaintext = await _hardwareVault.decrypt(
        _context(walletIndex, accountId),
        encrypted,
      );
      if (plaintext.length != 32) {
        HardwareSecretvault.clearBytes(plaintext);
        throw const SecureStoreUnavailable('账户 MiniSecretKey 长度异常');
      }
      return plaintext;
    } on FormatException {
      throw const SecureStoreUnavailable('账户硬件密文格式异常');
    } on HardwareSecretvaultException catch (error) {
      _mapAndThrow(error);
    } on PlatformException catch (error) {
      throw SecureStoreUnavailable(error.message ?? error.code);
    } finally {
      if (encrypted != null) HardwareSecretvault.clearBytes(encrypted);
    }
  }

  @override
  Future<bool> hasAccountKey(String accountId) async =>
      await _blobStore.read(_accountBlobKey(accountId)) != null;

  @override
  Future<void> deleteAccountKey({
    required int walletIndex,
    required String accountId,
  }) =>
      _blobStore.delete(_accountBlobKey(accountId));

  @override
  Future<void> deleteWalletKey({required int walletIndex}) => _hardwareVault
      .deleteKey(product: _product, scope: walletIndex.toString());

  @override
  Future<bool> hasWalletKey({required int walletIndex}) =>
      _hardwareVault.containsKey(
        product: _product,
        scope: walletIndex.toString(),
      );

  Never _mapAndThrow(HardwareSecretvaultException error) {
    switch (error.code) {
      case 'keyPermanentlyInvalidated':
        throw SeedKeyInvalidated(error.message);
      case 'userCancelled':
      case 'lockout':
        throw AuthCancelled(error.message);
      case 'notEnrolled':
        throw NoDeviceCredential(error.message);
      default:
        throw SecureStoreUnavailable(error.message);
    }
  }
}
