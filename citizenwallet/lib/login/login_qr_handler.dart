// CitizenWallet 公民钱包登录 QR 处理器:解析 QR_V1 登录签名请求、
// 构建 QR_V1 签名响应。平台系统签名已删,信任根 = 钱包签名验链上管理员集合。

import 'dart:convert';

import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/signature_message.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/qr/bodies/sign_response_body.dart';
import 'package:citizenwallet/signer/qr_signer.dart';

typedef LoginSignRequestEnvelope = QrEnvelope<SignRequestBody>;
typedef LoginSignResponseEnvelope = QrEnvelope<SignResponseBody>;

/// 展示用辅助:从登录签名请求中获取人可读系统名。
String loginSystemDisplayName(LoginSignRequestEnvelope c) {
  switch (_loginSystem(c).toLowerCase()) {
    case 'onchina':
      return '链上中国平台';
    default:
      return _loginSystem(c).toUpperCase();
  }
}

bool isLoginSignRequestExpired(LoginSignRequestEnvelope c) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return now >= (c.expiresAt ?? 0);
}

/// 登录请求的签名公钥必须与当前选中钱包 AccountId 完全一致。
///
/// 当前 sr25519 账户的 AccountId32 直接取签名公钥 32 字节；双方文本都必须已经是
/// 小写 `0x` 加 64 位十六进制，不在安全边界内做补前缀、大小写转换或 trim。
bool loginRequestTargetsAccountId(
  LoginSignRequestEnvelope request,
  String accountId,
) {
  if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(accountId)) {
    return false;
  }
  return request.body.signerPublicKeyHex == accountId;
}

/// 解析登录签名请求 envelope。
LoginSignRequestEnvelope parseLoginSignRequest(String raw) {
  QrEnvelope<QrBody> env;
  try {
    env = QrEnvelope.parse(raw);
  } on FormatException catch (e) {
    throw LoginQrException('无法解析登录二维码: ${e.message}');
  }
  if (env.kind != QrKind.signRequest) {
    throw const LoginQrException('二维码类型不是签名请求');
  }
  final body = env.body as SignRequestBody;
  if (body.action != QrActions.login) {
    throw const LoginQrException('二维码不是登录签名请求');
  }
  // 与离线签名同源校验请求 ID(字符集/长度):id 后续会裸拼进待签消息(以 `|`
  // 分隔),不校验则可被注入分隔符污染字段解析。
  final id = env.id;
  if (id == null || !QrSigner.isValidRequestId(id)) {
    throw const LoginQrException('登录二维码请求 ID 非法');
  }

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (now >= (env.expiresAt ?? 0)) {
    throw const LoginQrException('登录二维码已过期');
  }
  if (!isQrRequestExpiryValid(env.expiresAt!, now)) {
    throw const LoginQrException('登录二维码有效期过长');
  }
  _loginSystem(
    QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: env.id,
      expiresAt: env.expiresAt,
      body: body,
    ),
  );

  return QrEnvelope<SignRequestBody>(
    kind: QrKind.signRequest,
    id: env.id,
    expiresAt: env.expiresAt,
    body: body,
  );
}

/// 构建用户签名消息(CitizenWallet 钱包用自己的私钥签这串)。
String buildSignMessage(LoginSignRequestEnvelope c, String signerPublicKey) {
  return buildSignatureMessage(
    kind: QrKind.signResponse,
    id: c.id!,
    system: _loginSystem(c),
    expiresAt: c.expiresAt,
    principal: signerPublicKey,
  );
}

/// 从签名结果构建 QR_V1 k=2 登录签名响应 envelope。
LoginSignResponseEnvelope buildLoginSignResponse({
  required LoginSignRequestEnvelope request,
  required String signerPublicKey,
  required String signatureHex,
}) {
  return QrEnvelope<SignResponseBody>(
    kind: QrKind.signResponse,
    id: request.id,
    expiresAt: request.expiresAt,
    body: SignResponseBody.fromHex(
      signerPublicKeyHex: signerPublicKey,
      signatureHex: signatureHex,
    ),
  );
}

// 内部工具
// 登录 payload 固定为 `system` 的 UTF-8 字节(平台系统签名已删,无 sys_sig)。
String _loginSystem(LoginSignRequestEnvelope c) {
  final text = utf8.decode(c.body.payloadBytes, allowMalformed: false);
  if (text != 'onchina') {
    throw const LoginQrException('登录二维码载荷无效');
  }
  return text;
}

class LoginQrException implements Exception {
  final String message;
  const LoginQrException(this.message);
  @override
  String toString() => message;
}
