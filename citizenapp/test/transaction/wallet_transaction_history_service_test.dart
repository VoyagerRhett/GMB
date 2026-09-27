import 'dart:async';
import 'dart:convert';

import 'package:polkadart_scale_codec/polkadart_scale_codec.dart' as scale;
import 'package:substrate_metadata/substrate_metadata.dart' as metadata;
import 'package:citizenapp/transaction/history/citizenchain_transaction_event_decoder.dart';

import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/wallet_transaction_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_citizen_sdk.dart';
import '../support/isar_test_env.dart';

const _accountId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  useIsolatedIsar();

  test('单层和多层透明账户包装保留账户、金额、备注和执行结果', () {
    for (final depth in [1, 3]) {
      final decoded = const CitizenChainTransactionEventDecoder().decode(
        eventsBytes: _transferEvents(incoming: true, withTopics: true),
        metadataBytes: _eventMetadata(accountWrapperDepth: depth),
      );
      expect(decoded.transfers, hasLength(1));
      final transfer = decoded.transfers.single;
      expect(transfer.fromAccountId, '0x${'bb' * 32}');
      expect(transfer.toAccountId, _accountId);
      expect(transfer.amountFen, '100');
      expect(transfer.remark, '合成备注');
      expect(transfer.eventRecordIndex, 0);
      expect(transfer.extrinsicIndex, 0);
      expect(decoded.outcomes[0]!.succeeded, isTrue);
    }
  });

  test('纯包装循环和缺失引用明确拒绝，不无限递归', () {
    for (final bytes in [
      _eventMetadata(cyclicAccountId: true),
      _eventMetadata(missingAccountId: true),
    ]) {
      expect(
        () => const CitizenChainTransactionEventDecoder().decode(
          eventsBytes: _transferEvents(incoming: true),
          metadataBytes: bytes,
        ),
        throwsFormatException,
      );
    }
  });

  test('经过序列容器的合法递归可解码，包装不增加SCALE字节', () {
    final decoded = const CitizenChainTransactionEventDecoder().decode(
      eventsBytes: _transferEvents(incoming: true, recursiveEvent: true),
      metadataBytes: _eventMetadata(recursiveEvent: true),
    );
    expect(decoded.transfers.single.toAccountId, _accountId);
    expect(decoded.transfers.single.amountFen, '100');
    expect(decoded.outcomes[0]!.succeeded, isTrue);
  });

  test('包装解码失败不推进，修正后从原块恢复收款且重放不重复', () async {
    final chain = _HistoryChain()
      ..height = 1
      ..metadataBytes = _eventMetadata(cyclicAccountId: true);
    chain.encodedEvents[1] = _transferEvents(incoming: true);
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    await expectLater(service.sync(), throwsFormatException);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      0,
    );
    expect(await LocalTxStore.countByAccountId(_accountId), 0);
    chain.metadataBytes = _eventMetadata(accountWrapperDepth: 3);
    await service.sync();
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      1,
    );
    final records = await LocalTxStore.queryByAccountId(_accountId);
    expect(records, hasLength(1));
    expect(records.single.amountDeltaFen, '100');
    await service.sync();
    expect(await LocalTxStore.countByAccountId(_accountId), 1);
    await service.stop();
  });

  test('完整遍历 SDK history 分页并只投影 SDK execution 终态', () async {
    await _insert(txHash: '0x01', executionId: 'execution-newer');
    await _insert(txHash: '0x02', executionId: 'execution-older');
    final events = StreamController<CitizenSdkEvent>();
    final service = WalletTransactionHistoryService(
      history: _PagedHistory(),
      chain: TestCitizenChain(),
      wallet: _HistoryWallet(),
      events: events.stream,
    );

    await service.start();
    await service.sync();

    final records = await LocalTxStore.queryByAccountId(_accountId);
    final byHash = {for (final record in records) record.txHash: record};
    expect(byHash['0x01']?.status, LocalTxStore.statusInBlock);
    expect(byHash['0x01']?.blockHash, '0x${'11' * 32}');
    expect(byHash['0x02']?.status, LocalTxStore.statusFinalized);
    expect(byHash['0x02']?.blockNumber, 8);
    expect(byHash['0x02']?.extrinsicIndex, 3);

    await service.stop();
    await events.close();
  });
  test('按账户导入时间定位起点，只投影边界之后的区块且重启复用进度', () async {
    final chain = _HistoryChain();
    final wallet = _HistoryWallet(createdAt: 3500);
    final service = _service(chain, wallet);
    await service.start();
    await service.sync();
    expect(chain.eventBlocks, [4, 5, 6, 7, 8, 9, 10]);
    final cursor = (await LocalTxStore.historyCursor(_accountId))!;
    expect(cursor.startBlockNumber, 4);
    expect(cursor.cursorBlockNumber, 10);
    await service.stop();

    chain.eventBlocks.clear();
    chain.storageBlocks.clear();
    chain.height = 11;
    final restarted = _service(chain, wallet);
    await restarted.start();
    await restarted.sync();
    expect(chain.eventBlocks, [11]);
    expect(chain.storageBlocks, [11]);
    await restarted.stop();
  });

  test('同一轮有界处理32块，下一轮接续且不会跳过中间区块', () async {
    final chain = _HistoryChain()..height = 40;
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    await service.sync();
    expect(chain.eventBlocks, List.generate(32, (i) => i + 1));
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      32,
    );
    await service.sync();
    expect(chain.eventBlocks, List.generate(40, (i) => i + 1));
    await service.stop();
  });

  test('某块读取失败保留前一块进度，恢复后从失败块继续', () async {
    final chain = _HistoryChain()..failEventsAt = 6;
    final service = _service(chain, _HistoryWallet(createdAt: 4000));
    await service.start();
    await expectLater(service.sync(), throwsStateError);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      5,
    );
    chain.failEventsAt = null;
    chain.eventBlocks.clear();
    await service.sync();
    expect(chain.eventBlocks, [6, 7, 8, 9, 10]);
    await service.stop();
  });

  test('无法定位时间边界时不建立进度，也不以当前高度跳过', () async {
    final chain = _HistoryChain()..missingTimestamp = true;
    final service = _service(chain, _HistoryWallet(createdAt: 4000));
    await service.start();
    await expectLater(service.sync(), throwsFormatException);
    expect(await LocalTxStore.historyCursor(_accountId), isNull);
    expect(chain.eventBlocks, isEmpty);
    await service.stop();
  });

  test('导入时间晚于当前链时间时等待后续块，保留准确时间边界', () async {
    final chain = _HistoryChain();
    final service = _service(chain, _HistoryWallet(createdAt: 11500));
    await service.start();
    await service.sync();
    expect(chain.eventBlocks, isEmpty);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.startBlockNumber,
      11,
    );
    chain.height = 12;
    await service.sync();
    expect(chain.eventBlocks, [12]);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      12,
    );
    await service.stop();
  });

  test('并发刷新共用读取任务；停止后迟到事件不写库', () async {
    final chain = _HistoryChain()
      ..height = 1
      ..eventBarrier = Completer<Uint8List?>();
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    final first = service.sync();
    final second = service.sync();
    expect(identical(first, second), isTrue);
    await chain.eventEntered.future;
    final stopping = service.stop();
    chain.eventBarrier!.complete(null);
    await stopping;
    expect(chain.eventBlocks, [1]);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      0,
    );
  });

  test('退后台使在途块失效，返回前台后继续同一进度', () async {
    final chain = _HistoryChain()
      ..height = 1
      ..eventBarrier = Completer<Uint8List?>();
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    final waiting = service.sync();
    await chain.eventEntered.future;
    service.setForeground(false);
    chain.eventBarrier!.complete(null);
    await waiting;
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      0,
    );
    chain.eventBarrier = null;
    service.setForeground(true);
    await service.sync();
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      1,
    );
    await service.stop();
  });

  test('真实 SCALE 按字段名及稀疏索引解码，topics 不影响后续事件', () {
    final decoded = const CitizenChainTransactionEventDecoder().decode(
      eventsBytes: _transferEvents(incoming: true, withTopics: true),
      metadataBytes: _eventMetadata(),
    );
    expect(decoded.transfers, hasLength(1));
    expect(decoded.transfers.single.toAccountId, _accountId);
    expect(decoded.transfers.single.remark, '合成备注');
    expect(decoded.transfers.single.eventRecordIndex, 0);
    expect(decoded.transfers.single.amountFen, '100');
    expect(decoded.outcomes[0]!.succeeded, isTrue);
  });

  test('同一块相同金额的两笔转账按顺序分别合并备注', () {
    final decoded = const CitizenChainTransactionEventDecoder().decode(
      eventsBytes: _transferEvents(twice: true),
      metadataBytes: _eventMetadata(),
    );
    expect(decoded.transfers, hasLength(2));
    expect(decoded.transfers.map((e) => e.eventRecordIndex), [0, 2]);
    expect(decoded.transfers.map((e) => e.remark), ['合成备注', '第二笔']);
  });

  test('事件截断、尾随字节和孤立备注明确拒绝', () {
    final bytes = _transferEvents();
    for (final invalid in [
      Uint8List.sublistView(bytes, 0, bytes.length - 1),
      Uint8List.fromList([...bytes, 255]),
      _transferEvents(remarkOnly: true),
    ]) {
      expect(
        () => const CitizenChainTransactionEventDecoder().decode(
          eventsBytes: invalid,
          metadataBytes: _eventMetadata(),
        ),
        throwsA(isA<Object>()),
      );
    }
  });

  test('真实编码收款写入账户历史；重放不重复，错误执行不入账', () async {
    final chain = _HistoryChain()..height = 2;
    chain.encodedEvents[1] = _transferEvents(incoming: true);
    chain.encodedEvents[2] = _transferEvents(incoming: true, failed: true);
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    await service.sync();
    final rows = await LocalTxStore.queryByAccountId(_accountId);
    expect(rows, hasLength(1));
    expect(rows.single.amountDeltaFen, '100');
    expect(rows.single.source, 'sdk_finalized_event');
    expect(rows.single.remark, '合成备注');
    expect(rows.single.blockNumber, 1);
    await service.sync();
    expect(await LocalTxStore.countByAccountId(_accountId), 1);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      2,
    );
    await service.stop();
  });

  test('缺少 System 执行结果及正文锚点不符均不写记录或推进', () async {
    final chain = _HistoryChain()..height = 1;
    chain.encodedEvents[1] = _transferEvents(incoming: true, omitOutcome: true);
    final service = _service(chain, _HistoryWallet(createdAt: 1000));
    await service.start();
    await expectLater(service.sync(), throwsFormatException);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      0,
    );
    chain.encodedEvents[1] = _transferEvents(incoming: true);
    chain.wrongBodyAnchor = true;
    await expectLater(service.sync(), throwsStateError);
    expect(await LocalTxStore.countByAccountId(_accountId), 0);
    expect(
      (await LocalTxStore.historyCursor(_accountId))!.cursorBlockNumber,
      0,
    );
    chain.wrongBodyAnchor = false;
    await service.sync();
    expect(await LocalTxStore.countByAccountId(_accountId), 1);
    await service.stop();
  });
}

