import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/blake2b.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/login/login_qr_handler.dart';
import 'package:citizenwallet/signer/qr_signer.dart';

String _hexBytes(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> _u64Le(int value) =>
    List<int>.generate(8, (index) => (value >> (index * 8)) & 0xff);

List<int> _occupyAuthorizationTemplate(String cid, int expiresAt) => [
  ...List<int>.filled(32, 0x44),
  cid.length << 2,
  ...cid.codeUnits,
  ...List<int>.filled(32, 0),
  ..._u64Le(0),
  ..._u64Le(expiresAt),
];

List<int> _rebindAuthorizationTemplate(String cid, int expiresAt) => [
  ...List<int>.filled(32, 0x44),
  cid.length << 2,
  ...cid.codeUnits,
  ...List<int>.filled(32, 0x55),
  ...List<int>.filled(32, 0),
  ..._u64Le(7),
  ..._u64Le(expiresAt),
];

void main() {
  late QrSigner signer;
  late String testSignerPublicKeyHex;

  setUp(() {
    signer = QrSigner();
    final pair = Keyring.sr25519.fromSeed(Uint8List(32));
    pair.ss58Format = 2027;
    testSignerPublicKeyHex =
        '0x${pair.bytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  });

  group('QrSigner.generateRequestId', () {
    test('生成 base64url 短 ID', () {
      final id = QrSigner.generateRequestId();
      expect(id.length, 22);
      expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id), isTrue);
    });

    test('带前缀的 ID', () {
      final id = QrSigner.generateRequestId(prefix: 'tx-');
      expect(id.startsWith('tx-'), isTrue);
      expect(id.length, greaterThan(22));
    });

    test('每次生成不同 ID', () {
      final ids = List.generate(10, (_) => QrSigner.generateRequestId());
      expect(ids.toSet().length, 10);
    });
  });

  group('QrSigner.parseRequest', () {
    Map<String, dynamic> validEnvelope() {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return {
        'p': QrProtocols.qrV1,
        'k': QrKind.signRequest.code,
        'i': 'test-valid-req-id-0001',
        'e': now + 90,
        'b': SignRequestBody.fromHex(
          action: QrActions.transferWithRemark,
          signerPublicKeyHex: testSignerPublicKeyHex,
          payloadHex: '0x0102',
        ).toJson(),
      };
    }

    test('序列化和反序列化一致', () {
      final envelope = validEnvelope();
      final encoded = jsonEncode(envelope);
      final parsed = signer.parseRequest(encoded);

      expect(parsed.kind, QrKind.signRequest);
      expect(parsed.id, 'test-valid-req-id-0001');
      expect(parsed.body.action, QrActions.transferWithRemark);
      expect(parsed.body.signerPublicKeyHex, testSignerPublicKeyHex);
      expect(parsed.body.payloadHex, '0x0102');
    });

    test('拒绝非 JSON', () {
      expect(
        () => signer.parseRequest('not json'),
        throwsA(
          isA<QrSignException>().having(
            (e) => e.code,
            'code',
            QrSignErrorCode.invalidFormat,
          ),
        ),
      );
    });

    test('拒绝错误协议版本', () {
      final json = validEnvelope()..['p'] = 'WRONG_PROTO';
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(isA<QrSignException>()),
      );
    });

    test('拒绝非签名请求 kind', () {
      final json = validEnvelope()..['k'] = QrKind.signResponse.code;
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(
          isA<QrSignException>().having(
            (e) => e.code,
            'code',
            QrSignErrorCode.invalidField,
          ),
        ),
      );
    });

    test('拒绝缺少 action', () {
      final json = validEnvelope();
      (json['b'] as Map<String, dynamic>).remove('a');
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(isA<QrSignException>()),
      );
    });

    test('拒绝 envelope 与 body 未知字段', () {
      final envelopeUnknown = validEnvelope()..['extra'] = true;
      expect(
        () => signer.parseRequest(jsonEncode(envelopeUnknown)),
        throwsA(isA<QrSignException>()),
      );

      final bodyUnknown = validEnvelope();
      (bodyUnknown['b'] as Map<String, dynamic>)['extra'] = true;
      expect(
        () => signer.parseRequest(jsonEncode(bodyUnknown)),
        throwsA(isA<QrSignException>()),
      );
    });

    test('拒绝字符串 kind 与带填充 base64url', () {
      final stringKind = validEnvelope()..['k'] = '1';
      expect(
        () => signer.parseRequest(jsonEncode(stringKind)),
        throwsA(isA<QrSignException>()),
      );

      final padded = validEnvelope();
      final body = padded['b'] as Map<String, dynamic>;
      body['u'] = '${body['u']}=';
      expect(
        () => signer.parseRequest(jsonEncode(padded)),
        throwsA(isA<QrSignException>()),
      );
    });

    test('拒绝已过期请求', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final json = validEnvelope()..['e'] = now - 100;
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(
          isA<QrSignException>().having(
            (e) => e.code,
            'code',
            QrSignErrorCode.expired,
          ),
        ),
      );
    });

    test('到期秒等于当前秒也拒绝', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final json = validEnvelope()..['e'] = now;
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(
          isA<QrSignException>().having(
            (e) => e.code,
            'code',
            QrSignErrorCode.expired,
          ),
        ),
      );
    });

    test('拒绝远未来期限，正常短期请求保持可解析', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final distant = validEnvelope()
        ..['e'] = now + maxQrRequestLifetimeSeconds + 1;
      expect(
        () => signer.parseRequest(jsonEncode(distant)),
        throwsA(
          isA<QrSignException>().having(
            (e) => e.code,
            'code',
            QrSignErrorCode.invalidField,
          ),
        ),
      );
      expect(signer.parseRequest(jsonEncode(validEnvelope())).id, isNotNull);
    });

    test('拒绝空 payload', () {
      final json = validEnvelope();
      (json['b'] as Map<String, dynamic>)['d'] = '';
      expect(
        () => signer.parseRequest(jsonEncode(json)),
        throwsA(isA<QrSignException>()),
      );
    });

    test('构造请求拒绝非规范签名公钥文本', () {
      expect(
        () => SignRequestBody.fromHex(
          action: QrActions.login,
          signerPublicKeyHex: testSignerPublicKeyHex.toUpperCase(),
          payloadHex: '0x0102',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SignRequestBody.fromHex(
          action: QrActions.login,
          signerPublicKeyHex: testSignerPublicKeyHex.substring(2),
          payloadHex: '0x0102',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('QrSigner.buildResponse', () {
    test('构建 compact sign_response envelope', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final request = QrEnvelope<SignRequestBody>(
        kind: QrKind.signRequest,
        id: 'resp-test-req-id-0001',
        expiresAt: now + 90,
        body: SignRequestBody.fromHex(
          action: QrActions.login,
          signerPublicKeyHex: testSignerPublicKeyHex,
          payloadHex: '0x01020304',
        ),
      );

      final response = signer.buildResponse(
        request: request,
        signatureHex: '0x${'aa' * 64}',
      );

      expect(response.kind, QrKind.signResponse);
      expect(response.id, request.id);
      expect(response.body.signerPublicKeyHex, testSignerPublicKeyHex);
      expect(response.body.signatureHex, '0x${'aa' * 64}');

      final json = jsonDecode(response.toRawJson()) as Map<String, dynamic>;
      expect(json['p'], QrProtocols.qrV1);
      expect(json['k'], QrKind.signResponse.code);
      expect(json['b']['u'], isA<String>());
      expect(json['b']['s'], isA<String>());
      expect(json['b'].containsKey('payload_hash'), isFalse);
    });
  });

  group('登录请求目标钱包', () {
    test('只允许 b.u 指定的同一钱包', () {
      final request = QrEnvelope<SignRequestBody>(
        kind: QrKind.signRequest,
        id: 'targeted-login-request',
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
        body: SignRequestBody.fromHex(
          action: QrActions.login,
          signerPublicKeyHex: testSignerPublicKeyHex,
          payloadHex: '0x6f6e6368696e61',
        ),
      );

      expect(
        loginRequestTargetsAccountId(request, testSignerPublicKeyHex),
        isTrue,
      );
      expect(loginRequestTargetsAccountId(request, '0x${'22' * 32}'), isFalse);
      expect(
        loginRequestTargetsAccountId(
          request,
          testSignerPublicKeyHex.toUpperCase(),
        ),
        isFalse,
      );
      expect(
        loginRequestTargetsAccountId(
          request,
          testSignerPublicKeyHex.substring(2),
        ),
        isFalse,
      );
    });
  });

  group('QrSigner.computePayloadHash', () {
    test('相同输入产生相同哈希', () {
      final h1 = QrSigner.computePayloadHash('0x01020304');
      final h2 = QrSigner.computePayloadHash('0x01020304');
      expect(h1, h2);
    });

    test('不同输入产生不同哈希', () {
      final h1 = QrSigner.computePayloadHash('0x01020304');
      final h2 = QrSigner.computePayloadHash('0x05060708');
      expect(h1, isNot(h2));
    });

    test('哈希长度为 0x + 64 字符 hex', () {
      final h = QrSigner.computePayloadHash('0x0102');
      expect(h.startsWith('0x'), isTrue);
      expect(h.length, 66);
    });

    test('拒绝非规范 payload hex', () {
      expect(
        () => QrSigner.computePayloadHash('0102'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrSigner.computePayloadHash('0X0102'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrSigner.computePayloadHash('0xAA'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('QrSigner.signingBytesFor', () {
    test('公民签名确认使用 GMB OP_SIGN_CITIZEN_IDENTITY 哈希域', () {
      final body = SignRequestBody.fromHex(
        action: QrActions.citizenIdentity,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex: '0x01020304',
      );
      final input = Uint8List.fromList([0x47, 0x4d, 0x42, 0x10, 1, 2, 3, 4]);
      final digest = Blake2bDigest(digestSize: 32)
        ..update(input, 0, input.length);
      final expected = Uint8List(32);
      digest.doFinal(expected, 0);

      final actual = QrSigner.signingBytesFor(body);

      expect(actual.toList(), expected.toList());
      expect(actual.toList(), isNot(body.payloadBytes.toList()));
    });

    test('注册局首次绑定按精确 CidOccupyAuthorization 槽位签名', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      const expiresAt = 1800000000;
      final template = _occupyAuthorizationTemplate(cid, expiresAt);
      final account = List<int>.filled(32, 0xab);
      final body = SignRequestBody.fromHex(
        action: QrActions.citizenOccupy,
        signerPublicKeyHex: testSignerPublicKeyHex, // 占号下 b.u 被忽略
        payloadHex: '0x${_hexBytes(template)}',
      );
      final exactAuthorization = List<int>.from(template)
        ..setRange(32 + 1 + cid.length, 32 + 1 + cid.length + 32, account);
      final input = Uint8List.fromList([
        0x47,
        0x4d,
        0x42,
        0x12,
        ...exactAuthorization,
      ]);
      final digest = Blake2bDigest(digestSize: 32)
        ..update(input, 0, input.length);
      final expected = Uint8List(32);
      digest.doFinal(expected, 0);

      final actual = QrSigner.signingBytesFor(
        body,
        selfAccountId: Uint8List.fromList(account),
      );
      expect(actual.toList(), expected.toList());
    });

    test('注册局换绑域签名用 OP_SIGN_CID_ADMIN_REBIND(0x1F)', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      const expiresAt = 1800000000;
      final template = _rebindAuthorizationTemplate(cid, expiresAt);
      final account = List<int>.filled(32, 0xcd);
      final body = SignRequestBody.fromHex(
        action: QrActions.citizenRebind,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex: '0x${_hexBytes(template)}',
      );
      const accountOffset = 32 + 1 + cid.length + 32;
      final exactAuthorization = List<int>.from(template)
        ..setRange(accountOffset, accountOffset + 32, account);
      final input = Uint8List.fromList([
        0x47,
        0x4d,
        0x42,
        0x1f,
        ...exactAuthorization,
      ]);
      final digest = Blake2bDigest(digestSize: 32)
        ..update(input, 0, input.length);
      final expected = Uint8List(32);
      digest.doFinal(expected, 0);

      expect(
        QrSigner.signingBytesFor(
          body,
          selfAccountId: Uint8List.fromList(account),
        ).toList(),
        expected.toList(),
      );
    });

    test('占号缺少本账户时返回空(不盲签)', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      final template = _occupyAuthorizationTemplate(cid, 1800000000);
      final body = SignRequestBody.fromHex(
        action: QrActions.citizenOccupy,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex: '0x${_hexBytes(template)}',
      );
      expect(QrSigner.signingBytesFor(body).isEmpty, isTrue);
    });

    test('域签名拒绝非零占位、旧尾拼接与换绑到当前账户', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      final malformedOccupy = _occupyAuthorizationTemplate(cid, 1800000000);
      malformedOccupy[32 + 1 + cid.length] = 1;
      final occupyBody = SignRequestBody.fromHex(
        action: QrActions.citizenOccupy,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex: '0x${_hexBytes(malformedOccupy)}',
      );
      expect(
        QrSigner.signingBytesFor(
          occupyBody,
          selfAccountId: Uint8List.fromList(List<int>.filled(32, 0xab)),
        ),
        isEmpty,
      );

      final legacyBody = SignRequestBody.fromHex(
        action: QrActions.citizenOccupy,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex: '0x${_hexBytes([cid.length << 2, ...cid.codeUnits])}',
      );
      expect(
        QrSigner.signingBytesFor(
          legacyBody,
          selfAccountId: Uint8List.fromList(List<int>.filled(32, 0xab)),
        ),
        isEmpty,
      );

      final rebindBody = SignRequestBody.fromHex(
        action: QrActions.citizenRebind,
        signerPublicKeyHex: testSignerPublicKeyHex,
        payloadHex:
            '0x${_hexBytes(_rebindAuthorizationTemplate(cid, 1800000000))}',
      );
      expect(
        QrSigner.signingBytesFor(
          rebindBody,
          selfAccountId: Uint8List.fromList(List<int>.filled(32, 0x55)),
        ),
        isEmpty,
      );
    });
  });

  group('QrSigner.verifySr25519Signature', () {
    test('有效签名验证通过', () {
      final pair = Keyring.sr25519.fromSeed(Uint8List(32));
      final message = Uint8List.fromList([1, 2, 3, 4]);
      final signature = pair.sign(message);
      final signerPublicKey =
          '0x${pair.bytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      final sigHex =
          '0x${signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

      expect(
        QrSigner.verifySr25519Signature(
          signerPublicKeyHex: signerPublicKey,
          signatureHex: sigHex,
          message: message,
        ),
        isTrue,
      );
    });

    test('无效签名验证失败', () {
      expect(
        QrSigner.verifySr25519Signature(
          signerPublicKeyHex: '0x${'00' * 32}',
          signatureHex: '0x${'ff' * 64}',
          message: Uint8List.fromList([1, 2, 3, 4]),
        ),
        isFalse,
      );
    });
  });

  _onchinaAdminSigningDomain();
}

/// 链上中国治理动作签名域(op_tag 0x20)与链端金标逐字节对拍。
///
/// 该域此前对**裸 JSON 文本直签**(无 GMB 前缀、无 op_tag、不进 SIGN_OP_TAGS),
/// 2026-08-06 审计后收敛到统一哈希域。金标真源:
/// `citizenchain/runtime/primitives/tests/fixtures/signing_domain_vectors.json`
void _onchinaAdminSigningDomain() {
  test('onchina 治理动作签 signing_message(0x20),与链端金标逐字节相同', () {
    // 金标向量:op_tag=0x20, scale_payload=0102030405060708
    final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final body = SignRequestBody(
      action: QrActions.onchinaAdmin,
      alg: 1,
      signerPublicKey: base64Url.encode(Uint8List(32)).replaceAll('=', ''),
      payload: base64Url.encode(payload).replaceAll('=', ''),
    );

    final bytes = QrSigner.signingBytesFor(body);
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    expect(
      hex,
      '466ec54a3b9e92db537733a0ee4c386c8968d8b4d54ac7ae2b18bdb192028c6b',
      reason: '与 signing_domain_vectors.json 的 0x20 向量不一致 = 冷端与链端签名域漂移',
    );
  });
}
