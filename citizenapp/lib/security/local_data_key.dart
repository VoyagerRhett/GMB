import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:citizenapp/security/secure_storage.dart';

/// 当前钱包账户派生的私有数据密钥用途域。
///
/// 每个用途独立派生；同一钱包账户在同一 CID 绑定版本下可跨设备得到相同子钥，
/// 换绑后的新账户或新 [AccountDataBinding.bindingRevision] 必然得到不同子钥。
enum LocalKeyPurpose {
  /// 聊天正文、会话摘要等本地明文字段。
  chat(1, 'citizenapp.account-data/chat'),

  /// 聊天搜索的 HMAC 分词索引钥（只做 HMAC，不做加解密）。
  chatIndex(2, 'citizenapp.account-data/chat-index'),

  /// OpenMLS 状态信封（含设备签名私钥与群 ratchet 秘密）。
  mls(3, 'citizenapp.account-data/mls'),

  /// 聊天附件本地缓存文件。
  attachment(4, 'citizenapp.account-data/attachment'),

  /// 通讯录本地 Isar KV。
  contactsLocal(5, 'citizenapp.account-data/contacts-local'),

  /// 通讯录云端端到端密文。
  contactsCloud(6, 'citizenapp.account-data/contacts-cloud');

  const LocalKeyPurpose(this.provisionCode, this.domain);

  /// 冷钱包交付协议中的稳定用途编号；context 另行区分云通讯录加密钥与索引钥。
  final int provisionCode;

  /// HKDF `info` 主域，同时作为业务 AAD 的用途来源。
  final String domain;
}

/// 本机一个 CID 的钱包绑定元数据。
///
/// 这里只保存公开绑定事实，不保存任何数据密钥。真实数据访问确认缺钥时由当前账户
/// child 结合本结构派生用途钥并交给独立设备硬件钥封装；已有钥直接静默解封。正式换绑
/// 交接可在用户确认的交易作用域内显式读取旧、新账户材料。
class AccountDataBinding {
  const AccountDataBinding({
    required this.genesisHash,
    required this.cidNumber,
    required this.bindingRevision,
    required this.accountId,
  });

  final String genesisHash;
  final String cidNumber;
  final int bindingRevision;
  final String accountId;

  /// 校验链上绑定字段，防止调用方直接构造对象时绕过反序列化检查。
  void validate() {
    final cidBytes = utf8.encode(cidNumber);
    if (!_hashPattern.hasMatch(genesisHash)) {
      throw const AccountDataKeyException('创世哈希格式无效');
    }
    if (cidBytes.isEmpty || cidBytes.length > 32) {
      throw const AccountDataKeyException('cid_number 的 UTF-8 长度必须为 1-32 字节');
    }
    if (bindingRevision <= 0) {
      throw const AccountDataKeyException('CID 绑定版本必须大于 0');
    }
    if (!_accountIdPattern.hasMatch(accountId)) {
      throw const AccountDataKeyException('account_id 格式无效');
    }
  }

  Map<String, Object> toJson() => <String, Object>{
        'genesis_hash': genesisHash,
        'cid_number': cidNumber,
        'binding_revision': bindingRevision,
        'account_id': accountId,
      };

  static AccountDataBinding? fromJson(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final genesisHash = value['genesis_hash'];
      final cidNumber = value['cid_number'];
      final bindingRevision = value['binding_revision'];
      final accountId = value['account_id'];
      if (genesisHash is! String ||
          !_hashPattern.hasMatch(genesisHash) ||
          cidNumber is! String ||
          cidNumber.isEmpty ||
          utf8.encode(cidNumber).length > 32 ||
          bindingRevision is! int ||
          bindingRevision <= 0 ||
          accountId is! String ||
          !_accountIdPattern.hasMatch(accountId)) {
        return null;
      }
      return AccountDataBinding(
        genesisHash: genesisHash,
        cidNumber: cidNumber,
        bindingRevision: bindingRevision,
        accountId: accountId,
      );
    } on FormatException {
      return null;
    }
  }

  static final RegExp _hashPattern = RegExp(r'^0x[0-9a-f]{64}$');
  static final RegExp _accountIdPattern = RegExp(r'^0x[0-9a-f]{64}$');
}

