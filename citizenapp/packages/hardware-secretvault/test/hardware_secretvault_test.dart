import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmb_hardware_secretvault/hardware_secretvault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gmb/hardware_secretvault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('AAD 同时绑定产品、钱包作用域、AccountId 与机密类型', () {
    final first = HardwareSecretContext(
      product: 'citizenapp',
      scope: '1',
      accountId: '0x${'11' * 32}',
      secretType: HardwareSecretType.accountMiniSecret,
    ).associatedData();
    final second = HardwareSecretContext(
      product: 'citizenapp',
      scope: '1',
      accountId: '0x${'22' * 32}',
      secretType: HardwareSecretType.accountMiniSecret,
    ).associatedData();
    expect(second, isNot(orderedEquals(first)));
  });

  test('原生通道只收发字节数组', () async {
    late MethodCall observed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      observed = call;
      return Uint8List.fromList(<int>[9, 8, 7]);
    });
    final vault = HardwareSecretvault(channel: channel);
    final context = HardwareSecretContext(
      product: 'citizenwallet',
      scope: '0x${'11' * 32}',
      secretType: HardwareSecretType.masterMiniSecret,
    );
    final result = await vault.encrypt(context, Uint8List.fromList([1, 2, 3]));
    expect(observed.method, 'encrypt');
    final arguments = observed.arguments! as Map<Object?, Object?>;
    expect(arguments['plaintext'], isA<Uint8List>());
    expect(arguments['associatedData'], isA<Uint8List>());
    expect(result, orderedEquals([9, 8, 7]));
  });

  test('解密只读平台结果会复制为可清零的自有缓冲区', () async {
    final borrowed = Uint8List.fromList(<int>[9, 8, 7]).asUnmodifiableView();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'decrypt');
      return borrowed;
    });
    final vault = HardwareSecretvault(channel: channel);
    final context = HardwareSecretContext(
      product: 'citizenwallet',
      scope: '0x${'11' * 32}',
      secretType: HardwareSecretType.masterMiniSecret,
    );

    final plaintext = await vault.decrypt(
      context,
      Uint8List.fromList(<int>[1]),
    );
    expect(plaintext, orderedEquals(<int>[9, 8, 7]));
    expect(identical(plaintext, borrowed), isFalse);

    HardwareSecretvault.clearBytes(plaintext);
    expect(plaintext, orderedEquals(<int>[0, 0, 0]));
    expect(borrowed, orderedEquals(<int>[9, 8, 7]));
  });

  test('清零错误不会被全局吞掉', () {
    final borrowed = Uint8List.fromList(<int>[1]).asUnmodifiableView();
    expect(
      () => HardwareSecretvault.clearBytes(borrowed),
      throwsUnsupportedError,
    );
  });

  test('原生错误码原样映射，供两端统一 fail-closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'hardwareUnavailable', message: '无硬件');
    });
    final vault = HardwareSecretvault(channel: channel);
    final context = HardwareSecretContext(
      product: 'citizenwallet',
      scope: '0x${'11' * 32}',
      secretType: HardwareSecretType.masterMiniSecret,
    );
    await expectLater(
      vault.decrypt(context, Uint8List.fromList([1])),
      throwsA(
        isA<HardwareSecretvaultException>().having(
          (error) => error.code,
          'code',
          'hardwareUnavailable',
        ),
      ),
    );
  });
}
