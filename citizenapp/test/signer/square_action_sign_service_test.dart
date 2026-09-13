import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/qr/bodies/sign_response_body.dart';
import 'package:citizenapp/qr/bodies/sign_request_body.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/signing.dart';
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

Uint8List _payloadBytes() => Uint8List.fromList(<int>[
  ...scaleString('cancel_membership'),
  ...scaleString(_accountId),
  ...scaleString('sqa_1'),
  ...u64Le(1700000000000),
]);

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _signRequestRaw({int action = QrActions.squareAccountAction}) {
  return QrEnvelope<SignRequestBody>(
    kind: QrKind.signRequest,
    id: 'square-request-000001',
    issuedAt: 1800000000,
    expiresAt: 1900000000,
    body: SignRequestBody.fromHex(
      signerPublicKeyHex: '0x$_pubHex',
      payloadHex: '0x${_hex(_payloadBytes())}',
      action: action,
    ),
  ).toRawJson();
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
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.one,
    hotProfile: null,
    accounts: _accounts,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSigning implements CitizenSigning {
  Uint8List signature = Uint8List(64)..fillRange(0, 64, 0x5a);
  Uint8List? signedPayload;
  String? signedAccountId;

  @override
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent) async {
    signedAccountId = intent.accountId;
    signedPayload = intent.payload;
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'00' * 32}',
      signature: signature,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final service = SquareActionSignService();

  test(
    'prepare resolves accountId wallet by QR u signer public key + decodes action',
    () async {
      final wm = _FakeWallet([_account(accountId: '0x$_pubHex')]);
      final prep = await service.prepare(_signRequestRaw(), wm);
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
      service.prepare(_signRequestRaw(action: 0x7fff), wm),
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
      service.prepare(_signRequestRaw(action: QrActions.login), wm),
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
      service.prepare(_signRequestRaw(), wm),
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
          _signRequestRaw(),
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
      final prep = await service.prepare(_signRequestRaw(), wm);
      final signing = _FakeSigning();

      final responseJson = await service.sign(prep, signing, null);

      // 用 QR 指定的 account_id 对 signing_message(0x1D, payload) 签名。
      expect(signing.signedAccountId, '0x$_pubHex');
      final expected = signingMessage(
        opTag: kOpSignSquareAction,
        scalePayload: _payloadBytes(),
      );
      expect(signing.signedPayload, expected);

      // signResponse envelope 携带该 64B 签名。
      final env = QrEnvelope.parse(responseJson);
      expect(env.kind, QrKind.signResponse);
      final body = env.body as SignResponseBody;
      expect(body.signatureBytes.length, 64);
      expect(body.signatureBytes, signing.signature);
      // 请求-响应由 id 绑定。
      expect(env.id, isNotNull);

      // 冗余校验 JSON 结构。
      final decoded = jsonDecode(responseJson) as Map<String, dynamic>;
      expect(decoded['k'], 2);
    },
  );
}
