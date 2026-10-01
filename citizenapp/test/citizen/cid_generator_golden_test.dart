// 人主体 CID 号客户端生成器金标测试(链端 ↔ Dart 逐字节对齐)。
//
// 金标 CN951-CTZN1-539598435-2026 直接抄自 citizenchain
// `runtime/primitives/cid/generator.rs::citizen_cid_number_golden`
// (model B dev //0 公钥,CTZN,2026);任何生成规则漂移都会在这里红。

import 'package:citizenapp/citizen/cid_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // model B dev //0 账户公钥(与链端 golden `public_key` 逐字节一致)。
  const accountId =
      '0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972';

  group('generateCitizenCid 金标 (硬门禁)', () {
    test('CTZN 2026 == 链端钉死金标 CN951-CTZN1-539598435-2026', () {
      final cid = generateCitizenCid(
        accountId: accountId,
        institution: 'CTZN',
        year: 2026,
      );
      expect(cid, 'CN951-CTZN1-539598435-2026');
    });

    test('CTZN 号形完整校验:CN 前缀 + R5 全数字 + N9 全数字 + 定长', () {
      final cid = generateCitizenCid(
        accountId: accountId,
        institution: 'CTZN',
        year: 2026,
      );
      // 总长 = R5(5)+'-'+seg2(5)+'-'+N9(9)+'-'+year(4) + 3 个连字符 = 26。
      expect(cid.length, 26);
      final segments = cid.split('-');
      expect(segments, hasLength(4));
      final r5 = segments[0];
      expect(r5.substring(0, 2), 'CN');
      expect(RegExp(r'^[0-9]{3}$').hasMatch(r5.substring(2, 5)), isTrue);
      expect(RegExp(r'^[0-9]{9}$').hasMatch(segments[2]), isTrue);
      expect(segments[3], '2026');
    });

    test('NATP 同账户同年:CN 前缀 + segment2 = NATP+digit + 号形回环', () {
      final cid = generateCitizenCid(
        accountId: accountId,
        institution: 'NATP',
        year: 2026,
      );
      expect(cid.startsWith('CN'), isTrue);
      final segments = cid.split('-');
      expect(segments, hasLength(4));
      // segment2 = 'NATP' + 单个 digit(Profit 策略 ⇒ M1 是数字)。
      expect(segments[1].substring(0, 4), 'NATP');
      expect(RegExp(r'^[0-9]$').hasMatch(segments[1].substring(4)), isTrue);
      // 整体格式 CN\d{3}-NATP\d-\d{9}-2026。
      expect(
        RegExp(r'^CN[0-9]{3}-NATP[0-9]-[0-9]{9}-2026$').hasMatch(cid),
        isTrue,
      );
    });

    test('非人主体机构码与非法年份被拒', () {
      expect(
        () => generateCitizenCid(
          accountId: accountId,
          institution: 'SFGF',
          year: 2026,
        ),
        throwsArgumentError,
      );
      expect(
        () => generateCitizenCid(
          accountId: accountId,
          institution: 'CTZN',
          year: 202,
        ),
        throwsArgumentError,
      );
    });
  });
}
