import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _TransactionPlatform platform;

  setUp(() {
    platform = _TransactionPlatform();
    CitizenSdkPlatform.instance = platform;
  });

  tearDown(() async {
    CitizenSdkPlatform.instance = null;
    await platform.dispose();
  });

  test('转账只传公开业务字段并返回Runtime终态', () async {
    final sdk = await CitizenSdk.open();
    final transfer = await sdk.transactions.transferWithRemark(
      sourceAccountId: _account(1),
      destinationAccountId: _account(2),
      amountFen: BigInt.from(123),
      remark: '午餐',
    );

    expect(transfer.resolution, CitizenTransferResolution.finalizedSuccess);
    expect(transfer.execution?.status, CitizenExecutionStatus.success);
    expect(platform.lastArguments, <Object?>[
      1,
      'session-a',
      1,
      _account(1),
      _account(2),
      '123',
      '午餐',
    ]);
    await sdk.close();
  });

  test('finalized历史以账户闭集显式初始化和增量同步', () async {
    final sdk = await CitizenSdk.open();
    final initialized = await sdk.history.initializeFinalizedHistory(<String>[
      _account(1),
    ]);
    final synced = await sdk.history.syncFinalizedHistory(<String>[
      _account(1),
    ]);

    expect(initialized.revision, BigInt.one);
    expect(synced.revision, BigInt.from(2));
    expect(platform.historyMethods, <String>[
      'initializeFinalizedHistory',
      'syncFinalizedHistory',
    ]);
    await sdk.close();
  });

  test('交易公开API在字符串化、UTF-8编码和列表复制前拒绝超界输入', () async {
    final sdk = await CitizenSdk.open();
    final invalid = isA<CitizenSdkException>().having(
      (error) => error.code,
      'code',
      CitizenSdkErrorCode.invalidArgument,
    );

    await expectLater(
      sdk.transactions.transferWithRemark(
        sourceAccountId: _account(1),
        destinationAccountId: _account(2),
        amountFen: BigInt.zero,
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.transactions.transferWithRemark(
        sourceAccountId: _account(1),
        destinationAccountId: _account(2),
        amountFen: BigInt.one << 128,
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.transactions.transferWithRemark(
        sourceAccountId: _account(1),
        destinationAccountId: _account(2),
        amountFen: BigInt.one,
        remark: List<String>.filled(34, '旅').join(),
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.history.initializeFinalizedHistory(const <String>[]),
      throwsA(invalid),
    );
    await expectLater(
      sdk.history.syncFinalizedHistory(
        List<String>.filled(1991, _account(1), growable: false),
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.history.syncFinalizedHistory(<String>[_account(1), _account(1)]),
      throwsA(invalid),
    );
    expect(platform.historyMethods, isEmpty);
    expect(platform.lastArguments, isNull);
    await sdk.close();
  });
}

final class _TransactionPlatform implements CitizenSdkPlatform {
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  final List<String> historyMethods = <String>[];
  List<Object?>? lastArguments;

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    if (method == 'open') {
      return <Object?>[
        1,
        'session-a',
        0,
        <Object?>['created', 1],
      ];
    }
    final sequence = arguments[2]! as int;
    if (method == 'transferWithRemark') lastArguments = arguments;
    if (method == 'initializeFinalizedHistory' ||
        method == 'syncFinalizedHistory') {
      historyMethods.add(method);
    }
    final value = switch (method) {
      'transferWithRemark' => <Object?>[_transfer()],
      'initializeFinalizedHistory' => <Object?>[_history('1')],
      'syncFinalizedHistory' => <Object?>[_history('2')],
      'close' => <Object?>['disposed'],
      _ => throw StateError('未预期 method：$method'),
    };
    return <Object?>[1, 'session-a', sequence, value];
  }

  Future<void> dispose() => _events.close();
}

List<Object?> _transfer() => <Object?>[
  _account(9),
  'finalizedSuccess',
  <Object?>['success', _block(), 2, null, null, null],
  null,
];

List<Object?> _history(String revision) => <Object?>[
  revision,
  const <Object?>[],
  const <Object?>[],
  const <Object?>[],
];

List<Object?> _block() => <Object?>[_account(3), '8', 'finalized'];

String _account(int byte) =>
    '0x${List<String>.filled(32, byte.toRadixString(16).padLeft(2, '0')).join()}';