/// CID 私有数据顶层交接 intent 的持久状态。
enum AccountDataHandoverState { preparing, ready }

/// CID 钱包绑定元数据存储。
///
/// 每个 CID 使用独立键保存，切换默认账户只切换调用方当前上下文，不覆盖其它 CID。
/// 同一 CID 的绑定版本只能单调推进；同一版本出现不同账户或创世哈希时失败关闭。
/// 存储内容全是公开绑定字段，绝不形成额外用户私有数据主钥或领取凭证。
class AccountDataBindingStore {
  const AccountDataBindingStore(this._store);

  final LocalKeyBlobStore _store;

  static const String bindingCidNumbersKey =
      'citizenapp_account_data_binding_cid_numbers';
  static const String pendingHandoverKey =
      'citizenapp_account_data_pending_handover';

  /// 读取指定 CID 的绑定。禁止通过“当前激活值”间接寻找另一个用户。
  Future<AccountDataBinding?> readForCid(String cidNumber) async {
    _validateCidNumber(cidNumber);
    final raw = await _store.read(_bindingKey(cidNumber));
    if (raw == null || raw.isEmpty) return null;
    final binding = AccountDataBinding.fromJson(raw);
    if (binding == null || binding.cidNumber != cidNumber) {
      throw const AccountDataKeyException('CID 本地绑定记录损坏');
    }
    return binding;
  }

  /// 按账户精确查找本机公开绑定；只用于调用方已经持有明确 account_id 的数据入口。
  Future<AccountDataBinding?> readForAccountId(String accountId) async {
    if (!AccountDataBinding._accountIdPattern.hasMatch(accountId)) {
      throw const AccountDataKeyException('account_id 格式无效');
    }
    for (final cidNumber in await _readCidNumbers()) {
      final binding = await readForCid(cidNumber);
      if (binding?.accountId == accountId) return binding;
    }
    return null;
  }

  /// 返回全部逐 CID 绑定，供明确删除钱包时做精确隐私擦除；默认账户切换不得调用。
  Future<List<AccountDataBinding>> readAll() async {
    final result = <AccountDataBinding>[];
    for (final cidNumber in await _readCidNumbers()) {
      final binding = await readForCid(cidNumber);
      if (binding != null) result.add(binding);
    }
    return List<AccountDataBinding>.unmodifiable(result);
  }

  Future<void> activate(AccountDataBinding next) async {
    next.validate();
    final previous = await readForCid(next.cidNumber);
    if (previous != null) {
      if (previous.bindingRevision > next.bindingRevision) {
        throw const AccountDataKeyException('CID 本地绑定版本禁止回退');
      }
      if (previous.bindingRevision == next.bindingRevision &&
          (previous.genesisHash != next.genesisHash ||
              previous.cidNumber != next.cidNumber ||
              previous.accountId != next.accountId)) {
        throw const AccountDataKeyException('同一绑定版本的创世、CID 或账户不一致');
      }
    }
    await _store.write(_bindingKey(next.cidNumber), jsonEncode(next.toJson()));
    final cidNumbers = await _readCidNumbers();
    if (!cidNumbers.contains(next.cidNumber)) {
      await _writeCidNumbers(<String>[...cidNumbers, next.cidNumber]);
    }
  }

  /// 只删除指定 CID 的公开绑定指针，不触碰其它 CID 的数据或密钥。
  Future<void> clearForCid(String cidNumber) async {
    _validateCidNumber(cidNumber);
    await _store.delete(_bindingKey(cidNumber));
    final cidNumbers = await _readCidNumbers();
    if (cidNumbers.remove(cidNumber)) await _writeCidNumbers(cidNumbers);
  }

