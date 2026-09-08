import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// `citizenwallet/rust/src/account_crypto.rs` 在 CitizenWallet 的唯一 FFI 入口。
///
/// 冷端只需要 X25519 公钥、AES-GCM 封装及底层用途钥派生；所有私钥缓冲用后清零。
class NativeAccountCrypto {
  const NativeAccountCrypto._();

  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const String _libraryBase = 'libcitizenwallet_signer';
  static final DynamicLibrary _library = _openLibrary();

  static String _hostTargetDirectory() {
    final target = Platform.environment['CARGO_TARGET_DIR'];
    if (target == null || target.isEmpty || !p.isAbsolute(target)) {
      throw StateError('宿主测试必须由塔塔控制台提供 CARGO_TARGET_DIR');
    }
    return target;
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) return DynamicLibrary.open('$_libraryBase.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    final extension = Platform.isMacOS ? 'dylib' : 'so';
    return DynamicLibrary.open(
      p.join(
        _hostTargetDirectory(),
        'release',
        '$_libraryBase.$extension',
      ),
    );
  }

  static final _derive = _library.lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        IntPtr,
        Uint64,
        Pointer<Uint8>,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Uint8>,
      ),
      int Function(
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        int,
        int,
        Pointer<Uint8>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
      )>('account_crypto_derive_key');
  static final _publicKey = _library.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
      int Function(
          Pointer<Uint8>, Pointer<Uint8>)>('account_crypto_x25519_public_key');
  static final _seal = _library.lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Uint8>,
        IntPtr,
        Pointer<Uint8>,
        IntPtr,
        Pointer<IntPtr>,
      ),
      int Function(
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        Pointer<IntPtr>,
      )>('account_crypto_seal');

  static Uint8List deriveKey({
    required List<int> accountSecret,
    required List<int> genesisHash,
    required List<int> cidNumber,
    required int bindingRevision,
    required List<int> accountId,
    required List<int> purpose,
    required List<int> context,
  }) {
    _length(accountSecret, keyLength, 'accountSecret');
    _length(genesisHash, keyLength, 'genesisHash');
    _length(accountId, keyLength, 'accountId');
    final pointers = <({Pointer<Uint8> pointer, int length, bool secret})>[];
    Pointer<Uint8> copy(List<int> value, {bool secret = false}) {
      final pointer = calloc<Uint8>(value.isEmpty ? 1 : value.length);
      if (value.isNotEmpty) pointer.asTypedList(value.length).setAll(0, value);
      pointers.add((pointer: pointer, length: value.length, secret: secret));
      return pointer;
    }

    final output = calloc<Uint8>(keyLength);
    try {
      _check(
        _derive(
          copy(accountSecret, secret: true),
          copy(genesisHash),
          copy(cidNumber),
          cidNumber.length,
          bindingRevision,
          copy(accountId),
          copy(purpose),
          purpose.length,
          copy(context),
          context.length,
          output,
        ),
        'deriveKey',
      );
      return Uint8List.fromList(output.asTypedList(keyLength));
    } finally {
      for (final item in pointers) {
        if (item.secret && item.length > 0) {
          item.pointer.asTypedList(item.length).fillRange(0, item.length, 0);
        }
        calloc.free(item.pointer);
      }
      output.asTypedList(keyLength).fillRange(0, keyLength, 0);
      calloc.free(output);
    }
  }

  static Uint8List x25519PublicKey(List<int> secretBytes) {
    _length(secretBytes, keyLength, 'secret');
    final secret = calloc<Uint8>(keyLength);
    final output = calloc<Uint8>(keyLength);
    try {
      secret.asTypedList(keyLength).setAll(0, secretBytes);
      _check(_publicKey(secret, output), 'x25519PublicKey');
      return Uint8List.fromList(output.asTypedList(keyLength));
    } finally {
      secret.asTypedList(keyLength).fillRange(0, keyLength, 0);
      calloc.free(secret);
      calloc.free(output);
    }
  }

  static Uint8List seal({
    required List<int> recipientPublicKey,
    required List<int> senderSecret,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) {
    _length(recipientPublicKey, keyLength, 'recipientPublicKey');
    _length(senderSecret, keyLength, 'senderSecret');
    _length(nonce, nonceLength, 'nonce');
    final recipient = _copy(recipientPublicKey);
    final sender = _copy(senderSecret);
    final noncePointer = _copy(nonce);
    final plainPointer = _copy(plaintext);
    final aadPointer = _copy(aad);
    final output = calloc<Uint8>(plaintext.length + tagLength);
    final outputLength = calloc<IntPtr>();
    try {
      _check(
        _seal(
          recipient,
          sender,
          noncePointer,
          plainPointer,
          plaintext.length,
          aadPointer,
          aad.length,
          output,
          plaintext.length + tagLength,
          outputLength,
        ),
        'seal',
      );
      return Uint8List.fromList(output.asTypedList(outputLength.value));
    } finally {
      sender.asTypedList(keyLength).fillRange(0, keyLength, 0);
      plainPointer
          .asTypedList(plaintext.length)
          .fillRange(0, plaintext.length, 0);
      calloc.free(recipient);
      calloc.free(sender);
      calloc.free(noncePointer);
      calloc.free(plainPointer);
      calloc.free(aadPointer);
      calloc.free(output);
      calloc.free(outputLength);
    }
  }

  static Pointer<Uint8> _copy(List<int> bytes) {
    final pointer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static void _length(List<int> bytes, int expected, String name) {
    if (bytes.length != expected) throw ArgumentError('$name 必须为 $expected 字节');
  }

  static void _check(int code, String operation) {
    if (code != 0) throw StateError('原生账户密码学 $operation 失败(错误码 $code)');
  }
}