Future<void> _insert({required String txHash, required String executionId}) {
  return LocalTxStore.upsertLocalSubmitTransfer(
    ss58Address: 'sender',
    accountId: _accountId,
    txHash: txHash,
    executionId: executionId,
    callDataHash: '0x${'22' * 32}',
    amountDeltaFen: '-101',
    transferAmountFen: '100',
    feeFen: '1',
    counterpartySs58Address: 'recipient',
    fromSs58Address: 'sender',
    toSs58Address: 'recipient',
    usedNonce: 1,
    createdAtMillis: 1,
  );
}

final class _PagedHistory extends TestCitizenHistory {
  @override
  Future<CitizenTransactionHistoryPage> syncTransactionHistory() async {
    return CitizenTransactionHistoryPage(
      revision: BigInt.one,
      records: [_record('execution-newer', '0x01', inBlock: true)],
      nextBeforeExecutionId: 'execution-newer',
    );
  }

  @override
  Future<CitizenTransactionHistoryPage> getTransactionHistory({
    String? beforeExecutionId,
    int limit = 100,
  }) async {
    expect(beforeExecutionId, 'execution-newer');
    expect(limit, 100);
    return CitizenTransactionHistoryPage(
      revision: BigInt.one,
      records: [_record('execution-older', '0x02', inBlock: false)],
      nextBeforeExecutionId: null,
    );
  }

