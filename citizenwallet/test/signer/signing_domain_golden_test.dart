import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/blake2b.dart';

import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/signer/qr_signer.dart';
import 'package:citizenwallet/security/account_data_key_provision.dart';

// 冷钱包哈希域金标锁(citizenwallet ⇔ citizenchain)。
//
// 本文件**直接读真源**,冷钱包侧不保存镜像副本(与 Worker 侧同策略)。
//
// 为什么必须有这个文件:qr_signer_test.dart 里三处签名域断言都是**自证**——
// 测试自己用 Blake2bDigest 算一遍当 expected,再与实现比。那只证明了「实现调用了
// pointycastle」,没证明「结果与链端一致」。若 pointycastle 的 Blake2b 与 Rust 的
// blake2_256 在任何参数上有差异,或两处同时用错,测试照样全绿,而冷钱包是**真正
// 拿私钥出签的那一端**,签出链端不认的签名要到线上才暴露。
//
// 本文件的期望值一律来自真源(Rust 生成),自证由此变他证。
//
// 真源:citizenchain/runtime/primitives/tests/fixtures/signing_domain_vectors.json
// 规范实现:citizenchain/runtime/primitives/src/sign.rs::signing_message
// 契约:被签消息 = blake2_256( GMB(3B) || op_tag(1B) || payload )

const String _vectorsPath =
    'test/signer/fixtures/signing_domain_vectors.json';

/// 测试签名公钥占位:哈希域摘要不含 b.u,取值不影响被签字节。
const String _testSignerPublicKeyHex =
    '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48';

