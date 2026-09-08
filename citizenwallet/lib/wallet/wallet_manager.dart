import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39m;
import 'package:citizenwallet/security/hardware_secretvault.dart';
import 'package:citizenwallet/wallet/wallet_mini_secret.dart';
import 'package:isar_community/isar.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenwallet/wallet/native_sr25519.dart';
import 'package:citizenwallet/chain/chain_constants.dart';
import 'package:citizenwallet/isar/wallet_isar.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/security/account_data_key_provision.dart';
import 'package:citizenwallet/signer/qr_signer.dart';
import 'package:citizenwallet/wallet/wallet_secure_keys.dart';

/// 钱包（master）：一套助记词 = 一个种子 = 一个 master，其下派生多个账户。
class Wallet {
  const Wallet({
    required this.walletIndex,
    required this.walletName,
    required this.masterId,
    required this.createdAtMillis,
    required this.source,
    this.sortOrder = 0,
  });

  final int walletIndex;
  final String walletName;

  /// 主指纹 = 账户0（`//0`）的 accountId，唯一标识一套助记词。
  final String masterId;
  final int createdAtMillis;
  final String source;

  final int sortOrder;
}

/// 账户：钱包下按派生序号展开的一对公私钥。
/// 全部 `//index` 硬派生（含账户0 = `//0`，无 bare 根）；每账户密钥独立、单向。
class Account {
  const Account({
    required this.masterId,
    required this.accountIndex,
    required this.accountId,
    required this.ss58Address,
    required this.accountName,
    required this.createdAtMillis,
  });

  final String masterId;
  final int accountIndex;

  /// 小写 `0x` + 64 位十六进制（= 派生公钥原字节）。
  final String accountId;
  final String ss58Address;
  final String accountName;
  final int createdAtMillis;

  /// 展示用派生路径：`//index`（含账户0 = `//0`）。
  String get derivationPath => '//$accountIndex';
}

class WalletCreationResult {
  const WalletCreationResult({
    required this.wallet,
    required this.primaryAccount,
    required this.mnemonic,
  });

  final Wallet wallet;

  /// 账户0（`//0`），创建/导入后即存在。
  final Account primaryAccount;

  /// 助记词（创建时一次性展示；同时按钱包加密存储，供钱包详情备份查看）。
  final String mnemonic;
}

class WalletSignResult {
  const WalletSignResult({
    required this.signerPublicKey,
    required this.alg,
    required this.signatureHex,
  });

  final String signerPublicKey;
  final String alg;
  final String signatureHex;
}

/// 登录 QR 签名原文中的一次性请求边界。
///
/// 登录页面保持任务前 UI 不变；一次性占位与墙钟校验下沉到唯一的 UTF-8
/// 签名入口，确保生物识别和私钥调用前已经拒绝过期或重复请求。
class _LoginSignatureClaim {
  const _LoginSignatureClaim({
    required this.requestId,
    required this.expiresAt,
  });

  final String requestId;
  final int expiresAt;
}

class WalletAuthException implements Exception {
  const WalletAuthException(this.message);
  final String message;

  @override
  String toString() => 'WalletAuthException: $message';
}

/// 钱包机密清理未全部完成；数据库事实行会保留，确保下次仍能定位并重试清理。
class WalletLocalCleanupException implements Exception {
  const WalletLocalCleanupException(this.message);
  final String message;

  @override
  String toString() => 'WalletLocalCleanupException: $message';
}

/// 钱包页面统一的用户可见错误文案边界。
///
/// 明确的业务异常保留原文；未知的运行时、平台或编程错误一律收敛为中性提示，禁止把
/// `Unsupported operation`、类名、通道错误码等内部实现细节直接展示给用户。
String walletErrorMessage(Object error) {
  if (error is WalletAuthException) return error.message;
  if (error is WalletLocalCleanupException) return error.message;
  final text = error.toString();
  const exceptionPrefix = 'Exception: ';
  if (text.startsWith(exceptionPrefix)) {
    return text.substring(exceptionPrefix.length);
  }
  return '钱包操作失败，请重试';
}

