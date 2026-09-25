import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/signer/square_action_payload.dart';

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

  final CitizenQrDocument request;
  final String actionLabel;
  final SquareActionPayload decoded;
  final CitizenWalletStateAccount account;
}

/// 广场账户动作「签名响应方」（官网无私钥，CitizenApp 扫一扫代签）。
///
/// 流程：扫 signRequest → 解析/两色解码 → 按 QR `u` 定位 accountId 钱包（拒本机没有的账户）
/// → 用户核对动作 → **accountId 主钥**对 signing_message(0x1D) 签名（生物识别）→ 出 signResponse。
class SquareActionSignService {
  SquareActionSignService({required CitizenQr qr}) : _qr = qr;

  final CitizenQr _qr;

  /// 解析 + 两色解码 + 定位钱包（不签名、不弹生物识别）。失败抛 [SquareActionSignException]。
  Future<SquareActionSignPrep> prepare(
    String raw,
    CitizenSdkWallet wallet, {
    CitizenWalletStateAccount? requiredAccount,
  }) async {
    final CitizenQrDocument request;
    try {
      request = (await _qr.parseForPurpose(raw, CitizenQrScanPurpose.signingRequest)).document;
    } on CitizenSdkException catch (e) {
      throw SquareActionSignException(
        SquareActionSignError.invalidRequest,
        e.message,
      );
    }
    if (request.action != CitizenQrActions.squareAccountAction) {
      throw const SquareActionSignException(
        SquareActionSignError.invalidRequest, '该动作不属于 CitizenApp 业务二维码',
      );
    }
    const actionLabel = '广场账户动作签名';
    final decoded = decodeSquareActionPayload(
      '0x${request.reviewPayload!.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}',
    );
    final reviewFields = decoded?.reviewFields;
    if (decoded == null || reviewFields == null) {
      throw const SquareActionSignException(
        SquareActionSignError.undecodable,
        '签名内容无法完整中文展示，已拒绝签名',
      );
    }
    final requestAccountId = request.signerAccountId!.toLowerCase();
    final account =
        requiredAccount ??
        _findAccount(await wallet.getState().result, requestAccountId);
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
    final signBytes = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
      opTag: kOpSignSquareAction, scalePayload: prep.request.reviewPayload!,
    ));
    if (context != null && !context.mounted) {
      throw const SquareActionSignException(
        SquareActionSignError.invalidRequest, '当前签名页面已经关闭',
      );
    }
    final signature = await signCitizenPayload(
      signing: signing,
      context: context,
      accountId: prep.account.accountId,
      payload: signBytes,
      action: prep.request.action!,
    );
    return (await _qr.encodeDocument(CitizenQrContent.signResponse(
      requestId: prep.request.requestId!,
      expiresAt: BigInt.from(prep.request.expiresAt!),
      signerAccountId: prep.account.accountId,
      signature: signature,
    ))).canonicalText;
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
