import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/security/local_cipher.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/account_security_service.dart';

/// 通讯录唯一业务模型。
///
/// `cid_number` 是联系人关系的永久主键；`account_id` / `ss58_address` 是该 CID
/// 当前绑定的签名账户与展示地址，换绑后允许更新。公开昵称、头像和签名属于用户公开
/// 资料，不复制进通讯录；`contact_remark` 只保存当前用户自己的私人备注。
class UserContact {
  const UserContact({
    required this.cidNumber,
    required this.accountId,
    required this.ss58Address,
    required this.contactRemark,
    required this.createdAt,
    required this.updatedAt,
  });

  final String cidNumber;
  final String accountId;
  final String ss58Address;
  final String contactRemark;
  final int createdAt;
  final int updatedAt;

  UserContact copyWith({
    String? cidNumber,
    String? accountId,
    String? ss58Address,
    String? contactRemark,
    int? createdAt,
    int? updatedAt,
  }) {
    return UserContact(
      cidNumber: cidNumber ?? this.cidNumber,
      accountId: accountId ?? this.accountId,
      ss58Address: ss58Address ?? this.ss58Address,
      contactRemark: contactRemark ?? this.contactRemark,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cid_number': cidNumber,
        'account_id': accountId,
        'ss58_address': ss58Address,
        'contact_remark': contactRemark,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory UserContact.fromJson(Map<String, dynamic> json) {
    final cidNumber = UserContactService.requireCidNumber(
      json['cid_number']?.toString() ?? '',
    );
    final accountId = json['account_id']?.toString() ?? '';
    final ss58Address = json['ss58_address']?.toString().trim() ?? '';
    final contactRemark = json['contact_remark'];
    if (!isAccountIdText(accountId) ||
        ss58Address.isEmpty ||
        contactRemark is! String) {
      throw const FormatException('通讯录 CID、账户、地址或私人备注不合法');
    }
    if (UserContactService.accountIdFromSs58(ss58Address) != accountId) {
      throw const FormatException('通讯录 account_id 与 ss58_address 不匹配');
    }
    final createdAt = _asInt(json['created_at']);
    final updatedAt = _asInt(json['updated_at']);
    if (createdAt <= 0 || updatedAt <= 0) {
      throw const FormatException('通讯录时间戳不合法');
    }
    final normalizedRemark =
        UserContactService.normalizeContactRemark(contactRemark);
    return UserContact(
      cidNumber: cidNumber,
      accountId: accountId,
      ss58Address: UserContactService.normalizeSs58Address(ss58Address),
      contactRemark: normalizedRemark,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class ContactImportResult {
  const ContactImportResult({required this.contact, required this.created});

  final UserContact contact;
  final bool created;
}

enum ContactSyncPhase { idle, syncing, synced, pending, offline, failed }

class ContactSyncState {
  const ContactSyncState({
    required this.phase,
    this.updatedAt = 0,
    this.message,
  });

  final ContactSyncPhase phase;
  final int updatedAt;
  final String? message;

  String get label => switch (phase) {
        ContactSyncPhase.syncing => '正在同步',
        ContactSyncPhase.synced => '云端已同步',
        ContactSyncPhase.pending => '待同步',
        ContactSyncPhase.offline => '离线，显示本地通讯录',
        ContactSyncPhase.failed => '同步失败，点击重试',
        ContactSyncPhase.idle => '本地通讯录',
      };
}

/// 联系人端到端加密器。AES-GCM 保护内容与完整性，HMAC 生成不透明 contact_id；
/// 两把钥匙均经 AccountSecurityService 调用 CitizenSDK 应用派生钥，本类接触不到账户秘密。
class ContactCryptor {
  ContactCryptor({
    required String ownerCidNumber,
    required this.bindingRevision,
    required this.accountId,
    required this.keys,
  }) : ownerCidNumber = UserContactService.requireCidNumber(ownerCidNumber) {
    if (bindingRevision <= 0) {
      throw const FormatException('通讯录密文绑定版本必须大于 0');
    }
    UserContactService.requireAccountId(accountId);
  }

  static const String _domain = 'citizenapp.contacts';
  final String ownerCidNumber;
  final int bindingRevision;
  final String accountId;
  final ContactKeyMaterial keys;
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();

  Future<String> contactId(String cidNumber) async {
    final mac = await _hmac.calculateMac(
      utf8.encode(UserContactService.requireCidNumber(cidNumber)),
      secretKey: SecretKey(keys.indexKey),
    );
    return _hex(mac.bytes);
  }

  Future<SquareEncryptedContact> encrypt(UserContact contact) async {
    final id = await contactId(contact.cidNumber);
    final clear = utf8.encode(jsonEncode(<String, Object?>{
      'owner_cid_number': ownerCidNumber,
      'cid_number': contact.cidNumber,
      'account_id': contact.accountId,
      'ss58_address': contact.ss58Address,
      'contact_remark': contact.contactRemark,
      'created_at': contact.createdAt,
      'updated_at': contact.updatedAt,
    }));
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      clear,
      secretKey: SecretKey(keys.encryptionKey),
      nonce: nonce,
      aad: _aad(id),
    );
    return SquareEncryptedContact(
      bindingRevision: bindingRevision,
      accountId: accountId,
      contactId: id,
      ciphertext: _base64UrlEncode(box.cipherText),
      nonce: _base64UrlEncode(box.nonce),
      mac: _base64UrlEncode(box.mac.bytes),
      updatedAt: contact.updatedAt,
    );
  }

  Future<UserContact> decrypt(SquareEncryptedContact record) async {
    try {
      if (record.bindingRevision != bindingRevision ||
          record.accountId != accountId) {
        throw const FormatException('通讯录密文钱包绑定上下文不匹配');
      }
      final clear = await _aes.decrypt(
        SecretBox(
          _base64UrlDecode(record.ciphertext),
          nonce: _base64UrlDecode(record.nonce),
          mac: Mac(_base64UrlDecode(record.mac)),
        ),
        secretKey: SecretKey(keys.encryptionKey),
        aad: _aad(record.contactId),
      );
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic> ||
          decoded['owner_cid_number'] != ownerCidNumber) {
        throw const FormatException('通讯录密文归属不匹配');
      }
      final contact = UserContact.fromJson(<String, dynamic>{
        'cid_number': decoded['cid_number'],
        'account_id': decoded['account_id'],
        'ss58_address': decoded['ss58_address'],
        'contact_remark': decoded['contact_remark'],
        'created_at': decoded['created_at'],
        'updated_at': decoded['updated_at'],
      });
      if (await contactId(contact.cidNumber) != record.contactId) {
        throw const FormatException('通讯录密文索引不匹配');
      }
      return contact;
    } on SecretBoxAuthenticationError {
      throw const FormatException('通讯录密文认证失败');
    }
  }

  List<int> _aad(String id) => utf8.encode(
        '$_domain|$ownerCidNumber|$bindingRevision|$accountId|$id',
      );
}

/// 本地优先的加密通讯录服务。Isar 保存按永久 CID 隔离的可用缓存与待同步操作；
/// Cloudflare 只接收 [SquareEncryptedContact]，网络失败不会阻塞本地增删改。
class UserContactService {
  UserContactService({
    required AccountSecurityService accountSecurity,
    required CurrentUserContext currentUserContext,
    required SquareSessionProvider sessionProvider,
    required CitizenIdentityChainReader chainReader,
    SquareApiClient? apiClient,
    bool autoSync = true,
  })  : _accountSecurity = accountSecurity,
        _sessionProvider = sessionProvider,
        _apiClient = apiClient ?? SquareApiClient(),
        _currentUserContext = currentUserContext,
        _chainReader = chainReader,
        _autoSync = autoSync;

  static const String _contactsPrefix = 'user.contact.book:';
  static const String _pendingPrefix = 'user.contact.pending:';
  static const String _syncPrefix = 'user.contact.sync:';
  static const String _handoverPrefix = 'user.contact.handover:';
  static const String _inaccessiblePrefix = 'user.contact.inaccessible:';

  final AccountSecurityService _accountSecurity;
  final SquareSessionProvider _sessionProvider;
  final SquareApiClient _apiClient;
  final CurrentUserContext _currentUserContext;
  final CitizenIdentityChainReader _chainReader;
  final bool _autoSync;

  /// 只有刷新联系人绑定、转账等权限动作才创建链读入口。
  /// 普通通讯录/Chat 搜索只读本地密文，构造服务时不得建立第二节点。
  CitizenIdentityChainReader get _finalizedIdentityReader =>
      _chainReader;

  /// 通讯录永久归属 CID；当前绑定账户负责派生本绑定版本密钥和云会话鉴权。
  CurrentUserContext get _currentUser => _currentUserContext;

  final ValueNotifier<ContactSyncState> syncState =
      ValueNotifier<ContactSyncState>(
    const ContactSyncState(phase: ContactSyncPhase.idle),
  );

  /// 通讯录只属于当前 CID 身份，调用方不得用交易付款钱包覆盖其身份账户。
  Future<List<UserContact>> getContacts() async {
    final owner = await _requireIdentityOwner();
    return _getContacts(owner);
  }

  Future<List<UserContact>> _getContacts(_ContactOwner owner) async {
    return _readContacts(owner);
  }

  /// 从同一个 finalized 区块批量刷新全部联系人当前绑定账户。
  ///
  /// 绑定快照只是可更新缓存；联系人关系与备注仍只归 CID。失效或不闭环的 CID
  /// 不会用此前账户冒充有效绑定，也不会因此删除用户的联系人关系。
  Future<List<UserContact>> refreshContactBindings() async {
    final owner = await _requireIdentityOwner();
    final contacts = await _readContacts(owner);
    if (contacts.isEmpty) return contacts;
    final bindings = await _finalizedIdentityReader.readBindingsByCidNumbers(
      contacts.map((contact) => contact.cidNumber),
    );
    return _applyBindingSnapshots(owner, contacts, bindings);
  }

  /// 转账等账户敏感动作前，按 CID 严格读取 finalized 当前绑定。
  ///
  /// 链读失败、CID 未激活或双向绑定不闭环时直接失败，禁止回退通讯录旧地址。
  Future<UserContact> resolveCurrentContact(String contactCidNumber) async {
    final owner = await _requireIdentityOwner();
    final cidNumber = requireCidNumber(contactCidNumber);
    final contacts = await _readContacts(owner);
    final index =
        contacts.indexWhere((contact) => contact.cidNumber == cidNumber);
    if (index < 0) throw Exception('未找到联系人');
    final binding =
        await _finalizedIdentityReader.readBindingByCidNumber(cidNumber);
    if (binding == null) {
      throw StateError('联系人 CID 当前没有有效钱包绑定');
    }
    final refreshed = await _applyBindingSnapshots(
      owner,
      contacts,
      <String, CitizenBindingChainSnapshot>{cidNumber: binding},
    );
    return refreshed.firstWhere((contact) => contact.cidNumber == cidNumber);
  }

  Future<List<UserContact>> _applyBindingSnapshots(
    _ContactOwner owner,
    List<UserContact> contacts,
    Map<String, CitizenBindingChainSnapshot> bindings,
  ) async {
    final refreshed = contacts.toList(growable: true);
    final changed = <UserContact>[];
    for (var index = 0; index < refreshed.length; index++) {
      final contact = refreshed[index];
      final binding = bindings[contact.cidNumber];
      if (binding == null) continue;
      final accountId = requireAccountId(binding.accountIdText);
      if (accountId == contact.accountId) continue;
      final next = contact.copyWith(
        accountId: accountId,
        ss58Address: ss58FromAccountIdText(accountId),
        updatedAt: _nextTimestamp(contact.updatedAt),
      );
      refreshed[index] = next;
      changed.add(next);
    }
    if (changed.isEmpty) return _sorted(refreshed);

    final pending = (await _readPending(owner)).toList(growable: true);
    for (final contact in changed) {
      pending
        ..removeWhere((item) => item.cidNumber == contact.cidNumber)
        ..add(_PendingContactOp.upsert(contact.cidNumber, contact.updatedAt));
    }
    await _writeSnapshot(owner, refreshed, pending);
    await _setSyncState(owner, ContactSyncPhase.pending);
    if (_autoSync) unawaited(_syncOwner(owner));
    return _sorted(refreshed);
  }

  /// 返回通讯录当前所属的身份账户，供扫码页做“不能添加自己”校验。
  Future<String> getAccountId() async =>
      (await _requireIdentityOwner()).accountId;

  Future<ContactImportResult> addContact({
    required String cidNumber,
    required String ss58Address,
    required String contactRemark,
  }) async {
    final owner = await _requireIdentityOwner();
    final normalizedCidNumber = requireCidNumber(cidNumber);
    final normalizedSs58Address = normalizeSs58Address(ss58Address);
    final contactAccountId = accountIdFromSs58(normalizedSs58Address);
    final normalizedRemark = normalizeContactRemark(contactRemark);
    if (normalizedCidNumber == owner.cidNumber ||
        contactAccountId == owner.accountId) {
      throw const FormatException('不能把自己加入通讯录');
    }

    final contacts = (await _readContacts(owner)).toList(growable: true);
    final index =
        contacts.indexWhere((item) => item.cidNumber == normalizedCidNumber);
    final created = index < 0;
    final now = _nextTimestamp(created ? 0 : contacts[index].updatedAt);
    final contact = created
        ? UserContact(
            cidNumber: normalizedCidNumber,
            accountId: contactAccountId,
            ss58Address: normalizedSs58Address,
            contactRemark: normalizedRemark,
            createdAt: now,
            updatedAt: now,
          )
        : contacts[index].copyWith(
            accountId: contactAccountId,
            ss58Address: normalizedSs58Address,
            // 扫码得到的空备注不得抹掉用户已经填写的私人备注。
            contactRemark: normalizedRemark.isEmpty
                ? contacts[index].contactRemark
                : normalizedRemark,
            updatedAt: now,
          );
    if (created) {
      contacts.add(contact);
    } else {
      contacts[index] = contact;
    }
    await _writeContactsAndPending(
      owner,
      contacts,
      _PendingContactOp.upsert(contact.cidNumber, contact.updatedAt),
    );
    if (_autoSync) {
      unawaited(_syncOwner(owner));
    }
    return ContactImportResult(contact: contact, created: created);
  }

  Future<List<UserContact>> renameContact(
    String contactCidNumber,
    String contactRemark,
  ) async {
    final owner = await _requireIdentityOwner();
    final normalizedContactCidNumber = requireCidNumber(contactCidNumber);
    final normalizedRemark = normalizeContactRemark(contactRemark);
    final contacts = (await _getContacts(owner)).toList(growable: true);
    final index = contacts
        .indexWhere((item) => item.cidNumber == normalizedContactCidNumber);
    if (index < 0) {
      throw Exception('未找到联系人');
    }
    contacts[index] = contacts[index].copyWith(
      contactRemark: normalizedRemark,
      updatedAt: _nextTimestamp(contacts[index].updatedAt),
    );
    await _writeContactsAndPending(
      owner,
      contacts,
      _PendingContactOp.upsert(
        contacts[index].cidNumber,
        contacts[index].updatedAt,
      ),
    );
    if (_autoSync) {
      unawaited(_syncOwner(owner));
    }
    return _sorted(contacts);
  }

  Future<List<UserContact>> deleteContact(String contactCidNumber) async {
    final owner = await _requireIdentityOwner();
    final normalizedContactCidNumber = requireCidNumber(contactCidNumber);
    final contacts = (await _getContacts(owner))
        .where((item) => item.cidNumber != normalizedContactCidNumber)
        .toList(growable: false);
    await _writeContactsAndPending(
      owner,
      contacts,
      _PendingContactOp.delete(
        normalizedContactCidNumber,
        _nextTimestamp(),
      ),
    );
    if (_autoSync) {
      unawaited(_syncOwner(owner));
    }
    return _sorted(contacts);
  }

  /// 拉云端快照后重放本机待同步操作。损坏或属于其他钱包的密文只被忽略，
  /// 绝不覆盖本机有效缓存；下一次正常写入会修复对应云端记录。
  /// 同步入口同样只接受身份账户；付款钱包和调用方参数不能改变密文归属。
  Future<List<UserContact>> sync() async {
    return _syncOwner(await _requireIdentityOwner());
  }

  /// 链上换绑提交前预演通讯录交接，并只落目标账户密文暂存版。
  ///
  /// 本地此前密文只在内存中解开，随后立即用目标账户密钥重加密；目标云端密文只在
  /// finalized 后由新账户当前会话上传。源版本不覆盖、不删除，换绑失败时仍可正常使用。
  Future<void> stageAccountHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    _validateHandover(source, target);
    final sourceLocalKey = await _localKvKeyForBinding(source);
    final targetLocalKey = await _localKvKeyForBinding(target);
    ContactKeyMaterial? sourceCloudKeys;
    ContactKeyMaterial? targetCloudKeys;
    try {
      final canonicalKeys = <String>[
        '$_contactsPrefix${source.cidNumber}',
        '$_pendingPrefix${source.cidNumber}',
        '$_syncPrefix${source.cidNumber}',
      ];
      final stagedValues = <String, String>{};
      final stagedCanonicalKeys = <String>[];
      for (final canonicalKey in canonicalKeys) {
        final blob = await _readRawKv(canonicalKey);
        if (blob == null || blob.isEmpty) continue;
        final plaintext = await LocalCipher.decryptString(
          key: sourceLocalKey,
          blob: blob,
          aad: canonicalKey,
        );
        final targetCipher = await LocalCipher.encryptString(
          key: targetLocalKey,
          plaintext: plaintext,
          aad: canonicalKey,
        );
        final verified = await LocalCipher.decryptString(
          key: targetLocalKey,
          blob: targetCipher,
          aad: canonicalKey,
        );
        if (verified != plaintext) {
          throw StateError('通讯录本地新账户密文回读不一致');
        }
        stagedValues[_handoverValueKey(target, canonicalKey)] = targetCipher;
        stagedCanonicalKeys.add(canonicalKey);
      }

      // 先落只含目标密文的清单，再读取云端当前版本。换绑生效前绝不向 Worker 预写
      // 尚未成为当前绑定的目标版本，避免扩大当前会话的云端写权限。
      final manifestKey = _handoverManifestKey(target);
      await UserIsar.instance.writeTxn((isar) async {
        for (final entry in stagedValues.entries) {
          await _putKvInTxn(isar, entry.key, entry.value);
        }
        await _putKvInTxn(
          isar,
          manifestKey,
          jsonEncode(<String, Object?>{
            'source': source.toJson(),
            'target': target.toJson(),
            'canonical_keys': stagedCanonicalKeys,
            'staged_keys': stagedValues.keys.toList(growable: false),
            'previous_contact_ids': const <String>[],
            'target_contact_ids': const <String>[],
            'target_records': const <Object>[],
          }),
        );
      });

      sourceCloudKeys =
          await _accountSecurity.contactKeyMaterialForBinding(source);
      targetCloudKeys =
          await _accountSecurity.contactKeyMaterialForBinding(target);
      final sourceCryptor = ContactCryptor(
        ownerCidNumber: source.cidNumber,
        bindingRevision: source.bindingRevision,
        accountId: source.accountId,
        keys: sourceCloudKeys,
      );
      final targetCryptor = ContactCryptor(
        ownerCidNumber: target.cidNumber,
        bindingRevision: target.bindingRevision,
        accountId: target.accountId,
        keys: targetCloudKeys,
      );
      final sourceSession = await _sessionProvider.ensureSession();
      if (sourceSession == null ||
          sourceSession.cidNumber != source.cidNumber ||
          sourceSession.bindingRevision != source.bindingRevision ||
          sourceSession.accountId != source.accountId) {
        throw const SquareApiException('通讯录交接需要当前账户有效会话');
      }
      final previousContactIds = <String>[];
      final targetContactIds = <String>[];
      final targetRecords = <SquareEncryptedContact>[];
      String? cursor;
      do {
        final page = await _apiClient.fetchEncryptedContacts(
          session: sourceSession,
          cursor: cursor,
        );
        for (final record in page.items) {
          final contact = await sourceCryptor.decrypt(record);
          previousContactIds.add(record.contactId);
          final targetRecord = await targetCryptor.encrypt(contact);
          final verified = await targetCryptor.decrypt(targetRecord);
          if (jsonEncode(verified.toJson()) != jsonEncode(contact.toJson())) {
            throw StateError('通讯录云端新账户密文回读不一致');
          }
          targetContactIds.add(targetRecord.contactId);
          targetRecords.add(targetRecord);
          // 每生成一条目标密文就先持久化清单；明文不落盘，崩溃后只会保留可安全重试的密文。
          await UserIsar.instance.writeTxn((isar) async {
            await _putKvInTxn(
              isar,
              manifestKey,
              _encodeHandoverManifest(
                source: source,
                target: target,
                canonicalKeys: stagedCanonicalKeys,
                stagedKeys: stagedValues.keys.toList(growable: false),
                previousContactIds: previousContactIds,
                targetContactIds: targetContactIds,
                targetRecords: targetRecords,
              ),
            );
          });
        }
        cursor = page.nextCursor;
      } while (cursor != null);

      final manifest = _encodeHandoverManifest(
        source: source,
        target: target,
        canonicalKeys: stagedCanonicalKeys,
        stagedKeys: stagedValues.keys.toList(growable: false),
        previousContactIds: previousContactIds,
        targetContactIds: targetContactIds,
        targetRecords: targetRecords,
      );
      await UserIsar.instance.writeTxn((isar) async {
        await _putKvInTxn(isar, manifestKey, manifest);
      });
    } finally {
      sourceLocalKey.fillRange(0, sourceLocalKey.length, 0);
      targetLocalKey.fillRange(0, targetLocalKey.length, 0);
      sourceCloudKeys?.dispose();
      targetCloudKeys?.dispose();
    }
  }

  /// finalized 已确认新账户接管后提交本地暂存密文，并由新会话删除此前云端版本。
  ///
  /// 本方法幂等；只有目标密文上传回读、本地切换和此前云端清理全部成功才删除交接清单。
  Future<void> commitAccountHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    _validateHandover(source, target);
    final manifestKey = _handoverManifestKey(target);
    final raw = await _readRawKv(manifestKey);
    if (raw == null || raw.isEmpty) return;
    final manifest = jsonDecode(raw);
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('通讯录换绑交接清单损坏');
    }
    final canonicalKeys = (manifest['canonical_keys'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final stagedKeys = (manifest['staged_keys'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    if (canonicalKeys.length != stagedKeys.length) {
      throw const FormatException('通讯录换绑交接清单不完整');
    }
    final stagedValues = <String>[];
    for (final key in stagedKeys) {
      final value = await _readRawKv(key);
      if (value == null || value.isEmpty) {
        throw const FormatException('通讯录换绑暂存密文缺失');
      }
      stagedValues.add(value);
    }
    await UserIsar.instance.writeTxn((isar) async {
      for (var index = 0; index < canonicalKeys.length; index++) {
        await _putKvInTxn(isar, canonicalKeys[index], stagedValues[index]);
      }
    });

    final targetSession =
        await _sessionProvider.ensureSessionForAccountId(target.accountId);
    if (targetSession == null ||
        targetSession.cidNumber != target.cidNumber ||
        targetSession.bindingRevision != target.bindingRevision ||
        targetSession.accountId != target.accountId) {
      throw const SquareApiException('通讯录交接清理需要新账户当前有效会话');
    }
    final targetContactIds = (manifest['target_contact_ids'] as List?)
            ?.whereType<String>()
            .toSet() ??
        const <String>{};
    final targetRecords = (manifest['target_records'] as List?)
            ?.whereType<Map>()
            .map((record) => SquareEncryptedContact.fromJson(
                  Map<String, dynamic>.from(record),
                ))
            .toList(growable: false) ??
        const <SquareEncryptedContact>[];
    if (targetRecords.length != targetContactIds.length ||
        targetRecords.any((record) =>
            record.bindingRevision != target.bindingRevision ||
            record.accountId != target.accountId ||
            !targetContactIds.contains(record.contactId))) {
      throw const FormatException('通讯录目标账户密文清单不完整');
    }
    for (final record in targetRecords) {
      await _apiClient.putEncryptedContact(
        session: targetSession,
        contact: record,
      );
    }
    ContactKeyMaterial? targetKeys;
    try {
      targetKeys = await _accountSecurity.contactKeyMaterialForBinding(target);
      final targetCryptor = ContactCryptor(
        ownerCidNumber: target.cidNumber,
        bindingRevision: target.bindingRevision,
        accountId: target.accountId,
        keys: targetKeys,
      );
      final verifiedTargetIds = <String>{};
      String? cursor;
      do {
        final page = await _apiClient.fetchEncryptedContacts(
          session: targetSession,
          cursor: cursor,
        );
        for (final record in page.items) {
          await targetCryptor.decrypt(record);
          verifiedTargetIds.add(record.contactId);
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      if (!verifiedTargetIds.containsAll(targetContactIds)) {
        throw const SquareApiException('通讯录目标账户云端密文尚未完整回读，禁止清理此前版本');
      }
    } finally {
      targetKeys?.dispose();
    }
    final previousContactIds = (manifest['previous_contact_ids'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    for (final contactId in previousContactIds) {
      await _apiClient.deleteEncryptedContact(
        session: targetSession,
        contactId: contactId,
        bindingRevision: source.bindingRevision,
        accountId: source.accountId,
      );
    }
    await _deleteHandoverRows(manifestKey, stagedKeys);
  }

  /// 换绑交易未生效时删除目标暂存版；源密文始终不动。
  Future<void> discardAccountHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    _validateHandover(source, target);
    final manifestKey = _handoverManifestKey(target);
    final raw = await _readRawKv(manifestKey);
    if (raw == null || raw.isEmpty) return;
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    final stagedKeys = (manifest['staged_keys'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    await _deleteHandoverRows(manifestKey, stagedKeys);
  }

  /// 没有当前账户签名的换绑完成后，把此前绑定的本地通讯录密文移出当前入口。
  ///
  /// 这里只移动已经存在的密文，不解密、不重新加密，也不要求此前账户或此前设备。
  /// 新账户随后从空的当前 KV 开始使用通讯录；此前密文按公开绑定上下文保留，绝不被
  /// 新账户密钥误当作损坏数据覆盖。
  Future<void> isolateInaccessibleBinding(
    AccountDataBinding previous,
  ) async {
    previous.validate();
    final canonicalKeys = <String>[
      '$_contactsPrefix${previous.cidNumber}',
      '$_pendingPrefix${previous.cidNumber}',
      '$_syncPrefix${previous.cidNumber}',
    ];
    await UserIsar.instance.writeTxn((isar) async {
      for (final canonicalKey in canonicalKeys) {
        final row =
            await isar.userContactStateEntitys.getByStateKey(canonicalKey);
        if (row == null) continue;
        final archiveKey = _inaccessibleKey(previous, canonicalKey);
        final archive =
            await isar.userContactStateEntitys.getByStateKey(archiveKey) ??
                _newContactState(archiveKey);
        archive
          ..stateKey = archiveKey
          ..sealedPayload = row.sealedPayload;
        await isar.userContactStateEntitys.put(archive);
        await isar.userContactStateEntitys.delete(row.id);
      }
    });
  }

  Future<void> _deleteHandoverRows(
    String manifestKey,
    List<String> stagedKeys,
  ) async {
    await UserIsar.instance.writeTxn((isar) async {
      for (final key in stagedKeys) {
        final row = await isar.userContactStateEntitys.getByStateKey(key);
        if (row != null) await isar.userContactStateEntitys.delete(row.id);
      }
      final manifestRow =
          await isar.userContactStateEntitys.getByStateKey(manifestKey);
      if (manifestRow != null) {
        await isar.userContactStateEntitys.delete(manifestRow.id);
      }
    });
  }

  Future<List<UserContact>> _syncOwner(_ContactOwner owner) async {
    await _setSyncState(owner, ContactSyncPhase.syncing);
    ContactKeyMaterial? keys;
    try {
      keys = await _accountSecurity.ensureContactKeyMaterialForAccountId(
        owner.accountId,
      );
      final session = await _sessionProvider.ensureSession();
      if (session == null ||
          session.accountId != owner.accountId ||
          session.cidNumber != owner.cidNumber) {
        throw const SquareApiException('通讯录云同步需要当前 CID 与绑定账户的精确会话');
      }
      final cryptor = ContactCryptor(
        ownerCidNumber: owner.cidNumber,
        bindingRevision: owner.bindingRevision,
        accountId: owner.accountId,
        keys: keys,
      );
      final cloudRecords = <SquareEncryptedContact>[];
      String? cursor;
      do {
        final page = await _apiClient.fetchEncryptedContacts(
          session: session,
          cursor: cursor,
        );
        cloudRecords.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);

      final pending = await _readPending(owner);
      final pendingCidNumbers = pending.map((item) => item.cidNumber).toSet();
      final local = await _readContacts(owner);
      final merged = <String, UserContact>{};
      final localByContactId = <String, UserContact>{};
      for (final contact in local) {
        localByContactId[await cryptor.contactId(contact.cidNumber)] = contact;
      }
      for (final record in cloudRecords) {
        try {
          final contact = await cryptor.decrypt(record);
          if (!pendingCidNumbers.contains(contact.cidNumber)) {
            merged[contact.cidNumber] = contact;
          }
        } on FormatException {
          // 单条损坏不应让整个通讯录不可用，也不能覆盖同 ID 的本地有效缓存。
          final cached = localByContactId[record.contactId];
          if (cached != null) merged[cached.cidNumber] = cached;
        }
      }
      for (final contact in local) {
        if (pendingCidNumbers.contains(contact.cidNumber)) {
          merged[contact.cidNumber] = contact;
        }
      }
      await _writeContacts(owner, merged.values.toList(growable: false));

      for (final op in List<_PendingContactOp>.from(pending)) {
        if (op.action == _PendingAction.delete) {
          await _apiClient.deleteEncryptedContact(
            session: session,
            contactId: await cryptor.contactId(op.cidNumber),
          );
        } else {
          final contact = merged[op.cidNumber];
          if (contact == null) continue;
          await _apiClient.putEncryptedContact(
            session: session,
            contact: await cryptor.encrypt(contact),
          );
        }
        await _removePending(owner, op);
      }
      final result = await _readContacts(owner);
      await _setSyncState(owner, ContactSyncPhase.synced);
      return result;
    } on Exception catch (error) {
      final pending = await _readPending(owner);
      final phase =
          pending.isEmpty ? ContactSyncPhase.offline : ContactSyncPhase.failed;
      await _setSyncState(owner, phase, message: error.toString());
      return _readContacts(owner);
    } finally {
      keys?.dispose();
    }
  }

  Future<ContactSyncState> readSyncState() async {
    final owner = await _requireIdentityOwner();
    final raw = await _readKv(owner, '$_syncPrefix${owner.cidNumber}');
    if (raw == null) {
      return const ContactSyncState(phase: ContactSyncPhase.idle);
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) throw const FormatException();
      final phaseName = json['phase']?.toString();
      final phase = ContactSyncPhase.values.firstWhere(
        (item) => item.name == phaseName,
        orElse: () => ContactSyncPhase.idle,
      );
      return ContactSyncState(
        phase: phase,
        updatedAt: _asInt(json['updated_at']),
        message: json['message']?.toString(),
      );
    } on FormatException {
      return const ContactSyncState(phase: ContactSyncPhase.idle);
    }
  }

  /// 解析通讯录永久属主与当前授权账户；未注册 CID 必须失败关闭。
  Future<_ContactOwner> _requireIdentityOwner() async {
    var identity = await _currentUser.resolve();
    if (identity != null && !identity.isRegistered) {
      // 首次安装/重新导入可能还没有本机公开绑定；普通通讯录通过 Cloudflare
      // finalized 用户投影建立会话并恢复绑定，禁止为此建立第二节点。
      await _sessionProvider.ensureSession();
      identity = await _currentUser.resolve();
    }
    if (identity == null || !identity.isRegistered) {
      throw const AccountSecurityException('请先注册 CID 身份');
    }
    return _ContactOwner(
      cidNumber: requireCidNumber(identity.cidNumber),
      bindingRevision: identity.bindingRevision,
      accountId: requireAccountId(identity.accountId),
    );
  }

  Future<List<UserContact>> _readContacts(_ContactOwner owner) async {
    final raw = await _readKv(owner, '$_contactsPrefix${owner.cidNumber}');
    if (raw == null || raw.isEmpty) return const <UserContact>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <UserContact>[];
      return _sorted(decoded
          .whereType<Map<String, dynamic>>()
          .map(UserContact.fromJson)
          .toList(growable: false));
    } on FormatException {
      return const <UserContact>[];
    }
  }

  Future<List<_PendingContactOp>> _readPending(_ContactOwner owner) async {
    final raw = await _readKv(owner, '$_pendingPrefix${owner.cidNumber}');
    if (raw == null || raw.isEmpty) return const <_PendingContactOp>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <_PendingContactOp>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_PendingContactOp.fromJson)
          .toList(growable: false);
    } on FormatException {
      return const <_PendingContactOp>[];
    }
  }

  Future<void> _writeContactsAndPending(
    _ContactOwner owner,
    List<UserContact> contacts,
    _PendingContactOp next,
  ) async {
    final pending = (await _readPending(owner)).toList(growable: true)
      ..removeWhere((item) => item.cidNumber == next.cidNumber)
      ..add(next);
    await _writeSnapshot(owner, contacts, pending);
    await _setSyncState(owner, ContactSyncPhase.pending);
  }

  Future<void> _removePending(
      _ContactOwner owner, _PendingContactOp completed) async {
    final pending = (await _readPending(owner))
        .where((item) =>
            item.cidNumber != completed.cidNumber ||
            item.updatedAt > completed.updatedAt)
        .toList(growable: false);
    await _writePending(owner, pending);
  }

  Future<void> _writeSnapshot(
    _ContactOwner owner,
    List<UserContact> contacts,
    List<_PendingContactOp> pending,
  ) async {
    // 两份都在事务外先加密，不让密码学运算占住 Isar 写事务。
    final contactsKey = '$_contactsPrefix${owner.cidNumber}';
    final pendingKey = '$_pendingPrefix${owner.cidNumber}';
    final sealedContacts = await _sealKv(
      owner,
      contactsKey,
      jsonEncode(_sorted(contacts).map((item) => item.toJson()).toList()),
    );
    final sealedPending = await _sealKv(
      owner,
      pendingKey,
      jsonEncode(pending.map((item) => item.toJson()).toList()),
    );
    await UserIsar.instance.writeTxn((isar) async {
      await _putKvInTxn(isar, contactsKey, sealedContacts);
      await _putKvInTxn(isar, pendingKey, sealedPending);
    });
  }

  Future<void> _writeContacts(
          _ContactOwner owner, List<UserContact> contacts) =>
      _writeKv(
        owner,
        '$_contactsPrefix${owner.cidNumber}',
        jsonEncode(_sorted(contacts).map((item) => item.toJson()).toList()),
      );

  Future<void> _writePending(
          _ContactOwner owner, List<_PendingContactOp> pending) =>
      _writeKv(
        owner,
        '$_pendingPrefix${owner.cidNumber}',
        jsonEncode(pending.map((item) => item.toJson()).toList()),
      );

  Future<void> _setSyncState(
    _ContactOwner owner,
    ContactSyncPhase phase, {
    String? message,
  }) async {
    final state = ContactSyncState(
      phase: phase,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      message: message,
    );
    syncState.value = state;
    await _writeKv(
      owner,
      '$_syncPrefix${owner.cidNumber}',
      jsonEncode(<String, Object?>{
        'phase': phase.name,
        'updated_at': state.updatedAt,
        if (message != null) 'message': message,
      }),
    );
  }

  /// 取某条 KV 的本地加密子钥。
  ///
  /// 用 `LocalKeyPurpose.contactsLocal` 而**不复用云端通讯录钥**:两者域隔离,
  /// 本地密文被拿到也不等于同时暴露云端密文。
  Future<Uint8List> _localKvKey(_ContactOwner owner) =>
      _accountSecurity.readDataKeyForCurrentBinding(
        owner.accountId,
        LocalKeyPurpose.contactsLocal,
      );

  Future<Uint8List> _localKvKeyForBinding(AccountDataBinding binding) async {
    return (await _accountSecurity.deriveDataKeysForBindingHandover(
      binding,
      const <({LocalKeyPurpose purpose, String? context})>[
        (purpose: LocalKeyPurpose.contactsLocal, context: null),
      ],
    ))
        .single;
  }

  Future<String?> _readRawKv(String key) => UserIsar.instance.read(
      (isar) async => (await isar.userContactStateEntitys.getByStateKey(key))
          ?.sealedPayload);

  static void _validateHandover(
    AccountDataBinding source,
    AccountDataBinding target,
  ) {
    source.validate();
    target.validate();
    if (source.genesisHash != target.genesisHash ||
        source.cidNumber != target.cidNumber ||
        target.bindingRevision != source.bindingRevision + 1 ||
        source.accountId == target.accountId) {
      throw const FormatException('通讯录换绑交接上下文不合法');
    }
  }

  static String _handoverManifestKey(AccountDataBinding target) =>
      '$_handoverPrefix${target.cidNumber}:${target.bindingRevision}:${target.accountId}';

  static String _inaccessibleKey(
    AccountDataBinding binding,
    String canonicalKey,
  ) =>
      '$_inaccessiblePrefix${binding.cidNumber}:${binding.bindingRevision}:'
      '${binding.accountId}:${Uri.encodeComponent(canonicalKey)}';

  static String _handoverValueKey(
    AccountDataBinding target,
    String canonicalKey,
  ) =>
      '${_handoverManifestKey(target)}:${Uri.encodeComponent(canonicalKey)}';

  static String _encodeHandoverManifest({
    required AccountDataBinding source,
    required AccountDataBinding target,
    required List<String> canonicalKeys,
    required List<String> stagedKeys,
    required List<String> previousContactIds,
    required List<String> targetContactIds,
    required List<SquareEncryptedContact> targetRecords,
  }) =>
      jsonEncode(<String, Object?>{
        'source': source.toJson(),
        'target': target.toJson(),
        'canonical_keys': canonicalKeys,
        'staged_keys': stagedKeys,
        'previous_contact_ids': previousContactIds,
        'target_contact_ids': targetContactIds,
        'target_records': targetRecords
            .map((record) => record.toJson())
            .toList(growable: false),
      });

  /// AAD 绑完整 KV 键名,防止三份(通讯录 / 待同步 / 同步态)密文被互换。
  Future<String> _sealKv(
      _ContactOwner owner, String kvKey, String value) async {
    final key = await _localKvKey(owner);
    try {
      return await LocalCipher.encryptString(
        key: key,
        plaintext: value,
        aad: kvKey,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<String> _openKv(_ContactOwner owner, String kvKey, String blob) async {
    final key = await _localKvKey(owner);
    try {
      return await LocalCipher.decryptString(
        key: key,
        blob: blob,
        aad: kvKey,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// 读本地 KV 并解密。解密失败直接抛 [LocalCipherException],不静默返回 null——
  /// 静默会被上层当成"本地无缓存"而拉云端整表覆盖,悄悄丢掉待同步的本地改动。
  Future<String?> _readKv(_ContactOwner owner, String key) async {
    final blob = await UserIsar.instance.read((isar) async {
      return (await isar.userContactStateEntitys.getByStateKey(key))
          ?.sealedPayload;
    });
    if (blob == null || blob.isEmpty) return null;
    return _openKv(owner, key, blob);
  }

  /// 加密在事务外完成,不让密码学运算占住 Isar 写事务。
  Future<void> _writeKv(_ContactOwner owner, String key, String value) async {
    final sealed = await _sealKv(owner, key, value);
    await UserIsar.instance.writeTxn((isar) => _putKvInTxn(isar, key, sealed));
  }

  Future<void> _putKvInTxn(Isar isar, String key, String value) async {
    final row = await isar.userContactStateEntitys.getByStateKey(key) ??
        _newContactState(key);
    row
      ..stateKey = key
      ..sealedPayload = value;
    await isar.userContactStateEntitys.put(row);
  }

  static UserContactStateEntity _newContactState(String key) {
    for (final entry in <(String, String)>[
      (_contactsPrefix, 'book'),
      (_pendingPrefix, 'pending'),
      (_syncPrefix, 'sync'),
      (_handoverPrefix, 'handover'),
      (_inaccessiblePrefix, 'inaccessible'),
    ]) {
      if (!key.startsWith(entry.$1)) continue;
      final suffix = key.substring(entry.$1.length);
      final separator = suffix.indexOf(':');
      final ownerCidNumber =
          separator < 0 ? suffix : suffix.substring(0, separator);
      if (ownerCidNumber.isEmpty) {
        throw const FormatException('通讯录状态缺少 owner cid_number');
      }
      return UserContactStateEntity()
        ..stateKey = key
        ..ownerCidNumber = ownerCidNumber
        ..stateKind = entry.$2
        ..sealedPayload = '';
    }
    throw const FormatException('通讯录状态键不属于 UserContactStateEntity');
  }

  static String normalizeSs58Address(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw const FormatException('地址为空');
    try {
      final bytes = Keyring().decodeAddress(trimmed);
      final normalized = Keyring().encodeAddress(bytes, kGmbSs58Prefix);
      if (normalized != trimmed) {
        throw const FormatException('联系人地址不是本链 SS58 地址');
      }
      return normalized;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('联系人地址格式无效');
    }
  }

  static String accountIdFromSs58(String ss58Address) {
    final normalized = normalizeSs58Address(ss58Address);
    final bytes = Keyring().decodeAddress(normalized);
    return '0x${_hex(bytes)}';
  }

  static String requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  static String requireCidNumber(String cidNumber) {
    final normalized = cidNumber.trim();
    if (normalized.isEmpty || utf8.encode(normalized).length > 32) {
      throw const FormatException('cid_number 必须为 1 到 32 字节');
    }
    return normalized;
  }

  static String normalizeContactRemark(String contactRemark) {
    final normalized = contactRemark.trim();
    if (normalized.runes.length > 40) {
      throw const FormatException('联系人私人备注不能超过 40 个字符');
    }
    return normalized;
  }
}

/// 通讯录的永久属主与本次有效授权账户。
class _ContactOwner {
  const _ContactOwner({
    required this.cidNumber,
    required this.bindingRevision,
    required this.accountId,
  });

  final String cidNumber;
  final int bindingRevision;
  final String accountId;
}

enum _PendingAction { upsert, delete }

class _PendingContactOp {
  const _PendingContactOp({
    required this.action,
    required this.cidNumber,
    required this.updatedAt,
  });

  factory _PendingContactOp.upsert(String cidNumber, int updatedAt) =>
      _PendingContactOp(
        action: _PendingAction.upsert,
        cidNumber: cidNumber,
        updatedAt: updatedAt,
      );

  factory _PendingContactOp.delete(String cidNumber, int updatedAt) =>
      _PendingContactOp(
        action: _PendingAction.delete,
        cidNumber: cidNumber,
        updatedAt: updatedAt,
      );

  final _PendingAction action;
  final String cidNumber;
  final int updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'action': action.name,
        'cid_number': cidNumber,
        'updated_at': updatedAt,
      };

  factory _PendingContactOp.fromJson(Map<String, dynamic> json) {
    final action = json['action'] == 'delete'
        ? _PendingAction.delete
        : _PendingAction.upsert;
    return _PendingContactOp(
      action: action,
      cidNumber: UserContactService.requireCidNumber(
        json['cid_number']?.toString() ?? '',
      ),
      updatedAt: _asInt(json['updated_at']),
    );
  }
}

List<UserContact> _sorted(Iterable<UserContact> contacts) =>
    contacts.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// 联系人冲突时间戳必须为正且单设备单调递增，避免同一毫秒内连续修改被旧值覆盖。
int _nextTimestamp([int previous = 0]) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return now > previous ? now : previous + 1;
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

/// Worker 契约只接受 RFC 4648 Base64URL 字符集且不接受 `=` 填充。
String _base64UrlEncode(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

List<int> _base64UrlDecode(String value) {
  final padded = value.padRight(((value.length + 3) ~/ 4) * 4, '=');
  return base64Url.decode(padded);
}
