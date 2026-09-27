// 登录 QR 解析单测:重点覆盖新增的请求 id 校验(M1:防 `|` 注入污染待签消息)。
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/login/login_qr_handler.dart';

String _loginRaw(String id, {int? expiresAt}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return QrEnvelope<SignRequestBody>(
    kind: QrKind.signRequest,
    id: id,
    expiresAt: expiresAt ?? now + 60,
    body: SignRequestBody.fromHex(
      action: QrActions.login,
      signerPublicKeyHex: '0x${'ab' * 32}',
      payloadHex: '0x6f6e6368696e61', // 'onchina'
    ),
  ).toRawJson();
}

void main() {
  group('parseLoginSignRequest 请求 id 校验', () {
    test('合法 id 通过并回传', () {
      final env = parseLoginSignRequest(_loginRaw('offline-req-test-0001'));
      expect(env.id, 'offline-req-test-0001');
      expect(env.body.action, QrActions.login);
    });

    test('id 含非法字符(竖线)被拒', () {
      expect(
        () => parseLoginSignRequest(_loginRaw('abcdef|1234567890ab')),
        throwsA(isA<LoginQrException>()),
      );
    });

    test('id 过短被拒(< 16)', () {
      expect(
        () => parseLoginSignRequest(_loginRaw('short')),
        throwsA(isA<LoginQrException>()),
      );
    });

    test('拒绝远未来期限，避免永久保留已签请求', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        () => parseLoginSignRequest(
          _loginRaw(
            'offline-req-test-0002',
            expiresAt: now + maxQrRequestLifetimeSeconds + 1,
          ),
        ),
        throwsA(isA<LoginQrException>()),
      );
    });
  });
}
