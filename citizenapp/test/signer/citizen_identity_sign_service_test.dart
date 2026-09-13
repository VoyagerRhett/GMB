import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/qr/bodies/sign_request_body.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/citizen_identity_sign_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet({this.account});

  final CitizenWalletStateAccount? account;

  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
        revision: BigInt.one,
        hotProfile: null,
        accounts: account == null ? const [] : [account!],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSigning implements CitizenSigning {
  String? signedAccountId;

  @override
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent) async {
    signedAccountId = intent.accountId;
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'00' * 32}',
      signature: Uint8List(64),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _request({required int action, required List<int> payload}) {
  return QrEnvelope<SignRequestBody>(
    kind: QrKind.signRequest,
    id: 'citizen-request-000001',
    issuedAt: 1800000000,
    expiresAt: 1900000000,
    body: SignRequestBody.fromHex(
      action: action,
      signerPublicKeyHex: '0x${'11' * 32}',
      payloadHex:
          '0x${payload.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}',
    ),
  ).toRawJson();
}

List<int> _u32Le(int value) => [
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

List<int> _u64Le(int value) =>
    [for (var i = 0; i < 8; i++) (value >> (i * 8)) & 0xff];

List<int> _scaleText(String value) => [
      value.codeUnits.length << 2,
      ...value.codeUnits,
    ];

/// 内层 `VotingIdentityPayload` SCALE 字节，**不是**公民实际签名的内容。
List<int> _votingIdentityPayload() => [
      ..._scaleText('CN220-CTZN2-198805200-2026'),
      ...List<int>.filled(32, 0x11),
      ..._u32Le(20260728),
      ..._u32Le(20360728),
      0,
      ..._scaleText('CN22'),
      ..._scaleText('CN2201'),
      ..._scaleText('CN220101'),
    ];

const _genesisHashByte = 0xaa;
const _expectedIdentityVersion = 7;
const _authorizationExpiresAt = 1893456000;

/// 公民实际签名覆盖的**完整授权字节**，逐字节镜像唯一写入端
/// `onchina/src/domains/citizens/chain_identity.rs`
/// 的 `build_citizen_identity_authorization_bytes`：
/// `genesis_hash(32) ++ payload ++ expected_identity_version(8) ++ expires_at(8)`。
///
/// 本夹具曾只喂内层 payload，防重放三件套落地后长期红着 —— 夹具必须照写入端
/// 真实字节形态，否则「解码通过」证明不了任何跨端一致性。
Uint8List _validAuthorizationBytes() => Uint8List.fromList([
      ...List<int>.filled(32, _genesisHashByte),
      ..._votingIdentityPayload(),
      ..._u64Le(_expectedIdentityVersion),
      ..._u64Le(_authorizationExpiresAt),
    ]);

void main() {
  final service = CitizenIdentitySignService();

  test('协议登记的公民动作统一展示公民签名确认', () {
    expect(
      QrActions.actionLabelForCode(QrActions.citizenIdentity),
      '公民签名确认',
    );
  });

  test('非公民签名动作在读取钱包前即拒绝', () async {
    await expectLater(
      service.prepare(
        _request(action: QrActions.login, payload: Uint8List(1)),
        _FakeWallet(),
      ),
      throwsA(isA<CitizenIdentitySignException>()),
    );
  });

  test('无法完整解码的公民身份载荷禁止签名', () async {
    await expectLater(
      service.prepare(
        _request(action: QrActions.citizenIdentity, payload: Uint8List(1)),
        _FakeWallet(),
      ),
      throwsA(
        isA<CitizenIdentitySignException>().having(
          (error) => error.message,
          'message',
          contains('无法完整中文展示'),
        ),
      ),
    );
  });

  test('缺少防重放三件套的裸载荷禁止签名', () async {
    await expectLater(
      service.prepare(
        _request(
          action: QrActions.citizenIdentity,
          payload: _votingIdentityPayload(),
        ),
        _FakeWallet(),
      ),
      throwsA(
        isA<CitizenIdentitySignException>().having(
          (error) => error.message,
          'message',
          contains('无法完整中文展示'),
        ),
      ),
    );
  });

  test('卡片指定账户与请求一致时按该 account_id 签名', () async {
    final account = CitizenWalletStateAccount(
      signMode: CitizenWalletSignMode.hot,
      walletIndex: 0,
      accountIndex: 5,
      accountId: '0x${'11' * 32}',
      ss58Address: 'w5CitizenAccount',
      name: '账户5',
      createdAtMillis: BigInt.zero,
      isDefault: true,
    );
    final wallet = _FakeWallet(account: account);
    final signing = _FakeSigning();
    final raw = _request(
      action: QrActions.citizenIdentity,
      payload: _validAuthorizationBytes(),
    );
    final prep = await service.prepare(
      raw,
      wallet,
      requiredAccount: account,
    );
    await service.sign(prep, signing, null);
    expect(prep.account.accountIndex, 5);
    expect(signing.signedAccountId, account.accountId);
    // 防重放三件套必须原样解出来并展示，不能只是"跳过了外层字节"。
    expect(prep.decoded.genesisHashHex, '0x${'aa' * 32}');
    expect(prep.decoded.expectedIdentityVersion, _expectedIdentityVersion);
    expect(prep.decoded.authorizationExpiresAt, _authorizationExpiresAt);
  });
}
