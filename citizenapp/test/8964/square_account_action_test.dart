import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/signer/signing.dart';
import 'package:citizenapp/security/device_subkey.dart'
    show bytesToHex, hexToBytes;

const _accountId =
    '0x625e25364c7b68e0a83065ccb40afed43f8fe933e669b24f3d69a57eddb3b715';
const _payloadHex = '73712d616374696f6e';

/// Worker 登录响应按链上绑定下发身份主键 CID 号；缺失即会话不完整。
const _cidNumber = 'CN220-CTZN2-198805200-2026';

void main() {
  test('deleteAccount 钉死 op_tag 0x1D，走 challenge→sign→confirm', () async {
    Uint8List? signedMessage;
    Map<String, dynamic>? confirmBody;

    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/square/auth/challenge') {
          expect(jsonDecode(request.body)['account_id'], _accountId);
          return http.Response(
            jsonEncode({
              'ok': true,
              'challenge_id': 'sql_1',
              'cid_number': _cidNumber,
              'binding_revision': 1,
              'account_id': _accountId,
              'signing_payload_hex': _payloadHex,
            }),
            200,
          );
        }
        if (request.url.path == '/square/auth/session') {
          expect(jsonDecode(request.body)['account_id'], _accountId);
          return http.Response(
            jsonEncode({
              'ok': true,
              'session_token': 'sqs_test',
              'cid_number': _cidNumber,
              'binding_revision': 1,
              'expires_at': 4102444800000,
            }),
            200,
          );
        }
        if (request.url.path == '/square/account/delete/challenge') {
          expect(request.headers['authorization'], 'Bearer sqs_test');
          expect(jsonDecode(request.body)['account_id'], _accountId);
          return http.Response(
            jsonEncode({
              'ok': true,
              'challenge_id': 'sqa_1',
              'op_tag': 0x99, // 服务端乱下发 op_tag，客户端必须无视
              'signing_payload_hex': _payloadHex,
              'expires_at': 1800000000000,
            }),
            200,
          );
        }
        if (request.url.path == '/square/account/delete') {
          expect(request.headers['authorization'], 'Bearer sqs_test');
          confirmBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('not found', 404);
      }),
    );

    await client.ensureSession(
      accountId: _accountId,
      signLoginPayload: (_, __) async => '0xLOGIN',
    );
    await client.deleteAccount(
      accountId: _accountId,
      signAction: (message) async {
        signedMessage = message;
        return '0xSIG';
      },
    );

    // 客户端钉死 kOpSignSquareAction(0x1D)，绝不采用服务端下发的 0x99。
    expect(
      bytesToHex(signedMessage!),
      bytesToHex(
        signingMessage(
          opTag: kOpSignSquareAction,
          scalePayload: hexToBytes(_payloadHex),
        ),
      ),
    );
    expect(confirmBody, {
      'account_id': _accountId,
      'challenge_id': 'sqa_1',
      'signature': '0xSIG',
    });
  });

  test('challenge 响应缺 signing_payload_hex → SquareApiException', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient(
        (request) async {
          if (request.url.path == '/square/auth/challenge') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'challenge_id': 'sql_2',
                'cid_number': _cidNumber,
                'binding_revision': 1,
                'account_id': _accountId,
                'signing_payload_hex': _payloadHex,
              }),
              200,
            );
          }
          if (request.url.path == '/square/auth/session') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'session_token': 'sqs_test',
                'cid_number': _cidNumber,
                'binding_revision': 1,
                'expires_at': 4102444800000,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'ok': true, 'challenge_id': 'x'}),
            200,
          );
        },
      ),
    );

    await client.ensureSession(
      accountId: _accountId,
      signLoginPayload: (_, __) async => '0xLOGIN',
    );
    await expectLater(
      client.deleteAccount(
        accountId: _accountId,
        signAction: (_) async => '0x',
      ),
      throwsA(isA<SquareApiException>()),
    );
  });

  test('finalized 换绑立即清除旧会话，并拒绝换绑后才返回的旧握手', () async {
    const newAccountId =
        '0x2222222222222222222222222222222222222222222222222222222222222222';
    SquareApiClient.activateFinalizedBinding(
      cidNumber: _cidNumber,
      bindingRevision: 1,
      accountId: _accountId,
    );
    final cachedClient = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/square/auth/challenge') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'challenge_id': 'cached',
              'cid_number': _cidNumber,
              'binding_revision': 1,
              'account_id': _accountId,
              'signing_payload_hex': _payloadHex,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'session_token': 'cached-token',
            'cid_number': _cidNumber,
            'binding_revision': 1,
            'expires_at': 4102444800000,
          }),
          200,
        );
      }),
    );
    await cachedClient.ensureSession(
      accountId: _accountId,
      signLoginPayload: (_, __) async => '0xLOGIN',
    );

    final sessionRequested = Completer<void>();
    final sessionResponse = Completer<http.Response>();
    final lateClient = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/square/auth/challenge') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'challenge_id': 'late',
              'cid_number': _cidNumber,
              'binding_revision': 1,
              'account_id': _accountId,
              'signing_payload_hex': _payloadHex,
            }),
            200,
          );
        }
        sessionRequested.complete();
        return sessionResponse.future;
      }),
    );
    final late = lateClient.ensureSession(
      accountId: _accountId,
      signLoginPayload: (_, __) async => '0xLOGIN',
    );
    await sessionRequested.future;

    SquareApiClient.activateFinalizedBinding(
      cidNumber: _cidNumber,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    sessionResponse.complete(http.Response(
      jsonEncode({
        'ok': true,
        'session_token': 'late-token',
        'cid_number': _cidNumber,
        'binding_revision': 1,
        'expires_at': 4102444800000,
      }),
      200,
    ));

    await expectLater(
      cachedClient.deleteAccount(
        accountId: _accountId,
        signAction: (_) async => '0xSIG',
      ),
      throwsA(isA<SquareApiException>()),
    );
    await expectLater(late, throwsA(isA<SquareApiException>()));
  });
}
