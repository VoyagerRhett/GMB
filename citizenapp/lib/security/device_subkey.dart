import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:citizenapp/signer/signing.dart';

class DeviceSubkeyException implements Exception {
  const DeviceSubkeyException(this.message);

  final String message;

  @override
  String toString() => 'DeviceSubkeyException: $message';
}

/// CitizenApp P-256 设备子钥客户端（后台握手静默签名）。
///
/// 经原生桥在 Keystore/SE 生成 per-CID P-256 子钥（`PURPOSE_SIGN`、无生物门禁），
/// 导出公钥、对登录挑战做**硬件 ECDSA 签名**（私钥永不出硬件）。平台返回 DER(X9.62)
/// 签名，本类转成后端 Workers Web Crypto ES256 需要的**裸 r||s 64B**。
///
/// 用途：替代原先「静默读 sr25519 seed 签广场 session 挑战」的频繁路径；子钥归属
/// 由 sr25519 主钥一次性绑定证明 + 后端注册保证（`/square/auth/device/register`）。
class DeviceSubkey {
  DeviceSubkey({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'citizenapp/device_subkey';

  final MethodChannel _channel;

  /// 裸未压缩点 65B（`0x04||X||Y`）hex；子钥不存在则生成。
  Future<String> publicKeyHex(String cidNumber) async {
    _validateCidNumber(cidNumber);
    final hex = await _channel.invokeMethod<String>(
      'publicKey',
      <String, dynamic>{'cidNumber': cidNumber},
    );
    if (hex == null || hex.isEmpty) {
      throw const DeviceSubkeyException('设备子钥公钥获取失败');
    }
    return hex;
  }

  /// 硬件 P-256 ECDSA 签名 [payload]，返回**裸 r||s 64B**。
  Future<Uint8List> signRaw(String cidNumber, Uint8List payload) async {
    _validateCidNumber(cidNumber);
    final derHex = await _channel.invokeMethod<String>(
      'sign',
      <String, dynamic>{
        'cidNumber': cidNumber,
        'payload': base64Encode(payload),
      },
    );
    if (derHex == null || derHex.isEmpty) {
      throw const DeviceSubkeyException('设备子钥签名失败');
    }
    return derEcdsaToRaw(hexToBytes(derHex));
  }

  /// 同 [signRaw]，返回 hex 便于上送后端。
  Future<String> signRawHex(String cidNumber, Uint8List payload) async {
    return bytesToHex(await signRaw(cidNumber, payload));
  }

  Future<void> delete(String cidNumber) {
    _validateCidNumber(cidNumber);
    return _channel.invokeMethod<void>('delete', <String, dynamic>{
      'cidNumber': cidNumber,
    });
  }

  /// 只回读当前 CID 的硬件子钥是否仍存在；绝不创建新钥。
  Future<bool> contains(String cidNumber) async {
    _validateCidNumber(cidNumber);
    final exists = await _channel.invokeMethod<bool>(
      'contains',
      <String, dynamic>{'cidNumber': cidNumber},
    );
    if (exists == null) {
      throw const DeviceSubkeyException('设备子钥存在性复核失败');
    }
    return exists;
  }

  static void _validateCidNumber(String cidNumber) {
    final length = utf8.encode(cidNumber).length;
    if (length < 1 || length > 32) {
      throw ArgumentError.value(cidNumber, 'cidNumber', 'UTF-8 长度必须为 1-32 字节');
    }
  }
}

/// 设备绑定证明消息（客户端）。**必须与 worker `buildDeviceBindingSigningMessage`
/// 逐字节一致**：sr25519 主钥对
/// `signing_message(OP_SIGN_SQUARE_DEVICE_BIND,
/// cid_number ‖ binding_revision ‖ account_id ‖ p256_public_key ‖ issued_at)`
/// 签名，证明该 P-256 子钥属于 CID 的当前绑定版本。返回 32 字节摘要。
Uint8List buildDeviceBindingSigningMessage(
  String cidNumber,
  int bindingRevision,
  String accountId,
  String p256PublicKeyHex,
  int issuedAt,
) {
  return signingMessage(
    opTag: kOpSignSquareDeviceBind,
    scalePayload: encodeDeviceBindingPayload(
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
      p256PublicKeyHex: p256PublicKeyHex,
      issuedAtMillis: issuedAt,
    ),
  );
}

/// 设备子钥绑定的唯一 SCALE 载荷；CitizenApp 热签和 CitizenWallet 冷签逐字节共用。
Uint8List encodeDeviceBindingPayload({
  required String cidNumber,
  required int bindingRevision,
  required String accountId,
  required String p256PublicKeyHex,
  required int issuedAtMillis,
}) {
  final cidLength = utf8.encode(cidNumber).length;
  if (cidLength < 1 ||
      cidLength > 32 ||
      bindingRevision <= 0 ||
      !RegExp(r'^0x[0-9a-f]{64}$').hasMatch(accountId) ||
      !RegExp(r'^04[0-9a-f]{128}$').hasMatch(p256PublicKeyHex) ||
      issuedAtMillis <= 0) {
    throw const FormatException('设备子钥绑定载荷字段无效');
  }
  return Uint8List.fromList(<int>[
    ...scaleString(cidNumber),
    ...u64Le(bindingRevision),
    ...scaleString(accountId),
    ...scaleString(p256PublicKeyHex),
    ...u64Le(issuedAtMillis),
  ]);
}

/// DER(X9.62) ECDSA 签名 → 裸 `r||s`（各 [size] 字节，P-256 → 64B）。
///
/// P-256 签名恒为短形长度（总长 < 128B），故只需解析短形 SEQUENCE{INTEGER r,
/// INTEGER s}；r/s 的符号前导 0 会被去除、不足 [size] 左补 0。
Uint8List derEcdsaToRaw(Uint8List der, {int size = 32}) {
  var i = 0;
  if (i >= der.length || der[i++] != 0x30) {
    throw const FormatException('DER: 期望 SEQUENCE');
  }
  final seqLen = der[i++];
  if (seqLen >= 0x80) {
    throw const FormatException('DER: 非预期长形长度');
  }
  if (der[i++] != 0x02) {
    throw const FormatException('DER: 期望 INTEGER r');
  }
  final rLen = der[i++];
  final r = der.sublist(i, i + rLen);
  i += rLen;
  if (der[i++] != 0x02) {
    throw const FormatException('DER: 期望 INTEGER s');
  }
  final sLen = der[i++];
  final s = der.sublist(i, i + sLen);
  i += sLen;

  final out = Uint8List(size * 2);
  _writeFixed(r, out, 0, size);
  _writeFixed(s, out, size, size);
  return out;
}

void _writeFixed(List<int> value, Uint8List out, int offset, int size) {
  var start = 0;
  while (start < value.length - 1 && value[start] == 0) {
    start++;
  }
  final trimmed = value.sublist(start);
  if (trimmed.length > size) {
    throw const FormatException('DER: 整数超长');
  }
  final pad = size - trimmed.length;
  for (var j = 0; j < trimmed.length; j++) {
    out[offset + pad + j] = trimmed[j];
  }
}

Uint8List hexToBytes(String input) {
  final text = input.startsWith('0x') ? input.substring(2) : input;
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(List<int> bytes) {
  const chars = '0123456789abcdef';
  final sb = StringBuffer();
  for (final b in bytes) {
    sb
      ..write(chars[(b >> 4) & 0x0f])
      ..write(chars[b & 0x0f]);
  }
  return sb.toString();
}
