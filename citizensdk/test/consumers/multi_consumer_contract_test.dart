import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'citizenapp_fixture/citizenapp_fixture.dart';
import 'consumer_test_support.dart';
import 'external_signer/generic_qr_v1_signer.dart';
import 'reference/reference_consumer.dart';
import 'third_party_fixture/third_party_fixture.dart';

void main() {
  test('三类消费者共用相同公开端口并提交三种不透明 RuntimeCall', () async {
    final chain = RecordingChain();
    final wallet = RecordingWallet();
    final signing = RecordingSigning();
    final qr = RecordingQr();
    final transactions = RecordingTransactions();
    final history = RecordingHistory();
    final source = Uint8List(32);

    final reference = ReferenceConsumer(
      chain: chain,
      wallet: wallet,
      signing: signing,
      qr: qr,
      transactions: transactions,
      history: history,
    );
    final snapshot = await reference.inspect(
      signerAccountId: testAccountId,
      sourceAccountId: source,
      storageKey: Uint8List.fromList(<int>[1, 2]),
      payload: Uint8List.fromList(<int>[3, 4]),
      callData: Uint8List.fromList(<int>[5, 6]),
    );

    final citizenApp = CitizenAppFixture(
      chain: chain,
      transactions: transactions,
      history: history,
    );
    final destination = Uint8List.fromList(List<int>.filled(32, 7));
    final transfer = CitizenAppTransferDraft(
      destination: destination,
      amountFen: BigInt.from(900),
      remark: 'public square',
    );
    destination.fillRange(0, destination.length, 99);
    await citizenApp.prepareTransfer(sourceAccountId: source, draft: transfer);

    final thirdParty = ThirdPartyTravelFixture(
      chain: chain,
      transactions: transactions,
      history: history,
    );
    await thirdParty.prepareBooking(
      sourceAccountId: source,
      booking: TravelBookingDraft(
        bookingId: 'booking-42',
        routeCode: 'SEA-PDX',
        seatCount: 2,
      ),
    );

    expect(snapshot.walletRevision, BigInt.from(3));
    expect(snapshot.storage, <int>[9, 8, 7]);
    expect(snapshot.qrRequest, 'QR_V1 request');
    expect(snapshot.signingOutcome, isA<CitizenSigningCompleted>());
    expect(history.readCount, 1);
    expect(signing.intents.single.payload, <int>[3, 4]);
    expect(qr.reviewPayloads.single, <int>[3, 4]);
    expect(transactions.calls, hasLength(3));
    expect(transactions.calls[0].callData, <int>[5, 6]);
    expect(transactions.calls[1].callData.first, 41);
    expect(transactions.calls[1].callData[2], 7);
    expect(transactions.calls[2].callData.first, 73);
    expect(
      transactions.calls.map((call) => call.callData).toSet(),
      hasLength(3),
    );
  });

  test('CitizenApp 业务 storage、RuntimeCall 和事件解码全部留在消费夹具', () async {
    final destination = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );
    final draft = CitizenAppTransferDraft(
      destination: destination,
      amountFen: (BigInt.one << 80) + BigInt.from(17),
      remark: '提案付款',
    );
    final call = CitizenAppFixture.encodeTransferRuntimeCall(draft);
    final event = CitizenAppFixture.decodeTransferEvent(
      Uint8List.sublistView(call, 2),
    );

    expect(event.destination, destination);
    expect(event.amountFen, draft.amountFen);
    expect(event.remark, draft.remark);
    expect(
      CitizenAppFixture.transferStorageKey(destination),
      containsAll(destination),
    );
  });

  test('第三方业务使用独立字节结构且仍只调用通用链和交易端口', () async {
    final chain = RecordingChain();
    final transactions = RecordingTransactions();
    final history = RecordingHistory();
    final fixture = ThirdPartyTravelFixture(
      chain: chain,
      transactions: transactions,
      history: history,
    );
    final booking = TravelBookingDraft(
      bookingId: 'voyage-九',
      routeCode: 'NRT-SFO',
      seatCount: 3,
    );

    await fixture.readBooking(
      finalizedBlock: testFinalizedBlock,
      bookingId: booking.bookingId,
    );
    await fixture.prepareBooking(
      sourceAccountId: Uint8List(32),
      booking: booking,
    );
    await fixture.refreshSdkExecutionFacts();

    expect(chain.storageKeys.single, isNotEmpty);
    expect(transactions.calls.single.callData.first, 73);
    expect(history.syncCount, 1);
  });

  test('通用 QR_V1 签名器绑定请求、响应、账户和签名字节', () async {
    final signer = GenericQrV1Signer(
      qr: RecordingQr(),
      signing: RecordingSigning(),
    );
    final response = await signer.respond('QR_V1 request');

    expect(response.canonicalResponse, 'QR_V1 response');
    expect(response.requestId, 'request-1');
    expect(response.signerAccountId, testAccountId);
    expect(response.signature, hasLength(64));
    expect(() => response.signature[0] = 1, throwsUnsupportedError);
  });

  test('通用签名器对 request 绑定或响应签名漂移均失败关闭', () async {
    await expectLater(
      GenericQrV1Signer(
        qr: RecordingQr(),
        signing: RecordingSigning(mismatchedBinding: true),
      ).respond('QR_V1 request'),
      throwsFormatException,
    );
    await expectLater(
      GenericQrV1Signer(
        qr: RecordingQr(mismatchedResponseSignature: true),
        signing: RecordingSigning(),
      ).respond('QR_V1 request'),
      throwsFormatException,
    );
  });

  test('公共钱包词数与唯一 QR_V1 kind 数值闭集保持固定', () {
    expect(CitizenWalletWordCount.values.map((value) => value.value), <int>[
      12,
      18,
      24,
    ]);
    expect(CitizenQrKind.values.map((value) => value.value), <int>[1, 2, 5]);
    expect(CitizenQrKind.values.any((value) => value.value == 4), isFalse);
    expect(CitizenExternalSignerTransport.values, <Object>[
      CitizenExternalSignerTransport.qrV1,
    ]);
  });

  test('消费端业务边界自身拒绝无效长度和数值', () {
    expect(
      () => CitizenAppTransferDraft(
        destination: Uint8List(31),
        amountFen: BigInt.one,
        remark: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => CitizenAppTransferDraft(
        destination: Uint8List(32),
        amountFen: BigInt.zero,
        remark: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => TravelBookingDraft(bookingId: '', routeCode: 'A-B', seatCount: 1),
      throwsArgumentError,
    );
  });
}