  CitizenTransactionHistoryRecord _record(
    String executionId,
    String txHash, {
    required bool inBlock,
  }) {
    final block = CitizenBlockRef(
      hash: inBlock ? '0x${'11' * 32}' : '0x${'33' * 32}',
      number: BigInt.from(inBlock ? 7 : 8),
      finality: inBlock
          ? CitizenBlockFinality.best
          : CitizenBlockFinality.finalized,
    );
    return CitizenTransactionHistoryRecord(
      executionId: executionId,
      sourceAccountId: _accountId,
      callDataHash: '0x${'22' * 32}',
      transactionHash: txHash,
      status: inBlock
          ? CitizenTransactionHistoryStatus.inBlock
          : CitizenTransactionHistoryStatus.finalizedSuccess,
      block: block,
      execution: inBlock
          ? null
          : CitizenExecution(
              status: CitizenExecutionStatus.success,
              block: block,
              extrinsicIndex: 3,
              dispatchVariant: null,
              palletIndex: null,
              errorIndex: null,
            ),
      replacementHash: null,
      createdAtMillis: BigInt.one,
      updatedAtMillis: BigInt.from(2),
      poolRejectionReason: null,
    );
  }
}

WalletTransactionHistoryService _service(
  _HistoryChain chain,
  _HistoryWallet wallet,
) => WalletTransactionHistoryService(
  history: _EmptyHistory(),
  chain: chain,
  wallet: wallet,
  events: const Stream<CitizenSdkEvent>.empty(),
);

