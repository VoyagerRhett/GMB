// 设备子钥绑定（op_tag OP_SIGN_SQUARE_DEVICE_BIND = 0x1C）跨语言金标。
//
// 设备绑定是唯一「客户端 + Worker 双侧各自 SCALE 编码」的流，字段编码必须逐字节
// 一致。该 golden hex 必须与 Worker 端
// cloudflare/test/device_subkey.test.ts 的 DEVICE_BIND_GOLDEN_HEX 完全相同。

import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/security/device_subkey.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';

const _accountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _cidNumber = 'CN220-CTZN2-198805200-2026';
const _bindingRevision = 1;
final String _publicKey = '04${'ab' * 64}';
const int _issuedAt = 1700000000000;
const _goldenHex =
    'a12230133532467b7757ae9597b36255ba0228aaa2fe595b8975283d5efe148e';

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
  test('buildDeviceBindingSigningMessage matches Worker golden (0x1C)', () async {
    final message = await buildDeviceBindingSigningMessage(
      _cidNumber,
      _bindingRevision,
      _accountId,
      _publicKey,
      _issuedAt,
    );
    expect(message.length, 32);
    expect(bytesToHex(message), _goldenHex);
  });

  test('CitizenSDK Blake2Domain 输入与设备绑定逐字节共用 0x1C', () async {
    final payload = await encodeDeviceBindingPayload(
      cidNumber: _cidNumber,
      bindingRevision: _bindingRevision,
      accountId: _accountId,
      p256PublicKeyHex: _publicKey,
      issuedAtMillis: _issuedAt,
    );
    final coldSigningMessage = (await CitizenSigning.encodePayload(CitizenSigningPayload.message(
      opTag: kOpSignSquareDeviceBind,
      scalePayload: payload,
    )));
    expect(bytesToHex(coldSigningMessage), _goldenHex);
  });
}
