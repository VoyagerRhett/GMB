import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/qr/bodies/sign_request_body.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/qr/qr_router.dart';

void main() {
  late QrRouter router;

  setUp(() {
    router = QrRouter();
  });

  group('QrRouter QR_V1', () {
    test('通用 sign_request 不进入 CitizenApp 业务路由', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.signRequest.code,
        'i': 'ch-0123456789abcdef',
        'e': 1090,
        'b': SignRequestBody.fromHex(
          action: QrActions.login,
          signerPublicKeyHex:
              '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          payloadHex: '0x6369647c736967',
        ).toJson(),
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
      expect(result.envelope, isNull);
    });

    test('should route user_transfer', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.userTransfer.code,
        'i': 'tx-0123456789abcdef',
        'e': 1600,
        'b': {
          'n':
              '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
          'v': '100.50',
          't': 'GMB',
          'm': '房租',
          'l': 'CN001-SFGF-000000001-2026',
        },
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.userTransfer);
    });

    test('should route user_contact fixed code', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.userContact.code,
        'b': {
          'c': 'CN001-CTZN-000000001-2026',
          'n':
              '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
        },
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.userContact);
    });

    test('旧长键用户码、昵称字段与未知字段一律拒绝', () {
      // 单字母统一前的旧码(长键 + display_name/ss58_address)必须整体作废。
      final legacy = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.userContact.code,
        'b': {
          'cid_number': 'CN001-CTZN-000000001-2026',
          'ss58_address': 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT',
          'display_name': '张三',
        },
      });
      // 昵称一律不得进码:本机可篡改,进码即冒名风险。
      final withName = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.userContact.code,
        'b': {
          'c': 'CN001-CTZN-000000001-2026',
          'n':
              '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
          'display_name': '张三',
        },
      });
      final extra = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.userContact.code,
        'b': {
          'c': 'CN001-CTZN-000000001-2026',
          'n':
              '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
          'x': '别名',
        },
      });

      expect(router.route(legacy).type, QrRouteType.unknown);
      expect(router.route(withName).type, QrRouteType.unknown);
      expect(router.route(extra).type, QrRouteType.unknown);
    });

    test('链交易 sign_request 不进入 CitizenApp 业务路由', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.signRequest.code,
        'i': 'req-0123456789abcdef',
        'e': 1090,
        'b': SignRequestBody.fromHex(
          action: QrActions.transferWithRemark,
          signerPublicKeyHex:
              '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          payloadHex: '0xccdd',
        ).toJson(),
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
    });

    test('should reject removed account scheme', () {
      const raw =
          'gmb://account/5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
    });

    test('should reject bare SS58 QR payload', () {
      const raw = '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
    });

    test('should return unknown for unrecognized content', () {
      final result = router.route('hello world');
      expect(result.type, QrRouteType.unknown);
    });

    test('should return unknown for empty string', () {
      final result = router.route('');
      expect(result.type, QrRouteType.unknown);
    });

    test('should return unknown for JSON with unknown proto', () {
      final raw = jsonEncode({'p': 'UNKNOWN_PROTO', 'foo': 'bar'});
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
    });

    test('通用账户码不进入 CitizenApp 业务路由', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.accountIdCode.code,
        'b': {
          'n':
              '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
        },
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
      expect(result.envelope, isNull);
    });

    test('should reject legacy chat_node_pairing payload on k=5', () {
      // k=5 已回收给账户码；旧 chat_node_pairing 载荷靠 body 字段集精确匹配拒绝，
      // 不需要专门的拒绝分支。
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': 5,
        'b': {
          'node_peer_id': '12D3Koo',
          'node_multiaddr': '/ip4/1.2.3.4/tcp/30333',
          'endpoint_kind': 'ip4',
        },
      });
      final result = router.route(raw);
      expect(result.type, QrRouteType.unknown);
    });
  });

  _auditHardeningRegressions();
}

/// 2026-08-06 审计整改的回归锁:每一条都对应一个已确证的跨端分歧或缺失闸门,
/// 放松任何一条都会让「同一张码此端过、彼端拒」重新出现。
void _auditHardeningRegressions() {
  const accountId =
      '0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48';
  final router = QrRouter();

  group('审计整改回归', () {
    test('k 必须是整数:字符串/带符号/带前缀写法一律拒绝', () {
      // 曾用 int.tryParse 兜底,"5"/" 5"/"+5"/"0x5" 全被当合法 k,而冷端与 Rust 只收整数。
      for (final bad in <Object>['5', ' 5', '+5', '0x5', 5.0, true]) {
        final raw = jsonEncode({
          'p': QrProtocol.qrV1,
          'k': bad,
          'b': {'n': accountId},
        });
        expect(
          router.route(raw).type,
          QrRouteType.unknown,
          reason: 'k=$bad 必须被拒绝',
        );
      }
    });

    test('k=1 签名请求:body 多一个未知字段即拒', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.signRequest.code,
        'i': 'req_0123456789abcdef',
        'e': 4102444800,
        'b': {
          'a': 1024,
          'g': 1,
          'u': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          'd': 'AQID',
          'display': '伪造展示字段',
        },
      });
      expect(router.route(raw).type, QrRouteType.unknown);
    });

    test('k=2 签名响应:o/r 只出现一个即拒', () {
      final raw = jsonEncode({
        'p': QrProtocol.qrV1,
        'k': QrKind.signResponse.code,
        'i': 'req_0123456789abcdef',
        'e': 4102444800,
        'b': {
          'u': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          's': 'A' * 86,
          'o': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        },
      });
      expect(router.route(raw).type, QrRouteType.unknown);
    });

    test('base64url 严格:带填充与标准字母表 +/ 一律拒绝', () {
      for (final bad in ['++++', 'AA==', 'A/A']) {
        final raw = jsonEncode({
          'p': QrProtocol.qrV1,
          'k': QrKind.signRequest.code,
          'i': 'req_0123456789abcdef',
          'e': 4102444800,
          'b': {'a': 1024, 'g': 1, 'u': bad, 'd': 'AQID'},
        });
        expect(
          router.route(raw).type,
          QrRouteType.unknown,
          reason: 'u=$bad 必须被拒绝(Rust 侧 URL_SAFE_NO_PAD 也拒)',
        );
      }
    });

    test('用户码 CID 字符集白名单:零宽字符必须被拒', () {
      // "​CN...​".trim() 与原串完全相同 —— 只查 trim 挡不住零宽字符。
      for (final badCid in ['​CN001-CTZN-000000001-2026', '​​']) {
        final raw = jsonEncode({
          'p': QrProtocol.qrV1,
          'k': QrKind.userContact.code,
          'b': {'c': badCid, 'n': accountId},
        });
        expect(
          router.route(raw).type,
          QrRouteType.unknown,
          reason: '含零宽字符的 CID 必须被拒绝',
        );
      }
    });

    test('账户码 n 必须是规范小写 0x+64hex', () {
      for (final bad in <String>[
        '0X8EAF04151687736326C9FEA17E25FC5287613693C912909CB226AA4794F26A48',
        '8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48',
        '0x8eaf',
      ]) {
        final raw = jsonEncode({
          'p': QrProtocol.qrV1,
          'k': QrKind.accountIdCode.code,
          'b': {'n': bad},
        });
        expect(router.route(raw).type, QrRouteType.unknown, reason: 'n=$bad');
      }
    });
  });
}