final class _EmptyHistory extends TestCitizenHistory {
  @override
  Future<CitizenTransactionHistoryPage> syncTransactionHistory() async =>
      CitizenTransactionHistoryPage(
        revision: BigInt.zero,
        records: [],
        nextBeforeExecutionId: null,
      );
}

final class _HistoryWallet extends TestCitizenSdkWallet {
  _HistoryWallet({this.createdAt});
  final int? createdAt;
  @override
  CitizenSdkOperation<CitizenWalletState> getState() => testCitizenOperation(
    () => CitizenWalletState(
      revision: BigInt.one,
      hotProfile: null,
      cleanupPending: false,
      initializationState: createdAt == null
          ? CitizenWalletInitializationState.empty
          : CitizenWalletInitializationState.ready,
      accounts: [
        if (createdAt != null)
          CitizenWalletStateAccount(
            signMode: CitizenWalletSignMode.cold,
            walletIndex: 0,
            accountIndex: null,
            accountId: _accountId,
            ss58Address: 'synthetic-wallet',
            name: '测试钱包',
            createdAtMillis: BigInt.from(createdAt!),
            isDefault: true,
          ),
      ],
    ),
  );
}

final class _HistoryChain extends TestCitizenChain {
  int height = 10;
  final encodedEvents = <int, Uint8List>{};
  bool wrongBodyAnchor = false;
  Uint8List? metadataBytes;
  int? failEventsAt;
  bool missingTimestamp = false;
  final eventBlocks = <int>[];
  final storageBlocks = <int>[];
  final eventEntered = Completer<void>();
  Completer<Uint8List?>? eventBarrier;
  CitizenBlockRef block(int height) => CitizenBlockRef(
    hash: '0x${height.toRadixString(16).padLeft(64, '0')}',
    number: BigInt.from(height),
    finality: CitizenBlockFinality.finalized,
  );
  @override
  Future<String> getGenesisHash() async => '0x${'00' * 32}';
  @override
  Future<CitizenBlockRef> getFinalizedHead() async => block(height);
  @override
  Future<CitizenBlockRef> getFinalizedBlockAt(BigInt number) async {
    if (number <= BigInt.zero || number > BigInt.from(height)) {
      throw StateError('高度越界');
    }
    return block(number.toInt());
  }

  @override
  Future<Uint8List?> getStorage(CitizenBlockRef block, Uint8List key) async {
    storageBlocks.add(block.number.toInt());
    if (missingTimestamp) return null;
    return (ByteData(8)
          ..setUint64(0, block.number.toInt() * 1000, Endian.little))
        .buffer
        .asUint8List();
  }

