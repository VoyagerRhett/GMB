import 'dart:convert';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/foundation.dart';

import 'package:citizenapp/security/account_data_key_provision.dart';
import 'package:citizenapp/security/device_data_key_vault.dart';
import 'package:citizenapp/security/device_subkey.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';

/// CitizenApp 用户／设备安全操作错误；SDK 错误仍保留自己的错误码和阶段。
class AccountSecurityException implements Exception {
  const AccountSecurityException(this.message);

  final String message;

  @override
  String toString() => 'AccountSecurityException: $message';
}

/// 通讯录一次操作拥有的两把短期用途钥；调用方结束后必须立即清零。
final class ContactKeyMaterial {
  const ContactKeyMaterial({
    required this.encryptionKey,
    required this.indexKey,
  });

  final Uint8List encryptionKey;
  final Uint8List indexKey;

  void dispose() {
    encryptionKey.fillRange(0, encryptionKey.length, 0);
    indexKey.fillRange(0, indexKey.length, 0);
  }
}

typedef AccountSubkeyRegistrar = Future<void> Function({
  required String cidNumber,
  required int bindingRevision,
  required String accountId,
  required Future<String> Function({
    required Uint8List payload,
    required Uint8List signingMessage,
    required String devicePublicKey,
    required int issuedAtMillis,
  })
  signBinding,
});

typedef ColdDeviceBindingSigner = Future<String> Function({
  required AccountDataBinding binding,
  required Uint8List payload,
  required Uint8List signingMessage,
  required String devicePublicKey,
  required int issuedAtMillis,
});

typedef ColdAccountDataKeyProvider = Future<List<Uint8List>> Function({
  required AccountDataBinding binding,
  required List<DataKeyRequest> requests,
});

typedef AccountDataKeyDerive = Future<Uint8List> Function({
  required CitizenSdkWallet wallet,
  required AccountDataBinding binding,
  required LocalKeyPurpose purpose,
  String? context,
});
typedef AccountDataKeyDeriveBatch = Future<List<Uint8List>> Function({
  required CitizenSdkWallet wallet,
  required AccountDataBinding binding,
  required List<DataKeyRequest> requests,
});

/// CitizenApp 的 CID 绑定、P-256 设备子钥与用途钥业务。
///
/// 钱包目录、账户秘密、sr25519 与 HKDF 都由传入的 CitizenSDK 端口承担；本类不包装
/// SDK 钱包 API，也不提供创建、导入、改名、删除或签名的同义方法。
interface class AccountSecurityService {
  AccountSecurityService({
    required CitizenSdkWallet wallet,
    required CitizenSigning signing,
    required AccountSubkeyRegistrar subkeyRegistrar,
    required ColdDeviceBindingSigner coldDeviceBindingSigner,
    required ColdAccountDataKeyProvider coldAccountDataKeyProvider,
    LocalKeyBlobStore? blobStore,
    DeviceSubkey? deviceSubkey,
    DeviceDataKeyVault? deviceDataKeyVault,
    AccountDataKeyDerive? deriveApplicationKey,
    AccountDataKeyDeriveBatch? deriveApplicationKeys,
  }) : _wallet = wallet,
       _signing = signing,
       _subkeyRegistrar = subkeyRegistrar,
       _coldDeviceBindingSigner = coldDeviceBindingSigner,
       _coldAccountDataKeyProvider = coldAccountDataKeyProvider,
       _blobStore = blobStore ?? SecureStorageLocalKeyBlobStore(),
       _deviceSubkey = deviceSubkey ?? DeviceSubkey(),
       _deviceDataKeyVault = deviceDataKeyVault ?? DeviceDataKeyVault(),
       _deriveApplicationKey =
           deriveApplicationKey ?? AccountDataKeyDeriver.derive,
       _deriveApplicationKeys =
           deriveApplicationKeys ??
           (deriveApplicationKey == null
               ? AccountDataKeyDeriver.deriveBatch
               : null) {
    _bindingStore = AccountDataBindingStore(_blobStore);
  }

