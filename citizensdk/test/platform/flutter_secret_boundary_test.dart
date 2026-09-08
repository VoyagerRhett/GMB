import 'dart:typed_data';

import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = CitizenSdkFlutterCodec();

  test('五平台Flutter create/import/add只携带公开流程选择，不存在秘密字段槽', () {
    expect(
      codec.encodeRequest(
        method: 'createWallet',
        sessionId: 'session-a',
        requestSequence: 1,
        fields: const <Object?>[12],
      ),
      <Object?>[1, 'session-a', 1, 12],
    );
    expect(
      codec.encodeRequest(
        method: 'importWallet',
        sessionId: 'session-a',
        requestSequence: 2,
      ),
      <Object?>[1, 'session-a', 2],
    );
    expect(
      codec.encodeRequest(
        method: 'addWalletAccounts',
        sessionId: 'session-a',
        requestSequence: 3,
        fields: const <Object?>[
          <int>[1, 2],
        ],
      ),
      <Object?>[
        1,
        'session-a',
        3,
        const <int>[1, 2],
      ],
    );
  });

  test('安全查看没有秘密响应槽，拒绝错误账户及额外输入', () {
    final fields = <Object?>[_account(1)];
    expect(
      codec.encodeRequest(
        method: 'viewAccountPrivateKey',
        sessionId: 's',
        requestSequence: 1,
        fields: fields,
      ),
      <Object?>[1, 's', 1, _account(1)],
    );
    for (final invalid in <List<Object?>>[
      <Object?>[],
      <Object?>['account'],
      <Object?>[_account(1), Uint8List(32)],
    ]) {
      expect(
        () => codec.encodeRequest(
          method: 'viewAccountPrivateKey',
          sessionId: 's',
          requestSequence: 1,
          fields: invalid,
        ),
        throwsException,
      );
    }
    expect(
      codec
          .decodeResponse(
            method: 'viewAccountPrivateKey',
            raw: <Object?>[1, 's', 1, <Object?>[]],
            expectedSessionId: 's',
            expectedRequestSequence: 1,
          )
          .value,
      isEmpty,
    );
    for (final invalid in <List<Object?>>[
      <Object?>[Uint8List(32)],
      <Object?>[1],
      <Object?>[null],
      <Object?>[
        <String, Object?>{'privateKey': Uint8List(32)},
      ],
    ]) {
      expect(
        () => codec.decodeResponse(
          method: 'viewAccountPrivateKey',
          raw: <Object?>[1, 's', 1, invalid],
          expectedSessionId: 's',
          expectedRequestSequence: 1,
        ),
        throwsException,
      );
    }
  });

  test('sign只传公开账户和消息副本，返回公开64字节签名', () {
    final payload = Uint8List.fromList(<int>[1, 2, 3]);
    final request = codec.encodeRequest(
      method: 'signWalletPayload',
      sessionId: 'session-a',
      requestSequence: 1,
      fields: <Object?>[_account(1), payload],
    );
    expect(request, hasLength(5));
    expect(request[3], _account(1));
    expect(request[4], payload);

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
    expect(response.value, hasLength(1));
  });

  test('任意层Map都失败关闭，不能构造秘密或句柄旁路', () {
    for (final map in <Map<String, Object?>>[
      <String, Object?>{'mnemonic': 'secret'},
      <String, Object?>{'password': 'secret'},
      <String, Object?>{'nativeHandle': 1},
      <String, Object?>{'resultHandle': 1},
      <String, Object?>{'signedExtrinsic': Uint8List(1)},
    ]) {
      expect(
        () => codec.decodeEvent(<Object?>[
          1,
          'session-a',
          1,
          'lifecycleChanged',
          <Object?>[map],
        ]),
        throwsException,
      );
    }
  });
}

String _account(int byte) =>
    '0x${List<String>.filled(32, byte.toRadixString(16).padLeft(2, '0')).join()}';
