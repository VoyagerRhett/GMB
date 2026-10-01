import 'dart:typed_data';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'dart:async';
import 'package:citizen_sdk/src/platform/citizen_sdk_platform.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:citizen_sdk/src/account_codec.dart';

/// 既有业务测试共用一次SDK接线；每用例重新打开/关闭独立会话，不复制编码算法。
/// 默认只承接真实Core纯编码/QR；设备、钱包及像素替身必须由用例显式配置。
class TestCitizenSdkHarness {
  TestCitizenSdkHarness({
    Map<String, FutureOr<List<Object?>> Function(List<Object?>)> handlers = const {},
  }) {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() async {
      transport = TestCitizenSdkTransport(Map.of(handlers), useCore: true);
      sdk = await transport.open();
    });
    tearDown(() async {
      try {
        await sdk.close();
      } finally {
        await transport.dispose();
      }
    });
  }

  late TestCitizenSdkTransport transport;
  late CitizenSdk sdk;
}

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
  TestCitizenSdkTransport(this.handlers, {this.useCore = false});
  final bool useCore;
  _TestCitizenCore? _core;
  Future<List<Object?>> _invokeFields(String method, List<Object?> fields) async {
    final handler = handlers[method];
    if (handler != null) {
      return await handler(fields);
    }
    if (useCore) {
      return (_core ??= _TestCitizenCore()).invoke(method, fields);
    }
    throw StateError('UI测试未配置$method');
  }
  final Map<String, FutureOr<List<Object?>> Function(List<Object?>)> handlers;
  final List<String> calls = <String>[];
  final StreamController<Object?> _events = StreamController<Object?>.broadcast();
  int _nextSequence = 1;
  int _nextEventSequence = 1;
  void walletChanged() => _events.add(<Object?>[2, 'synthetic-ui-session', _nextEventSequence++, 'walletChanged', <Object?>[]]);
  @override Stream<Object?> get events => _events.stream;

  Future<CitizenSdk> open() async {
    CitizenSdkPlatform.instance = this;
    return CitizenSdk.open();
  }
  Future<void> dispose() async {
    if (identical(CitizenSdkPlatform.instance, this)) CitizenSdkPlatform.instance = null;
    _core?.close();
    await _events.close();
  }
  @override Future<Object?> invoke(String method, List<Object?> arguments) async {
    const version = CitizenSdkFlutterCodec.protocolVersion;
    if (arguments.first != version) {
      throw StateError('UI测试拒绝旧协议');
    }
    calls.add(method);
    if (method == 'open') {
      return <Object?>[version, 'synthetic-ui-session', 0, <Object?>['created', 1]];
    }
    if (method == 'encodeSigningPayload' || method == 'verifySignature') {
      return <Object?>[version, ...await _invokeFields(method, arguments.sublist(1))];
    }
    if (arguments.length < 3 || arguments[1] != 'synthetic-ui-session' || arguments[2] != _nextSequence++) {
      throw StateError('UI测试会话或序号不一致');
    }
    final List<Object?> value;
    if (method == 'close') { value = <Object?>['disposed']; }
    else {
      try {
        value = await _invokeFields(method, arguments.sublist(3));
      } on CitizenSdkException catch (error) {
        // 平台错误也必须精确关联本次请求，不能绕过SDK的session/sequence验证。
        throw CitizenSdkException(code: error.code, stage: error.stage, message: error.message,
          method: method, sessionId: 'synthetic-ui-session', requestSequence: arguments[2]! as int);
      }
    }
    return <Object?>[version, arguments[1], arguments[2], value];
  }
}

