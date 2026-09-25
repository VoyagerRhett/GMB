// 原签名域金标逐字节比较SDK Core真实结果；不保留App哈希镜像或预填答案。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';

const _fixturePath = 'test/signer/fixtures/signing_domain_vectors.json';

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

  group('签名消息金标向量(链端 primitives::sign ↔ Dart 逐字节对齐)', () {
    test('fixture 域常量为 GMB,与 Dart kGmbSignDomain 一致', () async {
      expect(root['domain'], 'GMB');
      expect(kGmbSignDomain, equals(const [0x47, 0x4D, 0x42]));
    });

    for (final v in vectors) {
      final name = v['name'] as String;
      final opTag = int.parse((v['op_tag'] as String).substring(2), radix: 16);
      final scalePayload = _hexToBytes(v['scale_payload_hex'] as String);
      final expectedHex = (v['message_hex'] as String).toLowerCase();

      test('$name (op_tag=0x${opTag.toRadixString(16)}) → $expectedHex', () async {
        final actual = (await CitizenSigning.encodePayload(CitizenSigningPayload.message(opTag: opTag, scalePayload: scalePayload)));
        expect(_hexLower(actual), expectedHex);
      });
    }
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