  Future<void> writePendingHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    source.validate();
    target.validate();
    if (!_isValidHandover(source, target)) {
      throw const AccountDataKeyException('CID 钱包换绑交接上下文无效');
    }
    final existing = await readPendingHandover();
    if (existing != null) {
      if (!_sameBinding(existing.source, source) ||
          !_sameBinding(existing.target, target)) {
        throw const AccountDataKeyException('已经存在其它 CID 钱包换绑交接 intent');
      }
      // stage 重试不得把已经 ready 的 intent 回退为 preparing。
      return;
    }
    final preparing = _encodePendingHandover(
      source: source,
      target: target,
      state: AccountDataHandoverState.preparing,
    );
    if (!await _store.compareAndSet(
      pendingHandoverKey,
      expected: null,
      next: preparing,
    )) {
      final concurrent = await readPendingHandover();
      if (concurrent == null ||
          !_sameBinding(concurrent.source, source) ||
          !_sameBinding(concurrent.target, target)) {
        throw const AccountDataKeyException('CID 钱包换绑交接 intent 并发冲突');
      }
    }
  }

  Future<void> markPendingHandoverReady({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    source.validate();
    target.validate();
    final raw = await _store.read(pendingHandoverKey);
    if (raw == null || raw.isEmpty) {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent 缺失');
    }
    final current = _decodePendingHandover(raw);
    if (!_sameBinding(current.source, source) ||
        !_sameBinding(current.target, target)) {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent 已变化');
    }
    if (current.state == AccountDataHandoverState.ready) return;
    final updated = _encodePendingHandover(
      source: source,
      target: target,
      state: AccountDataHandoverState.ready,
    );
    if (!await _store.compareAndSet(
      pendingHandoverKey,
      expected: raw,
      next: updated,
    )) {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent CAS 失败');
    }
  }

  Future<
      ({
        AccountDataBinding source,
        AccountDataBinding target,
        AccountDataHandoverState state,
      })?> readPendingHandover() async {
    final raw = await _store.read(pendingHandoverKey);
    if (raw == null || raw.isEmpty) return null;
    return _decodePendingHandover(raw);
  }

  Future<void> clearPendingHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    source.validate();
    target.validate();
    final raw = await _store.read(pendingHandoverKey);
    if (raw == null || raw.isEmpty) return;
    final current = _decodePendingHandover(raw);
    if (!_sameBinding(current.source, source) ||
        !_sameBinding(current.target, target)) {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent 已变化');
    }
    if (!await _store.compareAndSet(
      pendingHandoverKey,
      expected: raw,
      next: null,
    )) {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent CAS 失败');
    }
  }

  static String _encodePendingHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
    required AccountDataHandoverState state,
  }) =>
      jsonEncode(<String, Object>{
        'state': state.name,
        'source': source.toJson(),
        'target': target.toJson(),
      });

  static ({
    AccountDataBinding source,
    AccountDataBinding target,
    AccountDataHandoverState state,
  }) _decodePendingHandover(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length != 3 ||
          value.keys.toSet().difference(<String>{
            'state',
            'source',
            'target',
          }).isNotEmpty) {
        throw const AccountDataKeyException('CID 钱包换绑交接 intent 结构损坏');
      }
      final sourceRaw = value['source'];
      final targetRaw = value['target'];
      final stateRaw = value['state'];
      if (sourceRaw is! Map<String, dynamic> ||
          targetRaw is! Map<String, dynamic> ||
          stateRaw is! String) {
        throw const AccountDataKeyException('CID 钱包换绑交接 intent 结构损坏');
      }
      final source = AccountDataBinding.fromJson(jsonEncode(sourceRaw));
      final target = AccountDataBinding.fromJson(jsonEncode(targetRaw));
      AccountDataHandoverState? state;
      for (final candidate in AccountDataHandoverState.values) {
        if (candidate.name == stateRaw) {
          state = candidate;
          break;
        }
      }
      if (source == null ||
          target == null ||
          state == null ||
          !_isValidHandover(source, target)) {
        throw const AccountDataKeyException('CID 钱包换绑交接 intent 内容损坏');
      }
      return (source: source, target: target, state: state);
    } on FormatException {
      throw const AccountDataKeyException('CID 钱包换绑交接 intent JSON 损坏');
    }
  }

  static bool _sameBinding(
    AccountDataBinding left,
    AccountDataBinding right,
  ) =>
      left.genesisHash == right.genesisHash &&
      left.cidNumber == right.cidNumber &&
      left.bindingRevision == right.bindingRevision &&
      left.accountId == right.accountId;

  static String _bindingKey(String cidNumber) =>
      'citizenapp_account_data_binding_by_cid:${Uri.encodeComponent(cidNumber)}';

  Future<List<String>> _readCidNumbers() async {
    final raw = await _store.read(bindingCidNumbersKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const AccountDataKeyException('CID 本地绑定索引损坏');
      }
      final result = <String>[];
      final seen = <String>{};
      for (final value in decoded) {
        if (value is! String) {
          throw const AccountDataKeyException('CID 本地绑定索引损坏');
        }
        _validateCidNumber(value);
        if (seen.add(value)) result.add(value);
      }
      return result;
    } on FormatException {
      throw const AccountDataKeyException('CID 本地绑定索引损坏');
    }
  }

  Future<void> _writeCidNumbers(List<String> cidNumbers) => cidNumbers.isEmpty
      ? _store.delete(bindingCidNumbersKey)
      : _store.write(bindingCidNumbersKey, jsonEncode(cidNumbers));

  static void _validateCidNumber(String cidNumber) {
    final bytes = utf8.encode(cidNumber);
    if (bytes.isEmpty || bytes.length > 32) {
      throw const AccountDataKeyException('cid_number 的 UTF-8 长度必须为 1-32 字节');
    }
  }

  static bool _isValidHandover(
    AccountDataBinding source,
    AccountDataBinding target,
  ) =>
      source.genesisHash == target.genesisHash &&
      source.cidNumber == target.cidNumber &&
      target.bindingRevision == source.bindingRevision + 1 &&
      source.accountId != target.accountId;
}