  final CitizenSdkWallet _wallet;
  final CitizenSigning _signing;
  final AccountSubkeyRegistrar _subkeyRegistrar;
  final ColdDeviceBindingSigner _coldDeviceBindingSigner;
  final ColdAccountDataKeyProvider _coldAccountDataKeyProvider;
  final LocalKeyBlobStore _blobStore;
  final DeviceSubkey _deviceSubkey;
  final DeviceDataKeyVault _deviceDataKeyVault;
  final AccountDataKeyDerive _deriveApplicationKey;
  final AccountDataKeyDeriveBatch? _deriveApplicationKeys;
  late final AccountDataBindingStore _bindingStore;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Map<String, Future<void>> _dataKeyFlights = <String, Future<void>>{};
  final Map<String, Future<void>> _subkeyFlights = <String, Future<void>>{};

  static const String _pendingCleanupKey =
      'citizenapp_account_security_pending_cleanup';

  static const List<DataKeyRequest> _deviceDataKeyRequests = <DataKeyRequest>[
    (purpose: LocalKeyPurpose.chat, context: null),
    (purpose: LocalKeyPurpose.chatIndex, context: null),
    (purpose: LocalKeyPurpose.mls, context: null),
    (purpose: LocalKeyPurpose.attachment, context: null),
    (purpose: LocalKeyPurpose.contactsLocal, context: null),
    (purpose: LocalKeyPurpose.contactsCloud, context: 'encryption'),
    (purpose: LocalKeyPurpose.contactsCloud, context: 'index'),
  ];

  void notifyIdentityBindingChanged() => revision.value += 1;

  void notifyDefaultAccountChanged() => revision.value += 1;

  Future<ContactKeyMaterial> ensureContactKeyMaterialForAccountId(
    String accountId,
  ) async {
    final binding = await _requireBinding(accountId);
    final keys = await readDataKeysForBinding(binding, const <DataKeyRequest>[
      (purpose: LocalKeyPurpose.contactsCloud, context: 'encryption'),
      (purpose: LocalKeyPurpose.contactsCloud, context: 'index'),
    ]);
    return ContactKeyMaterial(encryptionKey: keys[0], indexKey: keys[1]);
  }

  Future<ContactKeyMaterial> contactKeyMaterialForBinding(
    AccountDataBinding binding,
  ) async {
    final keys = await deriveDataKeysForBindingHandover(
      binding,
      const <DataKeyRequest>[
        (purpose: LocalKeyPurpose.contactsCloud, context: 'encryption'),
        (purpose: LocalKeyPurpose.contactsCloud, context: 'index'),
      ],
    );
    return ContactKeyMaterial(encryptionKey: keys[0], indexKey: keys[1]);
  }

  Future<void> activateAccountDataBinding({
    required String genesisHash,
    required String cidNumber,
    required int bindingRevision,
    required String accountId,
  }) async {
    if (await _account(accountId) == null) {
      throw const AccountSecurityException('CID 当前绑定账户不在本机钱包中');
    }
    final binding = AccountDataBinding(
      genesisHash: genesisHash,
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
    );
    await _rejectSameAccountRevisionChange(binding);
    final previous = await _bindingStore.readForCid(binding.cidNumber);
    if (previous != null &&
        previous.genesisHash == binding.genesisHash &&
        previous.accountId == binding.accountId &&
        previous.bindingRevision == binding.bindingRevision) {
      // 同一会话反复进入页面不能广播身份变化，否则监听者再次登录形成循环。
      return;
    }
    await _bindingStore.activate(binding);
    notifyIdentityBindingChanged();
  }

  Future<Uint8List> readDataKeyForCurrentBinding(
    String accountId,
    LocalKeyPurpose purpose, {
    String? context,
  }) async => (await readDataKeysForBinding(
    await _requireBinding(accountId),
    <DataKeyRequest>[(purpose: purpose, context: context)],
  )).single;

