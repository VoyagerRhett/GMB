import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/proposal/admins-change/codec/account_id_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/codec/admin_account_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';

/// 分类管理员链读门面。
///
/// 机构严格读取 `AdminAccounts[cid_number]` 与对应 entity 的
/// `InstitutionGovernanceThresholds[cid_number]`；个人多签严格读取
/// `AdminAccounts[personal_account]` 与 `ActivePersonalThresholds[personal_account]`。
class AdminAccountService {
  const AdminAccountService({required CitizenChain chain}) : _chain = chain;

  static const Duration _cacheTtl = Duration(seconds: 30);
  static final Map<String, _AdminAccountCacheEntry> _cache = {};
  static final Map<String, Future<AdminAccountState?>> _inFlight = {};

  final CitizenChain _chain;

  Future<AdminAccountState?> fetchByIdentity(
    AdminAccountIdentity identity,
  ) async {
    final cacheKey = identity.identityKey;
    final cached = _cache[cacheKey];
    if (cached != null && cached.isFresh(_cacheTtl)) return cached.state;
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final future = _fetchUncached(identity);
    _inFlight[cacheKey] = future;
    return future.whenComplete(() {
      if (_inFlight[cacheKey] == future) _inFlight.remove(cacheKey);
    });
  }

  Future<AdminAccountState?> _fetchUncached(
    AdminAccountIdentity identity,
  ) async {
    final finalized = await _chain.getFinalizedHead();
    final AdminAccountState? decoded;
    if (identity.type == AdminAccountIdentityType.institution) {
      final cidNumber = identity.cidNumber!;
      final key = AdminAccountIdCodec.institutionAdminStorageKey(
        cidNumber,
        institutionCode: identity.institutionCode,
        adminKind: identity.kind,
      );
      final data = await _chain.getStorage(finalized, key);
      decoded = data == null
          ? null
          : AdminAccountCodec.decodeInstitution(
              cidNumber: cidNumber,
              data: data,
              institutionKind: identity.kind,
            );
    } else {
      final personalAccount =
          AdminAccountIdCodec.fromAccountIdText(identity.personalAccountId!);
      final key = AdminAccountIdCodec.personalAdminStorageKey(personalAccount);
      final data = await _chain.getStorage(finalized, key);
      decoded = data == null
          ? null
          : AdminAccountCodec.decodePersonal(personalAccount, data);
    }
    if (decoded == null) return null;
    final threshold = await _resolveThreshold(identity, finalized);
    final state = decoded.copyWith(threshold: threshold ?? 0);
    _cache[identity.identityKey] = _AdminAccountCacheEntry(state);
    return state;
  }

  Future<List<AdminPerson>> fetchAdmins(AdminAccountIdentity identity) async =>
      (await fetchByIdentity(identity))?.admins ?? const [];

  Future<int?> fetchThreshold(AdminAccountIdentity identity) async =>
      (await fetchByIdentity(identity))?.threshold;

  Future<bool> isAdmin(
    String accountId,
    AdminAccountIdentity identity,
  ) async {
    final normalizedAccountId = AdminAccountIdCodec.requireAccountId(accountId);
    return (await fetchAdmins(identity))
        .any((admin) => admin.account_id == normalizedAccountId);
  }

  void clearCache([AdminAccountIdentity? identity]) {
    if (identity == null) {
      _cache.clear();
      _inFlight.clear();
      return;
    }
    _cache.remove(identity.identityKey);
    _inFlight.remove(identity.identityKey);
  }

  void clearPersonalAccountCache(String personalAccountId) {
    final normalized = AdminAccountIdCodec.requireAccountId(personalAccountId);
    final key = 'personal-account:$normalized';
    _cache.remove(key);
    _inFlight.remove(key);
  }

  Future<int?> _resolveThreshold(
    AdminAccountIdentity identity,
    CitizenBlockRef finalized,
  ) async {
    if (identity.type == AdminAccountIdentityType.institution) {
      return _fetchThresholdStorage(
        palletName: identity.kind == 1 ? 'PrivateManage' : 'PublicManage',
        storageName: 'InstitutionGovernanceThresholds',
        finalized: finalized,
        keyData: AdminAccountIdCodec.scaleBytes(
          utf8.encode(identity.cidNumber!),
        ),
      );
    }
    return _fetchThresholdStorage(
      palletName: 'InternalVote',
      storageName: 'ActivePersonalThresholds',
      finalized: finalized,
      keyData:
          AdminAccountIdCodec.fromAccountIdText(identity.personalAccountId!),
    );
  }

  Future<int?> _fetchThresholdStorage({
    required String palletName,
    required String storageName,
    required Uint8List keyData,
    required CitizenBlockRef finalized,
  }) async {
    final key = _storageMapKey(palletName, storageName, keyData);
    final data = await _chain.getStorage(finalized, key);
    if (data == null || data.length != 4) return null;
    return ByteData.sublistView(data).getUint32(0, Endian.little);
  }

  Uint8List _storageMapKey(
    String palletName,
    String storageName,
    Uint8List keyData,
  ) {
    return Uint8List.fromList([
      ...Hasher.twoxx128.hashString(palletName),
      ...Hasher.twoxx128.hashString(storageName),
      ...AdminAccountIdCodec.blake2128Concat(keyData),
    ]);
  }

}

class _AdminAccountCacheEntry {
  _AdminAccountCacheEntry(this.state) : createdAt = DateTime.now();

  final AdminAccountState state;
  final DateTime createdAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
}
