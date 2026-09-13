import 'dart:convert';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/qr/bodies/account_data_key_response_body.dart';
import 'package:citizenapp/security/account_data_key_provision.dart';
import 'package:citizenapp/security/local_cipher.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/signer/signing.dart';

class _MemoryStore implements LocalKeyBlobStore {
  final Map<String, String> entries = <String, String>{};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, String value) async => entries[key] = value;

  @override
  Future<void> delete(String key) async => entries.remove(key);

  @override
  Future<bool> compareAndSet(
    String key, {
    required String? expected,
    String? next,
  }) async {
    if (entries[key] != expected) return false;
    if (next == null) {
      entries.remove(key);
    } else {
      entries[key] = next;
    }
    return true;
  }
}

final class _DerivingWallet implements CitizenSdkWallet {
  _DerivingWallet(Uint8List secret) : _secret = Uint8List.fromList(secret);

  final Uint8List _secret;

  @override
  Future<Uint8List> deriveApplicationKey({
    required String accountId,
    required Uint8List salt,
    required Uint8List info,
  }) async => Uint8List.fromList(
    sha256.convert(<int>[..._secret, ...salt, ...info]).bytes,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const genesisHash =
      '0x1111111111111111111111111111111111111111111111111111111111111111';
  const cidNumber = 'GD-CTZN1-8F3A2B';
  const firstAccountId =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const secondAccountId =
      '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final firstSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final secondSecret = Uint8List.fromList(
    List<int>.generate(32, (i) => 100 + i),
  );
  const firstBinding = AccountDataBinding(
    genesisHash: genesisHash,
    cidNumber: cidNumber,
    bindingRevision: 1,
    accountId: firstAccountId,
  );
  const secondBinding = AccountDataBinding(
    genesisHash: genesisHash,
    cidNumber: cidNumber,
    bindingRevision: 2,
    accountId: secondAccountId,
  );

