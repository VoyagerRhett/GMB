// WalletManager 单测（硬件严档存 master MiniSecretKey+助记词 + model B //index 派生）。
//
// 覆盖：建钱包(master)+账户0(//0)、加账户(读存储种子, //N)、按账户签名一致性、
// 导入对齐金标、删钱包/账户连带清硬件机密、重复导入拒绝、硬件信封密文落库、
// getMasterMnemonic 取回、getAccountPrivateKey 单账户隔离。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenwallet/isar/wallet_isar.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/qr/signature_message.dart';
import 'package:citizenwallet/wallet/wallet_manager.dart';
import 'package:citizenwallet/wallet/wallet_secure_keys.dart';

const String kDevPhrase =
    'bottom drive obey lake curtain smoke basket hold race lonely fit walk';
const String kOtherPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

// 金标（对齐 derivation_golden_test.dart，全 //index）。
const String kAccount0Id =
    '0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972';
const String kAccount0Ss58 =
    'w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2';
const String kAccount1Id =
    '0xb606fc73f57f03cdb4c932d475ab426043e429cecc2ffff0d2672b0df8398c48';
const String kAccount2Id =
    '0x46f136b564e1fad55031404dd84e5cd3fa76bfe7cc7599b39d38fd06663bbc0a';
const String kAccount0Child =
    '0x914dded06277afbe5b0e8a30bce539ec8a9552a784d08e530dc7c2915c478393';
const String kAccount1Child =
    '0x4433c3ada0cf37c3050d5435321872f4f84ef53d8b5f1f1560689d500b882245';

String _loginMessage({
  required String requestId,
  required String accountId,
  required int expiresAt,
}) {
  return buildSignatureMessage(
    kind: QrKind.signResponse,
    id: requestId,
    system: 'onchina',
    expiresAt: expiresAt,
    principal: accountId,
  );
}

/// 测试专用硬件金库：只模拟通道契约、AAD 绑定、密钥删除和认证失败，不模拟密码学。
final class _HardwareVaultMock {
  _HardwareVaultMock(this.messenger);

  static const channel = MethodChannel('gmb/hardware_secretvault');
  final TestDefaultBinaryMessenger messenger;
  final Map<String, _VaultRecord> _records = {};
  final Set<String> _keyScopes = {};
  var _nextCiphertext = 1;
  var encryptCalls = 0;
  var decryptCalls = 0;
  var deleteKeyCalls = 0;
  var containsKeyCalls = 0;
  int? failEncryptCall;
  var failNextDecrypt = false;
  var failDeleteKey = false;