/// CitizenApp 私有数据密钥域构造器。
///
/// App 只计算公开 salt/info；账户 secret 与 HKDF-SHA256 始终留在 CitizenSDK 金库。
/// 创世、CID、绑定版本、`account_id` 和用途继续逐字节保持原有业务合同。
abstract final class AccountDataKeyDeriver {
  static Future<Uint8List> derive({
    required CitizenSdkWallet wallet,
    required AccountDataBinding binding,
    required LocalKeyPurpose purpose,
    String? context,
  }) async {
    binding.validate();
    final saltMaterial = utf8.encode(
      'citizenapp.account-data/binding|${binding.genesisHash}|'
      '${binding.cidNumber}|${binding.bindingRevision}|${binding.accountId}',
    );
    final salt = Uint8List.fromList(sha256.convert(saltMaterial).bytes);
    final info = Uint8List.fromList(
      utf8.encode(context == null || context.isEmpty
          ? purpose.domain
          : '${purpose.domain}/$context'),
    );
    try {
      return await wallet.deriveApplicationKey(
        accountId: binding.accountId,
        salt: salt,
        info: info,
      );
    } on CitizenSdkException catch (error) {
      throw AccountDataKeyException(error.message);
    } finally {
      salt.fillRange(0, salt.length, 0);
      info.fillRange(0, info.length, 0);
    }
  }
}

class AccountDataKeyException implements Exception {
  const AccountDataKeyException(this.message);

  final String message;

  @override
  String toString() => 'AccountDataKeyException: $message';
}

/// 钱包安全存储的最小字符串接口。这里只保存当前绑定公开元数据，不保存派生密钥。
abstract interface class LocalKeyBlobStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> compareAndSet(
    String key, {
    required String? expected,
    String? next,
  });
}

/// CitizenApp 公开绑定与设备密文的唯一安全存储适配。
///
/// compare-and-set 只用于同进程换绑 intent；序列门确保 read/compare/write 不交错。
/// 旧 WalletIsar 记录不会被读取或转换。
final class SecureStorageLocalKeyBlobStore implements LocalKeyBlobStore {
  SecureStorageLocalKeyBlobStore([FlutterSecureStorage? storage])
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;
  static Future<void> _tail = Future<void>.value();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> compareAndSet(
    String key, {
    required String? expected,
    String? next,
  }) => _exclusive(() async {
    final current = await _storage.read(key: key);
    if (current != expected) return false;
    if (next == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: next);
    }
    return true;
  });

  static Future<T> _exclusive<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }
}
