import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/signer/signing.dart'
    show kOpSignCidRebind, signingMessage;
import 'package:citizenapp/security/device_subkey.dart' show bytesToHex;

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

  final SignRequestEnvelope request;
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
  CitizenOccupySignService({AppBusinessQrCodec? signer})
    : _signer = signer ?? AppBusinessQrCodec();
  final AppBusinessQrCodec _signer;

  /// [selectedAccount] = 用户自选或账户卡扫码入口锁定的绑定账户(占即绑一账户)。
  Future<CitizenOccupySignPrep> prepare(
    String raw,
    CitizenWalletStateAccount selectedAccount, [
    CitizenSdkWallet? wallet,
  ]) async {
    final SignRequestEnvelope request;
    try {
      request = _signer.parseRequest(raw);
    } on AppBusinessQrException catch (error) {
      throw CitizenOccupySignException(error.message);
    }
    final action = request.body.action;
    if (!QrActions.isSelfAccountDomainAction(action)) {
      throw const CitizenOccupySignException('该二维码不是注册局占号/换绑请求');
    }
    final actionLabel = QrActions.actionLabelForCode(action);
    if (actionLabel == null) {
      throw const CitizenOccupySignException('未登记的签名动作，已拒绝签名');
    }
    final authorization =
        AppBusinessQrCodec.decodeCidAccountAuthorizationTemplate(
          action: action,
          payload: Uint8List.fromList(request.body.payloadBytes),
        );
    if (authorization == null) {
      throw const CitizenOccupySignException('签名内容无法完整中文展示，已拒绝签名');
    }
    final outerExpiresAt = request.expiresAt;
    if (outerExpiresAt == null ||
        BigInt.from(outerExpiresAt) != authorization.expiresAt) {
      throw const CitizenOccupySignException('二维码过期时间与授权载荷不一致，已拒绝签名');
    }
    final accountId = _accountIdBytes(selectedAccount.accountId);
    if (accountId == null) {
      throw const CitizenOccupySignException('所选账户 account_id 格式错误');
    }
    final materializedPayload = authorization.materialize(accountId);
    if (materializedPayload == null) {
      throw const CitizenOccupySignException('换绑新账户不得与当前绑定账户相同');
    }
    // 只有当前账户私钥在本机可用时才附加旧账户签名；缺失时不伪造、不回退。
    final currentAccount =
        authorization.currentAccountId == null || wallet == null
        ? null
        : _findAccount(
            await wallet.getState(),
            authorization.currentAccountId!,
          );
    return CitizenOccupySignPrep(
      request: request,
      actionLabel: actionLabel,
      cidNumber: authorization.cidNumber,
      isOccupy: action == QrActions.citizenOccupy,
      genesisHash: authorization.genesisHash,
      currentAccountId: authorization.currentAccountId,
      expectedBindingRevision: authorization.expectedBindingRevision,
      expiresAt: authorization.expiresAt,
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
    final accountId = _accountIdBytes(prep.account.accountId);
    if (accountId == null) {
      throw const CitizenOccupySignException('所选账户 account_id 格式错误');
    }
    final bytes = AppBusinessQrCodec.signingBytesForHex(
      payloadHex: prep.request.body.payloadHex,
      action: prep.request.body.action,
      selfAccountId: accountId,
    );
    if (bytes.isEmpty) {
      throw const CitizenOccupySignException('签名负载为空,无法签名');
    }
    final signature = await signCitizenPayload(
      signing: signing,
      context: context,
      accountId: prep.account.accountId,
      payload: bytes,
      action: prep.request.body.action,
    );
    String? currentAccountSignatureHex;
    final currentAccount = prep.currentAccount;
    if (!prep.isOccupy && currentAccount != null) {
      if (context != null && !context.mounted) {
        throw const CitizenOccupySignException('当前签名页面已经关闭');
      }
      // 同一次换绑扫码内，当前账户和新账户共同绑定同一份 materialized payload。
      final currentAccountDigest = signingMessage(
        opTag: kOpSignCidRebind,
        scalePayload: prep.materializedPayload,
      );
      final currentAccountSignature = await signCitizenPayload(
        signing: signing,
        context: context,
        accountId: currentAccount.accountId,
        payload: currentAccountDigest,
        action: kOpSignCidRebind,
      );
      currentAccountSignatureHex = '0x${bytesToHex(currentAccountSignature)}';
    }
    return _signer.encodeResponse(
      _signer.buildResponse(
        request: prep.request,
        signatureHex: '0x${bytesToHex(signature)}',
        signerPublicKeyHexOverride: prep.account.accountId,
        currentAccountIdHex: currentAccount?.accountId,
        currentAccountSignatureHex: currentAccountSignatureHex,
      ),
    );
  }

  static Uint8List? _accountIdBytes(String accountIdHex) {
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(accountIdHex)) return null;
    final hex = accountIdHex.substring(2);
    final out = Uint8List(32);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
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
