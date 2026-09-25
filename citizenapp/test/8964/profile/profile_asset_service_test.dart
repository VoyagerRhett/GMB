import '../../support/fake_citizen_sdk.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/profile/services/profile_asset_service.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';

// `_headers` 对带 session 的请求强制要求设备请求签名器（发布会员体系后新增硬校验）；
// 测试用固定假签名占位，MockClient 不校验签名头。
SquareSession _session() => SquareSession(
      sessionToken: 'tok',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId:
          '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      signRequest: (_) async => 'test-device-signature',
    );

void main() {
  TestCitizenSdkHarness();
  test('uploads bytes and returns the object key and hash', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final sha = sha256.convert(bytes).toString();
    Map<String, dynamic>? prepareBody;
    String? putAuth;
    List<int>? putBody;

    final client = SquareApiClient(
      baseUrl: 'https://example.com',
      httpClient: MockClient((request) async {
        if (request.url.path == '/square/profile/assets/prepare') {
          prepareBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'ok': true,
              'object_key': 'profile/acct/avatar',
              'content_hash': sha,
              'upload_url':
                  'https://example.com/square/profile/assets?object_key=profile%2Facct%2Favatar&byte_size=5&sha256=$sha',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        putAuth = request.headers['authorization'];
        putBody = request.bodyBytes;
        return http.Response(
          '{"ok":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await ProfileAssetService(client: client).upload(
      session: _session(),
      kind: 'avatar',
      bytes: bytes,
      contentType: 'image/webp',
    );

    expect(result.objectKey, 'profile/acct/avatar');
    expect(result.contentHash, sha);
    expect(prepareBody!['sha256'], sha);
    expect(prepareBody!['content_type'], 'image/webp');
    expect(prepareBody!['byte_size'], 5);
    expect(putBody, bytes);
    expect(putAuth, 'Bearer tok');
  });

  test('throws when the upload PUT fails', () async {
    final client = SquareApiClient(
      baseUrl: 'https://example.com',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/prepare')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'object_key': 'profile/a/avatar',
              'content_hash': 'x',
              'upload_url':
                  'https://example.com/square/profile/assets?object_key=profile%2Fa%2Favatar&byte_size=1&sha256=x',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('nope', 500);
      }),
    );

    await expectLater(
      ProfileAssetService(client: client).upload(
        session: _session(),
        kind: 'avatar',
        bytes: Uint8List.fromList([1]),
        contentType: 'image/webp',
      ),
      throwsA(isA<SquareApiException>()),
    );
  });
}