/// 合成公开资料，不对应真实钱包；UI用例显式选择此夹具，绝不访问设备金库。
String get testCitizenAccountId => '0x${List.filled(32, '01').join()}';
List<Object?> testCitizenWalletProfile() => <Object?>[
  0, 'created', '1', testCitizenAccountId, testCitizenAccountId,
  <Object?>[<Object?>[0, testCitizenAccountId, citizenSs58FromAccountId(testCitizenAccountId), '钱包0', '1', true]],
  '钱包0',
];
List<Object?> testCitizenWalletState() => <Object?>[
  '1', testCitizenWalletProfile(),
  <Object?>[<Object?>['hot', 0, 0, testCitizenAccountId, citizenSs58FromAccountId(testCitizenAccountId), '钱包0', '1', true]],
  1, false, 0, <Object?>[],
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

// 测试仅调用公开C ABI执行真实Core编码/验签与QR-only协议，不提供钱包或复制算法。
// 当前Core由调用方准备在本轮CARGO_TARGET_DIR/debug；缺件失败，不跳过金标。
final class _CoreBytes extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;
  @ffi.Uint64()
  external int len;
}
final class _CoreOptions extends ffi.Struct {
  @ffi.Uint32()
  external int structSize;
  @ffi.Uint32()
  external int abiVersion;
  external _CoreBytes assetManifest;
  external _CoreBytes chainSpec;
  external _CoreBytes lightSyncState;
  external _CoreBytes systemName;
  external _CoreBytes systemVersion;
}
typedef _AllocateNative = ffi.Pointer<ffi.Void> Function(ffi.UintPtr, ffi.UintPtr);
typedef _Allocate = ffi.Pointer<ffi.Void> Function(int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Free = void Function(ffi.Pointer<ffi.Void>);
final _coreAllocate = ffi.DynamicLibrary.process().lookupFunction<_AllocateNative, _Allocate>('calloc');
final _coreFree = ffi.DynamicLibrary.process().lookupFunction<_FreeNative, _Free>('free');
final class _CoreArena {
  final _owned = <ffi.Pointer<ffi.Void>>[];
  ffi.Pointer<ffi.Uint8> allocate(int size) {
    final pointer = _coreAllocate(1, size == 0 ? 1 : size);
    if (pointer == ffi.nullptr) {
      throw StateError('测试C缓冲分配失败');
    }
    _owned.add(pointer);
    return pointer.cast<ffi.Uint8>();
  }
  ffi.Pointer<ffi.Uint8> bytes(List<int> value) {
    final pointer = allocate(value.length);
    pointer.asTypedList(value.length).setAll(0, value);
    return pointer;
  }
  _CoreBytes view(List<int> value) {
    final pointer = allocate(ffi.sizeOf<_CoreBytes>()).cast<_CoreBytes>();
    pointer.ref.data = bytes(value);
    pointer.ref.len = value.length;
    return pointer.ref;
  }
  void close() {
    for (final pointer in _owned.reversed) { _coreFree(pointer); }
    _owned.clear();
  }
}
typedef _Output = int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);
typedef _TextNative = ffi.Int32 Function(ffi.Uint64, _CoreBytes, ffi.Pointer<ffi.Uint8>, ffi.Uint64, ffi.Pointer<ffi.Uint64>);
typedef _Text = int Function(int, _CoreBytes, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);
typedef _PayloadNative = ffi.Int32 Function(ffi.Uint32, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>, ffi.Uint64, ffi.Pointer<ffi.Uint64>);
typedef _Payload = int Function(int, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);
typedef _AuthorizationNative = ffi.Int32 Function(ffi.Uint64, ffi.Uint32, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>, ffi.Uint64, ffi.Pointer<ffi.Uint64>);
typedef _Authorization = int Function(int, int, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);
typedef _AccountCodeNative = ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Uint64, ffi.Pointer<ffi.Uint64>);
typedef _AccountCode = int Function(int, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);
typedef _VerifyNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>);
typedef _Verify = int Function(ffi.Pointer<ffi.Uint8>, _CoreBytes, _CoreBytes, ffi.Pointer<ffi.Uint8>);
typedef _CreateNative = ffi.Int32 Function(ffi.Pointer<_CoreOptions>, ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<ffi.Uint64>);
typedef _Create = int Function(ffi.Pointer<_CoreOptions>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Uint64>);
typedef _DestroyNative = ffi.Int32 Function(ffi.Uint64);
typedef _Destroy = int Function(int);
typedef _NumberNative = ffi.Uint32 Function();
typedef _Number = int Function();
typedef _ErrorNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Uint64, ffi.Pointer<ffi.Uint64>);
typedef _Error = int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint64>);

