import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';

// 保留原SCALE金标输入及边界，公开Dart调用最终由真实SDK Core计算。
// 测试桥只搬运C ABI字节，不恢复App编码器；只读原向量，不修改其所有者。

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
  // 工具根与源码根不同；只读准确主仓金标，不在中央目录复制 Runtime 数据。
  final root = Platform.environment['GMB_ROOT'];
  if (root == null || !root.startsWith('/')) {
    throw StateError('SCALE 金标检查缺少准确 GMB_ROOT');
  }
  final file = File(
    '$root/citizenchain/runtime/primitives/tests/fixtures/scale_codec_vectors.json',
  );
  final canonical =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final compactVectors =
      (canonical['compact_u32'] as List).cast<Map<String, dynamic>>();
  final stringVectors =
      (canonical['scale_string'] as List).cast<Map<String, dynamic>>();
  final u64Vectors = (canonical['u64_le'] as List).cast<Map<String, dynamic>>();

  group('SCALE 编码原语与链端一致(直读 citizenchain 真源)', () {
    test('真源三组向量均可读且非空', () async {
      // 读成空数组时下面的循环一条用例都不生成而整体显示通过,这条挡住金标静默失效。
      expect(file.existsSync(), isTrue,
          reason: '真源不可达,cwd=${Directory.current.path}');
      expect(compactVectors, isNotEmpty);
      expect(stringVectors, isNotEmpty);
      expect(u64Vectors, isNotEmpty);
    });

    for (final vector in stringVectors) {
      final value = vector['value'] as String;
      final label = value.length > 24 ? '${value.substring(0, 24)}…' : value;
      test('scaleString(${jsonEncode(label)}) 共 ${vector['utf8_len']} 字节', () async {
        expect(_bytesToHex((await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString(value)))), vector['hex']);
      });
    }

    for (final vector in u64Vectors) {
      test('u64Le(${vector['value']})', () async {
        expect(_bytesToHex((await CitizenSigning.encodePayload(CitizenSigningPayload.u64Le(BigInt.from(vector['value'] as int))))), vector['hex']);
      });
    }
  });

  group('compact 长度前缀覆盖全部三档', () {
    // 通过SDK公开scaleString入口检查真实Core的compact(len) ++ utf8结果，
    // 用长度恰为向量取值的 ASCII 串反推前缀,即可把三档分支(< 2^6 / < 2^14 / < 2^30)
    // 的边界全部锁住。把 `<` 写成 `<=` 会让 63/64、16383/16384 中的一对编错字节数。
    for (final vector in compactVectors) {
      final length = vector['value'] as int;
      final expectedPrefix = vector['hex'] as String;
      // 4 字节档的上界是 2^30-1,构造那么长的字符串不现实;只覆盖可构造的长度。
      if (length > 65535) {
        continue;
      }
      test('长度 $length 的字符串前缀为 $expectedPrefix', () async {
        final encoded = (await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString('x' * length)));
        expect(
          _bytesToHex(encoded).substring(0, expectedPrefix.length),
          expectedPrefix,
        );
        // 前缀之后必须是原始字节,长度与前缀声明一致。
        expect(encoded.length, expectedPrefix.length ~/ 2 + length);
      });
    }
  });

  group('SCALE 编码原语的 fail-closed 边界', () {
    // 真源向量只覆盖合法取值。非法输入必须抛错而不是产出错误字节 ——
    // 静默产出会让一笔语义错误的交易被签名。
    test('u64Le 拒绝负数', () async {
      await expectLater(CitizenSigning.encodePayload(CitizenSigningPayload.u64Le(BigInt.from(-1))),
        throwsA(isA<CitizenSdkException>().having((error) => error.code, 'code', CitizenSdkErrorCode.invalidArgument)));
    });

    // 本App回归只构造65535字节以内的字符串，不把未执行的1GB边界宣称为通过。
  });
}