/// 钱包管理（HD model B：一套助记词 → 多账户，全 `//index` 硬派生，无 bare 根）。
///
/// **冷钱包存种子**：本设备是冷签保管方，按钱包(master)将 master [MiniSecretKey]
/// 与助记词存入共享硬件严档，做冷签与备份。账户不单独持久化密钥：
/// 签名 / 私钥导出时按 accountIndex 从种子**现场派生**、用后即弃。每账户 child
/// [MiniSecretKey] 单向硬派生，导出单账户私钥只暴露该账户；助记词是钱包级根备份。
///
/// 派生金标（冷热共享单源）：`test/wallet/derivation_golden_test.dart`，钉死
/// `fromSeed(childMiniSecret) == <助记词>//index` 逐字节相等。
class WalletManager {
  static const int _ss58Prefix = ChainConstants.ss58Prefix;
  static final RegExp _accountIdPattern = RegExp(r'^0x[0-9a-f]{64}$');
  static final WalletSecureKeys _secretStore = WalletSecureKeys();

  // ── 查询 ──
  Future<List<Wallet>> getWallets() async {
    final isar = await WalletIsar.instance.db();
    final rows = await isar.walletEntitys.where().sortBySortOrder().findAll();
    return rows.map(_toWallet).toList();
  }

  Future<Wallet?> getWalletByMasterId(String masterId) async {
    final isar = await WalletIsar.instance.db();
    final row =
        await isar.walletEntitys.filter().masterIdEqualTo(masterId).findFirst();
    return row == null ? null : _toWallet(row);
  }

  /// 某钱包下全部账户，按 accountIndex 升序。
  Future<List<Account>> getAccounts(String masterId) async {
    final isar = await WalletIsar.instance.db();
    final rows = await isar.accountEntitys
        .filter()
        .masterIdEqualTo(masterId)
        .sortByAccountIndex()
        .findAll();
    return rows.map(_toAccount).toList();
  }

  Future<Account?> getAccountByAccountId(String accountId) async {
    final isar = await WalletIsar.instance.db();
    final row = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    return row == null ? null : _toAccount(row);
  }

  // ── 创建 / 导入 / 加账户 ──
  /// 新建钱包：生成助记词 → 派生账户0（`//0`）→ 存 master 种子 + 助记词。
  ///
  /// [wordCount] 助记词个数，12（默认）或 24。助记词同时一次性返回展示。
  Future<WalletCreationResult> createWallet({
    int wordCount = 12,
    String password = '',
  }) async {
    assert(wordCount == 12 || wordCount == 24);
    final mnemonic = bip39m.Mnemonic.generate(
      bip39m.Language.english,
      length: wordCount == 24
          ? bip39m.MnemonicLength.words24
          : bip39m.MnemonicLength.words12,
    ).sentence;
    return _establishWallet(mnemonic, 'created', password: password);
  }

  /// 导入钱包：校验助记词 → 派生账户0（`//0`）→ 存 master 种子 + 助记词。
  Future<WalletCreationResult> importWallet(
    String mnemonic, {
    String password = '',
  }) async {
    final trimmed = mnemonic.trim();
    if (!_isValidMnemonic(trimmed)) {
      throw Exception('助记词无效，请检查拼写和空格');
    }
    return _establishWallet(trimmed, 'imported', password: password);
  }

  Future<WalletCreationResult> _establishWallet(
    String mnemonic,
    String source, {
    String password = '',
  }) async {
    // 创建前先确认设备具备强生物识别和硬件金库；硬件私钥永不落入 Dart 层。
    await _ensureHardwareAvailable();
    final seed = await WalletMiniSecret.fromMnemonic(
      mnemonic,
      password: password,
    );
    try {
      // 账户0 = //0（无 bare 根）。其 accountId 即 master 指纹。
      final acct0 = _deriveAccount(seed, 0);
      final masterId = acct0.accountId;

      final result = await _appendWalletAtomic(
        masterId: masterId,
        source: source,
        primary: acct0,
      );
      try {
        await _writeMasterMiniSecretKey(masterId, seed);
        await _writeMasterMnemonic(masterId, mnemonic);
        await _verifyWalletSecretsPersisted(masterId);
      } catch (writeError, writeStackTrace) {
        // 任一写入失败时仍逐项清密文与硬件 KEK；只有全部清理和回读通过后才删事实行。
        // 清理失败优先显式暴露并保留事实行，禁止吞异常后留下不可定位的机密残留。
        try {
          await _deleteWalletInternal(masterId);
        } on WalletLocalCleanupException {
          rethrow;
        }
        Error.throwWithStackTrace(writeError, writeStackTrace);
      }
      return WalletCreationResult(
        wallet: result.$1,
        primaryAccount: result.$2,
        mnemonic: mnemonic,
      );
    } finally {
      _zeroList(seed);
    }
  }

  /// 账户序号上界（`//index` 的 index 最大值;账户0 为创建时主账户）。
  static const int maxAccountIndex = 1989;

