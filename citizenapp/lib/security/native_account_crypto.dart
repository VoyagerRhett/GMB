import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:smoldot/smoldot.dart' show SmoldotPlatform;

/// `citizenapp/native/account-crypto` 在 CitizenApp 的唯一 Dart FFI 入口。
///
/// 所有私钥和明文用途钥缓冲在调用结束前清零；原生实现与 CitizenWallet 完全共用。
class NativeAccountCrypto {
  const NativeAccountCrypto._();

  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static final DynamicLibrary _library = SmoldotPlatform.loadLibrary();

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
  static final _open = _library.lookupFunction<
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
      )>('account_crypto_open');

  static Uint8List deriveKey({
    required List<int> accountSecret,
    required List<int> genesisHash,
    required String cidNumber,
    required int bindingRevision,
    required List<int> accountId,
    required String purpose,
    String context = '',
  }) {
    _length(accountSecret, keyLength, 'accountSecret');
    _length(genesisHash, keyLength, 'genesisHash');
    _length(accountId, keyLength, 'accountId');
    final cid = utf8.encode(cidNumber);
    final purposeBytes = utf8.encode(purpose);
    final contextBytes = utf8.encode(context);
    final secret = _copy(accountSecret);
    final genesis = _copy(genesisHash);
    final cidPointer = _copy(cid);
    final account = _copy(accountId);
    final purposePointer = _copy(purposeBytes);
    final contextPointer = _copy(contextBytes);
    final output = calloc<Uint8>(keyLength);
    try {
      _check(
        _derive(
          secret,
          genesis,
          cidPointer,
          cid.length,
          bindingRevision,
          account,
          purposePointer,
          purposeBytes.length,
          contextPointer,
          contextBytes.length,
          output,
        ),
        'deriveKey',
      );
      return Uint8List.fromList(output.asTypedList(keyLength));
    } finally {
      _free(secret, accountSecret.length, secret: true);
      _free(genesis, genesisHash.length);
      _free(cidPointer, cid.length);
      _free(account, accountId.length);
      _free(purposePointer, purposeBytes.length);
      _free(contextPointer, contextBytes.length);
      _free(output, keyLength, secret: true);
    }
  }

  static Uint8List x25519PublicKey(List<int> secretBytes) {
    _length(secretBytes, keyLength, 'secret');
    final secret = _copy(secretBytes);
    final output = calloc<Uint8>(keyLength);
    try {
      _check(_publicKey(secret, output), 'x25519PublicKey');
      return Uint8List.fromList(output.asTypedList(keyLength));
    } finally {
      _free(secret, keyLength, secret: true);
      _free(output, keyLength);
    }
  }

  static Uint8List seal({
    required List<int> recipientPublicKey,
    required List<int> senderSecret,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) =>
      _crypt(
        opening: false,
        keyA: recipientPublicKey,
        keyB: senderSecret,
        nonce: nonce,
        input: plaintext,
        aad: aad,
      );

  static Uint8List open({
    required List<int> recipientSecret,
    required List<int> senderPublicKey,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> aad,
  }) =>
      _crypt(
        opening: true,
        keyA: recipientSecret,
        keyB: senderPublicKey,
        nonce: nonce,
        input: ciphertext,
        aad: aad,
      );

  static Uint8List _crypt({
    required bool opening,
    required List<int> keyA,
    required List<int> keyB,
    required List<int> nonce,
    required List<int> input,
    required List<int> aad,
  }) {
    _length(
      keyA,
      keyLength,
      opening ? 'recipientSecret' : 'recipientPublicKey',
    );
    _length(keyB, keyLength, opening ? 'senderPublicKey' : 'senderSecret');
    _length(nonce, nonceLength, 'nonce');
    if (input.isEmpty ||
        aad.isEmpty ||
        (opening && input.length <= tagLength)) {
      throw ArgumentError('加密输入或 AAD 无效');
    }
    final first = _copy(keyA);
    final second = _copy(keyB);
    final noncePointer = _copy(nonce);
    final inputPointer = _copy(input);
    final aadPointer = _copy(aad);
    final capacity =
        opening ? input.length - tagLength : input.length + tagLength;
    final output = calloc<Uint8>(capacity);
    final outputLength = calloc<IntPtr>();
    try {
      final function = opening ? _open : _seal;
      _check(
        function(
          first,
          second,
          noncePointer,
          inputPointer,
          input.length,
          aadPointer,
          aad.length,
          output,
          capacity,
          outputLength,
        ),
        opening ? 'open' : 'seal',
      );
      return Uint8List.fromList(output.asTypedList(outputLength.value));
    } finally {
      _free(first, keyA.length, secret: opening);
      _free(second, keyB.length, secret: !opening);
      _free(noncePointer, nonce.length);
      _free(inputPointer, input.length, secret: !opening);
      _free(aadPointer, aad.length);
      _free(output, capacity, secret: opening);
      calloc.free(outputLength);
    }
  }

  static Pointer<Uint8> _copy(List<int> bytes) {
    final pointer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static void _free(Pointer<Uint8> pointer, int length, {bool secret = false}) {
    if (secret && length > 0) {
      pointer.asTypedList(length).fillRange(0, length, 0);
    }
    calloc.free(pointer);
  }

  static void _length(List<int> bytes, int expected, String name) {
    if (bytes.length != expected) throw ArgumentError('$name 必须为 $expected 字节');
  }

  static void _check(int code, String operation) {
    if (code != 0) throw StateError('原生账户密码学 $operation 失败(错误码 $code)');
  }
}
