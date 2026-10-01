// 账户派生跨语言金标向量测试(ADR-024 Tier 2)。
//
// 金标 fixture 由 Rust 切片导出(canonical 真源
// citizenchain/runtime/primitives/tests/fixtures/account_derive_vectors.json
// 的副本),逐条断言 Dart 镜像派生 == account_id,防止 Dart 与链端漂移。
//
// fixture 用 GMB 域生成,本测试证明 Dart 派生地址与链端逐字节一致。
//
// fixture 缺席时(Rust 切片尚未落地)skip,不阻塞纯 Dart 测试。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';

const _fixturePath =
    'test/governance/shared/account_derive_vectors.json';

void main() {
  final file = File(_fixturePath);
  if (!file.existsSync()) {
    test('金标向量 fixture 尚未生成(Rust 切片落地后启用)', () {
      markTestSkipped('缺少 $_fixturePath —— 由 Rust golden 切片导出');
    }, skip: '缺少 $_fixturePath');
    return;
  }

  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final int ss58 = root['ss58_format'] as int;
  final vectors = (root['vectors'] as List).cast<Map<String, dynamic>>();

  group('账户派生金标向量(链端 ↔ Dart 逐字节对齐)', () {
    test('fixture 域常量与本端 _domain 一致', () {
      // 域已改名 GMB(ADR-024 Tier 3),fixture 与 _domain 同步为 GMB。
      expect(root['domain'], 'GMB');
      expect(ss58, kGmbSs58Prefix);
    });

    for (final v in vectors) {
      final kind = v['kind'] as String;
      final expectedHex = v['account_id'] as String;
      final label =
          v['account_name'] != null ? '$kind / ${v['account_name']}' : kind;

      test('$label → $expectedHex', () {
        final actual = _deriveForVector(v, ss58);
        expect(accountIdText(actual), expectedHex);
      });
    }
  });
}

Uint8List _deriveForVector(Map<String, dynamic> v, int ss58) {
  final kind = v['kind'] as String;
  switch (kind) {
    case 'InstitutionMain':
      return deriveInstitutionMainAccountId(
        v['cid_number'] as String,
        ss58Prefix: ss58,
      );
    case 'InstitutionFee':
      return deriveInstitutionFeeAccountId(
        v['cid_number'] as String,
        ss58Prefix: ss58,
      );
    case 'InstitutionStake':
      return deriveAccountId(
        opTag: kOpStake,
        payload: utf8.encode(v['cid_number'] as String),
        ss58Prefix: ss58,
      );
    case 'InstitutionSafetyFund':
      return deriveAccountId(
        opTag: kOpSafetyFund,
        payload: utf8.encode(v['cid_number'] as String),
        ss58Prefix: ss58,
      );
    case 'InstitutionHe':
      return deriveAccountId(
        opTag: kOpHe,
        payload: utf8.encode(v['cid_number'] as String),
        ss58Prefix: ss58,
      );
    case 'InstitutionClearing':
      return deriveInstitutionClearingAccountId(
        v['cid_number'] as String,
        ss58Prefix: ss58,
      );
    case 'InstitutionNamed':
      return deriveInstitutionCustomAccountId(
        v['cid_number'] as String,
        v['account_name'] as String,
        ss58Prefix: ss58,
      );
    case 'Personal':
      final creator = _hexToBytes(v['creator_account_id'] as String);
      return deriveAccountId(
        opTag: kOpPersonal,
        payload: <int>[...creator, ...utf8.encode(v['account_name'] as String)],
        ss58Prefix: ss58,
      );
    default:
      fail('未知金标向量 kind: $kind');
  }
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
