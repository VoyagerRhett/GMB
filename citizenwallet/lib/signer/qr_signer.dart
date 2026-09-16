import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/blake2b.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/wallet/native_sr25519.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/qr/bodies/sign_response_body.dart';

import 'payload_decoder.dart';

enum QrSignErrorCode {
  invalidFormat,
  invalidField,
  invalidProtocol,
  expired,
  mismatchedRequest,
  mismatchedAccount,
  mismatchedSignerPublicKey,
  mismatchedPayloadHash,
  invalidSignature,
}

class QrSignException implements Exception {
  const QrSignException(this.code, this.message);

  final QrSignErrorCode code;
  final String message;

  @override
  String toString() => message;
}

typedef SignRequestEnvelope = QrEnvelope<SignRequestBody>;
typedef SignResponseEnvelope = QrEnvelope<SignResponseBody>;

class QrSigner {
  static const int maxPayloadChars = 32768;
  static const List<int> _gmbPrefix = [0x47, 0x4D, 0x42];
  static const int _opSignCitizenIdentity = 0x10;
  static const int _opSignCidOccupy = 0x12;
  static const int _opSignCidAdminRebind = 0x1F;

  /// 链上中国平台管理员治理动作;与 primitives::sign::OP_SIGN_ONCHINA_ADMIN 同值。
  static const int _opSignOnchinaAdmin = 0x20;

  /// 本机默认账户切换；与 primitives::sign::OP_SIGN_SWITCH_DEFAULT_ACCOUNT 同值。
  static const int _opSignSwitchDefaultAccount = 0x21;

  /// 广场/Chat P-256 设备子钥绑定；复用 primitives 既有 0x1C 域。
  static const int _opSignSquareDeviceBind = 0x1c;

  /// 广场账户敏感动作；与 primitives::sign::OP_SIGN_SQUARE_ACTION 同值。
  static const int _opSignSquareAction = 0x1d;

  /// 产品正式发布授权；对齐 primitives::sign::OP_SIGN_PUBLISH。
  static const int _opSignPublish = 0x24;
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  /// 请求 ID 合法性(共享单源:登录/离线签名同一规则,防两处漂移)。
  static bool isValidRequestId(String id) => _idPattern.hasMatch(id);

