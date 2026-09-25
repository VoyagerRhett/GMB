import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';

// 原App协议实现已删除；这里通过SDK公开入口检验同一Core真实协议，不恢复App解析器。
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

  const accountId = '0x1111111111111111111111111111111111111111111111111111111111111111';

  test('通用SDK编码签名请求，冷导入用途仍只允许账户码', () async {
    final request = await encodingSdk.qr.encodeDocument(CitizenQrContent.signRequest(
      requestId: 'business-request-000001', signerAccountId: accountId,
      reviewPayload: Uint8List.fromList([1]), action: CitizenQrActions.squareAccountAction,
      expiresAt: BigInt.from(1900000000)));
    expect((await encodingSdk.qr.parseForPurpose(request.canonicalText,
      CitizenQrScanPurpose.signingRequest)).document.action, CitizenQrActions.squareAccountAction);
    await expectLater(encodingSdk.qr.parseForPurpose(request.canonicalText,
      CitizenQrScanPurpose.coldAccountImport), throwsA(isA<CitizenSdkException>()));
  });

  test('公民身份与广场签名域由真实Core隔离，不生成App镜像算法', () async {
    final payload = Uint8List.fromList([1, 2, 3]);
    final identity = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
      opTag: kOpSignCitizenIdentity, scalePayload: payload));
    final square = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
      opTag: kOpSignSquareAction, scalePayload: payload));
    expect(identity, hasLength(32)); expect(square, hasLength(32));
    expect(identity, isNot(square));
  });

  test('注册局占号账户零槽只由SDK原位填充，坏模板不产出载荷', () async {
    const cid = 'CN220-CTZN2-100000001-2026';
    final payload = Uint8List.fromList([
      ...List<int>.filled(32, 0x44), cid.length << 2, ...cid.codeUnits,
      ...List<int>.filled(32, 0), ...List<int>.filled(8, 0),
      1, ...List<int>.filled(7, 0),
    ]);
    final result = await encodingSdk.qr.prepareAccountAuthorization(
      action: CitizenQrActions.citizenOccupy, payload: payload, accountId: '0x${'aa' * 32}');
    expect(result.reason, CitizenQrAuthorizationReason.valid);
    const offset = 32 + 1 + cid.length;
    expect(result.materializedPayload!.sublist(offset, offset + 32), List<int>.filled(32, 0xaa));
    final invalid = await encodingSdk.qr.prepareAccountAuthorization(
      action: CitizenQrActions.citizenOccupy, payload: payload.sublist(1), accountId: accountId);
    expect(invalid.reason, CitizenQrAuthorizationReason.invalidTemplate);
    expect(invalid.materializedPayload, isNull);
  });

  test('业务请求和响应保持同一request id、期限及签名账户', () async {
    final request = await encodingSdk.qr.encodeDocument(CitizenQrContent.signRequest(
      requestId: 'business-request-000002', signerAccountId: accountId,
      reviewPayload: Uint8List.fromList([1, 2]), action: CitizenQrActions.squareAccountAction,
      expiresAt: BigInt.from(1900000000)));
    final response = await encodingSdk.qr.encodeDocument(CitizenQrContent.signResponse(
      requestId: request.requestId!, expiresAt: BigInt.from(request.expiresAt!),
      signerAccountId: accountId, signature: Uint8List(64)..fillRange(0, 64, 0x22)));
    expect(response.requestId, request.requestId);
    expect(response.expiresAt, request.expiresAt);
    expect(response.signerAccountId, accountId);
  });
}