  void install() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
      switch (call.method) {
        case 'securityStatus':
          return <String, Object?>{
            'supported': true,
            'strongBiometricEnrolled': true,
          };
        case 'encrypt':
          encryptCalls++;
          if (failEncryptCall == encryptCalls) {
            throw PlatformException(code: 'encryptFailed');
          }
          final scope = args['scope']! as String;
          final aad = Uint8List.fromList(args['associatedData']! as Uint8List);
          final plaintext = Uint8List.fromList(args['plaintext']! as Uint8List);
          final ciphertext = Uint8List(8);
          ByteData.sublistView(ciphertext).setUint64(0, _nextCiphertext++);
          _records[_id(ciphertext)] = _VaultRecord(scope, aad, plaintext);
          _keyScopes.add(scope);
          return ciphertext;
        case 'decrypt':
          decryptCalls++;
          if (failNextDecrypt) {
            failNextDecrypt = false;
            throw PlatformException(code: 'userCancelled');
          }
          final scope = args['scope']! as String;
          final aad = args['associatedData']! as Uint8List;
          final ciphertext = args['ciphertext']! as Uint8List;
          final record = _records[_id(ciphertext)];
          if (!_keyScopes.contains(scope) ||
              record == null ||
              record.scope != scope ||
              !_sameBytes(record.aad, aad)) {
            throw PlatformException(code: 'authenticationFailed');
          }
          // 真机 StandardMessageCodec 返回的 TypedData 可能是只读视图；共享层必须
          // 立即复制为自有可清零缓冲区，禁止直接覆写此借用结果。
          return Uint8List.fromList(record.plaintext).asUnmodifiableView();
        case 'deleteKey':
          deleteKeyCalls++;
          if (failDeleteKey) {
            throw PlatformException(code: 'deleteFailed');
          }
          _keyScopes.remove(args['scope']! as String);
          return null;
        case 'containsKey':
          containsKeyCalls++;
          return _keyScopes.contains(args['scope']! as String);
      }
      throw PlatformException(code: 'notImplemented');
    });
  }

  void reset() {
    for (final record in _records.values) {
      record.aad.fillRange(0, record.aad.length, 0);
      record.plaintext.fillRange(0, record.plaintext.length, 0);
    }
    _records.clear();
    _keyScopes.clear();
    _nextCiphertext = 1;
    encryptCalls = 0;
    decryptCalls = 0;
    deleteKeyCalls = 0;
    containsKeyCalls = 0;
    failEncryptCall = null;
    failNextDecrypt = false;
    failDeleteKey = false;
  }

  void uninstall() => messenger.setMockMethodCallHandler(channel, null);

  static String _id(Uint8List bytes) => bytes.join(',');

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var different = 0;
    for (var index = 0; index < left.length; index++) {
      different |= left[index] ^ right[index];
    }
    return different == 0;
  }
}

