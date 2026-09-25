import '../support/fake_citizen_sdk.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/services/square_api_client.dart';

const _accountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _cidNumber = 'CN220-CTZN2-100000001-2026';

/// 会话自愈:登录完成阶段的两类 401(库无行 / 库有行但都不是本机钥)都必须
/// 触发一次本机子钥登记并重试;其余错误原样上抛、绝不登记。
///
/// `invalid_signature` 纳入自愈是修一个真实死锁:换新手机/重装/钱包重建后
/// walletIndex 换新 → 硬件 P-256 子钥换新 → 库里该身份行存在(挑战能发)但
/// 钥不配(完成必败),而登记只在 device_not_registered 触发 → 永久锁死广场。
MockClient _worker({
  required List<String> completeErrorCodes,
  required List<String> requestLog,
}) {
  var completeCalls = 0;
  return MockClient((request) async {
    requestLog.add(request.url.path);
    if (request.url.path == '/square/auth/challenge') {
      return http.Response(
        jsonEncode({
          'signing_payload_hex': '0x00',
          'challenge_id': 'c$completeCalls',
          'cid_number': _cidNumber,
          'binding_revision': 1,
          'account_id': _accountId,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/square/auth/session') {
      if (completeCalls < completeErrorCodes.length) {
        final code = completeErrorCodes[completeCalls++];
        return http.Response(
          jsonEncode({'error_code': code, 'message': '拒绝'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      completeCalls++;
      return http.Response(
        jsonEncode({
          'session_token': 'tok',
          'expires_at': 4102444800000,
          'cid_number': _cidNumber,
          'binding_revision': 1,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

Future<String> _sign(
  SquareLoginContext context,
  List<int> message,
) async =>
    '0x${'11' * 64}';

void main() {
  TestCitizenSdkHarness();
  test('invalid_signature(本机钥不在库中) → 登记一次本机子钥并重试成功', () async {
    final requestLog = <String>[];
    final client = SquareApiClient(
      baseUrl: 'https://worker.test',
      httpClient: _worker(
        completeErrorCodes: ['invalid_signature'],
        requestLog: requestLog,
      ),
    );
    var registerCalls = 0;
    final session = await client.ensureSession(
      accountId: _accountId,
      signLoginPayload: _sign,
      onDeviceNotRegistered: (_) async => registerCalls++,
    );
    expect(registerCalls, 1);
    expect(session.sessionToken, 'tok');
  });

  test('device_not_registered(库无行) → 原有自愈路径不回归', () async {
    final requestLog = <String>[];
    final client = SquareApiClient(
      baseUrl: 'https://worker.test',
      httpClient: _worker(
        completeErrorCodes: ['device_not_registered'],
        requestLog: requestLog,
      ),
    );
    var registerCalls = 0;
    final session = await client.ensureSession(
      accountId: _accountId,
      signLoginPayload: _sign,
      onDeviceNotRegistered: (_) async => registerCalls++,
    );
    expect(registerCalls, 1);
    expect(session.sessionToken, 'tok');
  });

  test('其它错误码(如 cid_not_bound) → 原样上抛,绝不触发登记', () async {
    final requestLog = <String>[];
    final client = SquareApiClient(
      baseUrl: 'https://worker.test',
      httpClient: _worker(
        completeErrorCodes: ['cid_not_bound', 'cid_not_bound'],
        requestLog: requestLog,
      ),
    );
    var registerCalls = 0;
    await expectLater(
      client.ensureSession(
        accountId: _accountId,
        signLoginPayload: _sign,
        onDeviceNotRegistered: (_) async => registerCalls++,
      ),
      throwsA(isA<SquareApiException>()
          .having((e) => e.errorCode, 'errorCode', 'cid_not_bound')),
    );
    expect(registerCalls, 0);
  });

  test('自愈只重试一次:登记后仍失败 → 上抛,不无限循环', () async {
    final requestLog = <String>[];
    final client = SquareApiClient(
      baseUrl: 'https://worker.test',
      httpClient: _worker(
        completeErrorCodes: ['invalid_signature', 'invalid_signature'],
        requestLog: requestLog,
      ),
    );
    var registerCalls = 0;
    await expectLater(
      client.ensureSession(
        accountId: _accountId,
        signLoginPayload: _sign,
        onDeviceNotRegistered: (_) async => registerCalls++,
      ),
      throwsA(isA<SquareApiException>()
          .having((e) => e.errorCode, 'errorCode', 'invalid_signature')),
    );
    expect(registerCalls, 1);
    expect(
      requestLog.where((p) => p == '/square/auth/session').length,
      2,
    );
  });
}
