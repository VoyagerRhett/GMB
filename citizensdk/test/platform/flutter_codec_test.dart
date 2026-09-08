import 'dart:convert';

import 'package:citizen_sdk/src/api/citizen_sdk_error.dart';
import 'package:citizen_sdk/src/api/citizen_sdk_events.dart';
import 'package:citizen_sdk/src/models/citizen_capability.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = CitizenSdkFlutterCodec();

  test('QR公开文档严格闭集，拒绝旧now tuple、外部签名拼装和非法结果', () {
    final json = <String, Object?>{
      'kind': 2,
      'canonical_text': 'response',
      'request_id': 'request-identifier',
      'expires_at': 1700000000,
      'signer_account_id': _account(1),
      'signature': '0x${'ab' * 64}',
    };
    final document = codec.decodeQrDocument(jsonEncode(json));
    expect(document.signature, hasLength(64));
    expect(() => document.signature![0] = 1, throwsUnsupportedError);
    expect(
      () => codec.decodeQrDocument(
        jsonEncode(<String, Object?>{...json, 'private_key': 'forbidden'}),
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeQrDocument(
        jsonEncode(<String, Object?>{...json, 'signature': '0x01'}),
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeQrDocument(jsonEncode(json), signed: true),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.encodeRequest(
        method: 'qrParse',
        sessionId: 's',
        requestSequence: 1,
        fields: <Object?>['request', 10],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(CitizenSdkFlutterCodec.methods, isNot(contains('qrSigningInput')));
    expect(
      CitizenSdkFlutterCodec.methods,
      isNot(contains('qrCreateSignResponse')),
    );
    expect(CitizenSdkFlutterCodec.methods, isNot(contains('qrEncodeImage')));
  });

  test('历史通知只含 sequence，拒绝额外 payload 与无效顺序号', () {
    final decoded = codec.decodeEvent(<Object?>[
      1,
      'session',
      7,
      'historyChanged',
      <Object?>[],
    ]);
    expect(decoded.event, isA<CitizenSdkHistoryChanged>());
    expect(decoded.event.sequence, 7);
    expect(
      () => codec.decodeEvent(<Object?>[
        1,
        'session',
        8,
        'historyChanged',
        <Object?>[1],
      ]),
      throwsA(isA<Object>()),
    );
    expect(
      () => codec.decodeEvent(<Object?>[
        1,
        'session',
        0,
        'historyChanged',
        <Object?>[],
      ]),
      throwsA(isA<Object>()),
    );
  });

  test('五平台 Flutter 的固定方法使用固定长度 tuple 且没有 Map 兼容旁路', () {
    const expectedMethods = <String>{
      'open',
      'start',
      'stop',
      'close',
      'getCapabilities',
      'getFinalizedHead',
      'getGenesisHash',
      'getAccountBalance',
      'getAccountBalances',
      'getAccountNonce',
      'getFeeSnapshot',
      'getWalletProfile',
      'viewAccountPrivateKey',
      'createWallet',
      'importWallet',
      'addWalletAccounts',
      'setActiveWalletAccount',
      'renameWalletAccount',
      'deleteWalletAccount',
      'deleteWallet',
      'reconcileWalletCleanup',
      'signWalletPayload',
      'verifySignature',
      'transferWithRemark',
      'initializeFinalizedHistory',
      'syncFinalizedHistory',
      'qrParse',
      'qrCreateSignRequest',
      'qrConsumeSignResponse',
      'qrCancelSignRequest',
      'qrEncodeAccountId',
      'qrEncodeUserTransfer',
      'qrDecodeLuminance',
      'qrEncode',
      'qrScan',
      'signQrRequest',
    };
    expect(CitizenSdkFlutterCodec.methods, expectedMethods);
    expect(codec.encodeOpen(), <Object?>[1, CitizenSdkModules.full]);
    expect(codec.encodeOpen(CitizenSdkModules.signing), <Object?>[1, 2]);
    for (final invalid in <int>[0, -1, 0x100000000]) {
      expect(
        () => codec.encodeOpen(invalid),
        throwsA(isA<CitizenSdkException>()),
      );
    }

    final account = _account(1);
    final requestFields = <String, List<Object?>>{
      for (final method in <String>[
        'start',
        'stop',
        'close',
        'getCapabilities',
        'getFinalizedHead',
        'getGenesisHash',
        'getFeeSnapshot',
        'getWalletProfile',
        'importWallet',
        'deleteWallet',
        'reconcileWalletCleanup',
      ])
        method: const <Object?>[],
      for (final method in <String>[
        'getAccountBalance',
        'getAccountNonce',
        'viewAccountPrivateKey',
        'setActiveWalletAccount',
        'deleteWalletAccount',
      ])
        method: <Object?>[account],
      'getAccountBalances': <Object?>[
        <String>[account, account],
      ],
      'createWallet': const <Object?>[24],
      'addWalletAccounts': const <Object?>[
        <int>[1, 7],
      ],
      'renameWalletAccount': <Object?>[account, 'main'],
      'signWalletPayload': <Object?>[
        account,
        Uint8List.fromList(<int>[1]),
      ],
      'transferWithRemark': <Object?>[account, _account(2), '1', 'remark'],
      'initializeFinalizedHistory': <Object?>[
        <String>[account],
      ],
      'syncFinalizedHistory': <Object?>[
        <String>[account],
      ],
      'qrParse': <Object?>['{}'],
      'qrCreateSignRequest': <Object?>[
        0x0400,
        account,
        Uint8List.fromList(<int>[4, 0]),
        120,
      ],
      'qrConsumeSignResponse': <Object?>['{}'],
      'qrCancelSignRequest': <Object?>['abcdefghijklmnop'],
      'qrEncodeAccountId': <Object?>[account],
      'qrEncodeUserTransfer': <Object?>[
        'abcdefghijklmnop',
        10,
        account,
        '1',
        'CNY',
        '',
        'bank-1',
      ],
      'qrDecodeLuminance': <Object?>[
        Uint8List.fromList(<int>[0]),
        1,
        1,
        1,
      ],
      'qrEncode': <Object?>['{}', 4],
      'qrScan': <Object?>[],
      'signQrRequest': <Object?>['{}'],
    };
    expect(<String>{
      'open',
      'verifySignature',
      ...requestFields.keys,
    }, expectedMethods);
    expect(
      codec.encodeVerification(
        accountId: account,
        signature: Uint8List(64),
        payload: Uint8List(0),
      ),
      <Object?>[1, account, Uint8List(64), Uint8List(0)],
    );
    expect(
      () => codec.encodeRequest(
        method: 'verifySignature',
        sessionId: 's',
        requestSequence: 1,
        fields: <Object?>[account, Uint8List(64), Uint8List(0)],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(codec.decodeVerification(<Object?>[1, false]), isFalse);
    expect(codec.decodeVerification(<Object?>[1, true]), isTrue);
    for (final invalid in <Object?>[
      <Object?>[
        1,
        's',
        1,
        <Object?>[false],
      ],
      <Object?>[1, 0],
      <Object?>[1],
      <Object?>[1, false, null],
      <Object?>[2, false],
    ]) {
      expect(
        () => codec.decodeVerification(invalid),
        throwsA(isA<CitizenSdkException>()),
      );
    }
    for (final entry in requestFields.entries) {
      expect(
        codec.encodeRequest(
          method: entry.key,
          sessionId: 'session-a',
          requestSequence: 7,
          fields: entry.value,
        ),
        <Object?>[1, 'session-a', 7, ...entry.value],
      );
      expect(
        () => codec.encodeRequest(
          method: entry.key,
          sessionId: 'session-a',
          requestSequence: 8,
          fields: <Object?>[...entry.value, 'forbidden-extra-position'],
        ),
        throwsA(isA<CitizenSdkException>()),
      );
    }
    expect(
      () => codec.decodeEvent(<String, Object?>{'protocolVersion': 1}),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeResponse(
        method: 'close',
        raw: <Object?>[1, 'session-a', 1, <String, Object?>{}],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('Dart请求字段错误稳定为invalidArgument而响应错误仍为decode', () {
    expect(
      () => codec.encodeRequest(
        method: 'getAccountBalance',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: const <Object?>['bad-account'],
      ),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.invalidArgument,
        ),
      ),
    );
    expect(
      () => codec.encodeRequest(
        method: 'unknown',
        sessionId: 'session-a',
        requestSequence: 1,
      ),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.unsupported,
        ),
      ),
    );
    expect(
      () => codec.decodeResponse(
        method: 'getFinalizedHead',
        raw: const <Object?>[1, 'session-a', 1, <Object?>[]],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 1,
      ),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.decode,
        ),
      ),
    );
  });

  test('协议版本必须是精确整数且response、event、error均拒绝double', () {
    expect(
      () => codec.decodeResponse(
        method: 'close',
        raw: const <Object?>[
          1.0,
          'session-a',
          1,
          <Object?>['disposed'],
        ],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeEvent(const <Object?>[
        1.0,
        'session-a',
        1,
        'lifecycleChanged',
        <Object?>['running'],
      ]),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodePlatformException(
        PlatformException(
          code: 'citizensdk.cancelled',
          details: const <Object?>[1.0, 'session-a', 1, 22, 'cancelled'],
        ),
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('sessionId在请求、响应、事件和错误外壳统一为1..128个code unit', () {
    final exactUnicodeBoundary = List<String>.filled(64, '🛰️').join();
    // Each satellite is three UTF-16 code units (surrogate pair + VS16), so
    // use a two-code-unit scalar to exercise the exact shared boundary.
    final exactSurrogateBoundary = List<String>.filled(64, '🌍').join();
    expect(exactUnicodeBoundary.length, greaterThan(128));
    expect(exactSurrogateBoundary.length, 128);
    expect(
      codec.encodeRequest(
        method: 'close',
        sessionId: exactSurrogateBoundary,
        requestSequence: 1,
      ),
      <Object?>[1, exactSurrogateBoundary, 1],
    );
    expect(
      () => codec.encodeRequest(
        method: 'close',
        sessionId: exactUnicodeBoundary,
        requestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    final tooLong = List<String>.filled(
      CitizenSdkFlutterCodec.maximumSessionIdCodeUnits + 1,
      's',
    ).join();
    expect(
      () => codec.encodeRequest(
        method: 'close',
        sessionId: tooLong,
        requestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeResponse(
        method: 'close',
        raw: <Object?>[
          1,
          tooLong,
          1,
          const <Object?>['disposed'],
        ],
        expectedSessionId: null,
        expectedRequestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodeEvent(<Object?>[
        1,
        tooLong,
        1,
        'lifecycleChanged',
        const <Object?>['running'],
      ]),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.decodePlatformException(
        PlatformException(
          code: 'citizensdk.cancelled',
          details: <Object?>[1, tooLong, 1, 22, 'cancelled'],
        ),
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('创世哈希和批量余额响应使用既有session外壳并拒绝非法公开值', () {
    final genesis = codec.decodeResponse(
      method: 'getGenesisHash',
      raw: <Object?>[
        1,
        's',
        1,
        <Object?>[_account(9)],
      ],
      expectedSessionId: 's',
      expectedRequestSequence: 1,
    );
    expect(genesis.value.single, _account(9));
    for (final invalid in <Object?>[
      'invalid',
      _account(9).toUpperCase(),
      null,
    ]) {
      expect(
        () => codec.decodeResponse(
          method: 'getGenesisHash',
          raw: <Object?>[
            1,
            's',
            1,
            <Object?>[invalid],
          ],
          expectedSessionId: 's',
          expectedRequestSequence: 1,
        ),
        throwsA(isA<CitizenSdkException>()),
      );
    }
    expect(codec.decodeBalances(<Object?>[]), isEmpty);
    final balance = <Object?>[_account(1), _block(9), '1', '0', '1'];
    expect(codec.decodeBalances(<Object?>[balance, balance]), hasLength(2));
    for (final invalid in <Object?>[
      <Object?>[
        balance,
        <Object?>[_account(1), _block(10), '1', '0', '1'],
      ],
      <Object?>[
        <Object?>[_account(1), _block(9), '1', '0', '2'],
      ],
      List<Object?>.filled(1991, balance),
    ]) {
      expect(
        () => codec.decodeBalances(invalid),
        throwsA(isA<CitizenSdkException>()),
      );
    }
  });

  test('响应严格校验 session、request sequence、长度和整数规范形式', () {
    final valid = <Object?>[
      1,
      'session-a',
      3,
      <Object?>[_block(9)],
    ];
    final decoded = codec.decodeResponse(
      method: 'getFinalizedHead',
      raw: valid,
      expectedSessionId: 'session-a',
      expectedRequestSequence: 3,
    );
    expect(codec.decodeBlock(decoded.value[0]).number, BigInt.from(9));

    for (final invalid in <Object?>[
      <Object?>[
        1,
        'other',
        3,
        <Object?>[_block(9)],
      ],
      <Object?>[
        1,
        'session-a',
        4,
        <Object?>[_block(9)],
      ],
      <Object?>[
        1,
        'session-a',
        3,
        <Object?>[_block(9)],
        null,
      ],
    ]) {
      expect(
        () => codec.decodeResponse(
          method: 'getFinalizedHead',
          raw: invalid,
          expectedSessionId: 'session-a',
          expectedRequestSequence: 3,
        ),
        throwsA(isA<CitizenSdkException>()),
      );
    }
    expect(
      () => codec.decodeResponse(
        method: 'getAccountBalance',
        raw: <Object?>[
          1,
          'session-a',
          3,
          <Object?>[
            <Object?>[_account(3), _block(9), '01', '0', '1'],
          ],
        ],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 3,
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('事件与错误使用独立固定 tuple 并拒绝未知枚举', () {
    final lifecycle = codec.decodeEvent(<Object?>[
      1,
      'session-a',
      1,
      'lifecycleChanged',
      <Object?>['running'],
    ]);
    expect(lifecycle.sessionId, 'session-a');
    expect(lifecycle.eventSequence, 1);

    final finalized = codec.decodeEvent(<Object?>[
      1,
      'session-a',
      2,
      'transferProgress',
      <Object?>[9, 'finalized', _block(10), null, 0],
    ]);
    expect(finalized.eventSequence, 2);
    expect(
      (finalized.event as CitizenSdkTransferProgress).status,
      CitizenTransferProgressStatus.finalized,
    );
    final invalid = codec.decodeEvent(<Object?>[
      1,
      'session-a',
      3,
      'transferProgress',
      const <Object?>[9, 'invalid', null, null, 0],
    ]);
    expect(
      (invalid.event as CitizenSdkTransferProgress).status,
      CitizenTransferProgressStatus.invalid,
    );
    final usurped = codec.decodeEvent(<Object?>[
      1,
      'session-a',
      4,
      'transferProgress',
      <Object?>[9, 'usurped', null, _account(8), 0],
    ]);
    expect(
      (usurped.event as CitizenSdkTransferProgress).status,
      CitizenTransferProgressStatus.usurped,
    );

    expect(
      () => codec.decodeEvent(<Object?>[
        1,
        'session-a',
        2,
        'unknown',
        const <Object?>[],
      ]),
      throwsA(isA<CitizenSdkException>()),
    );

    final exception = codec.decodePlatformException(
      PlatformException(
        code: 'citizensdk.authenticationCancelled',
        details: <Object?>[1, 'session-a', 8, 10, '用户取消'],
      ),
    );
    expect(exception.code, CitizenSdkErrorCode.authenticationCancelled);
    expect(exception.requestSequence, 8);
  });

  test('进程级事件先按session路由，foreign坏payload被忽略而本session失败关闭', () {
    final foreign = <Object?>[
      1,
      'foreign-session',
      'bad-sequence',
      'unknown',
      <Object?>[
        <String, Object?>{'forbidden': true},
      ],
    ];
    expect(codec.decodeEventForSession(foreign, 'session-a'), isNull);
    expect(
      () => codec.decodeEventForSession(<Object?>[
        1,
        'session-a',
        1,
        'unknown',
        <Object?>[
          <String, Object?>{'forbidden': true},
        ],
      ], 'session-a'),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('公开 bytes 只接受 Uint8List，签名严格为 64 字节', () {
    expect(
      codec.encodeRequest(
        method: 'signWalletPayload',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: <Object?>[_account(1), Uint8List(0)],
      ),
      <Object?>[1, 'session-a', 1, _account(1), Uint8List(0)],
    );
    final response = codec.decodeResponse(
      method: 'signWalletPayload',
      raw: <Object?>[
        1,
        'session-a',
        1,
        <Object?>[Uint8List(64)],
      ],
      expectedSessionId: 'session-a',
      expectedRequestSequence: 1,
    );
    expect(response.value.single, isA<Uint8List>());
    expect(
      () => codec.decodeResponse(
        method: 'signWalletPayload',
        raw: <Object?>[
          1,
          'session-a',
          2,
          <Object?>[List<int>.filled(64, 0)],
        ],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 2,
      ),
      throwsA(isA<CitizenSdkException>()),
    );

    expect(
      () => codec.encodeRequest(
        method: 'signWalletPayload',
        sessionId: 'session-a',
        requestSequence: 3,
        fields: <Object?>[
          _account(1),
          Uint8List(CitizenSdkFlutterCodec.maximumSigningPayloadBytes + 1),
        ],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('history 在复制 accountId 前拒绝超过 1990 个账户', () {
    expect(
      () => codec.encodeRequest(
        method: 'syncFinalizedHistory',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: <Object?>[
          List<Object?>.filled(
            CitizenSdkFlutterCodec.maximumHistoryAccounts + 1,
            _account(1),
            growable: false,
          ),
        ],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('add与十进制在逐项转换前执行固定资源上限', () {
    expect(
      () => codec.encodeRequest(
        method: 'addWalletAccounts',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: <Object?>[
          List<int>.filled(
            CitizenSdkFlutterCodec.maximumAdditionalWalletAccounts + 1,
            1,
            growable: false,
          ),
        ],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(
      () => codec.encodeRequest(
        method: 'transferWithRemark',
        sessionId: 'session-a',
        requestSequence: 2,
        fields: <Object?>[
          _account(1),
          _account(2),
          List<String>.filled(40, '1').join(),
          '',
        ],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('账户名只编码已修剪的 1..30 个 Unicode scalar', () {
    expect(
      codec.encodeRequest(
        method: 'renameWalletAccount',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: <Object?>[_account(1), '旅行钱包'],
      ),
      <Object?>[1, 'session-a', 1, _account(1), '旅行钱包'],
    );
    for (final name in <String>[
      ' 旅行钱包',
      '旅行钱包 ',
      '   ',
      for (var scalar = 0x1c; scalar <= 0x1f; scalar++)
        '钱包${String.fromCharCode(scalar)}',
      List<String>.filled(31, '旅').join(),
      List<String>.filled(129, 'a').join(),
    ]) {
      expect(
        () => codec.encodeRequest(
          method: 'renameWalletAccount',
          sessionId: 'session-a',
          requestSequence: 1,
          fields: <Object?>[_account(1), name],
        ),
        throwsA(isA<CitizenSdkException>()),
      );
    }
    expect(
      () => codec.encodeRequest(
        method: 'addWalletAccounts',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: const <Object?>[
          <int>[0],
        ],
      ),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('finalized head与能力状态逐项重建Rust值对象不变量', () {
    expect(
      () => codec.decodeResponse(
        method: 'getFinalizedHead',
        raw: <Object?>[
          1,
          'session-a',
          1,
          <Object?>[
            <Object?>[_account(1), '1', 'best'],
          ],
        ],
        expectedSessionId: 'session-a',
        expectedRequestSequence: 1,
      ),
      throwsA(isA<CitizenSdkException>()),
    );

    final valid = _capabilities();
    expect(codec.decodeCapabilities(valid).statuses, hasLength(10));
    final invalid = _capabilities();
    final statuses = invalid[1]! as List<Object?>;
    statuses[0] = <Object?>[
      CitizenCapabilityName.chainRead.name,
      true,
      true,
      true,
      false,
      'none',
    ];
    expect(
      () => codec.decodeCapabilities(invalid),
      throwsA(isA<CitizenSdkException>()),
    );

    expect(
      () => codec.decodeFeeSnapshot(<Object?>[
        <Object?>[_account(1), '1', 'best'],
        1,
        '0',
        '0',
      ]),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('wallet profile拒绝与AccountId不一致的CitizenChain SS58地址', () {
    final account = _account(1);
    expect(
      () => codec.decodeWalletProfile(<Object?>[
        0,
        'created',
        '1',
        account,
        account,
        <Object?>[
          <Object?>[0, account, 'wrong-address', '账户0', '1', true],
        ],
      ]),
      throwsA(isA<CitizenSdkException>()),
    );
  });

  test('history严格校验游标、记录、finalized转账和复合键', () {
    expect(codec.decodeHistory(_history()).records, hasLength(1));

    final regressedCursor = _history();
    final cursors = regressedCursor[1]! as List<Object?>;
    final cursor = cursors.single! as List<Object?>;
    cursor[2] = _block(0);
    expect(
      () => codec.decodeHistory(regressedCursor),
      throwsA(isA<CitizenSdkException>()),
    );

    final invalidRecord = _history();
    final records = invalidRecord[2]! as List<Object?>;
    final record = records.single! as List<Object?>;
    record[4] = '0';
    expect(
      () => codec.decodeHistory(invalidRecord),
      throwsA(isA<CitizenSdkException>()),
    );

    final invalidTransfer = _history();
    final transfers = invalidTransfer[3]! as List<Object?>;
    final transfer = transfers.single! as List<Object?>;
    transfer[7] = 'incoming';
    expect(
      () => codec.decodeHistory(invalidTransfer),
      throwsA(isA<CitizenSdkException>()),
    );

    final duplicate = _history();
    final duplicateCursors = duplicate[1]! as List<Object?>;
    duplicateCursors.add(List<Object?>.from(duplicateCursors.single! as List));
    expect(
      () => codec.decodeHistory(duplicate),
      throwsA(isA<CitizenSdkException>()),
    );
  });
}

String _account(int byte) =>
    '0x${List<String>.filled(32, byte.toRadixString(16).padLeft(2, '0')).join()}';

List<Object?> _block(int number) => <Object?>[
  _account(number),
  '$number',
  'finalized',
];

List<Object?> _capabilities() => <Object?>[
  '1',
  <Object?>[
    for (final name in CitizenCapabilityName.values)
      <Object?>[name.name, true, true, true, true, 'none'],
  ],
];

List<Object?> _history() => <Object?>[
  '1',
  <Object?>[
    <Object?>[_account(1), _block(1), _block(2)],
  ],
  <Object?>[
    <Object?>[
      _account(1),
      _account(9),
      '0',
      _account(2),
      '1',
      'pending',
      null,
      null,
      '1',
      '1',
      '',
      null,
    ],
  ],
  <Object?>[
    <Object?>[
      _account(1),
      _account(1),
      _account(2),
      '1',
      _block(2),
      0,
      0,
      'outgoing',
      'OnchainTransaction',
      '',
      Uint8List(0),
    ],
  ],
];