  /// 在指定钱包下新增账户：读存储种子，派生 `//index`（不产生新助记词）。
  ///
  /// [index] 为空 = 添加"下一个"(max+1);非空 = 指定序号(`1..maxAccountIndex`,
  /// 用于恢复非连续账户 / 加别处已注资的特定账户)。序号可非连续。校验先于读种子。
  Future<Account> addAccount(String masterId, {int? index}) async {
    final isar = await WalletIsar.instance.db();
    final wallet =
        await isar.walletEntitys.filter().masterIdEqualTo(masterId).findFirst();
    if (wallet == null) {
      throw const WalletAuthException('未找到钱包');
    }
    final seed = await _readMasterMiniSecretKey(masterId);
    if (seed == null) {
      throw const WalletAuthException('密钥不可用，请重新导入钱包');
    }
    try {
      late AccountEntity entity;
      await isar.writeTxn(() async {
        final accounts = await isar.accountEntitys
            .filter()
            .masterIdEqualTo(masterId)
            .findAll();
        final existing = accounts.map((e) => e.accountIndex).toSet();
        final int targetIndex;
        if (index == null) {
          final maxIndex = existing.fold<int>(-1, (m, i) => i > m ? i : m);
          targetIndex = maxIndex + 1;
          if (targetIndex > maxAccountIndex) {
            throw const WalletAuthException('已达账户序号上限 $maxAccountIndex');
          }
        } else {
          if (index < 1 || index > maxAccountIndex) {
            throw const WalletAuthException('账户序号需在 1–$maxAccountIndex');
          }
          if (existing.contains(index)) {
            throw WalletAuthException('账户$index 已存在');
          }
          targetIndex = index;
        }

        final derived = _deriveAccount(seed, targetIndex);
        entity = AccountEntity()
          ..masterId = masterId
          ..accountIndex = targetIndex
          ..accountId = derived.accountId
          ..ss58Address = derived.ss58Address
          ..accountName = '账户$targetIndex'
          ..createdAtMillis = DateTime.now().millisecondsSinceEpoch;
        await isar.accountEntitys.put(entity);
      });
      return _toAccount(entity);
    } finally {
      _zeroList(seed);
    }
  }

  // ── 删除 ──
  /// 删除整只钱包：连带其全部账户、master [MiniSecretKey]、助记词与硬件 KEK。
  Future<void> deleteWallet(String masterId) async {
    // 创建失败回滚可能已删掉 master 密文但硬件 KEK 清理失败；此时允许从保留的
    // 事实行重试剩余清理。正常钱包仍必须以硬件解封完成真实生物识别。
    if (await _secretStore.containsMasterMiniSecretKey(masterId)) {
      await _verifyMasterAccess(masterId);
    }
    await _deleteWalletInternal(masterId);
  }

  /// 无认证的删钱包实现（供显式删除与创建失败回滚复用，避免二次弹窗）。
  ///
  /// 每个机密清理项独立执行并回读，某一步失败也不跳过后续步骤；只有全部清理成功
  /// 才删除 Isar 事实行。失败时保留事实行，确保仍能定位 masterId 并继续重试。
  Future<void> _deleteWalletInternal(String masterId) async {
    final failures = <Object>[];
    await _attemptCleanup(
      failures,
      () => _secretStore.deleteMasterMiniSecretKey(masterId),
    );
    await _attemptCleanup(
      failures,
      () => _secretStore.deleteMnemonic(masterId),
    );
    await _attemptCleanup(
      failures,
      () => _secretStore.deleteHardwareKey(masterId),
    );
    await _attemptCleanup(failures, () async {
      if (await _secretStore.containsMasterMiniSecretKey(masterId)) {
        throw StateError('master MiniSecretKey 密文仍存在');
      }
    });
    await _attemptCleanup(failures, () async {
      if (await _secretStore.containsMnemonic(masterId)) {
        throw StateError('助记词密文仍存在');
      }
    });
    await _attemptCleanup(failures, () async {
      if (await _secretStore.containsHardwareKey(masterId)) {
        throw StateError('钱包硬件 KEK 仍存在');
      }
    });
    if (failures.isNotEmpty) {
      throw WalletLocalCleanupException(
        '钱包机密清理有 ${failures.length} 项失败，数据库事实已保留，请重试',
      );
    }

    final isar = await WalletIsar.instance.db();
    await isar.writeTxn(() async {
      await isar.accountEntitys.filter().masterIdEqualTo(masterId).deleteAll();
      final wallet = await isar.walletEntitys
          .filter()
          .masterIdEqualTo(masterId)
          .findFirst();
      if (wallet != null) {
        await isar.walletEntitys.delete(wallet.id);
      }
    });
  }