  @override
  Future<Uint8List?> getSystemEvents(CitizenBlockRef block) async {
    final number = block.number.toInt();
    eventBlocks.add(number);
    if (!eventEntered.isCompleted) eventEntered.complete();
    if (number == failEventsAt) throw StateError('合成区块暂时不可读');
    return eventBarrier == null
        ? encodedEvents[number]
        : await eventBarrier!.future;
  }

  @override
  Future<CitizenRuntimeContext> getRuntimeContext(
    CitizenBlockRef block,
  ) async => CitizenRuntimeContext(
    block: block,
    specVersion: 1,
    transactionVersion: 1,
    metadata: metadataBytes ?? _eventMetadata(),
  );
  @override
  Future<CitizenBlockBody> getBlockBody(CitizenBlockRef ref) async =>
      CitizenBlockBody(
        block: wrongBodyAnchor ? block(999) : ref,
        extrinsics: [
          Uint8List.fromList([4, 0]),
        ],
      );
}

/// 合成 V14 portable metadata；字段刻意共享 typeName，事件索引刻意不连续。
/// 使用依赖的 metadata 编码器生成字节，事件字节独立按 SCALE 布局编码，不调用生产适配器。
Uint8List _eventMetadata({
  int accountWrapperDepth = 1,
  bool cyclicAccountId = false,
  bool missingAccountId = false,
  bool recursiveEvent = false,
}) {
  metadata.Field field(String? name, int type, [String? typeName]) =>
      metadata.Field(name: name, type: type, typeName: typeName, docs: []);
  metadata.Variant variant(
    String name,
    int index,
    List<metadata.Field> fields,
  ) => metadata.Variant(name: name, index: index, fields: fields, docs: []);
  final definitions = <metadata.TypeDef>[
    const metadata.TypeDefPrimitive(metadata.Primitive.U8),
    const metadata.TypeDefPrimitive(metadata.Primitive.U32),
    const metadata.TypeDefPrimitive(metadata.Primitive.U128),
    const metadata.TypeDefArray(length: 32, type: 0),
    const metadata.TypeDefSequence(type: 0),
    metadata.TypeDefVariant(
      variants: [
        variant('ApplyExtrinsic', 0, [field(null, 1)]),
        variant('Finalization', 1, []),
        variant('Initialization', 2, []),
      ],
    ),
    metadata.TypeDefVariant(
      variants: [
        variant('Transfer', 3, [
          field('from', 3, 'T::AccountId'),
          field('to', 3, 'T::AccountId'),
          field('amount', 2, 'BalanceOf<T>'),
        ]),
      ],
    ),
    metadata.TypeDefVariant(
      variants: [
        variant('TransferWithRemark', 5, [
          field('from_account_id', 3, 'T::AccountId'),
          field('beneficiary_account_id', 3, 'T::AccountId'),
          field('amount', 2, 'BalanceOf<T>'),
          field('remark', 4, 'TransferRemarkOf<T>'),
        ]),
      ],
    ),
    metadata.TypeDefVariant(
      variants: [
        variant('ExtrinsicSuccess', 0, []),
        variant('ExtrinsicFailed', 1, []),
      ],
    ),
    metadata.TypeDefVariant(
      variants: [
        variant('System', 0, [field(null, 8)]),
        variant('Balances', 2, [field(null, 6)]),
        variant('OnchainTransaction', 4, [field(null, 7)]),
      ],
    ),
    const metadata.TypeDefSequence(type: 3),
    metadata.TypeDefComposite(
      fields: [field('phase', 5), field('event', 9), field('topics', 10)],
    ),
    const metadata.TypeDefSequence(type: 11),
    const metadata.TypeDefTuple([]),
  ];

  // 账户类型默认按 AccountId32 的透明包装形状生成，防止裸数组掩盖回归。
  for (var depth = 0; depth < accountWrapperDepth; depth++) {
    final inner = definitions.length;
    definitions.add(definitions[3]);
    definitions[3] = metadata.TypeDefComposite(fields: [field(null, inner)]);
  }
  if (cyclicAccountId) {
    final inner = definitions.length;
    definitions.add(metadata.TypeDefComposite(fields: [field(null, 3)]));
    definitions[3] = metadata.TypeDefComposite(fields: [field(null, inner)]);
  }
  if (missingAccountId) {
    definitions[3] = metadata.TypeDefComposite(fields: [field(null, 9999)]);
  }
  if (recursiveEvent) {
    // Node(Vec<Node>) 的递归经过序列长度，可用有限的嵌套空列表终止。
    final node = definitions.length;
    definitions.add(metadata.TypeDefComposite(fields: [field(null, node + 1)]));
    definitions.add(metadata.TypeDefSequence(type: node));
    final event = definitions[9] as metadata.TypeDefVariant;
    definitions[9] = metadata.TypeDefVariant(
      variants: [
        ...event.variants,
        variant('Tree', 9, [field(null, node)]),
      ],
    );
  }
  final runtime = metadata.RuntimeMetadataV14(
    types: [
      for (var i = 0; i < definitions.length; i++)
        metadata.PortableType(
          id: i,
          type: metadata.TypeMetadata(
            path: i == 9 ? ['RuntimeEvent'] : [],
            params: [],
            typeDef: definitions[i],
            docs: [],
          ),
        ),
    ],
    pallets: [
      metadata.PalletMetadataV14(
        name: 'System',
        index: 0,
        constants: [],
        storage: metadata.PalletStorageMetadata(
          prefix: 'System',
          entries: [
            metadata.StorageEntryMetadata(
              name: 'Events',
              modifier: metadata.StorageEntryModifier.default_,
              type: metadata.StorageEntryType(hashers: [], value: 12),
              defaultValue: [0],
              docs: [],
            ),
          ],
        ),
      ),
    ],
    extrinsic: metadata.ExtrinsicMetadataV14(
      type: 13,
      version: 4,
      signedExtensions: [],
      addressType: 3,
      callType: 13,
      signatureType: 3,
      extraType: 13,
    ),
    runtimeTypeId: 13,
    outerEnums: metadata.OuterEnumMetadata(
      callType: 13,
      eventType: 9,
      errorType: 13,
    ),
  );
  return Uint8List.fromList([
    0x6d,
    0x65,
    0x74,
    0x61,
    14,
    ...metadata.RuntimeMetadataV14.codec.encode(runtime),
  ]);
}

