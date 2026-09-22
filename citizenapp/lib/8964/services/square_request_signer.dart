import 'package:citizen_sdk/citizen_sdk.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';


typedef SquareDeviceSigner = Future<String> Function(Uint8List message);

/// 构造与 Worker 完全一致的请求证明；P-256 私钥仍由系统 Keystore/SE 持有。
Future<Map<String, String>> squareRequestHeaders({
  required String method,
  required Uri uri,
  required String body,
  required String sessionToken,
  required SquareDeviceSigner sign,
  int? requestTime,
  String? nonce,
}) async {
  return squareRequestHeadersForBytes(
    method: method,
    uri: uri,
    body: Uint8List.fromList(utf8.encode(body)),
    sessionToken: sessionToken,
    sign: sign,
    requestTime: requestTime,
    nonce: nonce,
  );
}

/// 二进制上传沿用同一设备证明协议，但哈希必须覆盖原始字节，不能先转字符串。
Future<Map<String, String>> squareRequestHeadersForBytes({
  required String method,
  required Uri uri,
  required Uint8List body,
  required String sessionToken,
  required SquareDeviceSigner sign,
  int? requestTime,
  String? nonce,
}) async {
  final time = requestTime ?? DateTime.now().millisecondsSinceEpoch;
  final requestNonce = nonce ?? _nonce();
  final path = _apiPath(uri);
  final canonical = <String>[
    'square_request',
    method.toUpperCase(),
    uri.hasQuery ? '$path?${uri.query}' : path,
    sha256.convert(body).toString(),
    '$time',
    requestNonce,
    sha256.convert(utf8.encode(sessionToken)).toString(),
  ].join('\n');
  // 请求证明属于现有广场 BFF 会话认证域，不新增链上签名类型。
  final message = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
    opTag: kOpSignSquareLogin,
    scalePayload: await CitizenSigning.encodePayload(CitizenSigningPayload.scaleString(canonical)),
  ));
  return {
    'x-device-time': '$time',
    'x-device-nonce': requestNonce,
    'x-device-signature': await sign(message),
  };
}

String _apiPath(Uri uri) {
  const prefix = '/api';
  if (uri.path == prefix) return '/';
  if (uri.path.startsWith('$prefix/')) {
    return uri.path.substring(prefix.length);
  }
  return uri.path;
}

String _nonce() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}