  static String generateRequestId({String prefix = ''}) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    final id = prefix.isEmpty ? token : '$prefix$token';
    return id.length > 128 ? id.substring(0, 128) : id;
  }

  /// 解析 sign_request envelope(CitizenWallet 公民钱包从 CitizenApp 扫到的内容)。
  SignRequestEnvelope parseRequest(String raw) {
    if (raw.isEmpty || raw.length > maxPayloadChars) {
      throw const QrSignException(
        QrSignErrorCode.invalidFormat,
        '扫码数据格式错误:内容为空或超出长度限制',
      );
    }
    // 预检 kind:在完整 body 解析之前拦截非 sign_request,
    // 避免 body 结构不匹配导致的 FormatException 掩盖真实错误。
    try {
      final preview = jsonDecode(raw);
      if (preview is Map<String, dynamic>) {
        final kindWire = preview['k'];
        final kind = QrKind.fromWire(kindWire);
        if (kind != QrKind.signRequest) {
          throw const QrSignException(
            QrSignErrorCode.invalidField,
            '二维码类型不是签名请求',
          );
        }
      }
    } on QrSignException {
      rethrow;
    } catch (_) {
      // JSON 解析失败等情况交给下面的 QrEnvelope.parse 统一报错
    }
    QrEnvelope<QrBody> env;
    try {
      env = QrEnvelope.parse(raw);
    } on FormatException catch (e) {
      throw QrSignException(QrSignErrorCode.invalidFormat, e.message);
    }
    if (env.kind != QrKind.signRequest) {
      throw const QrSignException(QrSignErrorCode.invalidField, '二维码类型不是签名请求');
    }
    final body = env.body as SignRequestBody;
    _validateRequestId(env.id!);
    _validateExpiry(expiresAt: env.expiresAt!);
    return QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: env.id,
      expiresAt: env.expiresAt,
      body: body,
    );
  }

  /// 构造 sign_response envelope(CitizenWallet 公民钱包签名完成后生成)。
  SignResponseEnvelope buildResponse({
    required SignRequestEnvelope request,
    required String signatureHex,
    String? signerPublicKeyHexOverride,
    int? nowEpochSeconds,
  }) {
    final requestBody = request.body;
    _validateHexField(signatureHex, 'signature');
    // 占号/换绑:请求 b.u 留空,响应 b.u 用钱包自选账户(override)带回,供 OnChina 取 account_id。
    final responseSignerPublicKeyHex =
        signerPublicKeyHexOverride ?? requestBody.signerPublicKeyHex;
    return QrEnvelope<SignResponseBody>(
      kind: QrKind.signResponse,
      id: request.id,
      expiresAt: request.expiresAt,
      body: SignResponseBody.fromHex(
        signerPublicKeyHex: responseSignerPublicKeyHex,
        signatureHex: signatureHex,
      ),
    );
  }

  String encodeResponse(SignResponseEnvelope response) => response.toRawJson();
  String encodeRequest(SignRequestEnvelope request) => request.toRawJson();

  static String computePayloadHash(String payloadHex) {
    final bytes = _hexToBytes(payloadHex);
    final digest = sha256.convert(bytes);
    return '0x${digest.toString()}';
  }

  static bool verifySr25519Signature({
    required String signerPublicKeyHex,
    required String signatureHex,
    required Uint8List message,
  }) {
    // 全仓 sr25519 唯一实现：原生 schnorrkel（[NativeSr25519]，与 CitizenApp
    // 热端同一份源码）。长度非法 / 公钥或签名格式错 / 验签不过一律 false（fail-closed）。
    try {
      return NativeSr25519.verify(
        _hexToBytes(signerPublicKeyHex),
        _hexToBytes(signatureHex),
        message,
      );
    } on Object {
      return false;
    }
  }

  /// Substrate 交易签名必须复刻 SignedPayload::using_encoded:
  /// payload <= 256B 时签原文,>256B 时签 blake2_256(payload)。
  static Uint8List signingBytesFor(
    SignRequestBody body, {
    Uint8List? selfAccountId,
  }) {
    final payload = body.payloadBytes;
    if (body.action == QrActions.citizenIdentity) {
      return _gmbSigningMessage(_opSignCitizenIdentity, payload);
    }
    if (QrActions.isSelfAccountDomainAction(body.action)) {
      if (selfAccountId == null || selfAccountId.length != 32) {
        return Uint8List(0);
      }
      // 两种授权结构的账户槽位置不同，必须严格解析模板并原位替换；
      // 禁止恢复旧版 `payload ++ account_id` 拼接。
      final authorization = body.action == QrActions.citizenOccupy
          ? PayloadDecoder.readCidOccupyAuthorizationTemplate(payload)
          : PayloadDecoder.readCidRebindAuthorizationTemplate(payload);
      final exactPayload = authorization?.materialize(selfAccountId);
      if (exactPayload == null) return Uint8List(0);
      final opTag = body.action == QrActions.citizenOccupy
          ? _opSignCidOccupy
          : _opSignCidAdminRebind;
      return _gmbSigningMessage(opTag, exactPayload);
    }
    // 链上中国治理动作:走统一哈希域,不再对裸 JSON 文本直签。
    if (body.action == QrActions.onchinaAdmin) {
      return _gmbSigningMessage(_opSignOnchinaAdmin, payload);
    }
    if (body.action == QrActions.switchDefaultAccount) {
      return _gmbSigningMessage(_opSignSwitchDefaultAccount, payload);
    }
    if (body.action == QrActions.squareDeviceBind) {
      return _gmbSigningMessage(_opSignSquareDeviceBind, payload);
    }
    if (body.action == QrActions.squareAccountAction) {
      return _gmbSigningMessage(_opSignSquareAction, payload);
    }
    if (body.action == QrActions.publish) {
      return _gmbSigningMessage(_opSignPublish, payload);
    }
    if (body.action == QrActions.accountDataKeyProvision) {
      // 真正签名内容还必须包含发送公钥、nonce 和密文摘要；普通签名路径无法构造。
      return Uint8List(0);
    }
    if (QrActions.isChainAction(body.action) && payload.length > 256) {
      final digest = Blake2bDigest(digestSize: 32)
        ..update(payload, 0, payload.length);
      final out = Uint8List(32);
      digest.doFinal(out, 0);
      return out;
    }
    return payload;
  }

  static Uint8List _gmbSigningMessage(int opTag, Uint8List payload) {
    final bytes = Uint8List.fromList([..._gmbPrefix, opTag, ...payload]);
    final digest = Blake2bDigest(digestSize: 32)
      ..update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  void _validateRequestId(String requestId) {
    if (!_idPattern.hasMatch(requestId)) {
      throw const QrSignException(QrSignErrorCode.invalidField, 'id 格式错误');
    }
  }

  void _validateHexField(String value, String field) {
    // 机读字段统一使用小写 0x hex，拒绝裸 hex、大写和混合大小写。
    if (!value.startsWith('0x')) {
      throw QrSignException(QrSignErrorCode.invalidField, '$field 必须以小写 0x 开头');
    }
    final text = value.substring(2);
    if (text.isEmpty || text.length.isOdd) {
      throw QrSignException(QrSignErrorCode.invalidField, '$field 必须是偶数字节 hex');
    }
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(text)) {
      throw QrSignException(QrSignErrorCode.invalidField, '$field 必须是小写 hex');
    }
  }

  void _validateExpiry({required int expiresAt}) {
    final now = _now();
    if (expiresAt <= now) {
      throw const QrSignException(QrSignErrorCode.expired, '交易签名请求已过期');
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static List<int> _hexToBytes(String input) {
    if (!input.startsWith('0x')) {
      throw const FormatException('hex 必须以小写 0x 开头');
    }
    final text = input.substring(2);
    if (text.isEmpty ||
        text.length.isOdd ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(text)) {
      throw const FormatException('hex 必须是小写偶数字节十六进制');
    }
    return List<int>.generate(
      text.length ~/ 2,
      (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16),
      growable: false,
    );
  }
}