  /// 删除单个账户；若删空该钱包全部账户则连带删钱包与密钥。删前强制认证。
  ///
  /// 账户0 是 master 锚点:尚有兄弟账户时禁止单独删账户0(否则 masterId 悬空、
  /// addAccount 只 max+1 无法重建、重导入又被查重挡住),须改删整只钱包。
  Future<void> deleteAccount(String accountId) async {
    final isar = await WalletIsar.instance.db();
    final existing = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    if (existing == null) {
      throw Exception('未找到账户');
    }
    await _verifyMasterAccess(existing.masterId);
    late String masterId;
    var deleteWallet = false;
    await isar.writeTxn(() async {
      // 查找、计数和删除必须处于同一事务，避免并发删账户时留下无账户钱包。
      final acct = await isar.accountEntitys
          .filter()
          .accountIdEqualTo(accountId)
          .findFirst();
      if (acct == null) {
        throw Exception('未找到账户');
      }
      masterId = acct.masterId;
      final accountCount =
          await isar.accountEntitys.filter().masterIdEqualTo(masterId).count();
      if (acct.accountIndex == 0 && accountCount > 1) {
        throw Exception('账户0是钱包锚点,请删除整个钱包');
      }
      deleteWallet = accountCount == 1;
      if (!deleteWallet) {
        await isar.accountEntitys.delete(acct.id);
      }
    });
    if (deleteWallet) {
      await _deleteWalletInternal(masterId);
    }
  }

  // ── 更新 ──
  static const int maxWalletNameLength = 5;

  // 寻址单源用 masterId(稳定主键;walletIndex 是可复用槽位,删钱包后会被
  // 新钱包重占,拿它定位有指向另一只钱包的窗口)。删除/查账户/签名已按 masterId,
  // 改名/重排同口径。
  Future<void> renameWallet(String masterId, String walletName) async {
    final nextName = walletName.trim();
    if (nextName.isEmpty) {
      throw Exception('钱包名称不能为空');
    }
    if (nextName.runes.length > maxWalletNameLength) {
      throw Exception('钱包名称最多$maxWalletNameLength个字');
    }
    final isar = await WalletIsar.instance.db();
    final row =
        await isar.walletEntitys.filter().masterIdEqualTo(masterId).findFirst();
    if (row == null) {
      throw Exception('未找到钱包');
    }
    await isar.writeTxn(() async {
      row.walletName = nextName;
      await isar.walletEntitys.put(row);
    });
  }

  static const int maxAccountNameLength = 5;

  /// 重命名账户(仅改显示名,不动任何密钥)。按 accountId 定位。
  Future<void> renameAccount(String accountId, String accountName) async {
    final nextName = accountName.trim();
    if (nextName.isEmpty) {
      throw Exception('账户名称不能为空');
    }
    if (nextName.runes.length > maxAccountNameLength) {
      throw Exception('账户名称最多$maxAccountNameLength个字');
    }
    final isar = await WalletIsar.instance.db();
    final row = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    if (row == null) {
      throw Exception('未找到账户');
    }
    await isar.writeTxn(() async {
      row.accountName = nextName;
      await isar.accountEntitys.put(row);
    });
  }

  /// 批量更新钱包排序。[masterIds] 顺序即新 sortOrder。
  Future<void> reorderWallets(List<String> masterIds) async {
    final isar = await WalletIsar.instance.db();
    await isar.writeTxn(() async {
      for (var i = 0; i < masterIds.length; i++) {
        final row = await isar.walletEntitys
            .filter()
            .masterIdEqualTo(masterIds[i])
            .findFirst();
        if (row != null) {
          row.sortOrder = i;
          await isar.walletEntitys.put(row);
        }
      }
    });
  }

  // ── 签名（按账户；读种子现场派生，签名完成立即清零可控密钥缓冲）──
  Future<Uint8List> signForAccount(String accountId, Uint8List payload) =>
      _signWithAccount(accountId, payload);

