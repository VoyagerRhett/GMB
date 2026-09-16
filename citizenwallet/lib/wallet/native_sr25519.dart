import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// sr25519 原生签名（schnorrkel）的 Dart 侧唯一入口。
///
/// 实现来自 `citizenwallet/rust/src/sr25519.rs`，由钱包独立维护。
/// 派生语义保持迁移前一致。冷钱包永久离线，
/// 只把这份签名实现编成独立小库 `libcitizenwallet_signer`（几百 KB），不引入链。
///
/// **为什么必须原生**：纯 Dart `sr25519` 走 BigInt 软算标量乘，真机实测一次
/// 「派生 + 签名」8.2 秒；schnorrkel 是 Substrate 官方实现，同样的活毫秒级。
///
/// **口径**（改动前先看 citizen-signer 的同名说明）：扩展模式恒 Ed25519、签名
/// 上下文恒 `substrate`、硬派生 chaincode 由调用方按 junction 顺序逐层传入。
/// 由冷端金标测试逐字节钉死，且与 CitizenApp 金标互等。
///
/// **安全**：出入参缓冲一律在 `finally` 里先清零再释放；原生侧同样用 `Zeroizing`
/// 擦除私钥材料，且全部入口 `catch_unwind`，任何内部异常只回错误码，不会 abort
/// 掉 App。错误码一律上抛，**绝不静默兜底成"空签名"或"验签通过"**。
class NativeSr25519 {
  const NativeSr25519._();

  static const int _seedLen = 32;
  static const int _publicLen = 32;
  static const int _signatureLen = 64;
  static const String _libBase = 'libcitizenwallet_signer';

  static final DynamicLibrary _lib = _open();

  /// 加载原生签名库。
  ///
  /// - Android：`.so` 随 APK 打包，按库名交给系统链接器解析；
  /// - iOS：静态库 `.a` 经 podspec 的 `-force_load` 直接链进 App 二进制，符号就在
  ///   本进程里，用 [DynamicLibrary.process] 取（iOS 不用 dylib：裸 dylib 要嵌入
  ///   加签名，且 App Store 要求动态库必须包在 .framework 里）；
  /// - macOS / Linux（`flutter test` 宿主）：找 `CARGO_TARGET_DIR/release` 下的构建产物，
  ///   由 `scripts/build-signer-native.sh host` 产出；扩展名按宿主平台取
  ///   （macOS `.dylib`、Linux `.so`），CI 在 Linux runner 上跑测试同样要能加载。
  static String _hostTargetDirectory() {
    final target = Platform.environment['CARGO_TARGET_DIR'];
    if (target == null || target.isEmpty || !p.isAbsolute(target)) {
      throw StateError('宿主测试必须提供源码外 CARGO_TARGET_DIR');
    }
    return target;
  }

  static DynamicLibrary _open() {
    if (Platform.isAndroid) return DynamicLibrary.open('$_libBase.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    final hostExt = Platform.isMacOS ? 'dylib' : 'so';
    final hostPath = p.join(
      _hostTargetDirectory(),
      'release',
      '$_libBase.$hostExt',
    );
    if (File(hostPath).existsSync()) return DynamicLibrary.open(hostPath);
    throw StateError(
      '未找到原生签名库 $_libBase：请先执行 scripts/build-signer-native.sh',
    );
  }

  static final _deriveHard = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>)>('citizen_sr25519_derive_hard');

  static final _publicKey = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
      int Function(
          Pointer<Uint8>, Pointer<Uint8>)>('citizen_sr25519_public_key');

