import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/signer/square_action_payload.dart';
import 'package:citizenapp/security/device_subkey.dart' show bytesToHex;

enum SquareActionSignError { invalidRequest, undecodable, accountNotLocal }

class SquareActionSignException implements Exception {
  const SquareActionSignException(this.error, this.message);

  final SquareActionSignError error;
  final String message;

  @override
  String toString() => message;
}

/// 扫到的广场账户动作签名请求，经校验/解码/定位钱包后的待签态。
class SquareActionSignPrep {
  const SquareActionSignPrep({
    required this.request,
    required this.actionLabel,
    required this.decoded,
    required this.account,
  });

  final SignRequestEnvelope request;
  final String actionLabel;
  final SquareActionPayload decoded;
  final CitizenWalletStateAccount account;
}

/// 广场账户动作「签名响应方」（官网无私钥，CitizenApp 扫一扫代签）。
///
/// 流程：扫 signRequest → 解析/两色解码 → 按 QR `u` 定位 accountId 钱包（拒本机没有/冷钱包）
/// → 用户核对动作 → **accountId 主钥**对 signing_message(0x1D) 签名（生物识别）→ 出 signResponse。
class SquareActionSignService {
  SquareActionSignService({AppBusinessQrCodec? signer})
    : _signer = signer ?? AppBusinessQrCodec();

  final AppBusinessQrCodec _signer;

  /// 解析 + 两色解码 + 定位钱包（不签名、不弹生物识别）。失败抛 [SquareActionSignException]。
  Future<SquareActionSignPrep> prepare(
    String raw,
    CitizenSdkWallet wallet, {
    CitizenWalletStateAccount? requiredAccount,
  }) async {
    final SignRequestEnvelope request;
    try {
      request = _signer.parseRequest(raw);
    } on AppBusinessQrException catch (e) {
      throw SquareActionSignException(
        SquareActionSignError.invalidRequest,
        e.message,
      );
    }
    final body = request.body;
    final actionLabel = QrActions.actionLabelForCode(body.action)!;
    final decoded = decodeSquareActionPayload(body.payloadHex);
    final reviewFields = decoded?.reviewFields;
    if (decoded == null || reviewFields == null) {
      throw const SquareActionSignException(
        SquareActionSignError.undecodable,
        '签名内容无法完整中文展示，已拒绝签名',
      );
    }
    final requestAccountId = body.signerPublicKeyHex.toLowerCase();
    final account =
        requiredAccount ??
        _findAccount(await wallet.getState(), requestAccountId);
    if (account == null ||
        _normalizeHex(account.accountId) != _normalizeHex(requestAccountId)) {
      throw const SquareActionSignException(
        SquareActionSignError.accountNotLocal,
        '此签名请求的账户不在本机',
      );
    }
    return SquareActionSignPrep(
      request: request,
      actionLabel: actionLabel,
      decoded: decoded,
      account: account,
    );
  }

  /// 主钥签名（读硬件金库、弹生物识别）→ 构造 signResponse envelope JSON。
  Future<String> sign(
    SquareActionSignPrep prep,
    CitizenSigning signing,
    BuildContext? context,
  ) async {
    final signBytes = AppBusinessQrCodec.signingBytesForHex(
      payloadHex: prep.request.body.payloadHex,
      action: prep.request.body.action,
    );
    final signature = await signCitizenPayload(
      signing: signing,
      context: context,
      accountId: prep.account.accountId,
      payload: signBytes,
      action: prep.request.body.action,
    );
    final response = _signer.buildResponse(
      request: prep.request,
      signatureHex: '0x${bytesToHex(signature)}',
    );
    return _signer.encodeResponse(response);
  }

  static String _normalizeHex(String hex) {
    final text = hex.startsWith('0x') || hex.startsWith('0X')
        ? hex.substring(2)
        : hex;
    return text.toLowerCase();
  }

  static CitizenWalletStateAccount? _findAccount(
    CitizenWalletState state,
    String accountId,
  ) {
    for (final account in state.accounts) {
      if (_normalizeHex(account.accountId) == _normalizeHex(accountId)) {
        return account;
      }
    }
    return null;
  }
}