  /// 一次生物识别内完成冷账户用途钥派生、X25519/AES-GCM 封装和 `0x22` 授权签名。
  /// 账户 child、用途钥和一次性发送私钥都只在内存短暂存在，用后立即清零。
  Future<({AccountDataKeyProvisionMaterial material, Uint8List signature})>
      provisionAccountDataKeys({
    required String accountId,
    required AccountDataKeyProvisionRequest request,
  }) async {
    if (request.expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const WalletAuthException('用途钥请求已过期，请重新扫描');
    }
    final isar = await WalletIsar.instance.db();
    final account = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    if (account == null || request.accountId != accountId) {
      throw const WalletAuthException('用途钥请求账户与当前账户不一致');
    }
    final seed = await _readMasterMiniSecretKey(account.masterId);
    if (seed == null) {
      throw const WalletAuthException('密钥不可用，请重新导入钱包');
    }
    try {
      final child = _childMiniSecret(seed, account.accountIndex);
      final childBytes = Uint8List.fromList(child);
      try {
        if (_accountIdFromBytes(NativeSr25519.publicKeyOf(childBytes)) !=
            accountId) {
          throw const WalletAuthException('本地签名密钥与账户不一致，请重新导入钱包');
        }
        final material = createAccountDataKeyProvision(
          request: request,
          accountSecret: childBytes,
        );
        final message = accountDataKeyProvisionSigningMessage(
          material.authorizationPayload,
        );
        try {
          final signature = NativeSr25519.sign(childBytes, message);
          return (material: material, signature: signature);
        } finally {
          message.fillRange(0, message.length, 0);
        }
      } finally {
        childBytes.fillRange(0, childBytes.length, 0);
        _zeroList(child);
      }
    } finally {
      _zeroList(seed);
    }
  }

  Future<WalletSignResult> signUtf8ForAccount(
    String accountId,
    String message,
  ) async {
    final loginClaim = _parseLoginSignatureClaim(
      accountId: accountId,
      message: message,
    );
    if (loginClaim != null) {
      final claimed = await SignedQrRequestStore.claim(
        requestId: loginClaim.requestId,
        expiresAt: loginClaim.expiresAt,
      );
      if (!claimed) {
        throw const WalletAuthException('该登录请求已处理或已过期，请重新扫描');
      }
    }

    final messageBytes = Uint8List.fromList(utf8.encode(message));
    try {
      final signature = await _signWithAccount(
        accountId,
        messageBytes,
        expiresAt: loginClaim?.expiresAt,
      );
      return WalletSignResult(
        signerPublicKey: accountId,
        alg: 'sr25519',
        signatureHex: '0x${_toHex(signature.toList(growable: false))}',
      );
    } catch (_) {
      if (loginClaim != null) {
        await SignedQrRequestStore.release(loginClaim.requestId);
      }
      rethrow;
    } finally {
      messageBytes.fillRange(0, messageBytes.length, 0);
    }
  }

  /// 定位账户 → 读种子 → 派生 → 校验公钥 → 签名；所有可控私钥缓冲在本方法内清零。
  Future<Uint8List> _signWithAccount(
    String accountId,
    Uint8List payload, {
    int? expiresAt,
  }) async {
    // 在任何硬件解密/生物识别前先拒绝过期请求，避免无意义地调取根机密。
    if (expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const WalletAuthException('登录请求已过期，请重新扫描');
    }
    final isar = await WalletIsar.instance.db();
    final acct = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    if (acct == null) {
      throw const WalletAuthException('未找到指定账户');
    }
    final seed = await _readMasterMiniSecretKey(acct.masterId);
    if (seed == null) {
      throw const WalletAuthException('密钥不可用，请重新导入钱包');
    }
    try {
      final child = _childMiniSecret(seed, acct.accountIndex);
      final childBytes = Uint8List.fromList(child);
      try {
        final localAccountId = _accountIdFromBytes(
          NativeSr25519.publicKeyOf(childBytes),
        );
        if (localAccountId != acct.accountId) {
          throw const WalletAuthException('本地签名密钥与账户不一致，请重新导入钱包');
        }
        return NativeSr25519.sign(childBytes, payload);
      } finally {
        childBytes.fillRange(0, childBytes.length, 0);
        _zeroList(child);
      }
    } finally {
      _zeroList(seed);
    }
  }