Uint8List _transferEvents({
  bool incoming = false,
  bool twice = false,
  bool failed = false,
  bool omitOutcome = false,
  bool remarkOnly = false,
  bool withTopics = false,
  bool recursiveEvent = false,
}) {
  final from = List.filled(32, incoming ? 0xbb : 0xaa);
  final to = List.filled(32, incoming ? 0xaa : 0xbb);
  final events = <List<int>>[];
  List<int> record(
    int pallet,
    int variant,
    List<int> payload, {
    bool topics = false,
  }) => [
    0,
    ...scale.U32Codec.codec.encode(0),
    pallet,
    variant,
    ...payload,
    ...scale.CompactCodec.codec.encode(topics ? 1 : 0),
    if (topics) ...List.filled(32, 0xcc),
  ];
  for (var i = 0; i < (twice ? 2 : 1); i++) {
    final transfer = [
      ...from,
      ...to,
      ...scale.U128Codec.codec.encode(BigInt.from(100)),
    ];
    if (!remarkOnly) events.add(record(2, 3, transfer, topics: withTopics));
    final remark = utf8.encode(i == 0 ? '合成备注' : '第二笔');
    events.add(
      record(4, 5, [
        ...transfer,
        ...scale.CompactCodec.codec.encode(remark.length),
        ...remark,
      ]),
    );
  }
  if (recursiveEvent) {
    // RuntimeEvent::Tree 包含两层单元素序列及空序列，无业务信息。
    events.add([0, ...scale.U32Codec.codec.encode(0), 9, 4, 4, 0, 0]);
  }
  if (!omitOutcome) events.add(record(0, failed ? 1 : 0, []));
  return Uint8List.fromList([
    ...scale.CompactCodec.codec.encode(events.length),
    ...events.expand((e) => e),
  ]);
}