  static final _sign = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, IntPtr, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>, int,
          Pointer<Uint8>)>('citizen_sr25519_sign');

  static final _verify = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, IntPtr),
      int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>,
          int)>('citizen_sr25519_verify');

  /// 按 [chainCode] 硬派生一层 child mini-secret（32 字节）。
  ///
  /// 多层派生按 junction 顺序逐层调用：上一层的输出作为下一层的 [seed]。
  static Uint8List deriveHard(List<int> seed, List<int> chainCode) {
    _require(seed.length == _seedLen, 'seed 必须是 32 字节');
    _require(chainCode.length == _seedLen, 'chainCode 必须是 32 字节');
    final seedPtr = calloc<Uint8>(_seedLen);
    final ccPtr = calloc<Uint8>(_seedLen);
    final outPtr = calloc<Uint8>(_seedLen);
    try {
      seedPtr.asTypedList(_seedLen).setAll(0, seed);
      ccPtr.asTypedList(_seedLen).setAll(0, chainCode);
      _check(_deriveHard(seedPtr, ccPtr, outPtr), 'deriveHard');
      return Uint8List.fromList(outPtr.asTypedList(_seedLen));
    } finally {
      // 私钥材料先清零再释放，缩短明文在堆上的存活窗口。
      _wipe(seedPtr, _seedLen);
      _wipe(outPtr, _seedLen);
      calloc.free(seedPtr);
      calloc.free(ccPtr);
      calloc.free(outPtr);
    }
  }

  /// child mini-secret → 公钥（32 字节，即 AccountId32 的字节）。
  static Uint8List publicKeyOf(List<int> child) {
    _require(child.length == _seedLen, 'child 必须是 32 字节');
    final childPtr = calloc<Uint8>(_seedLen);
    final outPtr = calloc<Uint8>(_publicLen);
    try {
      childPtr.asTypedList(_seedLen).setAll(0, child);
      _check(_publicKey(childPtr, outPtr), 'publicKeyOf');
      return Uint8List.fromList(outPtr.asTypedList(_publicLen));
    } finally {
      _wipe(childPtr, _seedLen);
      calloc.free(childPtr);
      calloc.free(outPtr);
    }
  }

  /// 用 child mini-secret 对 [message] 签名，返回 64 字节签名。
  ///
  /// sr25519 签名含随机数：同一输入两次签名字节不同（正常），对拍只能靠验签。
  static Uint8List sign(List<int> child, List<int> message) {
    _require(child.length == _seedLen, 'child 必须是 32 字节');
    final childPtr = calloc<Uint8>(_seedLen);
    final msgPtr = calloc<Uint8>(message.isEmpty ? 1 : message.length);
    final outPtr = calloc<Uint8>(_signatureLen);
    try {
      childPtr.asTypedList(_seedLen).setAll(0, child);
      if (message.isNotEmpty) {
        msgPtr.asTypedList(message.length).setAll(0, message);
      }
      _check(_sign(childPtr, msgPtr, message.length, outPtr), 'sign');
      return Uint8List.fromList(outPtr.asTypedList(_signatureLen));
    } finally {
      _wipe(childPtr, _seedLen);
      calloc.free(childPtr);
      calloc.free(msgPtr);
      calloc.free(outPtr);
    }
  }

  /// 验签：通过返回 true。公钥 32 字节、签名 64 字节。
  static bool verify(
    List<int> publicKey,
    List<int> signature,
    List<int> message,
  ) {
    _require(publicKey.length == _publicLen, 'publicKey 必须是 32 字节');
    _require(signature.length == _signatureLen, 'signature 必须是 64 字节');
    final pubPtr = calloc<Uint8>(_publicLen);
    final sigPtr = calloc<Uint8>(_signatureLen);
    final msgPtr = calloc<Uint8>(message.isEmpty ? 1 : message.length);
    try {
      pubPtr.asTypedList(_publicLen).setAll(0, publicKey);
      sigPtr.asTypedList(_signatureLen).setAll(0, signature);
      if (message.isNotEmpty) {
        msgPtr.asTypedList(message.length).setAll(0, message);
      }
      return _verify(pubPtr, sigPtr, msgPtr, message.length) == 0;
    } finally {
      calloc.free(pubPtr);
      calloc.free(sigPtr);
      calloc.free(msgPtr);
    }
  }

  static void _wipe(Pointer<Uint8> ptr, int length) {
    ptr.asTypedList(length).fillRange(0, length, 0);
  }

  static void _require(bool condition, String message) {
    if (!condition) throw ArgumentError(message);
  }

  /// 原生错误码一律上抛：签名失败绝不静默兜底成"空签名"或"验签通过"。
  static void _check(int code, String op) {
    if (code == 0) return;
    throw StateError('原生 sr25519 $op 失败(错误码 $code)');
  }
}