final class _TestCitizenCore {
  _TestCitizenCore() {
    final target = Platform.environment['CARGO_TARGET_DIR'];
    if (target == null || !target.startsWith('/')) {
      throw StateError('SDK金标缺少本轮CARGO_TARGET_DIR');
    }
    final name = Platform.isMacOS ? 'libcitizensdk.dylib' : 'libcitizensdk.so';
    final file = File('$target/debug/$name');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) != FileSystemEntityType.file) {
      throw StateError('SDK金标缺少调用方准备的当前Core：$target/debug/$name');
    }
    _library = ffi.DynamicLibrary.open(file.path);
    if (_library.lookupFunction<_NumberNative, _Number>('citizensdk_abi_version')() != 1 ||
        _library.lookupFunction<_NumberNative, _Number>('citizensdk_create_options_size')() != ffi.sizeOf<_CoreOptions>()) {
      throw StateError('SDK测试C ABI与真实Core不一致');
    }
  }
  late final ffi.DynamicLibrary _library;
  int _qr = 0;
  String _message() {
    final arena = _CoreArena();
    try {
      final count = arena.allocate(8).cast<ffi.Uint64>();
      final copy = _library.lookupFunction<_ErrorNative, _Error>('citizensdk_last_error_copy');
      if (copy(ffi.nullptr, 0, count) != 0 || count.value > 65536) {
        return 'Core拒绝测试输入';
      }
      final output = arena.allocate(count.value);
      if (copy(output, count.value, count) != 0) {
        return 'Core错误文本不可读取';
      }
      return utf8.decode(output.asTypedList(count.value));
    } finally { arena.close(); }
  }
  void _check(int code) {
    if (code == 0) return;
    // SDK公开枚举按C的1..22闭集排序；未知值不得当作成功或false。
    if (code < 1 || code > CitizenSdkErrorCode.values.length) {
      throw StateError('未知Core错误码$code');
    }
    throw CitizenSdkException(code: CitizenSdkErrorCode.values[code - 1], message: _message());
  }
  Uint8List _read(_CoreArena arena, _Output call) {
    final count = arena.allocate(8).cast<ffi.Uint64>();
    _check(call(ffi.nullptr, 0, count));
    final capacity = count.value;
    if (capacity > CitizenSdkFlutterCodec.maximumSigningPayloadBytes) {
      throw StateError('Core测试输出超限');
    }
    final output = arena.allocate(capacity);
    _check(call(output, capacity, count));
    if (count.value > capacity) {
      throw StateError('Core输出长度在复制时越界');
    }
    return Uint8List.fromList(output.asTypedList(count.value));
  }
  int _qrHandle(_CoreArena arena) {
    if (_qr != 0) {
      return _qr;
    }
    final options = arena.allocate(ffi.sizeOf<_CoreOptions>()).cast<_CoreOptions>();
    options.ref.structSize = ffi.sizeOf<_CoreOptions>();
    options.ref.abiVersion = 1;
    options.ref.systemName = arena.view(utf8.encode('citizenapp-tests'));
    options.ref.systemVersion = arena.view(utf8.encode('1'));
    final output = arena.allocate(8).cast<ffi.Uint64>();
    _check(_library.lookupFunction<_CreateNative, _Create>('citizensdk_create_with_modules')(
      options, ffi.nullptr, CitizenSdkModules.qr, output));
    _qr = output.value;
    if (_qr == 0) {
      throw StateError('Core未创建QR-only实例');
    }
    return _qr;
  }
  Uint8List _account(String value) {
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('测试账户不是规范公开AccountId');
    }
    return Uint8List.fromList(List.generate(32, (i) => int.parse(value.substring(2 + i * 2, 4 + i * 2), radix: 16)));
  }
  List<Object?> invoke(String method, List<Object?> fields) {
    final arena = _CoreArena();
    try {
      if (method == 'encodeSigningPayload') {
        final call = _library.lookupFunction<_PayloadNative, _Payload>('citizensdk_encode_signing_payload');
        final json = arena.view(utf8.encode(fields[1]! as String));
        final payload = arena.view(fields[2]! as Uint8List);
        return [_read(arena, (output, size, count) => call(fields[0]! as int, json, payload, output, size, count))];
      }
      if (method == 'verifySignature') {
        final result = arena.allocate(1);
        _check(_library.lookupFunction<_VerifyNative, _Verify>('citizensdk_verify_signature')(
          arena.bytes(_account(fields[0]! as String)), arena.view(fields[1]! as Uint8List),
          arena.view(fields[2]! as Uint8List), result));
        if (result.value > 1) {
          throw StateError('Core返回非法验证布尔值');
        }
        return [result.value == 1];
      }
      if (method == 'qrParse' || method == 'qrEncodeDocument') {
        final handle = _qrHandle(arena);
        final input = arena.view(utf8.encode(fields[0]! as String));
        final call = _library.lookupFunction<_TextNative, _Text>(
          method == 'qrParse' ? 'citizensdk_qr_parse' : 'citizensdk_qr_encode_document');
        return [utf8.decode(_read(arena, (output, size, count) => call(handle, input, output, size, count)))];
      }
      if (method == 'qrPrepareAccountAuthorization') {
        final handle = _qrHandle(arena);
        final payload = arena.view(fields[1]! as Uint8List);
        final account = arena.view(utf8.encode(fields[2]! as String));
        final call = _library.lookupFunction<_AuthorizationNative, _Authorization>('citizensdk_qr_prepare_account_authorization');
        return [utf8.decode(_read(arena, (output, size, count) =>
          call(handle, fields[0]! as int, payload, account, output, size, count)))];
      }
      if (method == 'qrEncodeAccountId') {
        final handle = _qrHandle(arena), account = arena.bytes(_account(fields[0]! as String));
        final call = _library.lookupFunction<_AccountCodeNative, _AccountCode>('citizensdk_qr_encode_account_id');
        return [utf8.decode(_read(arena, (output, size, count) => call(handle, account, output, size, count)))];
      }
      throw StateError('测试Core不承接未配置的方法$method；钱包、设备与签名必须显式用例注入');
    } finally { arena.close(); }
  }
  void close() {
    if (_qr != 0) {
      _check(_library.lookupFunction<_DestroyNative, _Destroy>('citizensdk_destroy')(_qr));
      _qr = 0;
    }
  }
}