  Future<List<Uint8List>> readDataKeysForBinding(
    AccountDataBinding binding,
    List<DataKeyRequest> requests,
  ) async {
    binding.validate();
    if (requests.isEmpty) {
      throw ArgumentError('私有数据用途列表不能为空');
    }
    // 正常只静默解封；缺失或硬件钥永久失效时在同一绑定内恢复原用途钥。
    // 钱包授权由SDK执行，取消、设备暂不可用或插件缺失不得循环重试。
    if (await _blobStore.read(_deviceDataKeyRecoveryName(binding)) != null ||
        !await _hasDeviceDataKeyBlobs(binding, requests)) {
      await ensureDeviceDataKeysForBinding(binding);
    }
    try {
      return await _openDeviceDataKeys(binding, requests);
    } on DeviceDataKeyVaultException catch (error) {
      if (error.code != 'keyPermanentlyInvalidated') rethrow;
      await ensureDeviceDataKeysForBinding(binding, rebuildAll: true);
      return _openDeviceDataKeys(binding, requests);
    }
  }

  Future<List<Uint8List>> deriveDataKeysForBindingHandover(
    AccountDataBinding binding,
    List<DataKeyRequest> requests,
  ) async {
    binding.validate();
    if (requests.isEmpty) {
      throw ArgumentError('私有数据用途列表不能为空');
    }
    final account = await _account(binding.accountId);
    if (account == null) {
      throw const AccountSecurityException('CID 当前绑定账户不在本机钱包中');
    }
    return _deriveOrProvide(account, binding, requests);
  }

  Future<void> ensureDeviceDataKeysForBinding(
    AccountDataBinding binding, {
    bool rebuildAll = false,
  }) {
    binding.validate();
    final key = _flightKey(binding);
    final existing = _dataKeyFlights[key];
    if (existing != null) return existing;
    late final Future<void> created;
    created = _ensureDeviceDataKeysForBinding(binding, rebuildAll: rebuildAll)
        .then((_) {
          if (identical(_dataKeyFlights[key], created)) {
            _dataKeyFlights.remove(key);
          }
        });
    // 失败结论继续由同一绑定的调用者共享；切页、恢复前台和后台同步不得
    // 把取消或失败当作下一次自动认证的机会。重启才重新读取持久恢复状态。
    _dataKeyFlights[key] = created;
    return created;
  }

  Future<void> _ensureDeviceDataKeysForBinding(
    AccountDataBinding binding, {
    required bool rebuildAll,
  }) async {
    final generation = revision.value;
    await _rejectSameAccountRevisionChange(binding);
    final account = await _account(binding.accountId);
    if (account == null) {
      throw const AccountSecurityException('CID 当前绑定账户不在本机钱包中');
    }
    final hardwareExists = await _deviceDataKeyVault.contains(
      account.walletIndex,
    );
    final recoveryName = _deviceDataKeyRecoveryName(binding);
    final recoveryPending = await _blobStore.read(recoveryName) != null;
    final recoverAll = rebuildAll || !hardwareExists || recoveryPending;
    final requests = recoverAll
        ? _deviceDataKeyRequests
        : await _missingDeviceDataKeyRequests(binding);
    if (requests.isEmpty) return;
    // 硬件重建中途失败也保留恢复事实；重启后不能把新硬件钥误当成旧密文可读。
    if (recoverAll) {
      await _recordDeviceKeyMaterialIndex(account.walletIndex, binding);
      await _blobStore.write(recoveryName, 'true');
    }
    final keys = await _deriveOrProvide(account, binding, requests);
    final previous = <String, String?>{};
    final sealed = <String, String>{};
    final written = <String>[];
    try {
      // 全部派生和封装成功后才替换持久密文；失败恢复旧值，不删除用户资料。
      for (var index = 0; index < requests.length; index += 1) {
        final request = requests[index];
        final key = keys[index];
        final name = _deviceDataKeyBlobName(binding, request);
        previous[name] = await _blobStore.read(name);
        sealed[name] = await _deviceDataKeyVault.seal(
          walletIndex: account.walletIndex,
          plaintext: key,
          aad: _deviceDataKeyAad(binding, account.walletIndex, request),
        );
        key.fillRange(0, key.length, 0);
      }
      if (revision.value != generation) {
        throw const AccountSecurityException('用途钥恢复期间身份已变化');
      }
      for (final entry in sealed.entries) {
        await _blobStore.write(entry.key, entry.value);
        written.add(entry.key);
        if (revision.value != generation) {
          throw const AccountSecurityException('用途钥恢复期间身份已变化');
        }
      }
      await _bindingStore.activate(binding);
      await _recordDeviceKeyMaterialIndex(account.walletIndex, binding);
      await _blobStore.delete(recoveryName);
    } catch (error) {
      for (final name in written.reversed) {
        final old = previous[name];
        if (old == null) {
          await _blobStore.delete(name);
        } else {
          await _blobStore.write(name, old);
        }
      }
      rethrow;
    } finally {
      for (final key in keys) {
        key.fillRange(0, key.length, 0);
      }
    }
  }

