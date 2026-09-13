// CitizenIdentity(pallet 10)自助占号 / 换绑 call data SCALE 布局测试。
//
// 逐字节钉死 pallet/call 前缀、CidNumberBound(BoundedVec<u8>)与 SignatureOf
// (BoundedVec<u8>)编码,以及当前账户换绑授权摘要 signing_message(0x11, ...),
// 防与链端 `self_occupy_cid` / `self_rebind_cid_account_id` 漂移。

import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import '../../support/fake_citizen_sdk.dart';
import 'package:citizenapp/my/myid/citizen_identity_transaction.dart';
import 'package:citizenapp/signer/signing.dart'
    show kOpSignCidRebind, signingMessage;
import 'package:flutter_test/flutter_test.dart';

CitizenIdentityTransaction _transaction(CitizenChain chain) =>
    CitizenIdentityTransaction(
      chain: chain,
      transactions: TestCitizenTransactions(),
    );

CitizenBlockRef _finalized(String hash, [int number = 88]) => CitizenBlockRef(
      hash: hash,
      number: BigInt.from(number),
      finality: CitizenBlockFinality.finalized,
    );

void main() {
  // 采用链端 CTZN 金标号做样本(26 字节 ASCII)。
  const cid = 'CN951-CTZN1-539598435-2026';
  final cidBytes = Uint8List.fromList(cid.codeUnits);
  // 26 < 64 ⇒ 单字节 SCALE compact = len << 2 = 104。
  const compactCid = 26 << 2; // 0x68

  group('self_occupy_cid call data', () {
    test('布局 [10,5, compact(len), ...cid.utf8]', () {
      final call = CitizenIdentityTransaction.buildSelfOccupyCidCall(cid);
      expect(call[0], 10);
      expect(call[1], 5);
      expect(call[2], compactCid);
      expect(call.sublist(3), cidBytes);
      expect(call.length, 3 + 26);
    });

    test('空 / 超 32 字节 cid 被拒', () {
      expect(() => CitizenIdentityTransaction.buildSelfOccupyCidCall(''),
          throwsArgumentError);
      expect(
        () => CitizenIdentityTransaction.buildSelfOccupyCidCall('X' * 33),
        throwsArgumentError,
      );
    });
  });

  group('self_rebind_cid_account_id call data', () {
    final sig = Uint8List(64)..fillRange(0, 64, 0xAB);
    final revision = BigInt.from(0x01020304);
    final expiresAt = BigInt.from(0x11121314);

    test('布局 [10,9,cid,revision:u64LE,expires:u64LE,sig]', () {
      final call = CitizenIdentityTransaction.buildSelfRebindCidAccountCall(
        cidNumber: cid,
        expectedBindingRevision: revision,
        expiresAt: expiresAt,
        currentAccountSignature: sig,
      );
      expect(call.sublist(0, 2), <int>[10, 9]);
      expect(call[2], compactCid);
      expect(call.sublist(3, 3 + 26), cidBytes);
      const revisionStart = 3 + 26;
      expect(
        call.sublist(revisionStart, revisionStart + 8),
        <int>[0x04, 0x03, 0x02, 0x01, 0, 0, 0, 0],
      );
      const expiresStart = revisionStart + 8;
      expect(
        call.sublist(expiresStart, expiresStart + 8),
        <int>[0x14, 0x13, 0x12, 0x11, 0, 0, 0, 0],
      );
      // sig 段:BoundedVec<u8> ⇒ compact(64) 两字节 [0x01,0x01] ++ 64 字节。
      const sigStart = expiresStart + 8;
      expect(call.sublist(sigStart, sigStart + 2), <int>[0x01, 0x01]);
      expect(call.sublist(sigStart + 2), sig);
      expect(call.length, sigStart + 2 + 64); // 111
    });

    test('非 64 字节签名或越界 u64 被拒', () {
      expect(
        () => CitizenIdentityTransaction.buildSelfRebindCidAccountCall(
          cidNumber: cid,
          expectedBindingRevision: revision,
          expiresAt: expiresAt,
          currentAccountSignature: Uint8List(63),
        ),
        throwsArgumentError,
      );
      expect(
        () => CitizenIdentityTransaction.buildSelfRebindCidAccountCall(
          cidNumber: cid,
          expectedBindingRevision: BigInt.one << 64,
          expiresAt: expiresAt,
          currentAccountSignature: sig,
        ),
        throwsArgumentError,
      );
    });
  });

  group('rebind 当前账户授权摘要', () {
    final genesisHash = Uint8List.fromList(List<int>.filled(32, 0x22));
    const currentAccount =
        '0x3333333333333333333333333333333333333333333333333333333333333333';
    const newAccount =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    final currentAccountBytes = Uint8List.fromList(List<int>.filled(32, 0x33));
    final newAccountBytes = Uint8List.fromList(
      List<int>.filled(32, 0x11),
    );
    final revision = BigInt.from(0x01020304);
    final expiresAt = BigInt.from(0x11121314);

    test('op=0x11 且字段逐字节对齐 CidRebindAuthorization SCALE', () {
      final digest = CitizenIdentityTransaction.buildRebindSigningDigest(
        genesisHash: genesisHash,
        cidNumber: cid,
        currentAccountId: currentAccount,
        newAccountId: newAccount,
        expectedBindingRevision: revision,
        expiresAt: expiresAt,
      );
      expect(kOpSignCidRebind, 0x11);
      expect(digest.length, 32);

      final payload = <int>[
        ...genesisHash,
        compactCid,
        ...cidBytes,
        ...currentAccountBytes,
        ...newAccountBytes,
        0x04,
        0x03,
        0x02,
        0x01,
        0,
        0,
        0,
        0,
        0x14,
        0x13,
        0x12,
        0x11,
        0,
        0,
        0,
        0,
      ];
      final expected =
          signingMessage(opTag: kOpSignCidRebind, scalePayload: payload);
      expect(digest, expected);
      expect(
        digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
        '15c430a70f07e25fee7b6023f6a24759994360cf07138da8f87a5aa5365cbf32',
      );
    });

    test('创世/当前账户/revision/expiry 任一变化都不能重放此前摘要', () {
      Uint8List digest({
        Uint8List? genesis,
        String? old,
        BigInt? revisionValue,
        BigInt? expiresValue,
      }) =>
          CitizenIdentityTransaction.buildRebindSigningDigest(
            genesisHash: genesis ?? genesisHash,
            cidNumber: cid,
            currentAccountId: old ?? currentAccount,
            newAccountId: newAccount,
            expectedBindingRevision: revisionValue ?? revision,
            expiresAt: expiresValue ?? expiresAt,
          );

      final baseline = digest();
      expect(digest(genesis: Uint8List(32)..[0] = 1), isNot(baseline));
      expect(digest(old: '0x${'44' * 32}'), isNot(baseline));
      expect(digest(revisionValue: revision + BigInt.one), isNot(baseline));
      expect(digest(expiresValue: expiresAt + BigInt.one), isNot(baseline));
    });

    test('非法 newAccountId 文本被拒', () {
      expect(
        () => CitizenIdentityTransaction.buildRebindSigningDigest(
          genesisHash: genesisHash,
          cidNumber: cid,
          currentAccountId: currentAccount,
          newAccountId: 'not-hex',
          expectedBindingRevision: revision,
          expiresAt: expiresAt,
        ),
        throwsArgumentError,
      );
    });
  });

  test('换绑上下文在同一 finalized 块读取当前账户/revision/链上时间', () async {
    final rpc = _RebindContextChain();
    final context = await _transaction(rpc)
        .fetchSelfRebindAuthorizationContext(cid);

    expect(context.genesisHash, Uint8List.fromList(List<int>.filled(32, 0x22)));
    expect(context.currentAccountId, '0x${'33' * 32}');
    expect(context.expectedBindingRevision, BigInt.from(7));
    expect(context.expiresAt, BigInt.from(1700000300));
    expect(rpc.readBlockHashes, List<String>.filled(3, '0x${'55' * 32}'));
    expect(rpc.storageKeys.toSet().length, 3);
  });

  test('revision=u64::MAX 在生成签名前 fail-closed', () async {
    final rpc = _RebindContextChain(
      revision: (BigInt.one << 64) - BigInt.one,
    );
    await expectLater(
      _transaction(rpc)
          .fetchSelfRebindAuthorizationContext(cid),
      throwsA(isA<StateError>()),
    );
  });

  group('finalized 目标绑定后置核验', () {
    const newAccount =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const blockHash =
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('账户与 revision 精确命中才通过', () async {
      final rpc = _FinalizedBindingChain(
        accountByte: 0x11,
        revision: 8,
      );
      await expectLater(
        _transaction(rpc).verifyFinalizedBindingState(
          cidNumber: cid,
          expectedAccountId: newAccount,
          expectedBindingRevision: BigInt.from(8),
          finalizedBlock: _finalized(blockHash),
        ),
        completes,
      );
      expect(rpc.readBlockHashes, <String>[blockHash, blockHash]);
    });

    test('extrinsic 已 finalized 但绑定仍是此前账户/此前 revision 时拒绝', () async {
      final rpc = _FinalizedBindingChain(
        accountByte: 0x33,
        revision: 7,
      );
      await expectLater(
        _transaction(rpc).verifyFinalizedBindingState(
          cidNumber: cid,
          expectedAccountId: newAccount,
          expectedBindingRevision: BigInt.from(8),
          finalizedBlock: _finalized(blockHash),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('目标账户已变但 revision 没有精确推进时拒绝', () async {
      final rpc = _FinalizedBindingChain(
        accountByte: 0x11,
        revision: 7,
      );
      await expectLater(
        _transaction(rpc).verifyFinalizedBindingState(
          cidNumber: cid,
          expectedAccountId: newAccount,
          expectedBindingRevision: BigInt.from(8),
          finalizedBlock: _finalized(blockHash),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('首次占号只接受目标账户 + revision=1', () async {
      final rpc = _FinalizedBindingChain(
        accountByte: 0x11,
        revision: 1,
      );
      await expectLater(
        _transaction(rpc).verifyFinalizedBindingState(
          cidNumber: cid,
          expectedAccountId: newAccount,
          expectedBindingRevision: BigInt.one,
          finalizedBlock: _finalized(blockHash),
        ),
        completes,
      );
    });

  });
}

class _RebindContextChain extends TestCitizenChain {
  _RebindContextChain({BigInt? revision})
      : revision = revision ?? BigInt.from(7);

  final BigInt revision;
  int _readIndex = 0;
  final List<String> readBlockHashes = <String>[];
  final List<String> storageKeys = <String>[];

  @override
  Future<CitizenBlockRef> getFinalizedHead() async =>
      _finalized('0x${'55' * 32}');

  @override
  Future<String> getGenesisHash() async => '0x${'22' * 32}';

  @override
  Future<Uint8List?> getStorage(
    CitizenBlockRef block,
    Uint8List storageKey,
  ) async {
    storageKeys.add(_hex(storageKey));
    readBlockHashes.add(block.hash);
    return switch (_readIndex++) {
      0 => Uint8List.fromList(List<int>.filled(32, 0x33)),
      1 => _u64(revision),
      2 => _u64(BigInt.from(1700000000000)),
      _ => throw StateError('unexpected storage read'),
    };
  }

  static Uint8List _u64(BigInt value) {
    final result = Uint8List(8);
    var remaining = value;
    for (var index = 0; index < result.length; index++) {
      result[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return result;
  }

  static String _hex(List<int> bytes) =>
      '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
}

class _FinalizedBindingChain extends TestCitizenChain {
  _FinalizedBindingChain({
    required this.accountByte,
    required this.revision,
  });

  final int accountByte;
  final int revision;
  int _readIndex = 0;
  final List<String> readBlockHashes = <String>[];

  @override
  Future<Uint8List?> getStorage(
    CitizenBlockRef block,
    Uint8List storageKey,
  ) async {
    readBlockHashes.add(block.hash);
    return switch (_readIndex++) {
      0 => Uint8List.fromList(List<int>.filled(32, accountByte)),
      1 => _RebindContextChain._u64(BigInt.from(revision)),
      _ => throw StateError('unexpected storage read: $storageKey'),
    };
  }
}