  /// 识别登录 QR 的规范签名原文；普通非 QR 文本签名保持原有行为。
  ///
  /// 格式由 `buildSignatureMessage` 唯一生成：
  /// `QR_V1|2|<request_id>|onchina|<expires_at>|<account_id_without_0x>`。
  _LoginSignatureClaim? _parseLoginSignatureClaim({
    required String accountId,
    required String message,
  }) {
    if (!message.startsWith('${QrProtocols.qrV1}|')) {
      return null;
    }
    if (!_accountIdPattern.hasMatch(accountId)) {
      throw const WalletAuthException('登录签名账户格式无效');
    }
    final parts = message.split('|');
    final expiresAt = parts.length == 6 ? int.tryParse(parts[4]) : null;
    final valid = parts.length == 6 &&
        parts[0] == QrProtocols.qrV1 &&
        parts[1] == QrKind.signResponse.code.toString() &&
        QrSigner.isValidRequestId(parts[2]) &&
        parts[3] == 'onchina' &&
        expiresAt != null &&
        parts[5] == accountId.substring(2);
    if (!valid) {
      throw const WalletAuthException('登录签名请求格式无效');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt <= now) {
      throw const WalletAuthException('登录请求已过期，请重新扫描');
    }
    return _LoginSignatureClaim(requestId: parts[2], expiresAt: expiresAt);
  }

  /// 查看钱包助记词（钱包级根备份；触发生物识别）。找不到即抛(与私钥导出同口径,
  /// 不让 UI 把 null 当"无数据"正常渲染)。
  Future<String> getMasterMnemonic(String masterId) async {
    final mnemonic = await _readMasterMnemonic(masterId);
    if (mnemonic == null || mnemonic.isEmpty) {
      throw const WalletAuthException('未找到该钱包的助记词备份，请重新导入钱包');
    }
    return mnemonic;
  }

  /// 导出该账户私钥（child mini-secret，`0x`+64hex；触发生物识别）。
  ///
  /// 从存储的 master 种子按 accountIndex 现场派生。child mini-secret 单向隔离:
  /// 导出单账户只暴露该账户,推不出根/兄弟(根级备份走助记词)。
  Future<String> getAccountPrivateKey(String accountId) async {
    final isar = await WalletIsar.instance.db();
    final acct = await isar.accountEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .findFirst();
    if (acct == null) {
      throw const WalletAuthException('未找到指定账户');
    }
    final seed = await _readMasterMiniSecretKey(acct.masterId);
    if (seed == null) {
      throw const WalletAuthException('密钥不可用，请重新导入钱包');
    }
    List<int>? childMiniSecretKey;
    try {
      childMiniSecretKey = _childMiniSecret(seed, acct.accountIndex);
      final childBytes = Uint8List.fromList(childMiniSecretKey);
      try {
        if (_accountIdFromBytes(NativeSr25519.publicKeyOf(childBytes)) !=
            accountId) {
          throw const WalletAuthException('本地私钥与账户不一致，请重新导入钱包');
        }
        // String 仅在用户明确导出私钥的 UI 边界生成；内部存取和签名始终保持字节。
        return '0x${_toHex(childBytes)}';
      } finally {
        childBytes.fillRange(0, childBytes.length, 0);
      }
    } finally {
      if (childMiniSecretKey != null) _zeroList(childMiniSecretKey);
      _zeroList(seed);
    }
  }

