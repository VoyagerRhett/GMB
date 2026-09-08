import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';

import 'package:citizenwallet/signer/payload_decoder.dart';

// SCALE **解码**金标锁(citizenwallet ⇔ citizenchain)。
//
// 本文件**直接读真源**,不保存镜像副本(与 Worker / citizenapp 同策略)。
//
// 为什么解码方向必须单独锁:编码错会签出链端不认的交易,当场失败;
// 解码错则是**冷钱包给用户展示的交易内容与实际要签的不符**——用户在错误信息下
// 按下签名。后者危险一个量级,而 citizenwallet 正是唯一的出签设备。
//
// 关键设计:payload 的长度前缀字节**直接取自真源 hex**(parity-scale-codec 生成),
// 本文件不做任何 compact 编码。这样测的是「解码器能否正确解析链端真值」,
// 而不是「解码器与本测试的编码实现是否自洽」。
//
// 真源:citizenchain/runtime/primitives/tests/fixtures/scale_codec_vectors.json
// 生成器:citizenchain/runtime/primitives/tests/scale_codec_golden.rs

const String _vectorsPath =
    'test/signer/fixtures/scale_codec_vectors.json';

/// transfer_with_remark 的 pallet/call 索引(与 payload_decoder_test.dart 同源)。
const List<int> _transferCallPrefix = [0x04, 0x00];

Uint8List _hexToBytes(String hex) {
  final clean = hex.toLowerCase().replaceFirst('0x', '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i += 1) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hexOf(List<int> payload) =>
    '0x${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

List<int> _u128Le(BigInt value) {
  final out = List<int>.filled(16, 0);
  var tmp = value;
  for (var i = 0; i < 16; i++) {
    out[i] = (tmp & BigInt.from(0xFF)).toInt();
    tmp = tmp >> 8;
  }
  return out;
}

/// compact 编码,仅供**构造非法输入**用(fail-closed 用例)。
/// 合法路径一律直接使用真源 hex,不经过本函数。
List<int> _compactU32(int value) {
  if (value < 64) return [value << 2];
  if (value < 16384) {
    final v = (value << 2) | 1;
    return [v & 0xff, (v >> 8) & 0xff];
  }
  final v = (value << 2) | 2;
  return [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
}

void main() {
  final tailGenesis = List<int>.generate(32, (i) => 0x49 ^ i);
  List<int> signingTail() => [
        0x00,
        ..._compactU32(1), // nonce
        ..._compactU32(0), // tip
        0x00,
        1, 0, 0, 0, // spec_version u32 LE
        1, 0, 0, 0, // tx_version u32 LE
        ...tailGenesis,
        ...tailGenesis,
        0x00,
      ];

  final dest = Keyring.sr25519.fromSeed(Uint8List(32));
  dest.ss58Format = 2027;
  // polkadart_keyring 0.7.1 的 bytes() 返回类型没有保留元素泛型；在测试边界
  // 明确收敛为字节列表，避免非法载荷夹具被推断成 List<dynamic>。
  final List<int> destBytes = dest.bytes().cast<int>();

  /// 用**给定的原始 remark 段字节**拼一笔完整的 transfer payload。
  /// remarkSegment 应为 `compact(len) ++ utf8`,合法路径下直接来自真源 hex。
  String buildTransfer(List<int> remarkSegment) => _hexOf([
        ..._transferCallPrefix,
        ...destBytes,
        ..._u128Le(BigInt.from(23400)),
        ...remarkSegment,
        ...signingTail(),
      ]);

  final file = File(_vectorsPath);
  final canonical = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final stringVectors =
      (canonical['scale_string'] as List).cast<Map<String, dynamic>>();

  group('SCALE 解码与链端编码一致(直读 citizenchain 真源)', () {
    test('真源向量可读且非空', () {
      // 读成空数组时下面的循环一条用例都不生成而整体显示通过,这条挡住金标静默失效。
      expect(file.existsSync(), isTrue,
          reason: '真源不可达,cwd=${Directory.current.path}');
      expect(stringVectors, isNotEmpty);
    });

    for (final vector in stringVectors) {
      final value = vector['value'] as String;
      final utf8Len = vector['utf8_len'] as int;
      final label = value.length > 20 ? '${value.substring(0, 20)}…' : value;

      test('解码链端编码的 remark(${jsonEncode(label)},$utf8Len 字节)', () {
        // 长度前缀 + 内容整段来自真源,本测试不做任何 compact 编码。
        final decoded = PayloadDecoder.decode(
            buildTransfer(_hexToBytes(vector['hex'] as String)));

        expect(decoded, isNotNull, reason: '解码器拒绝了链端合法编码');
        expect(decoded!.action, 'transfer');
        // remark 出现在 summary 的「，备注：」之后;空串时不带该后缀。
        if (value.isEmpty) {
          expect(decoded.summary.contains('备注'), isFalse,
              reason: '空 remark 不应产生备注后缀');
        } else {
          expect(decoded.summary.contains(value), isTrue,
              reason: '解出的 remark 与链端原文不一致(长度前缀解析错误?)');
        }
      });
    }
  });

  group('解码器 fail-closed 边界', () {
    // 真源向量只覆盖合法编码。非法长度前缀必须整笔拒绝,不得截断出一段"看起来正常"
    // 的 remark —— 那会让用户看到与实际签名内容不符的交易摘要。
    test('声明长度超过剩余字节时整笔拒绝', () {
      // 声明 200 字节但只给 4 字节内容。
      final bogus = [..._compactU32(200), 0x61, 0x62, 0x63, 0x64];
      expect(PayloadDecoder.decode(buildTransfer(bogus)), isNull);
    });

    test('两字节档前缀被截断时整笔拒绝', () {
      // 64 字节档的前缀是 2 字节(0x01 0x01),这里只给第一个字节后即结束 remark 段。
      final truncated = [0x01];
      expect(PayloadDecoder.decode(buildTransfer(truncated)), isNull);
    });

    test('声明长度 0 但尾部不是合法签名尾时拒绝', () {
      // remark 段声明 0 字节,随后塞入非签名尾的垃圾字节。
      final badTail = [
        ..._transferCallPrefix,
        ...destBytes,
        ..._u128Le(BigInt.from(23400)),
        ..._compactU32(0),
        0xde,
        0xad,
        0xbe,
        0xef,
      ];
      expect(PayloadDecoder.decode(_hexOf(badTail)), isNull);
    });
  });
}