  Future<List<Uint8List>> _deriveOrProvide(
    CitizenWalletStateAccount account,
    AccountDataBinding binding,
    List<DataKeyRequest> requests,
  ) async {
    final keys = <Uint8List>[];
    try {
      if (account.signMode == CitizenWalletSignMode.hot) {
        final batch = _deriveApplicationKeys;
        if (batch != null) {
          keys.addAll(
            await batch(wallet: _wallet, binding: binding, requests: requests),
          );
        } else {
          // 仅为显式注入旧单项派生测试替身保留；正式运行始终使用批量 SDK。
          for (final request in requests) {
            keys.add(
              await _deriveApplicationKey(
                wallet: _wallet,
                binding: binding,
                purpose: request.purpose,
                context: request.context,
              ),
            );
          }
        }
      } else {
        keys.addAll(
          await _coldAccountDataKeyProvider(
            binding: binding,
            requests: List<DataKeyRequest>.unmodifiable(requests),
          ),
        );
      }
      if (keys.length != requests.length ||
          keys.any((key) => key.length != 32)) {
        throw const AccountSecurityException('账户返回的用途钥清单无效');
      }
      return keys;
    } catch (_) {
      for (final key in keys) {
        key.fillRange(0, key.length, 0);
      }
      rethrow;
    }
  }

  Future<List<Uint8List>> _openDeviceDataKeys(
    AccountDataBinding binding,
    List<DataKeyRequest> requests,
  ) async {
    final account = await _account(binding.accountId);
    if (account == null) {
      throw const AccountSecurityException('CID 当前绑定账户不在本机钱包中');
    }
    final keys = <Uint8List>[];
    try {
      for (final request in requests) {
        final blob = await _blobStore.read(
          _deviceDataKeyBlobName(binding, request),
        );
        if (blob == null || blob.isEmpty) {
          throw const DeviceDataKeyVaultException('设备用途钥不存在');
        }
        final key = await _deviceDataKeyVault.open(
          walletIndex: account.walletIndex,
          blob: blob,
          aad: _deviceDataKeyAad(binding, account.walletIndex, request),
        );
        if (key.length != 32) {
          key.fillRange(0, key.length, 0);
          throw const DeviceDataKeyVaultException('设备用途钥长度无效');
        }
        keys.add(key);
      }
      return keys;
    } catch (_) {
      for (final key in keys) {
        key.fillRange(0, key.length, 0);
      }
      rethrow;
    }
  }

  Future<void> registerDeviceSubkeyForBinding(AccountDataBinding binding) {
    binding.validate();
    final key = _flightKey(binding);
    final existing = _subkeyFlights[key];
    if (existing != null) return existing;
    late final Future<void> created;
    created = _registerDeviceSubkeyForBinding(binding).whenComplete(() {
      if (identical(_subkeyFlights[key], created)) _subkeyFlights.remove(key);
    });
    _subkeyFlights[key] = created;
    return created;
  }

