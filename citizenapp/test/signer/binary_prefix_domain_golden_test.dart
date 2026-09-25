// 原二进制前缀及载荷金标仍逐字节比较；实际编码只调用SDK Core。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';

const _fixturePath = 'test/signer/fixtures/binary_prefix_domain_vectors.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestCitizenSdkTransport encodingTransport;
  late CitizenSdk encodingSdk;
  setUp(() async {
    encodingTransport = TestCitizenSdkTransport({}, useCore: true);
    encodingSdk = await encodingTransport.open();
  });
  tearDown(() async {
    await encodingSdk.close();
    await encodingTransport.dispose();
  });
  final file = File(_fixturePath);
  if (!file.existsSync()) {
    throw StateError('缺少原金标$_fixturePath');
  }

  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final vectors = (root['vectors'] as List).cast<Map<String, dynamic>>();
  final byName = {for (final v in vectors) v['name'] as String: v};

  group('二进制前缀域金标(链端 node ↔ 冷钱包 ↔ citizenapp 逐字节对齐)', () {
    test('fixture 域常量为 GMB,与 Dart kGmbSignDomain 一致', () async {
      expect(root['domain'], 'GMB');
      expect(kGmbSignDomain, equals(const [0x47, 0x4D, 0x42]));
      expect(kBinaryPrefixLen, 4);
    });

    test('binaryDomainPrefix(0x18) == ACTIVATE_ADMIN fixture prefix', () async {
      final v = byName['ACTIVATE_ADMIN']!;
      expect(kOpSignActivateAdmin, 0x18);
      expect(
        _hexLower((await CitizenSigning.encodePayload(CitizenSigningPayload.binaryPrefix(kOpSignActivateAdmin)))),
        (v['prefix_hex'] as String).toLowerCase(),
      );
    });

    test('binaryDomainPrefix(0x19) == DECRYPT fixture prefix', () async {
      final v = byName['DECRYPT']!;
      expect(kOpSignDecrypt, 0x19);
      expect(
        _hexLower((await CitizenSigning.encodePayload(CitizenSigningPayload.binaryPrefix(kOpSignDecrypt)))),
        (v['prefix_hex'] as String).toLowerCase(),
      );
    });

    test('ACTIVATE_ADMIN payload 逐字节 == fixture == Rust', () async {
      final v = byName['ACTIVATE_ADMIN']!;
      final inputs = v['sample_inputs'] as Map<String, dynamic>;
      final payload = (await CitizenSigning.encodePayload(CitizenSigningPayload.activateAdmin(
        cidNumber: inputs['cid_number'] as String,
        institutionCode: _hexToBytes(inputs['institution_code_hex'] as String),
        kind: inputs['kind'] as int,
        signerPublicKey: _hexToBytes(inputs['signer_public_key_hex'] as String),
        timestamp: BigInt.from(inputs['timestamp'] as int),
        nonce: _hexToBytes(inputs['nonce_hex'] as String),
      )));
      expect(payload.length, v['total_len'] as int);
      expect(_hexLower(payload), (v['payload_hex'] as String).toLowerCase());
    });

    test('DECRYPT challenge 逐字节 == fixture == Rust', () async {
      final v = byName['DECRYPT']!;
      final inputs = v['sample_inputs'] as Map<String, dynamic>;
      final payload = (await CitizenSigning.encodePayload(CitizenSigningPayload.decryptAdmin(
        cidNumber: inputs['cid_number'] as String,
        signerPublicKey: _hexToBytes(inputs['signer_public_key_hex'] as String),
        timestamp: BigInt.from(inputs['timestamp'] as int),
        nonce: _hexToBytes(inputs['nonce_hex'] as String),
      )));
      expect(payload.length, v['total_len'] as int);
      expect(_hexLower(payload), (v['payload_hex'] as String).toLowerCase());
    });
  });
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hexLower(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
