import 'dart:typed_data';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'dart:async';
import 'package:citizen_sdk/src/platform/citizen_sdk_platform.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:citizen_sdk/src/crypto/account_codec.dart';

/// CitizenApp 测试只为本用例覆盖实际调用的 CitizenChain 方法。
/// 未覆盖的公开能力一律失败，禁止测试伪造隐式默认链事实。
class TestCitizenChain implements CitizenChain {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenChain.${invocation.memberName} 未配置');
  }
}

/// CitizenTransactions 的严格测试基类；每个业务用例必须明确给出
/// prepare/execute/consume/cancel 中它真正依赖的结果。
class TestCitizenTransactions implements CitizenTransactions {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'CitizenTransactions.${invocation.memberName} 未配置',
    );
  }
}

/// CitizenHistory 的严格测试基类。
class TestCitizenHistory implements CitizenHistory {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenHistory.${invocation.memberName} 未配置');
  }
}

/// CitizenSdkWallet 的严格测试基类。
class TestCitizenSdkWallet implements CitizenSdkWallet {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenSdkWallet.${invocation.memberName} 未配置');
  }
}

/// 使用真实Dart SDK绑定的UI测试传输。只假造本用例明确配置的事实，不打开真实钱包。
class TestCitizenSdkTransport implements CitizenSdkPlatform {
  TestCitizenSdkTransport(this.handlers);
  final Map<String, FutureOr<List<Object?>> Function(List<Object?>)> handlers;
  final List<String> calls = <String>[];
  final StreamController<Object?> _events = StreamController<Object?>.broadcast();
  int _nextSequence = 1;
  @override Stream<Object?> get events => _events.stream;

  Future<CitizenSdk> open() async {
    CitizenSdkPlatform.instance = this;
    return CitizenSdk.open();
  }
  Future<void> dispose() async {
    if (identical(CitizenSdkPlatform.instance, this)) CitizenSdkPlatform.instance = null;
    await _events.close();
  }
  @override Future<Object?> invoke(String method, List<Object?> arguments) async {
    const version = CitizenSdkFlutterCodec.protocolVersion;
    if (arguments.first != version) throw StateError('UI测试拒绝旧协议');
    calls.add(method);
    if (method == 'open') return <Object?>[version, 'synthetic-ui-session', 0, <Object?>['created', 1]];
    if (arguments.length < 3 || arguments[1] != 'synthetic-ui-session' || arguments[2] != _nextSequence++) {
      throw StateError('UI测试会话或序号不一致');
    }
    final List<Object?> value;
    if (method == 'close') { value = <Object?>['disposed']; }
    else {
      final handler = handlers[method];
      if (handler == null) throw StateError('UI测试未配置$method');
      value = await handler(arguments.sublist(3));
    }
    return <Object?>[version, arguments[1], arguments[2], value];
  }
}

/// 合成公开资料，不对应真实钱包；UI用例显式选择此夹具，绝不访问设备金库。
String get testCitizenAccountId => '0x${List.filled(32, '01').join()}';
List<Object?> testCitizenWalletProfile() => <Object?>[
  0, 'created', '1', testCitizenAccountId, testCitizenAccountId,
  <Object?>[<Object?>[0, testCitizenAccountId, citizenSs58FromAccountId(testCitizenAccountId), '钱包0', '1', true]],
];
List<Object?> testCitizenWalletState() => <Object?>[
  '1', testCitizenWalletProfile(),
  <Object?>[<Object?>['hot', 0, 0, testCitizenAccountId, citizenSs58FromAccountId(testCitizenAccountId), '钱包0', '1', true]],
  1, false,
];

/// 立即交付合成结果的测试操作；不模拟原生排空或声称测试取消能力。
/// 取消/迟到等场景须由对应测试显式提供可控的CitizenSdkOperation。
CitizenSdkOperation<T> testCitizenOperation<T>(FutureOr<T> Function() result) =>
    CitizenSdkOperation<T>(
      operationId: (++_testOperationId).toString(),
      result: Future<T>.sync(result),
      cancel: () async => false,
    );
int _testOperationId = 0;


/// SDK端口的严格用例替身；只有本用例明确配置的能力可被调用，不解析QR或伪造授权。
class TestCitizenQr implements CitizenQr {
  Future<CitizenQrCapture> Function(CitizenQrScanPurpose)? captureFactory;
  Future<CitizenQrDocument> Function(String)? parseDocument;
  Future<CitizenQrScanResult> Function(String, CitizenQrScanPurpose)? acceptDocument;
  Future<List<CitizenQrScanResult>> Function(Uint8List, CitizenQrScanPurpose)? decodeImageResult;
  @override Future<CitizenQrCapture> openCapture(CitizenQrScanPurpose purpose) =>
      captureFactory!(purpose);
  @override Future<CitizenQrDocument> parse(String text) => parseDocument!(text);
  @override Future<CitizenQrScanResult> parseForPurpose(String text, CitizenQrScanPurpose purpose) =>
      acceptDocument!(text, purpose);
  @override Future<List<CitizenQrScanResult>> decodeImage(Uint8List bytes, CitizenQrScanPurpose purpose) =>
      decodeImageResult!(bytes, purpose);
  @override dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('CitizenQr.${invocation.memberName}未配置');
}

/// 合成摄像资源只用于App生命周期接线断言，不充当真实摄像设备验收。
class TestCitizenQrCapture implements CitizenQrCapture {
  final resultEvents = StreamController<CitizenQrScanResult>.broadcast(sync: true);
  final errorEvents = StreamController<CitizenSdkException>.broadcast(sync: true);
  final previewEvents = StreamController<CitizenQrPreview>.broadcast(sync: true);
  @override final int textureId = 42;
  @override CitizenQrPreview preview = const CitizenQrPreview(width: 640, height: 480, rotationDegrees: 90);
  @override Stream<CitizenQrPreview> get previewChanges => previewEvents.stream;
  @override Stream<CitizenQrScanResult> get results => resultEvents.stream;
  @override Stream<CitizenSdkException> get errors => errorEvents.stream;
  int pauseCalls = 0, resumeCalls = 0, closeCalls = 0;
  bool? torch;
  bool closed = false;
  Completer<void>? closeBarrier;
  Future<void>? _closing;
  @override Future<void> pause() async { pauseCalls++; }
  @override Future<void> resume() async { resumeCalls++; }
  @override Future<void> setTorch(bool enabled) async { torch = enabled; }
  @override Future<void> close() => _closing ??= () async {
    closeCalls++;
    if (closeBarrier != null) await closeBarrier!.future;
    closed = true;
    await resultEvents.close();
    await errorEvents.close();
    await previewEvents.close();
  }();
}
