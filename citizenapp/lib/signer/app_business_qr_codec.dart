import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:citizenapp/qr/bodies/sign_request_body.dart';
import 'package:citizenapp/qr/bodies/sign_response_body.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/signing.dart';

enum AppBusinessQrErrorCode {
  invalidFormat,
  invalidField,
  expired,
  unsupportedAction,
}

class AppBusinessQrException implements Exception {
  const AppBusinessQrException(this.code, this.message);

  final AppBusinessQrErrorCode code;
  final String message;

  @override
  String toString() => message;
}

typedef SignRequestEnvelope = QrEnvelope<SignRequestBody>;
typedef SignResponseEnvelope = QrEnvelope<SignResponseBody>;

/// 注册局占号/换绑二维码中的完整授权模板。
///
/// 生成端把待绑定账户写成 32 字节零槽；签名端必须严格解码全部字段且确认无尾字节，
/// 再把用户选择的账户原位填入。禁止恢复已经删除的末尾拼接载荷。
class CidAccountAuthorizationTemplate {
  CidAccountAuthorizationTemplate._({
    required Uint8List payload,
    required this.genesisHash,
    required this.cidNumber,
    required this.currentAccountId,
    required this.expectedBindingRevision,
    required this.expiresAt,
    required int accountOffset,
  })  : _payload = Uint8List.fromList(payload),
        _accountOffset = accountOffset;

  final Uint8List _payload;
  final int _accountOffset;
  final String genesisHash;
  final String cidNumber;
  final String? currentAccountId;
  final BigInt expectedBindingRevision;
  final BigInt expiresAt;

  /// 把所选账户填回授权结构的零槽，返回与 Runtime 逐字节一致的 SCALE。
  ///
  /// 换绑时当前账户与新账户相同必须拒绝，不能生成可签名载荷。
  Uint8List? materialize(Uint8List accountId) {
    if (accountId.length != 32) return null;
    final chainCurrentAccountId = currentAccountId;
    if (chainCurrentAccountId != null &&
        chainCurrentAccountId == AppBusinessQrCodec._bytesToLowerHex(accountId)) {
      return null;
    }
    final output = Uint8List.fromList(_payload);
    output.setRange(_accountOffset, _accountOffset + 32, accountId);
    return output;
  }
}

/// CitizenApp 专用业务二维码编解码器。
///
/// 只允许公民身份确认、注册局占号／换绑、广场账户动作和冷账户用途钥四类
/// CitizenApp 业务。通用账户码、通用签名会话和冷热钱包分流全部属于 CitizenSDK。
class AppBusinessQrCodec {
  static const int defaultTtlSeconds = 90;
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  static bool isSupportedAction(int action) =>
      action == QrActions.citizenIdentity ||
      QrActions.isSelfAccountDomainAction(action) ||
      action == QrActions.squareAccountAction ||
      action == QrActions.accountDataKeyProvision;

