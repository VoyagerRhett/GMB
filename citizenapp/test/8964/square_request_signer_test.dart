import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/notifications/app_push_token.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/services/square_request_signer.dart';

void main() {
  test('请求证明剥离同域 API 前缀并生成固定头', () async {
    Uint8List? signedMessage;
    final signature = '0x${List.filled(64, '11').join()}';
    final headers = await squareRequestHeaders(
      method: 'PUT',
      uri: Uri.parse('https://www.crcfrcn.com/api/square/push-endpoint'),
      body: '{}',
      sessionToken: 'session-token',
      requestTime: 1700000000000,
      nonce: '00112233445566778899aabbccddeeff',
      sign: (message) async {
        signedMessage = message;
        return signature;
      },
    );

    expect(signedMessage, isNotNull);
    expect(signedMessage, hasLength(32));
    expect(headers, {
      'x-device-time': '1700000000000',
      'x-device-nonce': '00112233445566778899aabbccddeeff',
      'x-device-signature': signature,
    });
  });

  test('普通应用推送端点使用当前会话设备证明和唯一最终路由登记', () async {
    late Map<String, dynamic> body;
    final before = DateTime.now().millisecondsSinceEpoch;
    final client = SquareApiClient(
      baseUrl: 'https://www.example.test/api',
      httpClient: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/square/push-endpoint');
        expect(request.headers['authorization'], 'Bearer session-a');
        expect(request.headers['x-device-signature'], 'request-signature');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'expires_at': body['expires_at'],
          }),
          200,
        );
      }),
    );
    await client.registerPushEndpoint(
      session: SquareSession(
        sessionToken: 'session-a',
        cidNumber: 'CN220-CTZN2-100000001-2026',
        bindingRevision: 1,
        accountId:
            '0x1111111111111111111111111111111111111111111111111111111111111111',
        expiresAt: 4102444800000,
        signRequest: (_) async => 'request-signature',
      ),
      endpoint: const AppPushToken(
        provider: 'fcm',
        token: 'fcm-token-1234567890',
        apnsEnvironment: null,
      ),
    );

    expect(body.keys.toSet(), {
      'push_provider',
      'push_token',
      'apns_environment',
      'expires_at',
    });
    expect(body['push_provider'], 'fcm');
    expect(body['push_token'], 'fcm-token-1234567890');
    expect(body['apns_environment'], isNull);
    expect(
      body['expires_at'],
      inInclusiveRange(
        before + const Duration(days: 90).inMilliseconds,
        DateTime.now().millisecondsSinceEpoch +
            const Duration(days: 90).inMilliseconds,
      ),
    );
  });
}
