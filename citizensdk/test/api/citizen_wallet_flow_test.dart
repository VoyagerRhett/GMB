import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizen_sdk/src/crypto/account_codec.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _WalletPlatform platform;

  setUp(() {
    platform = _WalletPlatform();
    CitizenSdkPlatform.instance = platform;
  });

  tearDown(() async {
    CitizenSdkPlatform.instance = null;
    await platform.dispose();
  });

  test('create/import/add只启动原生安全流程并返回公开profile', () async {
    final sdk = await CitizenSdk.open();
    final created = await sdk.wallet.create(
      wordCount: CitizenWalletWordCount.words24,
    );
    final imported = await sdk.wallet.importWallet();
    final expanded = await sdk.wallet.addAccounts(const <int>[1, 2]);

    expect(created.origin, CitizenWalletOrigin.created);
    expect(imported.origin, CitizenWalletOrigin.imported);
    expect(expanded.accounts, hasLength(3));
    expect(platform.argumentsByMethod['createWallet'], <Object?>[
      1,
      'session-a',
      1,
      24,
    ]);
    expect(platform.argumentsByMethod['importWallet'], <Object?>[
      1,
      'session-a',
      2,
    ]);
    expect(platform.argumentsByMethod['addWalletAccounts'], <Object?>[
      1,
      'session-a',
      3,
      const <int>[1, 2],
    ]);
    await sdk.close();
  });

  test('三种助记词数量使用准确数值且默认十二词，不向Dart传递秘密', () async {
    expect(CitizenWalletWordCount.values.map((value) => value.value), [
      12,
      18,
      24,
    ]);
    final sdk = await CitizenSdk.open();
    await sdk.wallet.create();
    expect(platform.argumentsByMethod['createWallet']!.last, 12);
    for (final count in CitizenWalletWordCount.values) {
      await sdk.wallet.create(wordCount: count);
      final request = platform.argumentsByMethod['createWallet']!;
      expect(request, hasLength(4));
      expect(request.last, count.value);
    }
    await sdk.close();
  });

  test('原生输入合同拒绝十五词、二十一词及任意其他数量', () {
    const codec = CitizenSdkFlutterCodec();
    for (final count in [0, 11, 15, 21, 25]) {
      expect(
        () => codec.encodeRequest(
          method: 'createWallet',
          sessionId: 'session-a',
          requestSequence: 1,
          fields: [count],
        ),
        throwsA(
          isA<CitizenSdkException>().having(
            (error) => error.code,
            'code',
            CitizenSdkErrorCode.invalidArgument,
          ),
        ),
      );
    }
  });

  test('签名模块独立选择而不合并钱包门面', () async {
    final sdk = await CitizenSdk.open(modules: CitizenSdkModules.signing);
    expect(platform.argumentsByMethod['open'], <Object?>[1, 2]);
    expect(sdk.signing, isA<CitizenSigning>());
    await sdk.close();
  });

  test('私钥查看只传账户，等真实完成后返回void，不提前结束', () async {
    final sdk = await CitizenSdk.open(modules: CitizenSdkModules.wallet);
    platform.viewCompletion = Completer<void>();
    var completed = false;
    final Future<void> viewing = sdk.wallet.viewAccountPrivateKey(_account(1));
    final completion = viewing.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(platform.argumentsByMethod['viewAccountPrivateKey'], <Object?>[
      1,
      'session-a',
      1,
      _account(1),
    ]);
    platform.viewCompletion!.complete();
    await completion;
    expect(completed, isTrue);
    await sdk.close();
  });

  test('私钥查看拒绝额外响应槽，取消和认证失败保留原错误', () async {
    final sdk = await CitizenSdk.open(modules: CitizenSdkModules.wallet);
    platform.viewResponse = <Object?>[Uint8List(32)];
    await expectLater(
      sdk.wallet.viewAccountPrivateKey(_account(1)),
      throwsA(isA<CitizenSdkException>()),
    );
    platform.viewResponse = null;
    for (final code in <CitizenSdkErrorCode>[
      CitizenSdkErrorCode.cancelled,
      CitizenSdkErrorCode.unavailable,
    ]) {
      platform.viewError = CitizenSdkException(
        code: code,
        message: '原生安全流程未完成',
      );
      await expectLater(
        sdk.wallet.viewAccountPrivateKey(_account(1)),
        throwsA(
          isA<CitizenSdkException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }
    platform.viewError = null;
    await sdk.close();
  });

  test('未open纯验签无需事件订阅或任何会话资源，原生true/false原样返回', () async {
    for (final valid in <bool>[false, true]) {
      platform.verificationResult = valid;
      expect(
        await CitizenSigning.verify(
          accountId: _account(1),
          signature: Uint8List(64),
          payload: Uint8List(0),
        ),
        valid,
      );
    }
    expect(platform.argumentsByMethod.keys, <String>['verifySignature']);
    expect(platform.argumentsByMethod['verifySignature'], <Object?>[
      1,
      _account(1),
      Uint8List(64),
      Uint8List(0),
    ]);
    expect(platform.eventReads, 0);
    await expectLater(
      CitizenSigning.verify(
        accountId: _account(1),
        signature: Uint8List(63),
        payload: Uint8List(0),
      ),
      throwsA(isA<CitizenSdkException>()),
    );
    expect(platform.eventReads, 0);
    expect(platform.verificationCalls, 2);
  });

  test('sign消息使用临时副本并仅返回公开sr25519签名', () async {
    final sdk = await CitizenSdk.open();
    final callerPayload = Uint8List.fromList(<int>[1, 2, 3]);
    final signature = await sdk.signing.sign(
      accountId: _account(1),
      payload: callerPayload,
    );

    expect(callerPayload, <int>[1, 2, 3]);
    expect(signature.bytes, hasLength(64));
    expect(platform.borrowedPayloadAfterReturn, everyElement(0));
    await sdk.close();
  });

  test('空签名载荷有效且账户名在编码前统一修剪', () async {
    final sdk = await CitizenSdk.open();
    await sdk.signing.sign(accountId: _account(1), payload: Uint8List(0));
    await sdk.wallet.renameAccount(accountId: _account(1), name: '  旅行钱包  ');

    expect(
      platform.argumentsByMethod['signWalletPayload']![4],
      isA<Uint8List>().having((value) => value.length, 'length', 0),
    );
    expect(platform.argumentsByMethod['renameAccount']![4], '旅行钱包');
    await sdk.close();
  });

  test('统一钱包状态包含冷热账户且默认账户只从首项读取', () async {
    final sdk = await CitizenSdk.open();
    final initial = await sdk.wallet.getState();
    final imported = await sdk.wallet.importColdAccount(
      accountId: _account(2),
      name: '  冷钱包  ',
    );
    final reordered = await sdk.wallet.reorderAccountsWithoutDefaultChange(
      expectedRevision: imported.revision,
      accountIds: <String>[_account(1), _account(2)],
    );
    final renamed = await sdk.wallet.renameAccount(
      accountId: _account(2),
      name: '离线签名',
    );
    final deleted = await sdk.wallet.deleteAccount(_account(2));

    expect(initial.defaultAccount?.accountId, _account(1));
    expect(imported.accounts.last.signMode, CitizenWalletSignMode.cold);
    expect(reordered.defaultAccount?.accountId, _account(1));
    expect(renamed.accounts.last.name, '离线签名');
    expect(deleted.accounts, hasLength(1));
    expect(platform.argumentsByMethod['importColdAccountId']![4], '冷钱包');
    expect(
      platform.argumentsByMethod['reorderWalletAccountsWithoutDefaultChange']!
          .sublist(3),
      <Object?>[
        '2',
        <String>[_account(1), _account(2)],
      ],
    );
    await sdk.close();
  });

  test('钱包公开API在复制或递增请求序号前拒绝超界输入', () async {
    final sdk = await CitizenSdk.open();
    final invalid = isA<CitizenSdkException>().having(
      (error) => error.code,
      'code',
      CitizenSdkErrorCode.invalidArgument,
    );

    await expectLater(
      sdk.wallet.addAccounts(
        List<int>.filled(
          CitizenSdkFlutterCodec.maximumAdditionalWalletAccounts + 1,
          1,
          growable: false,
        ),
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.signing.sign(
        accountId: _account(1),
        payload: Uint8List(
          CitizenSdkFlutterCodec.maximumSigningPayloadBytes + 1,
        ),
      ),
      throwsA(invalid),
    );
    await expectLater(
      sdk.wallet.renameAccount(
        accountId: _account(1),
        name: List<String>.filled(129, 'a').join(),
      ),
      throwsA(invalid),
    );
    // Opening the session is expected; every rejected wallet operation must
    // fail before it allocates a request sequence or reaches the platform.
    expect(platform.argumentsByMethod.keys.toList(), <String>['open']);
    await sdk.close();
  });

  test('delete返回null profile且不能把秘密放入Dart响应', () async {
    final sdk = await CitizenSdk.open();
    await sdk.wallet.delete();
    expect(platform.argumentsByMethod['deleteWallet'], hasLength(3));
    await sdk.close();
  });
}

final class _WalletPlatform implements CitizenSdkPlatform {
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  final Map<String, List<Object?>> argumentsByMethod =
      <String, List<Object?>>{};
  Uint8List? borrowedPayloadAfterReturn;
  int eventReads = 0;
  int verificationCalls = 0;
  bool verificationResult = false;
  Completer<void>? viewCompletion;
  CitizenSdkException? viewError;
  List<Object?>? viewResponse;

  @override
  Stream<Object?> get events {
    eventReads += 1;
    return _events.stream;
  }

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    argumentsByMethod[method] = arguments;
    if (method == 'open') {
      return <Object?>[
        1,
        'session-a',
        0,
        <Object?>['created', 1],
      ];
    }
    if (method == 'verifySignature') {
      verificationCalls += 1;
      return <Object?>[1, verificationResult];
    }
    final sequence = arguments[2]! as int;
    if (method == 'viewAccountPrivateKey') {
      await viewCompletion?.future;
      final error = viewError;
      if (error != null) {
        throw CitizenSdkException(
          code: error.code,
          message: error.message,
          sessionId: 'session-a',
          requestSequence: sequence,
        );
      }
      return <Object?>[1, 'session-a', sequence, viewResponse ?? <Object?>[]];
    }
    final value = switch (method) {
      'createWallet' => <Object?>[_profile('created', 1)],
      'importWallet' => <Object?>[_profile('imported', 1)],
      'addWalletAccounts' => <Object?>[_profile('imported', 3)],
      'signWalletPayload' => <Object?>[Uint8List(64)],
      'getWalletState' => <Object?>[_state(includeCold: false, revision: 1)],
      'importColdAccountId' => <Object?>[
        _state(includeCold: true, revision: 2),
      ],
      'reorderWalletAccountsWithoutDefaultChange' => <Object?>[
        _state(includeCold: true, revision: 3),
      ],
      'renameAccount' => <Object?>[
        _state(includeCold: true, revision: 4, coldName: '离线签名'),
      ],
      'deleteAccount' => <Object?>[_state(includeCold: false, revision: 5)],
      'deleteWallet' => const <Object?>[null],
      'close' => <Object?>['disposed'],
      _ => throw StateError('未预期 method：$method'),
    };
    if (method == 'signWalletPayload') {
      borrowedPayloadAfterReturn = arguments[4]! as Uint8List;
    }
    return <Object?>[1, 'session-a', sequence, value];
  }

  Future<void> dispose() => _events.close();
}

List<Object?> _profile(String origin, int accountCount) {
  final accounts = List<List<Object?>>.generate(accountCount, (index) {
    final accountId = _account(index + 1);
    return <Object?>[
      index,
      accountId,
      citizenSs58FromAccountId(accountId),
      '账户$index',
      '${index + 1}',
      index == 0,
    ];
  });
  return <Object?>[0, origin, '1', _account(1), _account(1), accounts];
}

List<Object?> _state({
  required bool includeCold,
  required int revision,
  String coldName = '冷钱包',
}) {
  final hot = _profile('created', 1);
  return <Object?>[
    '$revision',
    hot,
    <Object?>[
      <Object?>[
        'hot',
        0,
        0,
        _account(1),
        citizenSs58FromAccountId(_account(1)),
        '账户0',
        '1',
        true,
      ],
      if (includeCold)
        <Object?>[
          'cold',
          1,
          null,
          _account(2),
          citizenSs58FromAccountId(_account(2)),
          coldName,
          '2',
          false,
        ],
    ],
  ];
}

String _account(int byte) =>
    '0x${List<String>.filled(32, byte.toRadixString(16).padLeft(2, '0')).join()}';
