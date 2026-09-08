import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:smoldot/smoldot.dart' show SmoldotPlatform;

/// sr25519 原生签名（schnorrkel）的 Dart 侧唯一入口。
///
/// 实现来自 `citizenapp/native/citizen-signer`，与 CitizenWallet 冷端**共用同一份
/// 源码**（冷热派生口径一旦分叉，同一助记词会算出不同账户）。热端的 FFI 外壳由
/// `smoldot/ffi/src/lib.rs` 里的 `citizen_signer::export_citizen_signer_ffi!()` 导出，与
/// smoldot 同处 `libsmoldot` 一个库，因此这里复用 `SmoldotPlatform.loadLibrary()`
/// 而不另开库句柄。
///
/// **为什么必须原生**：纯 Dart `sr25519` 走 BigInt 软算标量乘，真机实测一次
/// 「派生 + 签名」8.2 秒——用户按完指纹要干等，且曾把主线程拖到 Android ANR。
/// schnorrkel 是 Substrate 官方实现，同样的活毫秒级。
///
/// **口径**（错一处钱包就变成另一个账户，改动前先看 citizen-signer 的同名说明）：
/// 扩展模式恒 Ed25519、签名上下文恒 `substrate`、硬派生 chaincode 由调用方按
/// junction 顺序逐层传入。由 `test/wallet/derivation_golden_test.dart` 逐字节钉死
/// ——它拿本实现直接对拍 Substrate 官方权威向量（`//Alice`、`//0 //1 //2` 的
/// accountId / ss58 / childMiniSecret），改动后金标必须原样通过。
///
/// **安全**：私钥材料只在本进程内存中短暂存在，出入参缓冲一律在 `finally` 里
/// 先清零再释放；原生侧同样用 `Zeroizing` 擦除，且全部入口 `catch_unwind`，
/// 任何内部异常只回错误码，不会 abort 掉 App。
class NativeSr25519 {
  const NativeSr25519._();

  static const int _seedLen = 32;
  static const int _publicLen = 32;
  static const int _signatureLen = 64;

  static final DynamicLibrary _lib = SmoldotPlatform.loadLibrary();

  static final _deriveHard = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>)>('citizen_sr25519_derive_hard');

  static final _publicKey = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>)>('citizen_sr25519_public_key');

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
  /// 多层派生按 junction 顺序逐层调用：上一层的输出作为下一层的 [seed]，与
  /// 纯 Dart 侧的循环逐字节一致。
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
