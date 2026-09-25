import '../support/fake_citizen_sdk.dart';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/signer/square_action_sign_service.dart';

const _accountId =
    '0xd43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d';
const _signerSs58Address = '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
final Uint8List _pubBytes = Uint8List.fromList(
  List.generate(32, (i) => (i + 7) & 0xff),
);
final String _pubHex = _pubBytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

Future<Uint8List> _payloadBytes() async => Uint8List.fromList(<int>[
  ...(await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString('cancel_membership'))),
  ...(await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString(_accountId))),
  ...(await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString('sqa_1'))),
  ...(await CitizenSigning.encodePayload(CitizenSigningPayload.u64Le(BigInt.from(1700000000000)))),
]);

Future<String> _signRequestRaw(CitizenQr qr, {int action = CitizenQrActions.squareAccountAction}) async {
  return (await qr.encodeDocument(CitizenQrContent.signRequest(
    requestId: 'square-request-000001', expiresAt: BigInt.from(1900000000),
    signerAccountId: '0x$_pubHex', reviewPayload: await _payloadBytes(), action: action,
  ))).canonicalText;
}

CitizenWalletStateAccount _account({required String accountId, int index = 3}) {
  return CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot,
    walletIndex: 0,
    accountIndex: index,
    ss58Address: _signerSs58Address,
    accountId: accountId,
    name: '账户$index',
    createdAtMillis: BigInt.zero,
    isDefault: true,
  );
}

class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet(this._accounts);
  final List<CitizenWalletStateAccount> _accounts;

  @override
  CitizenSdkOperation<CitizenWalletState> getState() => testCitizenOperation(() async => CitizenWalletState(
    initializationState: _accounts.isEmpty ? CitizenWalletInitializationState.empty : CitizenWalletInitializationState.ready,
    cleanupPending: false,
    revision: BigInt.one,
    hotProfile: null,
    accounts: _accounts,
  ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSigning implements CitizenSigning {
  Uint8List signature = Uint8List(64)..fillRange(0, 64, 0x5a);
  Uint8List? signedPayload;
  String? signedAccountId;

  @override
  CitizenSdkOperation<CitizenSigningOutcome> begin(CitizenSigningIntent intent) => testCitizenOperation(() async {
    signedAccountId = intent.accountId;
    signedPayload = intent.payload;
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'00' * 32}',
      signature: signature,
    );
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestCitizenSdkTransport encodingTransport;
  late CitizenSdk encodingSdk;
  setUp(() async {
    encodingTransport = TestCitizenSdkTransport({}, useCore: true);
    encodingSdk = await encodingTransport.open();
  });
  tearDown(() async {
    await encodingSdk.close();
    await encodingTransport.dispose();
  });

  late SquareActionSignService service;
  setUp(() { service = SquareActionSignService(qr: encodingSdk.qr); });

  test(
    'prepare resolves accountId wallet by QR u signer public key + decodes action',
    () async {
      final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
      final prep = await service.prepare(await _signRequestRaw(encodingSdk.qr), wm);
      expect(prep.account.accountIndex, 3);
      expect(prep.actionLabel, '广场账户动作签名');
      expect(prep.decoded.action, 'cancel_membership');
      expect(prep.decoded.actionTypeLabel, '取消订阅');
      expect(prep.decoded.reviewFields, isNotNull);
    },
  );

  test('prepare rejects unknown non-App action before signing', () async {
    final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
    await expectLater(
      service.prepare(await _signRequestRaw(encodingSdk.qr, action: 0x7fff), wm),
      throwsA(
        isA<SquareActionSignException>()
            .having(
              (e) => e.error,
              'error',
              SquareActionSignError.invalidRequest,
            )
            .having(
              (e) => e.message,
              'message',
              contains('不属于 CitizenApp 业务二维码'),
            ),
      ),
    );
  });

  test('prepare rejects registered non-App action before signing', () async {
    final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
    await expectLater(
      service.prepare(await _signRequestRaw(encodingSdk.qr, action: CitizenQrActions.login), wm),
      throwsA(
        isA<SquareActionSignException>()
            .having(
              (e) => e.error,
              'error',
              SquareActionSignError.invalidRequest,
            )
            .having(
              (e) => e.message,
              'message',
              contains('不属于 CitizenApp 业务二维码'),
            ),
      ),
    );
  });

  test('prepare throws accountNotLocal when no wallet matches u', () async {
    final wm = _FakeWallet([_account(accountId: '0x${'aa' * 32}')]);
    await expectLater(
      service.prepare(await _signRequestRaw(encodingSdk.qr), wm),
      throwsA(
        isA<SquareActionSignException>().having(
          (e) => e.error,
          'error',
          SquareActionSignError.accountNotLocal,
        ),
      ),
    );
  });

  test(
    'prepare rejects card-selected account when QR u is another account',
    () async {
      final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
      await expectLater(
        service.prepare(
          await _signRequestRaw(encodingSdk.qr),
          wm,
          requiredAccount: _account(accountId: '0x${'aa' * 32}'),
        ),
        throwsA(
          isA<SquareActionSignException>().having(
            (e) => e.error,
            'error',
            SquareActionSignError.accountNotLocal,
          ),
        ),
      );
    },
  );

  test(
    'sign signs signing_message(0x1D) with accountId wallet and builds signResponse',
    () async {
      final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
      final prep = await service.prepare(await _signRequestRaw(encodingSdk.qr), wm);
      final signing = _FakeSigning();

      final responseJson = await service.sign(prep, signing, null);

      // 用 QR 指定的 account_id 对 signing_message(0x1D, payload) 签名。
      expect(signing.signedAccountId, '0x$_pubHex');
      final expected = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignSquareAction,
        scalePayload: await _payloadBytes(),
      ));
      expect(signing.signedPayload, expected);

      // 响应由同一SDK解码；保留签名、请求标识及有效期绑定断言。
      final response = await encodingSdk.qr.parse(responseJson);
      expect(response.kind, CitizenQrKind.signResponse);
      expect(response.signature, hasLength(64));
      expect(response.signature, signing.signature);
      expect(response.requestId, prep.request.requestId);
      expect(response.expiresAt, prep.request.expiresAt);
    },
  );
}