final class _VaultRecord {
  const _VaultRecord(this.scope, this.aad, this.plaintext);
  final String scope;
  final Uint8List aad;
  final Uint8List plaintext;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final hardwareVault = _HardwareVaultMock(binding.defaultBinaryMessenger);
  final manager = WalletManager();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    hardwareVault
      ..reset()
      ..install();
    await WalletIsar.instance.resetForTest();
  });

  tearDown(() async {
    hardwareVault
      ..reset()
      ..uninstall();
    await WalletIsar.instance.resetForTest();
  });

  test('Isar 最终 schema 指纹固定，依赖升级不得静默改库', () {
    expect(WalletEntitySchema.id, 495311719639707741);
    expect(WalletEntitySchema.properties.keys, {
      'createdAtMillis',
      'masterId',
      'sortOrder',
      'source',
      'walletIndex',
      'walletName',
    });
    expect(WalletEntitySchema.indexes.keys, {'walletIndex', 'masterId'});

    expect(AccountEntitySchema.id, -996322080142432925);
    expect(AccountEntitySchema.properties.keys, {
      'accountId',
      'accountIndex',
      'accountName',
      'createdAtMillis',
      'masterId',
      'ss58Address',
    });
    expect(AccountEntitySchema.indexes.keys, {
      'masterId_accountIndex',
      'accountId',
      'ss58Address',
    });

    expect(AppKvEntitySchema.id, -4757328183228885293);
    expect(AppKvEntitySchema.properties.keys, {
      'boolValue',
      'intValue',
      'key',
      'stringValue',
    });
    expect(AppKvEntitySchema.indexes.keys, {'key'});
  });

  test('community 引擎启动前幂等清理 Isar 3.1 旧锁文件', () async {
    const directory = '/tmp/gmb-citizenwallet-isar31-compat';
    const databaseName = 'legacy_lock_cleanup_test';
    final testDirectory = Directory(directory);
    final legacyLock = File('$directory/$databaseName.isar.lock');
    try {
      await testDirectory.create(recursive: true);
      await legacyLock.writeAsString('');

      await WalletIsar.instance.cleanupLegacyLockFileForTest(
        directory,
        databaseName,
      );
      expect(await legacyLock.exists(), isFalse);

      // 第二次调用仍应成功，避免升级后每次启动出现残留清理异常。
      await WalletIsar.instance.cleanupLegacyLockFileForTest(
        directory,
        databaseName,
      );
    } finally {
      if (await testDirectory.exists() && await testDirectory.list().isEmpty) {
        await testDirectory.delete();
      }
    }
  });

  test('createWallet 建钱包 + 账户0(//0)，masterId == 账户0 accountId', () async {
    final result = await manager.createWallet();
    expect(result.primaryAccount.accountIndex, 0);
    expect(result.primaryAccount.derivationPath, '//0');
    expect(result.wallet.masterId, result.primaryAccount.accountId);

    final accounts = await manager.getAccounts(result.wallet.masterId);
    expect(accounts.length, 1);
    expect(accounts.single.accountId, result.primaryAccount.accountId);
  });

  test('18词创建、备份与重新导入恢复同一账户和密码派生', () async {
    const password = 'Aa1!中华';
    final created = await manager.createWallet(
      wordCount: 18,
      password: password,
    );
    expect(created.mnemonic.split(' ').length, 18);
    expect(
      await manager.getMasterMnemonic(created.wallet.masterId) ==
          created.mnemonic,
      isTrue,
    );

    // 删除后按原导入路径恢复，核对同一助记词和密码仍得到原账户0。
    await manager.deleteWallet(created.wallet.masterId);
    final restored = await manager.importWallet(
      created.mnemonic,
      password: password,
    );
    expect(
      restored.primaryAccount.accountId == created.primaryAccount.accountId,
      isTrue,
    );
    expect(restored.wallet.masterId == created.wallet.masterId, isTrue);
    expect(
      await manager.getMasterMnemonic(restored.wallet.masterId) ==
          created.mnemonic,
      isTrue,
    );
  });

  test('18词导入拒绝未知词和词数不足，且不新增钱包', () async {
    final created = await manager.createWallet(wordCount: 18);
    final words = created.mnemonic.split(' ');
    final unknownWord = [...words]..[0] = 'notaword';
    expect(
      () => manager.importWallet(unknownWord.join(' ')),
      throwsA(isA<Exception>()),
    );
    expect(
      () => manager.importWallet(words.take(17).join(' ')),
      throwsA(isA<Exception>()),
    );
    expect((await manager.getWallets()).length, 1);
  });

  test('原12词默认值与24词创建结果保持不变', () async {
    final twelve = await manager.createWallet();
    final twentyFour = await manager.createWallet(wordCount: 24);
    expect(twelve.mnemonic.split(' ').length, 12);
    expect(twentyFour.mnemonic.split(' ').length, 24);
    expect((await manager.getWallets()).length, 2);
  });

  test('导入入口仅接受12、18、24词，其他词数不建立钱包', () async {
    for (final count in [0, 11, 13, 15, 21, 23, 25]) {
      final phrase = List.filled(count, 'abandon').join(' ');
      expect(
        () => manager.importWallet(phrase),
        throwsA(predicate((e) => '$e'.contains('助记词必须为 12、18 或 24 个单词'))),
      );
    }
    expect(await manager.getWallets(), isEmpty);
  });

  test('24词创建后按原导入路径恢复同一账户0', () async {
    final created = await manager.createWallet(wordCount: 24);
    await manager.deleteWallet(created.wallet.masterId);
    final restored = await manager.importWallet(created.mnemonic);
    expect(restored.primaryAccount.accountId, created.primaryAccount.accountId);
  });

  test('importWallet 账户0(//0) 对齐金标', () async {
    final result = await manager.importWallet(kDevPhrase);
    expect(result.primaryAccount.accountId, kAccount0Id);
    expect(result.primaryAccount.ss58Address, kAccount0Ss58);
    expect(result.wallet.masterId, kAccount0Id);
  });

  test('importWallet 非空 password 对齐 Subkey 且 password 不持久化', () async {
    final created = await manager.importWallet(kDevPhrase, password: 'Aa1!中华');
    expect(
      created.primaryAccount.accountId,
      '0x582cdc8c9b4c0ab469a54850285004eec274d08baa1ccd885300697c1410a939',
    );
    expect(
      await manager.getMasterMnemonic(created.wallet.masterId),
      kDevPhrase,
    );
    const storage = FlutterSecureStorage();
    final all = await storage.readAll();
    expect(
      all.keys.where((key) => key.toLowerCase().contains('password')),
      isEmpty,
    );
    expect(all.values, isNot(contains('Aa1!中华')));
  });

  test('addAccount 派生 //1 //2，对齐金标且序号递增（读存储种子）', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);
    final a2 = await manager.addAccount(created.wallet.masterId);

    expect(a1.accountIndex, 1);
    expect(a1.accountId, kAccount1Id);
    expect(a2.accountIndex, 2);
    expect(a2.accountId, kAccount2Id);

    final accounts = await manager.getAccounts(created.wallet.masterId);
    expect(accounts.map((e) => e.accountIndex).toList(), [0, 1, 2]);
  });

  test('钱包错误文案保留业务消息并隐藏内部运行时细节', () {
    expect(walletErrorMessage(const WalletAuthException('账户已存在')), '账户已存在');
    expect(walletErrorMessage(Exception('助记词无效')), '助记词无效');
    expect(
      walletErrorMessage(UnsupportedError('只读缓冲区')),
      '钱包操作失败，请重试',
    );
  });

  test('signForAccount 产出可被该账户公钥验证的签名', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);

    final payload = Uint8List.fromList(List<int>.generate(48, (i) => i));
    final sig = await manager.signForAccount(a1.accountId, payload);

    final verifier = await Keyring.sr25519.fromUri('$kDevPhrase//1');
    expect(verifier.verify(payload, sig), isTrue);

    // 账户0(//0) 的公钥不应验通账户1 的签名。
    final wrong = await Keyring.sr25519.fromUri('$kDevPhrase//0');
    expect(wrong.verify(payload, sig), isFalse);
  });

  test('登录签名请求过期时在硬件解封和私钥调用前拒绝', () async {
    final created = await manager.importWallet(kDevPhrase);
    final decryptCalls = hardwareVault.decryptCalls;
    final message = _loginMessage(
      requestId: 'login-expired-test-0001',
      accountId: created.primaryAccount.accountId,
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1,
    );

    await expectLater(
      manager.signUtf8ForAccount(created.primaryAccount.accountId, message),
      throwsA(
        isA<WalletAuthException>().having(
          (error) => error.message,
          'message',
          contains('已过期'),
        ),
      ),
    );
    expect(hardwareVault.decryptCalls, decryptCalls);
  });

  test('登录签名请求 ID 成功签名后持久化拒绝重复调用', () async {
    final created = await manager.importWallet(kDevPhrase);
    final decryptCalls = hardwareVault.decryptCalls;
    final message = _loginMessage(
      requestId: 'login-replay-test-0001',
      accountId: created.primaryAccount.accountId,
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
    );

    await manager.signUtf8ForAccount(created.primaryAccount.accountId, message);
    await expectLater(
      manager.signUtf8ForAccount(created.primaryAccount.accountId, message),
      throwsA(
        isA<WalletAuthException>().having(
          (error) => error.message,
          'message',
          contains('已处理'),
        ),
      ),
    );
    expect(hardwareVault.decryptCalls - decryptCalls, 1);
  });

  test('登录签名认证失败会释放请求占位，允许用户再次确认', () async {
    final created = await manager.importWallet(kDevPhrase);
    final decryptCalls = hardwareVault.decryptCalls;
    hardwareVault.failNextDecrypt = true;
    final message = _loginMessage(
      requestId: 'login-retry-test-00001',
      accountId: created.primaryAccount.accountId,
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
    );

    await expectLater(
      manager.signUtf8ForAccount(created.primaryAccount.accountId, message),
      throwsA(isA<WalletAuthException>()),
    );
    final result = await manager.signUtf8ForAccount(
      created.primaryAccount.accountId,
      message,
    );
    expect(result.signerPublicKey, created.primaryAccount.accountId);
    expect(hardwareVault.decryptCalls - decryptCalls, 2);
  });

  test('deleteWallet 连带清账户与 seed/助记词密钥', () async {
    final created = await manager.importWallet(kDevPhrase);
    await manager.addAccount(created.wallet.masterId);
    await manager.deleteWallet(created.wallet.masterId);

    expect(await manager.getWallets(), isEmpty);
    expect(await manager.getAccounts(created.wallet.masterId), isEmpty);
    const storage = FlutterSecureStorage();
    expect(
      await storage.read(
        key: WalletSecureKeys.masterMiniSecretKey(kAccount0Id),
      ),
      isNull,
    );
    expect(
      await storage.read(key: WalletSecureKeys.mnemonic(kAccount0Id)),
      isNull,
    );
  });

  test('创建写入失败会清完密文与硬件 KEK 后再回滚事实行', () async {
    hardwareVault.failEncryptCall = 2;

    await expectLater(
      manager.importWallet(kDevPhrase),
      throwsA(isA<WalletAuthException>()),
    );

    expect(await manager.getWallets(), isEmpty);
    const storage = FlutterSecureStorage();
    expect(
      await storage.read(
        key: WalletSecureKeys.masterMiniSecretKey(kAccount0Id),
      ),
      isNull,
    );
    expect(
      await storage.read(key: WalletSecureKeys.mnemonic(kAccount0Id)),
      isNull,
    );
    expect(hardwareVault.deleteKeyCalls, 1);
    expect(hardwareVault.containsKeyCalls, greaterThanOrEqualTo(1));
  });

  test('回滚清理失败会继续执行其余项并保留事实行供再次清理', () async {
    hardwareVault
      ..failEncryptCall = 2
      ..failDeleteKey = true;

    await expectLater(
      manager.importWallet(kDevPhrase),
      throwsA(isA<WalletLocalCleanupException>()),
    );

    expect(await manager.getWallets(), hasLength(1));
    const storage = FlutterSecureStorage();
    expect(
      await storage.read(
        key: WalletSecureKeys.masterMiniSecretKey(kAccount0Id),
      ),
      isNull,
    );
    expect(
      await storage.read(key: WalletSecureKeys.mnemonic(kAccount0Id)),
      isNull,
    );
    expect(hardwareVault.deleteKeyCalls, 1);
    expect(hardwareVault.containsKeyCalls, greaterThanOrEqualTo(1));

    // master 密文已删除时，显式删钱包只重试残留清理，不再解封不存在的明文。
    hardwareVault.failDeleteKey = false;
    await manager.deleteWallet(kAccount0Id);
    expect(await manager.getWallets(), isEmpty);
  });

  test('重复导入同一助记词被拒绝', () async {
    await manager.importWallet(kDevPhrase);
    expect(() => manager.importWallet(kDevPhrase), throwsA(isA<Exception>()));
  });

  test('并发重复导入只允许一个钱包原子落库', () async {
    final results = await Future.wait(
      [manager.importWallet(kDevPhrase), manager.importWallet(kDevPhrase)].map((
        future,
      ) async {
        try {
          await future;
          return true;
        } catch (_) {
          return false;
        }
      }),
    );

    expect(results.where((ok) => ok), hasLength(1));
    expect(await manager.getWallets(), hasLength(1));
    expect(await manager.getAccounts(kAccount0Id), hasLength(1));
  });

  test('getAccountByAccountId 精确命中/未知返回 null(扫码定位边界)', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);

    expect((await manager.getAccountByAccountId(kAccount0Id))?.accountIndex, 0);
    expect(
      (await manager.getAccountByAccountId(a1.accountId))?.accountIndex,
      1,
    );
    expect(
      await manager.getAccountByAccountId(
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd0',
      ),
      isNull,
    );
  });

  test('getWalletByMasterId 命中/未知', () async {
    final created = await manager.importWallet(kDevPhrase);
    expect(
      (await manager.getWalletByMasterId(created.wallet.masterId))?.masterId,
      created.wallet.masterId,
    );
    expect(await manager.getWalletByMasterId(kAccount1Id), isNull);
  });

  test('deleteAccount 删非末位账户,账户0与钱包保留', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);
    await manager.addAccount(created.wallet.masterId); // //2

    await manager.deleteAccount(a1.accountId);

    final accounts = await manager.getAccounts(created.wallet.masterId);
    expect(accounts.map((e) => e.accountIndex).toList(), [0, 2]);
    expect(await manager.getWallets(), hasLength(1));
  });

  test('deleteAccount 拒绝删账户0(尚有兄弟账户)', () async {
    final created = await manager.importWallet(kDevPhrase);
    await manager.addAccount(created.wallet.masterId);
    expect(() => manager.deleteAccount(kAccount0Id), throwsA(isA<Exception>()));
    expect(await manager.getAccountByAccountId(kAccount0Id), isNotNull);
  });

  test('deleteAccount 删光账户级联删钱包与密钥', () async {
    final created = await manager.importWallet(kDevPhrase);
    await manager.deleteAccount(kAccount0Id);
    expect(await manager.getWallets(), isEmpty);
    expect(await manager.getAccounts(created.wallet.masterId), isEmpty);
    const storage = FlutterSecureStorage();
    expect(
      await storage.read(
        key: WalletSecureKeys.masterMiniSecretKey(kAccount0Id),
      ),
      isNull,
    );
  });

  test('删中间账户后 addAccount 仍为 max+1(不回填空档,行为钉死)', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);
    await manager.addAccount(created.wallet.masterId); // //2
    await manager.deleteAccount(a1.accountId); // 删 //1,留 0,2

    final a3 = await manager.addAccount(created.wallet.masterId);
    expect(a3.accountIndex, 3); // max(2)+1,不回填 1
  });

  test('renameWallet / reorderWallets', () async {
    final w1 = await manager.importWallet(kDevPhrase);
    final w2 = await manager.importWallet(kOtherPhrase);

    await manager.renameWallet(w1.wallet.masterId, '主号');
    final renamed = await manager.getWalletByMasterId(w1.wallet.masterId);
    expect(renamed?.walletName, '主号');

    await manager.reorderWallets([w2.wallet.masterId, w1.wallet.masterId]);
    final ordered = await manager.getWallets();
    expect(ordered.first.masterId, w2.wallet.masterId);
  });

  test('master MiniSecretKey + 助记词硬件信封密文落库并可取回', () async {
    final created = await manager.importWallet(kDevPhrase);
    const storage = FlutterSecureStorage();
    final seedStored = await storage.read(
      key: WalletSecureKeys.masterMiniSecretKey(created.wallet.masterId),
    );
    final mnStored = await storage.read(
      key: WalletSecureKeys.mnemonic(created.wallet.masterId),
    );
    expect(seedStored, isNotNull);
    expect(mnStored, isNotNull);
    // master MiniSecretKey 从未编码成明文 hex；SecureStorage 只有信封密文。
    expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(seedStored!), isFalse);
    // 助记词密文里不得含明文助记词。
    expect(mnStored!.contains(kDevPhrase), isFalse);
    // getMasterMnemonic 解密取回原文。
    expect(
      await manager.getMasterMnemonic(created.wallet.masterId),
      kDevPhrase,
    );
  });

  test('交换不同钱包种子密文会因 masterId 归属校验被拒绝', () async {
    final first = await manager.importWallet(kDevPhrase);
    final second = await manager.importWallet(kOtherPhrase);
    const storage = FlutterSecureStorage();
    final firstKey = WalletSecureKeys.masterMiniSecretKey(
      first.wallet.masterId,
    );
    final secondKey = WalletSecureKeys.masterMiniSecretKey(
      second.wallet.masterId,
    );
    final firstCipher = await storage.read(key: firstKey);
    final secondCipher = await storage.read(key: secondKey);
    await storage.write(key: firstKey, value: secondCipher);
    await storage.write(key: secondKey, value: firstCipher);

    expect(
      () => manager.addAccount(first.wallet.masterId),
      throwsA(isA<WalletAuthException>()),
    );
  });

  test('交换不同钱包助记词密文会因 masterId 归属校验被拒绝', () async {
    final first = await manager.importWallet(kDevPhrase);
    final second = await manager.importWallet(kOtherPhrase);
    const storage = FlutterSecureStorage();
    final firstKey = WalletSecureKeys.mnemonic(first.wallet.masterId);
    final secondKey = WalletSecureKeys.mnemonic(second.wallet.masterId);
    final firstCipher = await storage.read(key: firstKey);
    final secondCipher = await storage.read(key: secondKey);
    await storage.write(key: firstKey, value: secondCipher);
    await storage.write(key: secondKey, value: firstCipher);

    expect(
      () => manager.getMasterMnemonic(first.wallet.masterId),
      throwsA(isA<WalletAuthException>()),
    );
  });

  test('getAccountPrivateKey 从种子派生该账户 child mini-secret,单账户隔离', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a1 = await manager.addAccount(created.wallet.masterId);

    final key0 = await manager.getAccountPrivateKey(kAccount0Id);
    final key1 = await manager.getAccountPrivateKey(a1.accountId);

    expect(key0, kAccount0Child);
    expect(key1, kAccount1Child);
    // 隔离:两账户私钥互不相同,单把泄漏不牵连另一把。
    expect(key0, isNot(equals(key1)));
  });

  test('addAccount 指定序号:仅[0]时加 //3,非连续,accountId 对齐 fromUri', () async {
    final created = await manager.importWallet(kDevPhrase);
    final a3 = await manager.addAccount(created.wallet.masterId, index: 3);
    expect(a3.accountIndex, 3);
    final ref = await Keyring.sr25519.fromUri('$kDevPhrase//3');
    ref.ss58Format = 2027;
    final refId =
        '0x${ref.bytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    expect(a3.accountId, refId);

    final accounts = await manager.getAccounts(created.wallet.masterId);
    expect(accounts.map((e) => e.accountIndex).toList(), [0, 3]);
  });

  test('addAccount 指定序号:回填低于 max 的空缺([0,3]→加//1→[0,1,3])', () async {
    final created = await manager.importWallet(kDevPhrase);
    await manager.addAccount(created.wallet.masterId, index: 3);
    await manager.addAccount(created.wallet.masterId, index: 1);
    final accounts = await manager.getAccounts(created.wallet.masterId);
    expect(accounts.map((e) => e.accountIndex).toList(), [0, 1, 3]);
  });

  test('addAccount 指定序号:已存在/序号0/越界 均被拒', () async {
    final created = await manager.importWallet(kDevPhrase);
    await manager.addAccount(created.wallet.masterId); // //1
    expect(
      () => manager.addAccount(created.wallet.masterId, index: 1),
      throwsA(isA<WalletAuthException>()),
    );
    expect(
      () => manager.addAccount(created.wallet.masterId, index: 0),
      throwsA(isA<WalletAuthException>()),
    );
    expect(
      () => manager.addAccount(
        created.wallet.masterId,
        index: WalletManager.maxAccountIndex + 1,
      ),
      throwsA(isA<WalletAuthException>()),
    );
  });

  test('addAccount 指定序号:上界 1989 可加', () async {
    final created = await manager.importWallet(kDevPhrase);
    final top = await manager.addAccount(
      created.wallet.masterId,
      index: WalletManager.maxAccountIndex,
    );
    expect(top.accountIndex, WalletManager.maxAccountIndex);
  });

  test('并发添加下一个账户在事务内分配不重复序号', () async {
    final created = await manager.importWallet(kDevPhrase);
    final accounts = await Future.wait([
      manager.addAccount(created.wallet.masterId),
      manager.addAccount(created.wallet.masterId),
    ]);
    expect(accounts.map((account) => account.accountIndex).toSet(), {1, 2});
  });
}