  /// 生成加密安全的随机 request id。base64url 比 hex 短,可降低二维码密度。
  static String generateRequestId({String prefix = ''}) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    final id = prefix.isEmpty ? token : '$prefix$token';
    return id.length > 128 ? id.substring(0, 128) : id;
  }

  /// 构造 QR_V1 签名请求。
  SignRequestEnvelope buildRequest({
    required String requestId,
    required String signerPublicKey,
    required String payloadHex,
    required int action,
    int? nowEpochSeconds,
    int ttlSeconds = defaultTtlSeconds,
  }) {
    final now = nowEpochSeconds ?? _now();
    _validateAction(action);
    _validateRequestId(requestId);
    _validateHexField(signerPublicKey, 'signer_public_key');
    _validateHexField(payloadHex, 'payload');
    return QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: requestId,
      issuedAt: now,
      expiresAt: now + ttlSeconds,
      body: SignRequestBody.fromHex(
        action: action,
        signerPublicKeyHex: signerPublicKey,
        payloadHex: payloadHex,
      ),
    );
  }

  String encodeRequest(SignRequestEnvelope request) => request.toRawJson();

  String encodeResponse(SignResponseEnvelope response) => response.toRawJson();

  /// 构造 sign_response envelope。签名响应只携带 u/s,请求绑定由 id 完成。
  SignResponseEnvelope buildResponse({
    required SignRequestEnvelope request,
    required String signatureHex,
    String? signerPublicKeyHexOverride,
    String? currentAccountIdHex,
    String? currentAccountSignatureHex,
  }) {
    _validateAction(request.body.action);
    _validateHexField(signatureHex, 'signature');
    return QrEnvelope<SignResponseBody>(
      kind: QrKind.signResponse,
      id: request.id,
      issuedAt: request.issuedAt,
      expiresAt: request.expiresAt,
      body: SignResponseBody.fromHex(
        // 占号/换绑:请求 b.u 留空,响应 b.u 用钱包自选账户带回,供 OnChina 取 account_id。
        signerPublicKeyHex:
            signerPublicKeyHexOverride ?? request.body.signerPublicKeyHex,
        signatureHex: signatureHex,
        currentAccountIdHex: currentAccountIdHex,
        currentAccountSignatureHex: currentAccountSignatureHex,
      ),
    );
  }

  SignRequestEnvelope parseRequest(String raw) {
    QrEnvelope<QrBody> env;
    try {
      env = QrEnvelope.parse(raw);
    } on FormatException catch (e) {
      throw AppBusinessQrException(AppBusinessQrErrorCode.invalidFormat, e.message);
    }
    if (env.kind != QrKind.signRequest) {
      throw const AppBusinessQrException(AppBusinessQrErrorCode.invalidField, '二维码类型不是签名请求');
    }
    final body = env.body as SignRequestBody;
    _validateAction(body.action);
    _validateRequestId(env.id!);
    _validateExpiry(expiresAt: env.expiresAt!);
    return QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: env.id,
      issuedAt: env.issuedAt,
      expiresAt: env.expiresAt,
      body: body,
    );
  }

  /// 按 CitizenApp 业务动作构造交给 CitizenSDK 的最终签名字节。
  static Uint8List signingBytesForHex({
    required String payloadHex,
    required int action,
    Uint8List? selfAccountId,
  }) {
    final payload = Uint8List.fromList(_hexToBytes(payloadHex));
    if (action == QrActions.citizenIdentity) {
      return signingMessage(
        opTag: kOpSignCitizenIdentity,
        scalePayload: payload,
      );
    }
    if (QrActions.isSelfAccountDomainAction(action)) {
      if (selfAccountId == null || selfAccountId.length != 32) {
        return Uint8List(0);
      }
      // 两种授权结构的账户槽位置不同：严格解析完整模板并原位填入所选账户。
      // 任何零槽污染、revision 错误、尾字节或当前账户与新账户相同都 fail-closed。
      final authorization = decodeCidAccountAuthorizationTemplate(
        action: action,
        payload: payload,
      );
      final exactPayload = authorization?.materialize(selfAccountId);
      if (exactPayload == null) return Uint8List(0);
      final opTag = action == QrActions.citizenOccupy
          ? kOpSignCidOccupy
          : kOpSignCidAdminRebind;
      return signingMessage(opTag: opTag, scalePayload: exactPayload);
    }
    if (action == QrActions.squareAccountAction) {
      return signingMessage(opTag: kOpSignSquareAction, scalePayload: payload);
    }
    if (action == QrActions.accountDataKeyProvision) return payload;
    throw const AppBusinessQrException(
      AppBusinessQrErrorCode.unsupportedAction,
      '该动作不属于 CitizenApp 业务二维码',
    );
  }

  /// 严格解析注册局占号/换绑的完整授权模板。
  ///
  /// occupy:
  /// `genesis_hash + bounded cid + account_id(32B 零槽) + revision=0 + expires`
  ///
  /// rebind:
  /// `genesis_hash + bounded cid + current_account_id`
  /// `+ new_account_id(32B 零槽) + revision(nonzero) + expires`
  static CidAccountAuthorizationTemplate?
      decodeCidAccountAuthorizationTemplate({
    required int action,
    required Uint8List payload,
  }) {
    if (action == QrActions.citizenOccupy) {
      return _decodeCidOccupyAuthorizationTemplate(payload);
    }
    if (action == QrActions.citizenRebind) {
      return _decodeCidRebindAuthorizationTemplate(payload);
    }
    return null;
  }

  static CidAccountAuthorizationTemplate? _decodeCidOccupyAuthorizationTemplate(
    Uint8List bytes,
  ) {
    if (bytes.length < 32) return null;
    var offset = 32;
    final cidRead = _readCanonicalBoundedCid(bytes, offset);
    if (cidRead == null) return null;
    offset = cidRead.$2;
    final accountOffset = offset;
    if (!_hasZeroAccountSlot(bytes, accountOffset)) return null;
    offset += 32;
    if (offset + 16 != bytes.length) return null;
    final revision = _readU64LittleEndian(bytes, offset);
    offset += 8;
    final expiresAt = _readU64LittleEndian(bytes, offset);
    if (revision != BigInt.zero || expiresAt <= BigInt.zero) return null;
    return CidAccountAuthorizationTemplate._(
      payload: bytes,
      genesisHash: _bytesToLowerHex(bytes.sublist(0, 32)),
      cidNumber: cidRead.$1,
      currentAccountId: null,
      expectedBindingRevision: revision,
      expiresAt: expiresAt,
      accountOffset: accountOffset,
    );
  }

  static CidAccountAuthorizationTemplate? _decodeCidRebindAuthorizationTemplate(
    Uint8List bytes,
  ) {
    if (bytes.length < 64) return null;
    var offset = 32;
    final cidRead = _readCanonicalBoundedCid(bytes, offset);
    if (cidRead == null) return null;
    offset = cidRead.$2;
    if (offset + 32 > bytes.length) return null;
    final currentAccount = bytes.sublist(offset, offset + 32);
    offset += 32;
    final accountOffset = offset;
    if (!_hasZeroAccountSlot(bytes, accountOffset)) return null;
    offset += 32;
    if (offset + 16 != bytes.length) return null;
    final revision = _readU64LittleEndian(bytes, offset);
    offset += 8;
    final expiresAt = _readU64LittleEndian(bytes, offset);
    if (revision <= BigInt.zero || expiresAt <= BigInt.zero) return null;
    return CidAccountAuthorizationTemplate._(
      payload: bytes,
      genesisHash: _bytesToLowerHex(bytes.sublist(0, 32)),
      cidNumber: cidRead.$1,
      currentAccountId: _bytesToLowerHex(currentAccount),
      expectedBindingRevision: revision,
      expiresAt: expiresAt,
      accountOffset: accountOffset,
    );
  }

  /// CID 上限只有 32 字节，因此其规范 SCALE Compact 长度只能使用单字节 mode 0。
  static (String, int)? _readCanonicalBoundedCid(Uint8List bytes, int offset) {
    if (offset >= bytes.length || (bytes[offset] & 0x03) != 0) return null;
    final length = bytes[offset] >> 2;
    if (length == 0 || length > 32) return null;
    final start = offset + 1;
    final end = start + length;
    if (end > bytes.length) return null;
    final raw = bytes.sublist(start, end);
    if (raw.any((byte) => byte < 0x21 || byte > 0x7e)) return null;
    return (String.fromCharCodes(raw), end);
  }

  static bool _hasZeroAccountSlot(Uint8List bytes, int offset) {
    if (offset + 32 > bytes.length) return false;
    for (var index = offset; index < offset + 32; index++) {
      if (bytes[index] != 0) return false;
    }
    return true;
  }

  static BigInt _readU64LittleEndian(Uint8List bytes, int offset) {
    var value = BigInt.zero;
    for (var index = 7; index >= 0; index--) {
      value = (value << 8) | BigInt.from(bytes[offset + index]);
    }
    return value;
  }

  static String _bytesToLowerHex(List<int> bytes) =>
      '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';

  void _validateRequestId(String requestId) {
    if (!_idPattern.hasMatch(requestId)) {
      throw const AppBusinessQrException(AppBusinessQrErrorCode.invalidField, 'id 格式错误');
    }
  }

  static void _validateAction(int action) {
    if (!isSupportedAction(action)) {
      throw const AppBusinessQrException(
        AppBusinessQrErrorCode.unsupportedAction,
        '该动作不属于 CitizenApp 业务二维码',
      );
    }
  }

  void _validateHexField(String value, String field) {
    if (!value.startsWith('0x')) {
      throw AppBusinessQrException(AppBusinessQrErrorCode.invalidField, '$field 必须以 0x 开头');
    }
    final text = value.substring(2);
    if (text.isEmpty || text.length.isOdd) {
      throw AppBusinessQrException(AppBusinessQrErrorCode.invalidField, '$field 必须是偶数字节 hex');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
      throw AppBusinessQrException(AppBusinessQrErrorCode.invalidField, '$field 必须是合法 hex');
    }
  }

  void _validateExpiry({required int expiresAt}) {
    final now = _now();
    if (expiresAt <= now) {
      throw const AppBusinessQrException(AppBusinessQrErrorCode.expired, '交易签名请求已过期');
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static List<int> _hexToBytes(String input) {
    final text = input.startsWith('0x') || input.startsWith('0X')
        ? input.substring(2)
        : input;
    if (text.isEmpty || text.length.isOdd) return const <int>[];
    return List<int>.generate(
      text.length ~/ 2,
      (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16),
      growable: false,
    );
  }
}
