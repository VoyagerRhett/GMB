import 'dart:typed_data';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/security/device_subkey.dart';

/// 对设备绑定证明消息（`signing_message` 的 32 字节摘要）做 sr25519 主钥签名，
/// 返回 `0x` hex 签名。
typedef DeviceBindingSigner = Future<String> Function({
  required Uint8List payload,
  required Uint8List signingMessage,
  required String devicePublicKey,
  required int issuedAtMillis,
});
typedef TurnstileTokenProvider = Future<String?> Function();

const _turnstileTokenMinLength = 20;
const _turnstileTokenMaxLength = 2048;

/// 等待根导航器进入可展示状态后，只展示一次设备绑定验证页。
///
/// 冷启动时会话握手可能早于 `MaterialApp` 首帧；此前直接返回空 token 会让正式
/// Worker 必然以 `turnstile_required` 拒绝 iOS 新设备登记。这里仅等待前台 UI，
/// 不重试验证、不在后台伪造 token，也不把取消当成功。
Future<String> acquireDeviceBindingTurnstileToken({
  required bool Function() isUiReady,
  required TurnstileTokenProvider present,
  Duration readyTimeout = const Duration(seconds: 15),
  Duration pollInterval = const Duration(milliseconds: 50),
  Future<void> Function(Duration duration)? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  final deadline = DateTime.now().add(readyTimeout);
  while (!isUiReady()) {
    if (!DateTime.now().isBefore(deadline)) {
      throw const SquareApiException(
        '设备安全验证界面尚未就绪，请稍后重试',
        errorCode: 'turnstile_ui_unavailable',
      );
    }
    await wait(pollInterval);
  }

  final token = await present();
  if (token == null || token.isEmpty) {
    throw const SquareApiException(
      '设备安全验证已取消',
      errorCode: 'turnstile_cancelled',
    );
  }
  if (token.length < _turnstileTokenMinLength ||
      token.length > _turnstileTokenMaxLength) {
    throw const SquareApiException(
      '设备安全验证结果不合法',
      errorCode: 'turnstile_token_invalid',
    );
  }
  return token;
}

/// 编排 P-256 设备子钥注册：取子钥公钥 → 构造 `signing_message(OP_SIGN_SQUARE_DEVICE_BIND)`
/// 32B 摘要 → sr25519 主钥签摘要 → 上报后端。
///
/// 仅在 Worker 明确返回 `device_not_registered` 后调用：读取当前绑定账户 child 完成
/// 一次鉴权签名。钱包创建、CID finalized、页面进入与后台预热均不得调用。
class DeviceSubkeyRegistrar {
  DeviceSubkeyRegistrar({
    DeviceSubkey? deviceSubkey,
    SquareApiClient? apiClient,
    TurnstileTokenProvider? turnstileToken,
  })  : _subkey = deviceSubkey ?? DeviceSubkey(),
        _api = apiClient ?? SquareApiClient(),
        _turnstileToken = turnstileToken;

  final DeviceSubkey _subkey;
  final SquareApiClient _api;
  final TurnstileTokenProvider? _turnstileToken;

  Future<void> register({
    required String cidNumber,
    required int bindingRevision,
    required String accountId,
    required DeviceBindingSigner signBinding,
    int? issuedAtMillis,
  }) async {
    // publicKeyHex 返回裸未压缩点：签名消息 SCALE preimage 用裸（保持逐字节与后端一致），
    // 跨端 wire 文本统一带 `0x`（ADR-041），后端入口一次 require 0x + strip。
    final publicKey = await _subkey.publicKeyHex(cidNumber);
    final issuedAt = issuedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    final payload = encodeDeviceBindingPayload(
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
      p256PublicKeyHex: publicKey,
      issuedAtMillis: issuedAt,
    );
    final message = buildDeviceBindingSigningMessage(
      cidNumber,
      bindingRevision,
      accountId,
      publicKey,
      issuedAt,
    );
    final signatureHex = await signBinding(
      payload: payload,
      signingMessage: message,
      devicePublicKey: publicKey,
      issuedAtMillis: issuedAt,
    );
    final tokenProvider = _turnstileToken;
    if (tokenProvider == null) {
      throw const SquareApiException(
        '设备安全验证未配置',
        errorCode: 'turnstile_ui_unavailable',
      );
    }
    final turnstileToken = await tokenProvider();
    if (turnstileToken == null ||
        turnstileToken.length < _turnstileTokenMinLength ||
        turnstileToken.length > _turnstileTokenMaxLength) {
      throw const SquareApiException(
        '设备安全验证未完成',
        errorCode: 'turnstile_token_invalid',
      );
    }
    await _api.registerDeviceSubkey(
      accountId: accountId,
      p256PublicKeyHex: '0x$publicKey',
      issuedAt: issuedAt,
      bindingSignatureHex: signatureHex,
      turnstileToken: turnstileToken,
    );
  }
}
