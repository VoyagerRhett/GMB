import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/signer/signing.dart';

void main() {
  final codec = AppBusinessQrCodec();
  const accountId =
      '0x1111111111111111111111111111111111111111111111111111111111111111';

  test('只接受 CitizenApp 明确拥有的业务动作', () {
    expect(
      [
        QrActions.citizenIdentity,
        QrActions.citizenOccupy,
        QrActions.citizenRebind,
        QrActions.squareAccountAction,
        QrActions.accountDataKeyProvision,
      ].every(AppBusinessQrCodec.isSupportedAction),
      isTrue,
    );
    expect(
      () => codec.buildRequest(
        requestId: 'business-request-000001',
        signerPublicKey: accountId,
        payloadHex: '0x01',
        action: QrActions.transferWithRemark,
      ),
      throwsA(
        isA<AppBusinessQrException>().having(
          (error) => error.code,
          'code',
          AppBusinessQrErrorCode.unsupportedAction,
        ),
      ),
    );
  });

  test('公民身份和广场动作只生成各自业务域签名字节', () {
    final identity = AppBusinessQrCodec.signingBytesForHex(
      payloadHex: '0x010203',
      action: QrActions.citizenIdentity,
    );
    final square = AppBusinessQrCodec.signingBytesForHex(
      payloadHex: '0x010203',
      action: QrActions.squareAccountAction,
    );
    expect(
      identity,
      signingMessage(
        opTag: kOpSignCitizenIdentity,
        scalePayload: const [1, 2, 3],
      ),
    );
    expect(
      square,
      signingMessage(opTag: kOpSignSquareAction, scalePayload: const [1, 2, 3]),
    );
  });

  test('注册局占号账户零槽只由用户选择的账户原位填充', () {
    const cid = 'CN220-CTZN2-100000001-2026';
    final payload = Uint8List.fromList([
      ...List<int>.filled(32, 0x44),
      cid.length << 2,
      ...cid.codeUnits,
      ...List<int>.filled(32, 0),
      ...List<int>.filled(8, 0),
      1,
      ...List<int>.filled(7, 0),
    ]);
    final template = AppBusinessQrCodec.decodeCidAccountAuthorizationTemplate(
      action: QrActions.citizenOccupy,
      payload: payload,
    );
    expect(template, isNotNull);
    final account = Uint8List.fromList(List<int>.filled(32, 0xaa));
    final materialized = template!.materialize(account)!;
    const offset = 32 + 1 + cid.length;
    expect(materialized.sublist(offset, offset + 32), account);
  });

  test('业务请求和响应保持同一 request id', () {
    final request = codec.buildRequest(
      requestId: 'business-request-000002',
      signerPublicKey: accountId,
      payloadHex: '0x0102',
      action: QrActions.squareAccountAction,
      nowEpochSeconds: 1900000000,
    );
    final response = codec.buildResponse(
      request: request,
      signatureHex: '0x${'22' * 64}',
    );
    expect(response.id, request.id);
    expect(response.body.signerPublicKeyHex, accountId);
  });
}
