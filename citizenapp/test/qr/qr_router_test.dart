import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/qr/qr_router.dart';

/// App路由只处理SDK事实；原严格协议/坏码回归已移入SDK codec.rs直接验证真实解析器。
void main() {
  final router = QrRouter();
  for (final entry in <CitizenQrKind, QrRouteType>{
    CitizenQrKind.userContact: QrRouteType.userContact,
    CitizenQrKind.userTransfer: QrRouteType.userTransfer,
    CitizenQrKind.accountDataKeyResponse: QrRouteType.accountDataKeyResponse,
    CitizenQrKind.signRequest: QrRouteType.unknown,
    CitizenQrKind.signResponse: QrRouteType.unknown,
    CitizenQrKind.accountId: QrRouteType.unknown,
  }.entries) {
    test('SDK码型${entry.key}保持原页面路由${entry.value}', () {
      final document = CitizenQrDocument(
        kind: entry.key, canonicalText: 'sdk-canonical', scanPurposeMask: 0,
      );
      final result = router.route(raw: 'source-text', document: document);
      expect(result.type, entry.value);
      expect(result.raw, 'source-text');
      expect(result.document, entry.value == QrRouteType.unknown ? null : same(document));
    });
  }

  test('SDK没有给出有效文档时，任何原文都不触发App第二解析器', () {
    for (final raw in ['', 'hello world', 'gmb://account/removed',
      '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY',
      '{"p":"QR_V1","k":3,"b":{"c":"CID","n":"untrusted"}}']) {
      final result = router.route(raw: raw);
      expect(result.type, QrRouteType.unknown);
      expect(result.document, isNull);
    }
  });
}