Uint8List _hexToBytes(String hex) {
  final clean = hex.toLowerCase().replaceFirst('0x', '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i += 1) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 与 `QrSigner._gmbSigningMessage` 同构的独立实现。
///
/// 此处**只做摘要**,期望值来自真源而非本函数,故不构成自证:本函数算错,
/// 与真源比对立即失败。
Uint8List _blake2Digest(List<int> input) {
  final digest = Blake2bDigest(digestSize: 32)
    ..update(Uint8List.fromList(input), 0, input.length);
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  return out;
}

void main() {
  final file = File(_vectorsPath);
  final canonical = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final domain = canonical['domain'] as String;
  final vectors = (canonical['vectors'] as List).cast<Map<String, dynamic>>();
  final gmbPrefix = utf8.encode(domain);

  group('哈希域摘要原语与链端一致(直读 citizenchain 真源)', () {
    test('真源可读、域为 GMB 且向量非空', () {
      // 读成空数组时下面的循环一条用例都不生成而整体显示通过,这条挡住金标静默失效。
      expect(
        file.existsSync(),
        isTrue,
        reason: '真源不可达,cwd=${Directory.current.path}',
      );
      expect(domain, 'GMB');
      expect(vectors, isNotEmpty);
    });

    // 覆盖真源全部 op_tag。冷钱包只签其中三个域,但摘要原语是共用的:
    // 一旦 pointycastle 与 Rust 的 blake2_256 有任何差异,这里会全线飘红。
    for (final vector in vectors) {
      final name = vector['name'] as String;
      final opTag = int.parse(vector['op_tag'] as String);
      final payload = _hexToBytes(vector['scale_payload_hex'] as String);
      final expected = (vector['message_hex'] as String).toLowerCase();

      test('$name (op_tag ${vector['op_tag']}) 摘要与链端逐字节一致', () {
        final actual = _blake2Digest([...gmbPrefix, opTag, ...payload]);
        expect(_bytesToHex(actual), expected);
      });
    }
  });

  group('冷钱包公开出签路径与链端一致', () {
    // 摘要原语对了,不代表 QrSigner 拼装对。这里走真实出签入口 signingBytesFor,
    // 端到端验证「冷钱包实际签的字节」== 链端金标。
    //
    // 可直接覆盖 OP_SIGN_CITIZEN_IDENTITY 与默认账户切换；另两个域
    // (cid_occupy / cid_admin_rebind)
    // 要求 payload 是结构化的 Authorization 模板并原位替换账户槽,真源向量的
    // 任意字节 payload 套不进该结构。这两个域的槽位与 op_tag 组装由
    // qr_signer_test.dart 覆盖,其摘要正确性已由上一组独立锁住。
    Map<String, dynamic>? vectorNamed(String name) {
      for (final vector in vectors) {
        if (vector['name'] == name) return vector;
      }
      return null;
    }

    test('OP_SIGN_CITIZEN_IDENTITY 走 signingBytesFor 产出链端金标摘要', () {
      final vector = vectorNamed('OP_SIGN_CITIZEN_IDENTITY');
      expect(vector, isNotNull, reason: '真源缺少 OP_SIGN_CITIZEN_IDENTITY 向量');

      final body = SignRequestBody.fromHex(
        action: QrActions.citizenIdentity,
        signerPublicKeyHex: _testSignerPublicKeyHex,
        payloadHex: '0x${vector!['scale_payload_hex']}',
      );

      final actual = QrSigner.signingBytesFor(body);

      expect(
        _bytesToHex(actual),
        (vector['message_hex'] as String).toLowerCase(),
      );
      // 顺带钉死「签的是摘要不是原文」——回归成透传即被抓住。
      expect(actual.toList(), isNot(body.payloadBytes.toList()));
    });

    test('OP_SIGN_SWITCH_DEFAULT_ACCOUNT 走 signingBytesFor 产出链端金标摘要', () {
      final vector = vectorNamed('OP_SIGN_SWITCH_DEFAULT_ACCOUNT');
      expect(
        vector,
        isNotNull,
        reason: '真源缺少 OP_SIGN_SWITCH_DEFAULT_ACCOUNT 向量',
      );
      final body = SignRequestBody.fromHex(
        action: QrActions.switchDefaultAccount,
        signerPublicKeyHex: _testSignerPublicKeyHex,
        payloadHex: '0x${vector!['scale_payload_hex']}',
      );

      final actual = QrSigner.signingBytesFor(body);

      expect(
        _bytesToHex(actual),
        (vector['message_hex'] as String).toLowerCase(),
      );
    });

    test('OP_SIGN_SQUARE_ACTION 走 signingBytesFor 产出链端金标摘要', () {
      final vector = vectorNamed('OP_SIGN_SQUARE_ACTION');
      expect(vector, isNotNull, reason: '真源缺少 OP_SIGN_SQUARE_ACTION 向量');
      final body = SignRequestBody.fromHex(
        action: QrActions.squareAccountAction,
        signerPublicKeyHex: _testSignerPublicKeyHex,
        payloadHex: '0x${vector!['scale_payload_hex']}',
      );

      final actual = QrSigner.signingBytesFor(body);

      expect(
        _bytesToHex(actual),
        (vector['message_hex'] as String).toLowerCase(),
      );
    });

    test('OP_SIGN_ACCOUNT_DATA_KEY_PROVISION 走 0x22 专用入口产出链端金标摘要', () {
      final vector = vectorNamed('OP_SIGN_ACCOUNT_DATA_KEY_PROVISION');
      expect(
        vector,
        isNotNull,
        reason: '真源缺少 OP_SIGN_ACCOUNT_DATA_KEY_PROVISION 向量',
      );
      final actual = accountDataKeyProvisionSigningMessage(
        _hexToBytes(vector!['scale_payload_hex'] as String),
      );
      expect(
        _bytesToHex(actual),
        (vector['message_hex'] as String).toLowerCase(),
      );
    });

    test('OP_SIGN_PUBLISH 走 signingBytesFor 产出链端金标摘要', () {
      final vector = vectorNamed('OP_SIGN_PUBLISH');
      expect(vector, isNotNull, reason: '真源缺少 OP_SIGN_PUBLISH 向量');
      final body = SignRequestBody.fromHex(
        action: QrActions.publish,
        signerPublicKeyHex: _testSignerPublicKeyHex,
        payloadHex: '0x${vector!['scale_payload_hex']}',
      );
      expect(
        _bytesToHex(QrSigner.signingBytesFor(body)),
        (vector['message_hex'] as String).toLowerCase(),
      );
    });

    test('冷钱包七个哈希域的 op_tag 均在真源登记', () {
      // 冷钱包私有常量 _opSignCitizenIdentity/_opSignCidOccupy/_opSignCidAdminRebind
      // 测试访问不到,改为断言真源侧登记值,任一端重排域编号都会在此暴露。
      expect(vectorNamed('OP_SIGN_CITIZEN_IDENTITY')?['op_tag'], '0x10');
      expect(vectorNamed('cid_occupy')?['op_tag'], '0x12');
      expect(vectorNamed('cid_admin_rebind')?['op_tag'], '0x1f');
      expect(vectorNamed('OP_SIGN_SWITCH_DEFAULT_ACCOUNT')?['op_tag'], '0x21');
      expect(vectorNamed('OP_SIGN_SQUARE_ACTION')?['op_tag'], '0x1d');
      expect(
        vectorNamed('OP_SIGN_ACCOUNT_DATA_KEY_PROVISION')?['op_tag'],
        '0x22',
      );
      expect(vectorNamed('OP_SIGN_PUBLISH')?['op_tag'], '0x24');
    });
  });
}