  Future<void> _registerDeviceSubkeyForBinding(
    AccountDataBinding binding,
  ) async {
    await _rejectSameAccountRevisionChange(binding);
    final account = await _account(binding.accountId);
    if (account == null) {
      throw const AccountSecurityException('CID 当前绑定账户不在本机钱包中');
    }
    await _subkeyRegistrar(
      cidNumber: binding.cidNumber,
      bindingRevision: binding.bindingRevision,
      accountId: binding.accountId,
      signBinding:
          ({
            required payload,
            required signingMessage,
            required devicePublicKey,
            required issuedAtMillis,
          }) async {
            if (account.signMode == CitizenWalletSignMode.hot) {
              final signature = await _signing
                  .sign(accountId: binding.accountId, payload: signingMessage)
                  .result;
              return '0x${_hex(signature.bytes)}';
            }
            return _coldDeviceBindingSigner(
              binding: binding,
              payload: payload,
              signingMessage: signingMessage,
              devicePublicKey: devicePublicKey,
              issuedAtMillis: issuedAtMillis,
            );
          },
    );
    await _bindingStore.activate(binding);
    await _recordDeviceKeyMaterialIndex(account.walletIndex, binding);
  }

  Future<AccountDataBinding?> readAccountDataBindingForCid(String cidNumber) =>
      _bindingStore.readForCid(cidNumber);

  Future<AccountDataBinding?> readAccountDataBindingForAccountId(
    String accountId,
  ) => _bindingStore.readForAccountId(accountId);

  Future<AccountDataBinding> accountDataBindingForAccountId(String accountId) =>
      _requireBinding(accountId);

