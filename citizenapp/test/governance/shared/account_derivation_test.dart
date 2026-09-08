// account_derivation 统一派生原语单测(ADR-018 §九,公权机构卡0)。
//
// golden 向量取自链端权威源(勿手算、勿照抄本端计算结果):
//   - 主/费账户:citizenchain/runtime/primitives/cid/china/china_cb.rs 的
//     main_account / fee_account 字面常量
//   - 安全基金/两和基金:金标 fixture tests/fixtures/account_derive_vectors.json
//     (由 Rust ACCOUNT_DERIVE_UPDATE=1 回填,重生走 citizenchain/scripts/sync-derive-vectors.sh)
// 用以交叉验证本端派生与 citizenchain primitives 字节对齐:
//   preimage = b"GMB" || op_tag || ss58.to_le_bytes() || payload
//   OP_MAIN(0x01)/OP_FEE(0x02)/OP_SAFETY(0x04)/OP_HE(0x05): payload = cid_number
//   OP_CLEARING(0x07): payload = cid_number
//   OP_FCSF(0x08): payload = 联邦安全局 cid_number
//   OP_NAME(0x00,永久冻结): payload = cid_number || account_name

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/reserved_account_names.dart';

void main() {
  // 国家储委会 LN001-NRC0G-944805165-2026（T3/T4 新机构码 + GMB 域，单源 china_cb.rs）
  const nrcCid = 'LN001-NRC0G-944805165-2026';
  const nrcMain =
      '0x7c0c099ee4df10c5bd3f618ddf132b6d15390fa27d2c1369f70aeb6b5f3907e5';
  const nrcFee =
      '0xfabe3c11d600221ab4156ebaae3c00c8efae939442f4cd1a764cfdf62461a387';
  const nrcSafety =
      '0x4ac779852c175087c445c35efecfef3ce6e0232702152ea2283f0b5ec3952e53';
  const nrcHe =
      '0xda5544a52e806f6e5daeba3e2f0be134b218a9c348f2804b7e933deb9ed84e86';
  // 中枢省 ZS001-PRC0E-016974075-2026（T3/T4 新机构码 + GMB 域，单源 china_cb.rs）
  const prcCid = 'ZS001-PRC0E-016974075-2026';
  const prcMain =
      '0x54bad80b12cedbf7a1569fb96d18d90c4793949a356eb16c6304841af81001dd';
  const prcFee =
      '0x1f88202bf56fad5c7acfb08bc95322bb0149f8561cdb1f10a9331d46067b353a';
  // 联邦安全局与正式创世 FCSF 账户（链上 finalized 余额账户）。
  const fscCid = 'ZS001-FSC0W-434172688-2026';
  const fcsfAccountId =
      '0xc0e4ce3c11401ad661ae139081bbc797db51d0efe71df3ffb107f3dcb0064802';

  group('机构账户派生 golden 向量(链上注册表交叉验证)', () {
    test('国家储委会主账户 OP_MAIN', () {
      expect(accountIdText(deriveInstitutionMainAccountId(nrcCid)), nrcMain);
    });

    test('国家储委会费用账户 OP_FEE', () {
      expect(accountIdText(deriveInstitutionFeeAccountId(nrcCid)), nrcFee);
    });

    test('中枢省主账户 / 费用账户', () {
      expect(accountIdText(deriveInstitutionMainAccountId(prcCid)), prcMain);
      expect(accountIdText(deriveInstitutionFeeAccountId(prcCid)), prcFee);
    });

    test('名字路由:主账户/费用账户与显式派生一致', () {
      expect(
        accountIdText(
          deriveInstitutionAccountIdByName(nrcCid, kReservedNameMain),
        ),
        nrcMain,
      );
      expect(
        accountIdText(
          deriveInstitutionAccountIdByName(nrcCid, kReservedNameFee),
        ),
        nrcFee,
      );
    });

    test('名字路由:安全基金 OP_SAFETY / 两和基金 OP_HE', () {
      expect(
        accountIdText(
          deriveInstitutionAccountIdByName(nrcCid, kReservedNameSafetyFund),
        ),
        nrcSafety,
      );
      expect(
        accountIdText(
          deriveInstitutionAccountIdByName(nrcCid, kReservedNameHe),
        ),
        nrcHe,
      );
    });

    test('名字路由:联邦公民安全基金 OP_FCSF', () {
      expect(
        accountIdText(
          deriveInstitutionAccountIdByName(fscCid, kReservedNameFcsf),
        ),
        fcsfAccountId,
      );
      expect(kReservedAccountNames, contains(kReservedNameFcsf));
      expect(isForbiddenAccountName(kReservedNameFcsf), isTrue);
    });
  });

  group('自定义账户 OP_NAME(0x00)', () {
    test('payload 追加 account_name,与手工构造一致', () {
      const name = '业务专户A';
      final expected = Hasher.blake2b256.hash(
        Uint8List.fromList(<int>[
          ...utf8.encode('GMB'),
          0x00,
          2027 & 0xFF,
          (2027 >> 8) & 0xFF,
          ...utf8.encode(nrcCid),
          ...utf8.encode(name),
        ]),
      );
      expect(
        accountIdText(deriveInstitutionCustomAccountId(nrcCid, name)),
        accountIdText(expected),
      );
    });

    test('自定义账户不同于主账户', () {
      expect(
        accountIdText(deriveInstitutionCustomAccountId(nrcCid, '专户')),
        isNot(accountIdText(deriveInstitutionMainAccountId(nrcCid))),
      );
    });

    test('空账户名抛错(对齐链端 EmptyAccountName)', () {
      expect(
        () => deriveInstitutionCustomAccountId(nrcCid, ''),
        throwsArgumentError,
      );
    });

    test('自定义名命中受限保留名抛错', () {
      expect(
        () => deriveInstitutionCustomAccountId(nrcCid, kReservedNameMain),
        throwsArgumentError,
      );
      expect(
        () => deriveInstitutionCustomAccountId(fscCid, kReservedNameFcsf),
        throwsArgumentError,
      );
    });
  });

  group('个人多签派生(OP_PERSONAL 0x06)归位后行为不变', () {
    test('SS58 输出与 core 派生一致', () {
      final creator = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final viaCore = ss58FromAccountId(
        deriveAccountId(
          opTag: kOpPersonal,
          payload: <int>[...creator, ...utf8.encode('个人钱包')],
        ),
      );
      expect(
        derivePersonalAccountSs58(
          creatorAccountId: creator,
          accountName: '个人钱包',
        ),
        viaCore,
      );
    });

    test('creator 非 32 字节抛错', () {
      expect(
        () => derivePersonalAccountSs58(
          creatorAccountId: Uint8List(31),
          accountName: 'x',
        ),
        throwsArgumentError,
      );
    });
  });
}
