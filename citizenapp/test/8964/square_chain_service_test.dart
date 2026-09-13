import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart/scale_codec.dart' show CompactBigIntCodec;

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import '../support/fake_citizen_sdk.dart';

void main() {
  test('publish_post call_data 与 runtime 下标和字段顺序一致', () {
    final hashHex = List<int>.generate(32, (index) => index + 1)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    final callData = SquareChainService.buildPublishPostCallData(
      postId: 'sqp_abc',
      postType: SquarePostType.video,
      contentHashHex: hashHex,
      storageReceiptId: 'sqr_receipt',
    );

    final expected = <int>[
      34,
      0,
      ...CompactBigIntCodec.codec.encode(BigInt.from(7)),
      ...utf8.encode('sqp_abc'),
      2,
      ...List<int>.generate(32, (index) => index + 1),
      ...CompactBigIntCodec.codec.encode(BigInt.from(11)),
      ...utf8.encode('sqr_receipt'),
    ];
    expect(callData, Uint8List.fromList(expected));
  });

  test('publish_post 拒绝零 content_hash', () {
    expect(
      () => SquareChainService.buildPublishPostCallData(
        postId: 'sqp_abc',
        postType: SquarePostType.document,
        contentHashHex: '00' * 32,
        storageReceiptId: 'sqr_receipt',
      ),
      throwsArgumentError,
    );
  });

  test('只把护照有效且状态正常的投票身份视为有效', () {
    final normal = _votingIdentityBytes(
      citizenStatus: 0,
    );
    final revoked = _votingIdentityBytes(
      citizenStatus: 1,
    );

    expect(
      SquareChainService.votingIdentityIsActive(normal, today: 20260722),
      isTrue,
    );
    expect(
      SquareChainService.votingIdentityIsActive(normal, today: 20400101),
      isFalse,
    );
    expect(
      SquareChainService.votingIdentityIsActive(revoked, today: 20260722),
      isFalse,
    );
    expect(
      SquareChainService.votingIdentityIsActive(
        Uint8List.sublistView(normal, 0, 9),
        today: 20260722,
      ),
      isFalse,
    );
  });

  test('广场身份使用永久 CID 闭环快照而不是旧 Account-keyed storage', () async {
    final service = SquareChainService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      identityChainReader: _FakeIdentityReader(
        CitizenIdentityChainSnapshot(
          cidNumber: 'CN001-CTZN-000000001-2026',
          accountId: Uint8List(32),
          bindingRevision: 1,
          votingIdentity: _votingIdentityBytes(citizenStatus: 0),
          candidateIdentity: _candidateIdentityBytes(),
        ),
      ),
    );

    final identity = await service.fetchIdentity('ignored-in-reader');
    expect(identity.cidNumber, 'CN001-CTZN-000000001-2026');
    expect(identity.identityLevel, 'candidate');
  });

  test('匿名 active CID 保留帖子归属但不升级投票身份', () async {
    final service = SquareChainService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      identityChainReader: _FakeIdentityReader(
        CitizenIdentityChainSnapshot(
          cidNumber: 'CN001-CTZN-000000002-2026',
          accountId: Uint8List(32),
          bindingRevision: 1,
          votingIdentity: null,
        ),
      ),
    );

    final identity = await service.fetchIdentity('ignored-in-reader');
    expect(identity.cidNumber, 'CN001-CTZN-000000002-2026');
    expect(identity.identityLevel, 'visitor');
    expect(
      await service.fetchNormalCitizenCidNumber('ignored-in-reader'),
      'CN001-CTZN-000000002-2026',
    );
  });

  test('三档平台价格通过一次 finalized storage 批量读取', () async {
    final chain = _BatchPriceChain();
    final service = SquareChainService(
      chain: chain,
      transactions: TestCitizenTransactions(),
    );

    final prices = await service.fetchAllPlatformPrices(forceFresh: true);

    expect(prices, const {
      'freedom': 29900,
      'democracy': 99900,
      'spark': 199900,
    });
    expect(chain.fetchCount, 1);
    expect(chain.requestedKeyCount, 3);
  });
}

Uint8List _candidateIdentityBytes() {
  final out = BytesBuilder();
  for (final value in ['CN', '001', '0001', '陈', '明']) {
    final bytes = utf8.encode(value);
    out.add(CompactBigIntCodec.codec.encode(BigInt.from(bytes.length)));
    out.add(bytes);
  }
  out.add([0]);
  out.add(_u32(20000131));
  out.add(_u32(88));
  return out.toBytes();
}

Uint8List _votingIdentityBytes({
  required int citizenStatus,
}) {
  final out = BytesBuilder();
  out.add(_u32(20260101));
  out.add(_u32(20360101));
  out.add([citizenStatus]);
  for (final code in ['CN', '001', '0001']) {
    final bytes = utf8.encode(code);
    out.add(CompactBigIntCodec.codec.encode(BigInt.from(bytes.length)));
    out.add(bytes);
  }
  out.add(_u32(88));
  return out.toBytes();
}

class _FakeIdentityReader extends CitizenIdentityChainReader {
  _FakeIdentityReader(this.snapshot) : super(chain: TestCitizenChain());

  final CitizenIdentityChainSnapshot? snapshot;

  @override
  Future<CitizenIdentityChainSnapshot?> readByAccountId(
          String ss58Address) async =>
      snapshot;
}

class _BatchPriceChain extends TestCitizenChain {
  int fetchCount = 0;
  int requestedKeyCount = 0;

  @override
  Future<CitizenBlockRef> getFinalizedHead() async => CitizenBlockRef(
        hash: '0x${'11' * 32}',
        number: BigInt.one,
        finality: CitizenBlockFinality.finalized,
      );

  @override
  Future<List<Uint8List?>> getStorageBatch(
    CitizenBlockRef block,
    List<Uint8List> keys,
  ) async {
    fetchCount++;
    requestedKeyCount = keys.length;
    const prices = [29900, 99900, 199900];
    return <Uint8List?>[
      for (var index = 0; index < keys.length; index++) _u128(prices[index]),
    ];
  }
}

List<int> _u32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

Uint8List _u128(int value) {
  final bytes = Uint8List(16);
  ByteData.sublistView(bytes).setUint64(0, value, Endian.little);
  return bytes;
}
