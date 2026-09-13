import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/services/device_subkey_registrar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/device_subkey.dart';
import 'package:citizenapp/security/account_security_service.dart';

/// 只覆写 publicKeyHex（返回**裸**公钥），其余走原生桥（本测试不触发）。
class _FakeDeviceSubkey extends DeviceSubkey {
  _FakeDeviceSubkey(this._pub);
  final String _pub;
  @override
  Future<String> publicKeyHex(String cidNumber) async => _pub;

  @override
  Future<String> signRawHex(String cidNumber, Uint8List payload) async =>
      'aa' * 64;
}

const _accountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _binding = AccountDataBinding(
  genesisHash:
      '0xabababababababababababababababababababababababababababababababab',
  cidNumber: 'CN220-CTZN2-198805200-2026',
  bindingRevision: 1,
  accountId: _accountId,
);

class _SessionApi extends SquareApiClient {
  _SessionApi({required this.deviceMissing});

  final bool deviceMissing;

  @override
  Future<SquareSession> ensureSession({
    required String accountId,
    required SquareLoginSigner signLoginPayload,
    SquareMissingDeviceHandler? onDeviceNotRegistered,
  }) async {
    final context = SquareLoginContext(
      cidNumber: _binding.cidNumber,
      bindingRevision: _binding.bindingRevision,
      accountId: accountId,
    );
    await signLoginPayload(context, Uint8List(32));
    if (deviceMissing) await onDeviceNotRegistered!(context);
    return SquareSession(
      sessionToken: 'session',
      cidNumber: _binding.cidNumber,
      bindingRevision: _binding.bindingRevision,
      accountId: accountId,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      signRequest: (message) => signLoginPayload(context, message),
    );
  }
}

class _SessionWalletManager implements AccountSecurityService {
  int registrationCalls = 0;

  @override
  Future<AccountDataBinding> accountDataBindingForAccountId(
    String accountId,
  ) async =>
      _binding;

  @override
  Future<AccountDataBinding?> readAccountDataBindingForAccountId(
    String accountId,
  ) async =>
      _binding;

  @override
  Future<void> activateAccountDataBinding({
    required String genesisHash,
    required String cidNumber,
    required int bindingRevision,
    required String accountId,
  }) async {}

  @override
  Future<void> registerDeviceSubkeyForBinding(
    AccountDataBinding binding,
  ) async {
    registrationCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async => CurrentUser(
        account: CitizenWalletStateAccount(
          signMode: CitizenWalletSignMode.hot,
          walletIndex: 7,
          accountIndex: 0,
          accountId: _accountId,
          ss58Address: 'ss58',
          name: '测试账户',
          createdAtMillis: BigInt.one,
          isDefault: true,
        ),
        binding: _binding,
      );

  @override
  void invalidate() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('注册 wire 的 p256_public_key 带 0x 前缀（ADR-041），公钥本身裸', () async {
    // 65 字节未压缩点裸 hex（04 || 128 hex）。
    final barePub = '04${'a' * 128}';
    const accountId =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    Map<String, dynamic>? registerBody;

    final api = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/square/auth/device/register') {
          registerBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('not found', 404);
      }),
    );

    final registrar = DeviceSubkeyRegistrar(
      deviceSubkey: _FakeDeviceSubkey(barePub),
      apiClient: api,
      turnstileToken: () async => 'turnstile-device-bind-token',
    );

    await registrar.register(
      cidNumber: 'CN220-CTZN2-198805200-2026',
      bindingRevision: 1,
      accountId: accountId,
      signBinding: ({
        required payload,
        required signingMessage,
        required devicePublicKey,
        required issuedAtMillis,
      }) async =>
          '0xBINDINGSIG',
      issuedAtMillis: 1700000000000,
    );

    // wire 文本统一带 0x（拒裸）；公钥值本体保持裸，仅前缀。
    expect(registerBody, isNotNull);
    expect(registerBody!['p256_public_key'], '0x$barePub');
    expect(registerBody!['account_id'], accountId);
    expect(registerBody!['binding_signature'], '0xBINDINGSIG');
    expect(
      registerBody!['turnstile_token'],
      'turnstile-device-bind-token',
    );
  });

  test('冷启动等待根导航器就绪后只展示一次设备验证', () async {
    var readyChecks = 0;
    var presentCalls = 0;
    final token = await acquireDeviceBindingTurnstileToken(
      isUiReady: () => ++readyChecks >= 3,
      present: () async {
        presentCalls++;
        return 'turnstile-device-bind-token';
      },
      delay: (_) async {},
    );

    expect(token, 'turnstile-device-bind-token');
    expect(presentCalls, 1);
  });

  test('根导航器超时不提交空 token', () async {
    await expectLater(
      acquireDeviceBindingTurnstileToken(
        isUiReady: () => false,
        present: () async => 'turnstile-device-bind-token',
        readyTimeout: Duration.zero,
        delay: (_) async {},
      ),
      throwsA(
        isA<SquareApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'turnstile_ui_unavailable',
        ),
      ),
    );
  });

  test('用户取消设备验证时失败关闭且不产生空 token', () async {
    await expectLater(
      acquireDeviceBindingTurnstileToken(
        isUiReady: () => true,
        present: () async => null,
      ),
      throwsA(
        isA<SquareApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'turnstile_cancelled',
        ),
      ),
    );
  });

  test('广场已有子钥直接静默登录；Worker 确认缺钥时才登记一次', () async {
    final existingWallet = _SessionWalletManager();
    final existing = SquareSessionProvider(
      client: _SessionApi(deviceMissing: false),
      accountSecurity: existingWallet,
      deviceSubkey: _FakeDeviceSubkey('04${'a' * 128}'),
      currentUserContext: _SessionIdentityCache(),
    );
    expect(await existing.ensureSession(), isNotNull);
    expect(existingWallet.registrationCalls, 0);

    final missingWallet = _SessionWalletManager();
    final missing = SquareSessionProvider(
      client: _SessionApi(deviceMissing: true),
      accountSecurity: missingWallet,
      deviceSubkey: _FakeDeviceSubkey('04${'b' * 128}'),
      currentUserContext: _SessionIdentityCache(),
    );
    expect(await missing.ensureSession(), isNotNull);
    expect(missingWallet.registrationCalls, 1);
  });
}
