import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';

class CitizenOccupySignException implements Exception {
  const CitizenOccupySignException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 注册局代办占号/换绑的已校验待签态。请求 b.u 留空,绑定账户由用户自选。
class CitizenOccupySignPrep {
  const CitizenOccupySignPrep({
    required this.request,
    required this.actionLabel,
    required this.cidNumber,
    required this.isOccupy,
    required this.genesisHash,
    required this.currentAccountId,
    required this.expectedBindingRevision,
    required this.expiresAt,
    required this.account,
    required this.materializedPayload,
    this.currentAccount,
  });

  final CitizenQrDocument request;
  final String actionLabel;
  final String cidNumber;
  final bool isOccupy;
  final String genesisHash;

  /// 换绑授权模板中的当前绑定账户；首次占号时为空。
  final String? currentAccountId;
  final BigInt expectedBindingRevision;
  final BigInt expiresAt;
  final CitizenWalletStateAccount account;

  /// 当前账户仅在本机存在可签名私钥时取得，不建立任何服务端恢复通道。
  final CitizenWalletStateAccount? currentAccount;

  /// 已填入新 account_id 的完整 SCALE 载荷，新旧账户对同一份换绑语义签名。
  final Uint8List materializedPayload;
}

/// 注册局占号/换绑签名服务。
///
/// 请求 `b.u` 留空；`d` 必须是包含创世哈希、CID、账户零槽、绑定 revision 和过期时间的
/// 完整 Runtime 授权模板。服务严格解码、核对外层 `e == 内层 expires_at`，再把用户选择
/// 的本机账户原位填入零槽签名；响应 `b.u` 用该账户带回。
class CitizenOccupySignService {
  CitizenOccupySignService({required CitizenQr qr}) : _qr = qr;
  final CitizenQr _qr;

  /// [selectedAccount] = 用户自选或账户卡扫码入口锁定的绑定账户(占即绑一账户)。
  Future<CitizenOccupySignPrep> prepare(
    String raw,
    CitizenWalletStateAccount selectedAccount, [
    CitizenSdkWallet? wallet,
  ]) async {
    final CitizenQrDocument request;
    try {
      request = (await _qr.parseForPurpose(raw, CitizenQrScanPurpose.signingRequest)).document;
    } on CitizenSdkException catch (error) {
      throw CitizenOccupySignException(error.message);
    }
    final action = request.action!;
    if (!CitizenQrActions.isSelfAccountDomainAction(action)) {
      throw const CitizenOccupySignException('该二维码不是注册局占号/换绑请求');
    }
    final actionLabel = action == CitizenQrActions.citizenOccupy
        ? '注册局占号绑定确认' : '注册局换绑账户确认';
    final authorization = await _qr.prepareAccountAuthorization(
      action: action, payload: request.reviewPayload!, accountId: selectedAccount.accountId,
    );
    switch (authorization.reason) {
      case CitizenQrAuthorizationReason.invalidTemplate:
        throw const CitizenOccupySignException('签名内容无法完整中文展示，已拒绝签名');
      case CitizenQrAuthorizationReason.invalidAccountId:
        throw const CitizenOccupySignException('所选账户 account_id 格式错误');
      case CitizenQrAuthorizationReason.sameAccount:
        throw const CitizenOccupySignException('换绑新账户不得与当前绑定账户相同');
      case CitizenQrAuthorizationReason.valid:
        break;
    }
    final outerExpiresAt = request.expiresAt;
    if (outerExpiresAt == null ||
        BigInt.from(outerExpiresAt) != authorization.expiresAt) {
      throw const CitizenOccupySignException('二维码过期时间与授权载荷不一致，已拒绝签名');
    }
    final materializedPayload = authorization.materializedPayload!;
    // 只有当前账户私钥在本机可用时才附加旧账户签名；缺失时不伪造、不回退。
    final currentAccount =
        authorization.currentAccountId == null || wallet == null
        ? null
        : _findAccount(
            await wallet.getState().result,
            authorization.currentAccountId!,
          );
    return CitizenOccupySignPrep(
      request: request,
      actionLabel: actionLabel,
      cidNumber: authorization.cidNumber!,
      isOccupy: action == CitizenQrActions.citizenOccupy,
      genesisHash: authorization.genesisHash!,
      currentAccountId: authorization.currentAccountId,
      expectedBindingRevision: authorization.expectedBindingRevision!,
      expiresAt: authorization.expiresAt!,
      account: selectedAccount,
      currentAccount: currentAccount,
      materializedPayload: materializedPayload,
    );
  }

  Future<String> sign(
    CitizenOccupySignPrep prep,
    CitizenSigning signing,
    BuildContext? context,
  ) async {
    final bytes = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
      opTag: prep.isOccupy ? kOpSignCidOccupy : kOpSignCidAdminRebind,
      scalePayload: prep.materializedPayload,
    ));
    if (context != null && !context.mounted) {
      throw const CitizenOccupySignException('当前签名页面已经关闭');
    }
    final signature = await signCitizenPayload(
      signing: signing,
      context: context,
      accountId: prep.account.accountId,
      payload: bytes,
      action: prep.request.action!,
    );
    Uint8List? currentAccountSignature;
    final currentAccount = prep.currentAccount;
    if (!prep.isOccupy && currentAccount != null) {
      if (context != null && !context.mounted) {
        throw const CitizenOccupySignException('当前签名页面已经关闭');
      }
      // 同一次换绑扫码内，当前账户和新账户共同绑定同一份 materialized payload。
      final currentAccountDigest = await CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignCidRebind,
        scalePayload: prep.materializedPayload,
      ));
      if (context != null && !context.mounted) {
        throw const CitizenOccupySignException('当前签名页面已经关闭');
      }
      currentAccountSignature = await signCitizenPayload(
        signing: signing,
        context: context,
        accountId: currentAccount.accountId,
        payload: currentAccountDigest,
        action: kOpSignCidRebind,
      );
    }
    return (await _qr.encodeDocument(CitizenQrContent.signResponse(
      requestId: prep.request.requestId!,
      expiresAt: BigInt.from(prep.request.expiresAt!),
      signerAccountId: prep.account.accountId,
      signature: signature,
      currentAccountId: currentAccountSignature == null ? null : currentAccount?.accountId,
      currentAccountSignature: currentAccountSignature,
    ))).canonicalText;
  }

  static CitizenWalletStateAccount? _findAccount(
    CitizenWalletState state,
    String accountId,
  ) {
    final expected = accountId.toLowerCase();
    for (final account in state.accounts) {
      if (account.accountId.toLowerCase() == expected) return account;
    }
    return null;
  }
}