  // ── 派生 ──
  /// 从 master mini-secret 派生账户 [index]（全部 `//index` 硬派生，无 bare 根）,
  /// 返回该账户公钥 accountId + ss58。
  _DerivedAccount _deriveAccount(List<int> seed, int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', '不能为负');
    }
    final childMiniSecretKey = _childMiniSecret(seed, index);
    final childBytes = Uint8List.fromList(childMiniSecretKey);
    try {
      final accountId = _accountIdFromBytes(
        NativeSr25519.publicKeyOf(childBytes),
      );
      return _DerivedAccount(
        accountId: accountId,
        // SS58 编解码(base58 + 校验和)仍走 polkadart_keyring，非密码学。
        ss58Address: Keyring().encodeAddress(
          _hexToBytes(accountId),
          _ss58Prefix,
        ),
      );
    } finally {
      childBytes.fillRange(0, childBytes.length, 0);
      _zeroList(childMiniSecretKey);
    }
  }

  /// 提取账户 `//index` 的 child mini-secret（32B）。
  ///
  /// 复用共享真源解析 Substrate 官方数字硬派生 [ChainCode]，再对 root SecretKey
  /// 执行 `hardDeriveMiniSecretKey`。金标钉死 `fromSeed(child) == //index`。
  List<int> _childMiniSecret(List<int> seed, int index) {
    final chainCode = WalletMiniSecret.hardJunctionChainCode(index);
    try {
      return NativeSr25519.deriveHard(seed, chainCode);
    } finally {
      _zeroList(chainCode);
    }
  }

  // ── 硬件严档（按 master 存 MiniSecretKey + 助记词硬件信封密文）──
  Future<void> _writeMasterMiniSecretKey(
    String masterId,
    Uint8List miniSecretKey,
  ) async {
    try {
      await _secretStore.writeMasterMiniSecretKey(masterId, miniSecretKey);
    } on HardwareSecretvaultException catch (error) {
      throw _mapHardwareError(error);
    }
  }

  /// 解封 master [MiniSecretKey] 并逐字节验证账户0归属；调用方负责 finally 清零。
  Future<Uint8List?> _readMasterMiniSecretKey(String masterId) async {
    Uint8List? miniSecretKey;
    try {
      miniSecretKey = await _secretStore.readMasterMiniSecretKey(masterId);
    } on HardwareSecretvaultException catch (error) {
      throw _mapHardwareError(error);
    }
    if (miniSecretKey == null) return null;
    try {
      if (miniSecretKey.length != 32) {
        throw const WalletAuthException('钱包 MiniSecretKey 长度异常，请重新导入钱包');
      }
      if (_deriveAccount(miniSecretKey, 0).accountId != masterId) {
        throw const WalletAuthException('钱包 MiniSecretKey 归属异常，请重新导入钱包');
      }
      return miniSecretKey;
    } catch (_) {
      _zeroList(miniSecretKey);
      rethrow;
    }
  }

  Future<void> _writeMasterMnemonic(String masterId, String mnemonic) async {
    final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
    try {
      await _secretStore.writeMnemonic(masterId, mnemonicBytes);
    } on HardwareSecretvaultException catch (error) {
      throw _mapHardwareError(error);
    } finally {
      _zeroList(mnemonicBytes);
    }
  }

  Future<String?> _readMasterMnemonic(String masterId) async {
    Uint8List? mnemonicBytes;
    try {
      mnemonicBytes = await _secretStore.readMnemonic(masterId);
      if (mnemonicBytes == null) return null;
      final mnemonic = utf8.decode(mnemonicBytes, allowMalformed: false);
      if (!_isValidMnemonic(mnemonic)) {
        throw const WalletAuthException('钱包助记词数据异常，请重新导入钱包');
      }
      // password 按安全边界不持久化，无法从备份展示入口复算 masterId；硬件信封的
      // AAD 已严格绑定 masterId 与 mnemonic 类型，此处继续执行 BIP-39 checksum。
      return mnemonic;
    } on HardwareSecretvaultException catch (error) {
      throw _mapHardwareError(error);
    } on FormatException {
      throw const WalletAuthException('钱包密钥数据异常，请重新导入钱包');
    } finally {
      if (mnemonicBytes != null) _zeroList(mnemonicBytes);
    }
  }

  Future<void> _ensureHardwareAvailable() async {
    try {
      await _secretStore.ensureAvailable();
    } on HardwareSecretvaultException catch (error) {
      throw _mapHardwareError(error);
    }
  }

  /// 以真实硬件解封验证钱包访问权限，明文 [MiniSecretKey] 在返回前立即清零。
  Future<void> _verifyMasterAccess(String masterId) async {
    Uint8List? miniSecretKey;
    try {
      miniSecretKey = await _readMasterMiniSecretKey(masterId);
      if (miniSecretKey == null) {
        throw const WalletAuthException('密钥不可用，请重新导入钱包');
      }
    } finally {
      if (miniSecretKey != null) _zeroList(miniSecretKey);
    }
  }

  /// 创建/导入完成前回读三项事实：两类硬件信封密文与钱包专属硬件 KEK。
  /// 任一缺失都按整笔失败进入统一回滚，禁止返回只有数据库外壳的半成品钱包。
  Future<void> _verifyWalletSecretsPersisted(String masterId) async {
    if (!await _secretStore.containsMasterMiniSecretKey(masterId)) {
      throw StateError('master MiniSecretKey 密文持久化校验失败');
    }
    if (!await _secretStore.containsMnemonic(masterId)) {
      throw StateError('助记词密文持久化校验失败');
    }
    if (!await _secretStore.containsHardwareKey(masterId)) {
      throw StateError('钱包硬件 KEK 持久化校验失败');
    }
  }

  static WalletAuthException _mapHardwareError(
    HardwareSecretvaultException error,
  ) {
    switch (error.code) {
      case 'userCancelled':
      case 'lockout':
      case 'authError':
        return const WalletAuthException('未通过生物识别验证');
      case 'keyPermanentlyInvalidated':
        return const WalletAuthException('钱包硬件密钥已失效，请用助记词重新导入钱包');
      case 'noStrongBiometric':
      case 'notEnrolled':
        return const WalletAuthException('必须先在系统设置中录入强生物识别（指纹或面容）');
      case 'hardwareUnavailable':
      case 'unavailable':
        return const WalletAuthException('设备不支持钱包所需的硬件安全金库');
      default:
        return const WalletAuthException('钱包硬件金库访问失败，请重试');
    }
  }

  static Future<void> _attemptCleanup(
    List<Object> failures,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      failures.add(error);
    }
  }

  // ── 内部工具 ──
  /// 原子建钱包：同一事务分配 walletIndex、写 WalletEntity + 账户0（`//0`）。
  Future<(Wallet, Account)> _appendWalletAtomic({
    required String masterId,
    required String source,
    required _DerivedAccount primary,
  }) async {
    final isar = await WalletIsar.instance.db();
    final now = DateTime.now().millisecondsSinceEpoch;
    late int walletIndex;
    late int sortOrder;
    await isar.writeTxn(() async {
      final duplicate = await isar.walletEntitys
          .filter()
          .masterIdEqualTo(masterId)
          .findFirst();
      if (duplicate != null) {
        throw Exception('该钱包已存在（${duplicate.walletName}），无需重复导入');
      }
      final wallets =
          await isar.walletEntitys.where().sortByWalletIndex().findAll();
      final used = wallets.map((e) => e.walletIndex).toSet();
      walletIndex = 1;
      while (used.contains(walletIndex)) {
        walletIndex++;
      }
      final maxSort = wallets.isEmpty
          ? -1
          : wallets.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b);
      sortOrder = maxSort + 1;

      final wallet = WalletEntity()
        ..walletIndex = walletIndex
        ..walletName = '钱包$walletIndex'
        ..masterId = masterId
        ..createdAtMillis = now
        ..source = source
        ..sortOrder = sortOrder;
      await isar.walletEntitys.put(wallet);

      final account = AccountEntity()
        ..masterId = masterId
        ..accountIndex = 0
        ..accountId = primary.accountId
        ..ss58Address = primary.ss58Address
        ..accountName = '账户0'
        ..createdAtMillis = now;
      await isar.accountEntitys.put(account);
    });

    return (
      Wallet(
        walletIndex: walletIndex,
        walletName: '钱包$walletIndex',
        masterId: masterId,
        createdAtMillis: now,
        source: source,
        sortOrder: sortOrder,
      ),
      Account(
        masterId: masterId,
        accountIndex: 0,
        accountId: primary.accountId,
        ss58Address: primary.ss58Address,
        accountName: '账户0',
        createdAtMillis: now,
      ),
    );
  }

  static void _zeroList(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  static bool _isValidMnemonic(String mnemonic) {
    try {
      bip39m.Mnemonic.fromSentence(mnemonic, bip39m.Language.english);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _toHex(List<int> bytes) {
    const chars = '0123456789abcdef';
    final buf = StringBuffer();
    for (final b in bytes) {
      buf
        ..write(chars[(b >> 4) & 0x0f])
        ..write(chars[b & 0x0f]);
    }
    return buf.toString();
  }

  String _accountIdFromBytes(List<int> bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        '账户 ID 必须是 32 字节',
      );
    }
    final text = '0x${_toHex(bytes)}';
    if (!_accountIdPattern.hasMatch(text)) {
      throw StateError('派生出的 accountId 非规范形式');
    }
    return text;
  }

  List<int> _hexToBytes(String input) {
    final text = input.startsWith('0x') ? input.substring(2) : input;
    if (text.isEmpty || text.length.isOdd) return const <int>[];
    final out = <int>[];
    for (var i = 0; i < text.length; i += 2) {
      out.add(int.parse(text.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  Wallet _toWallet(WalletEntity row) => Wallet(
        walletIndex: row.walletIndex,
        walletName: row.walletName,
        masterId: row.masterId,
        createdAtMillis: row.createdAtMillis,
        source: row.source,
        sortOrder: row.sortOrder,
      );

  Account _toAccount(AccountEntity row) => Account(
        masterId: row.masterId,
        accountIndex: row.accountIndex,
        accountId: row.accountId,
        ss58Address: row.ss58Address,
        accountName: row.accountName,
        createdAtMillis: row.createdAtMillis,
      );
}

class _DerivedAccount {
  const _DerivedAccount({required this.accountId, required this.ss58Address});
  final String accountId;
  final String ss58Address;
}