  Future<void> recordPendingAccountDataHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) => _bindingStore.writePendingHandover(source: source, target: target);

  Future<void> markPendingAccountDataHandoverReady({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) => _bindingStore.markPendingHandoverReady(source: source, target: target);

  Future<
    ({
      AccountDataBinding source,
      AccountDataBinding target,
      AccountDataHandoverState state,
    })?
  >
  readPendingAccountDataHandover() => _bindingStore.readPendingHandover();

  Future<void> clearPendingAccountDataHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) => _bindingStore.clearPendingHandover(source: source, target: target);

  /// 在 SDK 钱包事实删除前保存 App 设备材料的精确清理意图。
  Future<void> prepareAccountCleanup({
    required List<String> accountIds,
    required Set<int> walletIndexes,
    required bool deleteWalletWideKey,
  }) async {
    if (accountIds.isEmpty) return;
    if (deleteWalletWideKey && walletIndexes.length != 1) {
      throw const AccountSecurityException('整钱包清理必须只包含一个 wallet_index');
    }
    final value = jsonEncode(<String, Object>{
      'account_ids': accountIds,
      'wallet_indices': walletIndexes.toList()..sort(),
      'delete_wallet_wide_key': deleteWalletWideKey,
    });
    final current = await _blobStore.read(_pendingCleanupKey);
    if (current != null && current != value) {
      throw const AccountSecurityException('已有其它账户安全清理尚未完成');
    }
    await _blobStore.write(_pendingCleanupKey, value);
  }

  /// 原清理提示只读既有意图的存在事实，不在页面刷新中执行或撤销清理。
  Future<bool> get hasPendingAccountCleanup async =>
      await _blobStore.read(_pendingCleanupKey) != null;

  /// SDK安全清理完成后调用原关联清理能力；全部成功才清除同一持久意图。
  Future<void> reconcileAccountCleanup() async {
    final raw = await _blobStore.read(_pendingCleanupKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded.length != 3) {
      throw const AccountSecurityException('账户安全清理意图损坏');
    }
    final ids = decoded['account_ids'];
    final indexes = decoded['wallet_indices'];
    final deleteWide = decoded['delete_wallet_wide_key'];
    if (ids is! List ||
        indexes is! List ||
        deleteWide is! bool ||
        ids.any((value) => value is! String) ||
        indexes.any((value) => value is! int)) {
      throw const AccountSecurityException('账户安全清理意图字段损坏');
    }
    final accountIds = ids.cast<String>().toSet();
    final state = await _wallet.getState().result;
    if (state.accounts.any(
          (account) => accountIds.contains(account.accountId),
        ) ||
        state.diagnostics.any(
          (record) => indexes.contains(record.walletIndex),
        )) {
      // 存在事实时保留意图；普通刷新不能撤销另一条已接纳删除的准备记录。
      throw const AccountSecurityException('钱包事实仍存在，尚不能执行后续清理');
    }
    // 诊断仍在即事实未删；Core安全清理未完成时保留原意图，不能先清关联设备材料。
    if (state.cleanupPending) {
      throw const AccountSecurityException('钱包安全清理尚未完成');
    }
    final bindings = await _bindingStore.readAll();
    for (final binding in bindings.where(
      (binding) => accountIds.contains(binding.accountId),
    )) {
      await _deleteDeviceKeyMaterial(binding);
      await _deviceSubkey.delete(binding.cidNumber);
      await _bindingStore.clearForCid(binding.cidNumber);
    }
    for (final index in indexes.cast<int>()) {
      await _removeDeviceKeyMaterialIndexEntries(index, accountIds);
      if (deleteWide) await _deviceDataKeyVault.delete(index);
    }
    // 原历史/清算行清理仍调用各自唯一实现；全部成功后才归还同一持久意图。
    for (final accountId in accountIds) {
      await LocalTxStore.deleteWalletLocalHistory(accountId);
      await ClearingBankPrefs.clear(accountId);
    }
    await _blobStore.delete(_pendingCleanupKey);
    if (await _blobStore.read(_pendingCleanupKey) != null) {
      throw const AccountSecurityException('账户安全清理意图未能删除');
    }
    revision.value += 1;
  }

  Future<void> cancelAccountCleanup() => _blobStore.delete(_pendingCleanupKey);

  /// AppLock 全量擦除使用：删除全部已登记 CID 的 P-256 子钥、用途钥密文与当前
  /// SDK 目录可证明的设备数据钥。旧钱包数据库不参与扫描、迁移或回退。
  Future<void> wipeAllDeviceMaterial(Iterable<int> walletIndexes) async {
    final indexes = walletIndexes.toSet();
    final bindings = await _bindingStore.readAll();
    // 首次恢复取消也会登记公开索引；全量擦除必须覆盖尚未激活的恢复状态。
    for (final index in indexes) {
      for (final binding in await _readDeviceKeyMaterialIndex(
        _deviceKeyMaterialIndexName(index),
      )) {
        if (!bindings.any((item) => _flightKey(item) == _flightKey(binding))) {
          bindings.add(binding);
        }
      }
    }
    for (final binding in bindings) {
      await _deleteDeviceKeyMaterial(binding);
      await _deviceSubkey.delete(binding.cidNumber);
      await _bindingStore.clearForCid(binding.cidNumber);
    }
    for (final index in indexes) {
      await _deviceDataKeyVault.delete(index);
      await _blobStore.delete(_deviceKeyMaterialIndexName(index));
    }
    await _blobStore.delete(_pendingCleanupKey);
    revision.value += 1;
  }

  Future<AccountDataBinding> _requireBinding(String accountId) async {
    final binding = await _bindingStore.readForAccountId(accountId);
    if (binding == null || binding.accountId != accountId) {
      throw const AccountSecurityException('当前 CID 钱包绑定尚未激活私有数据密钥');
    }
    return binding;
  }

  Future<CitizenWalletStateAccount?> _account(String accountId) async {
    final state = await _wallet.getState().result;
    for (final account in state.accounts) {
      if (account.accountId == accountId) return account;
    }
    return null;
  }

  Future<void> _rejectSameAccountRevisionChange(
    AccountDataBinding binding,
  ) async {
    final active = await _bindingStore.readForCid(binding.cidNumber);
    if (active != null &&
        active.genesisHash == binding.genesisHash &&
        active.accountId == binding.accountId &&
        active.bindingRevision != binding.bindingRevision) {
      throw const AccountSecurityException('相同钱包账户不允许通过绑定版本变化重复换绑');
    }
  }

  Future<bool> _hasDeviceDataKeyBlobs(
    AccountDataBinding binding,
    List<DataKeyRequest> requests,
  ) async {
    for (final request in requests) {
      final blob = await _blobStore.read(
        _deviceDataKeyBlobName(binding, request),
      );
      if (blob == null || blob.isEmpty) return false;
    }
    return true;
  }

  Future<List<DataKeyRequest>> _missingDeviceDataKeyRequests(
    AccountDataBinding binding,
  ) async {
    final missing = <DataKeyRequest>[];
    for (final request in _deviceDataKeyRequests) {
      final blob = await _blobStore.read(
        _deviceDataKeyBlobName(binding, request),
      );
      if (blob == null || blob.isEmpty) missing.add(request);
    }
    return missing;
  }

  static String _flightKey(AccountDataBinding binding) =>
      '${binding.genesisHash}|${binding.cidNumber}|${binding.accountId}';

  static String _deviceDataKeyRecoveryName(AccountDataBinding binding) =>
      'device_data_key_recovery_pending_'
      '${Uri.encodeComponent(binding.genesisHash)}_'
      '${Uri.encodeComponent(binding.cidNumber)}_'
      '${binding.bindingRevision}_${binding.accountId}';

  static String _deviceDataKeyBlobName(
    AccountDataBinding binding,
    DataKeyRequest request,
  ) =>
      'citizenapp_device_data_key_'
      '${Uri.encodeComponent(binding.genesisHash)}_'
      '${Uri.encodeComponent(binding.cidNumber)}_'
      '${binding.bindingRevision}_${binding.accountId}_'
      '${request.purpose.name}_${Uri.encodeComponent(request.context ?? '')}';

  static Uint8List _deviceDataKeyAad(
    AccountDataBinding binding,
    int walletIndex,
    DataKeyRequest request,
  ) => Uint8List.fromList(
    utf8.encode(
      'wallet_index=$walletIndex|genesis_hash=${binding.genesisHash}|'
      'cid_number=${binding.cidNumber}|binding_revision=${binding.bindingRevision}|'
      'account_id=${binding.accountId}|purpose=${request.purpose.domain}|'
      'context=${request.context ?? ''}',
    ),
  );

  static String _deviceKeyMaterialIndexName(int walletIndex) =>
      'citizenapp_device_key_material_index_$walletIndex';

  Future<void> _recordDeviceKeyMaterialIndex(
    int walletIndex,
    AccountDataBinding binding,
  ) async {
    final name = _deviceKeyMaterialIndexName(walletIndex);
    final bindings = await _readDeviceKeyMaterialIndex(name);
    if (!bindings.any((item) => _flightKey(item) == _flightKey(binding))) {
      bindings.add(binding);
    }
    await _blobStore.write(
      name,
      jsonEncode(bindings.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<AccountDataBinding>> _readDeviceKeyMaterialIndex(
    String name,
  ) async {
    final raw = await _blobStore.read(name);
    if (raw == null || raw.isEmpty) return <AccountDataBinding>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const AccountSecurityException('设备数据钥密文索引不是数组');
    }
    final bindings = <AccountDataBinding>[];
    for (final value in decoded) {
      if (value is! Map) {
        throw const AccountSecurityException('设备数据钥密文索引条目无效');
      }
      final binding = AccountDataBinding.fromJson(jsonEncode(value));
      if (binding == null) {
        throw const AccountSecurityException('设备数据钥密文索引绑定损坏');
      }
      bindings.add(binding);
    }
    return bindings;
  }

  Future<void> _removeDeviceKeyMaterialIndexEntries(
    int walletIndex,
    Set<String> accountIds,
  ) async {
    final name = _deviceKeyMaterialIndexName(walletIndex);
    final remaining = (await _readDeviceKeyMaterialIndex(name))
        .where((binding) => !accountIds.contains(binding.accountId))
        .toList(growable: false);
    if (remaining.isEmpty) {
      await _blobStore.delete(name);
    } else {
      await _blobStore.write(
        name,
        jsonEncode(remaining.map((item) => item.toJson()).toList()),
      );
    }
  }

  Future<void> _deleteDeviceKeyMaterial(AccountDataBinding binding) async {
    final recoveryName = _deviceDataKeyRecoveryName(binding);
    await _blobStore.delete(recoveryName);
    if (await _blobStore.read(recoveryName) != null) {
      throw const AccountSecurityException('设备用途钥恢复状态仍存在');
    }
    for (final request in _deviceDataKeyRequests) {
      final name = _deviceDataKeyBlobName(binding, request);
      await _blobStore.delete(name);
      if (await _blobStore.read(name) != null) {
        throw AccountSecurityException('设备数据钥密文仍存在：$name');
      }
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  void dispose() => revision.dispose();
}