  group('当前钱包绑定元数据', () {
    late _MemoryStore store;
    late AccountDataBindingStore bindingStore;

    setUp(() {
      store = _MemoryStore();
      bindingStore = AccountDataBindingStore(store);
    });

    test('只保存公开绑定字段，不保存任何派生密钥', () async {
      await bindingStore.activate(firstBinding);
      final active = await bindingStore.readForCid(cidNumber);
      expect(active?.genesisHash, genesisHash);
      expect(active?.cidNumber, cidNumber);
      expect(active?.bindingRevision, 1);
      expect(active?.accountId, firstAccountId);
      expect(store.entries.length, 2);
      expect(
        store.entries.values,
        everyElement(isNot(contains(firstSecret.join(',')))),
      );
    });

    test('绑定版本禁止回退，同版本字段冲突失败关闭', () async {
      await bindingStore.activate(secondBinding);
      await expectLater(
        bindingStore.activate(firstBinding),
        throwsA(isA<AccountDataKeyException>()),
      );
      await expectLater(
        bindingStore.activate(
          const AccountDataBinding(
            genesisHash: genesisHash,
            cidNumber: cidNumber,
            bindingRevision: 2,
            accountId: firstAccountId,
          ),
        ),
        throwsA(isA<AccountDataKeyException>()),
      );
    });

    test('多 CID 绑定互不覆盖，不触碰无关持久值', () async {
      store.entries['unrelated_sentinel'] = 'keep';
      const secondCidBinding = AccountDataBinding(
        genesisHash: genesisHash,
        cidNumber: 'CN220-CTZN2-198805201-2026',
        bindingRevision: 1,
        accountId:
            '0x3333333333333333333333333333333333333333333333333333333333333333',
      );

      await bindingStore.activate(firstBinding);
      await bindingStore.activate(secondCidBinding);
      expect(
        (await bindingStore.readForCid(cidNumber))?.accountId,
        firstAccountId,
      );
      expect(
        (await bindingStore.readForCid(secondCidBinding.cidNumber))?.accountId,
        secondCidBinding.accountId,
      );
      expect(store.entries['unrelated_sentinel'], 'keep');

      await bindingStore.clearForCid(cidNumber);
      expect(await bindingStore.readForCid(cidNumber), isNull);
      expect(
        await bindingStore.readForCid(secondCidBinding.cidNumber),
        isNotNull,
      );
    });

    test('直接构造的无效链上绑定字段也失败关闭', () async {
      const invalidBindings = <AccountDataBinding>[
        AccountDataBinding(
          genesisHash: '0x01',
          cidNumber: cidNumber,
          bindingRevision: 1,
          accountId: firstAccountId,
        ),
        AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: '123456789012345678901234567890123',
          bindingRevision: 1,
          accountId: firstAccountId,
        ),
        AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: cidNumber,
          bindingRevision: 0,
          accountId: firstAccountId,
        ),
        AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: cidNumber,
          bindingRevision: 1,
          accountId: '0x01',
        ),
      ];
      for (final binding in invalidBindings) {
        await expectLater(
          bindingStore.activate(binding),
          throwsA(isA<AccountDataKeyException>()),
        );
        await expectLater(
          AccountDataKeyDeriver.derive(
            wallet: _DerivingWallet(firstSecret),
            binding: binding,
            purpose: LocalKeyPurpose.chat,
          ),
          throwsA(isA<AccountDataKeyException>()),
        );
      }
      expect(store.entries, isEmpty);
    });

    test('换绑交接日志只保存相邻版本的公开绑定上下文并可清除', () async {
      await bindingStore.writePendingHandover(
        source: firstBinding,
        target: secondBinding,
      );
      final pending = await bindingStore.readPendingHandover();
      expect(pending?.source.accountId, firstAccountId);
      expect(pending?.target.accountId, secondAccountId);
      expect(pending?.target.bindingRevision, 2);
      expect(pending?.state, AccountDataHandoverState.preparing);
      expect(store.entries.keys, <String>[
        AccountDataBindingStore.pendingHandoverKey,
      ]);
      expect(
        store.entries.values.single,
        isNot(contains(firstSecret.join(','))),
      );
      expect(
        store.entries.values.single,
        isNot(contains(secondSecret.join(','))),
      );

      await bindingStore.markPendingHandoverReady(
        source: firstBinding,
        target: secondBinding,
      );
      expect(
        (await bindingStore.readPendingHandover())?.state,
        AccountDataHandoverState.ready,
      );

      await bindingStore.clearPendingHandover(
        source: firstBinding,
        target: secondBinding,
      );
      expect(await bindingStore.readPendingHandover(), isNull);
      expect(store.entries, isEmpty);
    });

    test('换绑交接拒绝跨 CID、跨创世、跳版本和同账户目标', () async {
      final invalidTargets = <AccountDataBinding>[
        const AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: 'GD-CTZN1-OTHER',
          bindingRevision: 2,
          accountId: secondAccountId,
        ),
        const AccountDataBinding(
          genesisHash:
              '0x2222222222222222222222222222222222222222222222222222222222222222',
          cidNumber: cidNumber,
          bindingRevision: 2,
          accountId: secondAccountId,
        ),
        const AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: cidNumber,
          bindingRevision: 3,
          accountId: secondAccountId,
        ),
        const AccountDataBinding(
          genesisHash: genesisHash,
          cidNumber: cidNumber,
          bindingRevision: 2,
          accountId: firstAccountId,
        ),
      ];
      for (final target in invalidTargets) {
        await expectLater(
          bindingStore.writePendingHandover(
            source: firstBinding,
            target: target,
          ),
          throwsA(isA<AccountDataKeyException>()),
        );
      }
      expect(store.entries, isEmpty);
    });

    test('已落盘交接记录被篡改成跳版本时读取也失败关闭', () async {
      await bindingStore.writePendingHandover(
        source: firstBinding,
        target: secondBinding,
      );
      final decoded =
          jsonDecode(store.entries[AccountDataBindingStore.pendingHandoverKey]!)
              as Map<String, dynamic>;
      (decoded['target'] as Map<String, dynamic>)['binding_revision'] = 3;
      store.entries[AccountDataBindingStore.pendingHandoverKey] = jsonEncode(
        decoded,
      );

      await expectLater(
        bindingStore.readPendingHandover(),
        throwsA(isA<AccountDataKeyException>()),
      );
    });
  });

  group('当前钱包账户用途子钥', () {
    test('同一账户同一绑定跨设备派生结果一致', () async {
      final first = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(firstSecret),
        binding: firstBinding,
        purpose: LocalKeyPurpose.chat,
      );
      final anotherDevice = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(Uint8List.fromList(firstSecret)),
        binding: firstBinding,
        purpose: LocalKeyPurpose.chat,
      );
      expect(anotherDevice, first);
    });

    test('全部用途域互相隔离', () async {
      final values = <String>{};
      for (final purpose in LocalKeyPurpose.values) {
        final key = await AccountDataKeyDeriver.derive(
          wallet: _DerivingWallet(firstSecret),
          binding: firstBinding,
          purpose: purpose,
        );
        expect(key, hasLength(32));
        values.add(key.join(','));
      }
      expect(values.length, LocalKeyPurpose.values.length);
    });

    test('同一用途的 encryption 与 index 上下文互相隔离', () async {
      final encryptionKey = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(firstSecret),
        binding: firstBinding,
        purpose: LocalKeyPurpose.contactsCloud,
        context: 'encryption',
      );
      final indexKey = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(firstSecret),
        binding: firstBinding,
        purpose: LocalKeyPurpose.contactsCloud,
        context: 'index',
      );
      expect(indexKey, isNot(encryptionKey));
    });

    test('没有当前账户签名交接时，新钱包不能直接解密此前钱包历史私有密文', () async {
      final currentKey = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(firstSecret),
        binding: firstBinding,
        purpose: LocalKeyPurpose.chat,
      );
      final oldCiphertext = await LocalCipher.encryptString(
        key: currentKey,
        plaintext: '此前钱包历史私有数据',
        aad: '${LocalKeyPurpose.chat.domain}|message-before-rebind',
      );
      final newKey = await AccountDataKeyDeriver.derive(
        wallet: _DerivingWallet(secondSecret),
        binding: secondBinding,
        purpose: LocalKeyPurpose.chat,
      );
      expect(newKey, isNot(currentKey));
      await expectLater(
        LocalCipher.decryptString(
          key: newKey,
          blob: oldCiphertext,
          aad: '${LocalKeyPurpose.chat.domain}|message-before-rebind',
        ),
        throwsA(isA<LocalCipherException>()),
      );
    });
  });

  group('冷钱包用途钥加密交付', () {
    test('共享原语完成派生、0x22 授权、验签和解封', () async {
      final child = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      const accountId =
          '0x1111111111111111111111111111111111111111111111111111111111111111';
      const channel = MethodChannel('citizen/sdk/core/v1');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'verifySignature');
        return <Object?>[1, true];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const binding = AccountDataBinding(
        genesisHash: genesisHash,
        cidNumber: cidNumber,
        bindingRevision: 1,
        accountId: accountId,
      );
      final requests = <DataKeyRequest>[
        (purpose: LocalKeyPurpose.chat, context: null),
        (purpose: LocalKeyPurpose.contactsCloud, context: 'encryption'),
      ];
      final recipientSecret = Uint8List.fromList(List<int>.filled(32, 0x31));
      final session = await AccountDataKeyProvisionSession.create(
        binding: binding,
        requests: requests,
        expiresAt: 1900000000,
        recipientSecret: recipientSecret,
        requestNonce: List<int>.filled(16, 0x41),
      );
      final keys = <Uint8List>[];
      try {
        for (final request in requests) {
          keys.add(
            await AccountDataKeyDeriver.derive(
              wallet: _DerivingWallet(child),
              binding: binding,
              purpose: request.purpose,
              context: request.context,
            ),
          );
        }
        final plaintext = Uint8List.fromList(<int>[
          requests.length << 2,
          LocalKeyPurpose.chat.provisionCode,
          0,
          ...keys[0],
          LocalKeyPurpose.contactsCloud.provisionCode,
          1,
          ...keys[1],
        ]);
        final senderSecret = Uint8List.fromList(List<int>.filled(32, 0x51));
        final nonce = Uint8List.fromList(List<int>.filled(12, 0x61));
        final sealed = await _sealAccountDataBundle(
          recipientSecret: recipientSecret,
          senderSecret: senderSecret,
          nonce: nonce,
          plaintext: plaintext,
          aad: session.payload,
        );
        final senderPublicKey = sealed.senderPublicKey;
        final ciphertext = sealed.ciphertext;
        final authorization = accountDataKeyProvisionAuthorization(
          requestPayload: session.payload,
          senderPublicKey: senderPublicKey,
          nonce: nonce,
          ciphertext: ciphertext,
        );
        final message = signingMessage(
          opTag: kOpSignAccountDataKeyProvision,
          scalePayload: authorization,
        );
        final signature = Uint8List(64);
        final body = AccountDataKeyResponseBody.fromBytes(
          signerPublicKey: List<int>.filled(32, 0x11),
          signature: signature,
          keyExchangePublicKey: senderPublicKey,
          encryptionNonce: nonce,
          ciphertext: ciphertext,
        );

        final opened = await session.open(body);
        expect(opened, hasLength(2));
        expect(opened[0], keys[0]);
        expect(opened[1], keys[1]);
        for (final key in opened) {
          key.fillRange(0, key.length, 0);
        }

        final tampered = Uint8List.fromList(ciphertext)..[0] ^= 1;
        expect(
          session.open(
            AccountDataKeyResponseBody.fromBytes(
              signerPublicKey: List<int>.filled(32, 0x11),
              signature: signature,
              keyExchangePublicKey: senderPublicKey,
              encryptionNonce: nonce,
              ciphertext: tampered,
            ),
          ),
          throwsA(isA<AccountDataKeyException>()),
        );
        plaintext.fillRange(0, plaintext.length, 0);
        senderSecret.fillRange(0, senderSecret.length, 0);
        message.fillRange(0, message.length, 0);
      } finally {
        for (final key in keys) {
          key.fillRange(0, key.length, 0);
        }
        child.fillRange(0, child.length, 0);
        recipientSecret.fillRange(0, recipientSecret.length, 0);
        session.dispose();
      }
    });

    test('请求用 UTF-8 字节长度编码 CID，重复用途失败关闭', () {
      const binding = AccountDataBinding(
        genesisHash: genesisHash,
        cidNumber: '公民-A',
        bindingRevision: 1,
        accountId: firstAccountId,
      );
      final payload = encodeAccountDataKeyProvisionRequest(
        binding: binding,
        recipientPublicKey: List<int>.filled(32, 1),
        requests: <DataKeyRequest>[
          (purpose: LocalKeyPurpose.chat, context: null),
        ],
        expiresAt: 1900000000,
        requestNonce: List<int>.filled(16, 2),
      );
      expect(payload[32], utf8.encode('公民-A').length << 2);
      expect(
        () => encodeAccountDataKeyProvisionRequest(
          binding: binding,
          recipientPublicKey: List<int>.filled(32, 1),
          requests: <DataKeyRequest>[
            (purpose: LocalKeyPurpose.chat, context: null),
            (purpose: LocalKeyPurpose.chat, context: null),
          ],
          expiresAt: 1900000000,
          requestNonce: List<int>.filled(16, 2),
        ),
        throwsA(isA<AccountDataKeyException>()),
      );
    });
  });
}

Future<({Uint8List senderPublicKey, Uint8List ciphertext})>
_sealAccountDataBundle({
  required Uint8List recipientSecret,
  required Uint8List senderSecret,
  required Uint8List nonce,
  required Uint8List plaintext,
  required Uint8List aad,
}) async {
  final x25519 = X25519();
  final sender = await x25519.newKeyPairFromSeed(senderSecret);
  final recipient = await x25519.newKeyPairFromSeed(recipientSecret);
  final senderPublicKey = await sender.extractPublicKey();
  final recipientPublicKey = await recipient.extractPublicKey();
  final shared = await x25519.sharedSecretKey(
    keyPair: sender,
    remotePublicKey: recipientPublicKey,
  );
  final salt = await Sha256().hash(aad);
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: salt.bytes,
    info: utf8.encode('citizenapp.account-data/provision'),
  );
  final box = await AesGcm.with256bits().encrypt(
    plaintext,
    secretKey: key,
    nonce: nonce,
    aad: aad,
  );
  return (
    senderPublicKey: Uint8List.fromList(senderPublicKey.bytes),
    ciphertext: Uint8List.fromList(<int>[...box.cipherText, ...box.mac.bytes]),
  );
}
