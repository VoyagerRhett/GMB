import 'dart:typed_data';

import '../chain_constants.dart';
import '../qr/qr_protocols.dart';
import '../qr/envelope.dart';
import '../qr/bodies/account_data_key_response_body.dart';
import '../isar/wallet_isar.dart';
import '../security/account_data_key_provision.dart';
import '../wallet/wallet_manager.dart';
import 'action_labels.dart';
import 'field_labels.dart';
import 'payload_decoder.dart';
import 'qr_signer.dart';

enum OfflineSignErrorCode {
  accountNotFound,
  accountMismatch,
  invalidPayload,
  contentMismatch,
  expired,
  replayed,
}

class OfflineSignException implements Exception {
  const OfflineSignException(this.code, this.message);

  final OfflineSignErrorCode code;
  final String message;

  @override
  String toString() => message;
}

/// 离线签名验证结果。
class OfflineSignVerification {
  const OfflineSignVerification({
    required this.decoded,
    required this.status,
    required this.actionLabel,
    this.rejectReason,
  });

  final DecodedPayload? decoded;
  final SignDecisionStatus status;
  final String? actionLabel;
  final String? rejectReason;

  bool get canSign => status == SignDecisionStatus.normal;
}

/// 公民钱包扫码签名只允许两种终态。
///
/// normal = 绿色,允许签名；reject = 红色,禁止签名。
/// 不再保留“动作不匹配/解码失败”等独立状态,原因统一放入 rejectReason。
enum SignDecisionStatus { normal, reject }

/// 离线签名执行服务。
class OfflineSignService {
  OfflineSignService({WalletManager? walletManager, QrSigner? signer})
      : _walletManager = walletManager ?? WalletManager(),
        _signer = signer ?? QrSigner();

  final WalletManager _walletManager;
  final QrSigner _signer;

  SignRequestEnvelope parseRequest(String raw) {
    return _signer.parseRequest(raw);
  }

  OfflineSignVerification verifyPayload(SignRequestEnvelope request) {
    final body = request.body;
    final qrActionLabel = actionLabelForQrAction(body.action);
    if (qrActionLabel == null) {
      return const OfflineSignVerification(
        decoded: null,
        status: SignDecisionStatus.reject,
        actionLabel: null,
        rejectReason: '未登记的签名动作，已拒绝签名',
      );
    }

    // Runtime 升级只在 QR 中携带 32B 待签摘要,原始 WASM call_data 留在生成端 session。
    if (QrActions.isRuntimeHashOnly(body.action)) {
      if (body.payloadBytes.length == 32) {
        return OfflineSignVerification(
          decoded: null,
          status: SignDecisionStatus.normal,
          actionLabel: qrActionLabel,
        );
      }
      return OfflineSignVerification(
        decoded: null,
        status: SignDecisionStatus.reject,
        actionLabel: qrActionLabel,
        rejectReason: 'Runtime 升级签名载荷必须是 32 字节哈希，已拒绝签名',
      );
    }

    // 注册局首次绑定/换绑域签名：严格解析完整授权模板，外层 e 必须等于模板
    // expires_at；账户槽只能由当前所选账户原位替换。
    if (QrActions.isSelfAccountDomainAction(body.action)) {
      final isOccupy = body.action == QrActions.citizenOccupy;
      final authorization = isOccupy
          ? PayloadDecoder.readCidOccupyAuthorizationTemplate(body.payloadBytes)
          : PayloadDecoder.readCidRebindAuthorizationTemplate(
              body.payloadBytes,
            );
      if (authorization == null) {
        return OfflineSignVerification(
          decoded: null,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '占号/换绑签名载荷无法解码，已拒绝签名',
        );
      }
      if (authorization.genesisHash != ChainConstants.genesisHash) {
        return OfflineSignVerification(
          decoded: null,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '签名载荷不属于正式创世链，已拒绝签名',
        );
      }
      if (request.expiresAt != authorization.expiresAt) {
        return OfflineSignVerification(
          decoded: null,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '二维码过期时间与授权载荷不一致，已拒绝签名',
        );
      }
      final fields = <String, String>{
        'genesis_hash': authorization.genesisHash,
        'cid_number': authorization.cidNumber,
        if (authorization.currentAccountId != null)
          'current_account_id': authorization.currentAccountId!,
        'expected_binding_revision':
            authorization.expectedBindingRevision.toString(),
        'expires_at': authorization.expiresAt.toString(),
      };
      final decodedDomain = DecodedPayload(
        action: isOccupy ? 'citizen_occupy' : 'citizen_rebind',
        summary: isOccupy
            ? '注册局首次绑定,把 CID ${authorization.cidNumber} 绑定到你的账户'
            : '注册局换绑,把 CID ${authorization.cidNumber} 绑定到你的新账户',
        fields: fields,
        reviewFields: fields,
      );
      for (final fieldKey in decodedDomain.reviewFields.keys) {
        if (!hasFieldLabel(fieldKey)) {
          return OfflineSignVerification(
            decoded: decodedDomain,
            status: SignDecisionStatus.reject,
            actionLabel: qrActionLabel,
            rejectReason: '签名字段缺少中文名称，已拒绝签名',
          );
        }
      }
      return OfflineSignVerification(
        decoded: decodedDomain,
        status: SignDecisionStatus.normal,
        actionLabel: qrActionLabel,
      );
    }

    var decoded = PayloadDecoder.decode(
      body.payloadHex,
      expectedAction: QrActions.actionKeyForCode(body.action),
    );

    if (decoded == null) {
      return OfflineSignVerification(
        decoded: null,
        status: SignDecisionStatus.reject,
        actionLabel: qrActionLabel,
        rejectReason: body.payloadBytes.length == 32 &&
                QrActions.isChainAction(body.action)
            ? '普通链交易不能只签 32 字节哈希，已拒绝签名'
            : '签名载荷无法解码，已拒绝签名',
      );
    }

    if (QrActions.isChainAction(body.action)) {
      final signingContext =
          PayloadDecoder.readSigningPayloadContext(body.payloadBytes);
      if (signingContext == null) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '链上交易必须携带完整 SigningPayload，已拒绝裸 call data',
        );
      }
      if (signingContext.genesisHash != ChainConstants.genesisHash) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '交易不属于正式创世链，已拒绝签名',
        );
      }
      if (signingContext.transactionVersion !=
          ChainConstants.transactionVersion) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '交易格式版本不受当前钱包支持，请升级公民钱包',
        );
      }
      final contextFields = <String, String>{
        'genesis_hash': signingContext.genesisHash,
        'spec_version': signingContext.specVersion.toString(),
        'transaction_version': signingContext.transactionVersion.toString(),
      };
      decoded = DecodedPayload(
        action: decoded.action,
        summary: decoded.summary,
        fields: <String, String>{...decoded.fields, ...contextFields},
        reviewFields: <String, String>{
          ...decoded.reviewFields,
          ...contextFields,
        },
      );
    } else {
      // 自定义签名域只要携带 genesis_hash，也必须与同一正式创世锚点严格相等。
      final payloadGenesisHash = decoded.fields['genesis_hash'];
      if (payloadGenesisHash != null &&
          payloadGenesisHash != ChainConstants.genesisHash) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '签名载荷不属于正式创世链，已拒绝签名',
        );
      }
    }

    if (body.action == QrActions.switchDefaultAccount) {
      final payloadSigner = decoded.fields['current_default_account_id'];
      final payloadExpiresAt = int.tryParse(decoded.fields['expires_at'] ?? '');
      if (payloadSigner != body.signerPublicKeyHex ||
          payloadExpiresAt != request.expiresAt) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '原默认账户或过期时间与签名请求不一致，已拒绝签名',
        );
      }
    }
    if (body.action == QrActions.squareDeviceBind) {
      final payloadSigner = decoded.fields['account_id'];
      final issuedAtMillis = int.tryParse(decoded.fields['issued_at'] ?? '');
      if (payloadSigner != body.signerPublicKeyHex ||
          issuedAtMillis == null ||
          request.expiresAt != issuedAtMillis ~/ 1000 + 120) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '设备绑定账户或签发时间与签名请求不一致，已拒绝签名',
        );
      }
    }
    if (body.action == QrActions.squareAccountAction) {
      final payloadSigner = decoded.fields['account_id'];
      final payloadExpiresAt = int.tryParse(decoded.fields['expires_at'] ?? '');
      final envelopeExpiresAt = request.expiresAt;
      final expiryMatches = payloadExpiresAt != null &&
          envelopeExpiresAt != null &&
          (payloadExpiresAt == envelopeExpiresAt ||
              payloadExpiresAt == envelopeExpiresAt * 1000);
      if (payloadSigner != body.signerPublicKeyHex || !expiryMatches) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '广场动作账户或过期时间与签名请求不一致，已拒绝签名',
        );
      }
    }
    if (body.action == QrActions.accountDataKeyProvision) {
      final provision = AccountDataKeyProvisionRequest.decode(
        body.payloadBytes,
      );
      if (provision == null ||
          provision.accountId != body.signerPublicKeyHex ||
          provision.expiresAt != request.expiresAt) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '用途钥请求账户或过期时间不一致，已拒绝提供',
        );
      }
    }
    if (body.action == QrActions.publish) {
      final payloadExpiresAt = int.tryParse(decoded.fields['expires_at'] ?? '');
      if (payloadExpiresAt != request.expiresAt) {
        return OfflineSignVerification(
          decoded: decoded,
          status: SignDecisionStatus.reject,
          actionLabel: qrActionLabel,
          rejectReason: '发布授权过期时间与签名请求不一致，已拒绝签名',
        );
      }
    }

    final decodedActionLabel = actionLabelForDecodedAction(decoded.action);
    if (decodedActionLabel == null) {
      return OfflineSignVerification(
        decoded: decoded,
        status: SignDecisionStatus.reject,
        actionLabel: qrActionLabel,
        rejectReason: '签名动作缺少中文名称，已拒绝签名',
      );
    }

    final decodedAction = QrActions.fromDecodedAction(decoded.action);
    if (decodedAction == 0) {
      return OfflineSignVerification(
        decoded: decoded,
        status: SignDecisionStatus.reject,
        actionLabel: qrActionLabel,
        rejectReason: '签名动作未登记，已拒绝签名',
      );
    }
    if (decodedAction != body.action) {
      return OfflineSignVerification(
        decoded: decoded,
        status: SignDecisionStatus.reject,
        actionLabel: qrActionLabel,
        rejectReason: '签名动作和载荷内容不匹配，已拒绝签名',
      );
    }

    String? missingField;
    for (final fieldKey in decoded.reviewFields.keys) {
      if (!hasFieldLabel(fieldKey)) {
        missingField = fieldKey;
        break;
      }
    }
    if (missingField != null) {
      return OfflineSignVerification(
        decoded: decoded,
        status: SignDecisionStatus.reject,
        actionLabel: decodedActionLabel,
        rejectReason: '签名字段缺少中文名称，已拒绝签名',
      );
    }

    return OfflineSignVerification(
      decoded: decoded,
      status: SignDecisionStatus.normal,
      actionLabel: decodedActionLabel,
    );
  }

  Future<SignResponseEnvelope> signRequestRaw({
    required String accountId,
    required String raw,
  }) async {
    final request = parseRequest(raw);
    return signParsedRequest(accountId: accountId, request: request);
  }

  /// 为 `a=14` 生成独立 `k=6` 加密用途钥响应，而不是普通签名响应。
  Future<QrEnvelope<AccountDataKeyResponseBody>> provisionAccountDataKeys({
    required String accountId,
    required SignRequestEnvelope request,
  }) async {
    if (request.body.action != QrActions.accountDataKeyProvision) {
      throw const OfflineSignException(
        OfflineSignErrorCode.invalidPayload,
        '当前请求不是账户数据用途钥提供',
      );
    }
    final verification = verifyPayload(request);
    if (!verification.canSign) {
      throw OfflineSignException(
        OfflineSignErrorCode.contentMismatch,
        verification.rejectReason ?? '用途钥请求已拒绝',
      );
    }
    final provision = AccountDataKeyProvisionRequest.decode(
      request.body.payloadBytes,
    );
    if (provision == null || provision.accountId != accountId) {
      throw const OfflineSignException(
        OfflineSignErrorCode.accountMismatch,
        '用途钥请求账户与所选账户不一致',
      );
    }
    final requestId = request.id!;
    final claimed = await SignedQrRequestStore.claim(
      requestId: requestId,
      expiresAt: request.expiresAt!,
    );
    if (!claimed) {
      throw const OfflineSignException(
        OfflineSignErrorCode.replayed,
        '该用途钥请求已处理或已过期，请生成新请求',
      );
    }
    try {
      final result = await _walletManager.provisionAccountDataKeys(
        accountId: accountId,
        request: provision,
      );
      return QrEnvelope<AccountDataKeyResponseBody>(
        kind: QrKind.accountDataKeyResponse,
        id: request.id,
        expiresAt: request.expiresAt,
        body: AccountDataKeyResponseBody.fromBytes(
          signerPublicKey: _accountIdBytes(accountId),
          signature: result.signature,
          keyExchangePublicKey: result.material.senderPublicKey,
          encryptionNonce: result.material.nonce,
          ciphertext: result.material.ciphertext,
        ),
      );
    } catch (_) {
      await SignedQrRequestStore.release(requestId);
      rethrow;
    }
  }

  /// 按账户签名。签名主体是账户（accountId），QR 请求里的
  /// `signerPublicKeyHex` 即指定该由哪个账户签，故此处只需按账户定位并逐字比对。
  Future<SignResponseEnvelope> signParsedRequest({
    required String accountId,
    required SignRequestEnvelope request,
  }) async {
    final body = request.body;
    if (body.action == QrActions.accountDataKeyProvision) {
      throw const OfflineSignException(
        OfflineSignErrorCode.invalidPayload,
        '用途钥提供必须返回独立加密响应，禁止生成普通签名响应',
      );
    }
    // 签名时再次校验过期
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((request.expiresAt ?? 0) <= now) {
      throw const OfflineSignException(
        OfflineSignErrorCode.expired,
        '签名请求已过期,请重新扫描',
      );
    }

    final account = await _walletManager.getAccountByAccountId(accountId);
    if (account == null) {
      throw const OfflineSignException(
        OfflineSignErrorCode.accountNotFound,
        '未找到指定账户',
      );
    }

    // 首次绑定/换绑:b.u 留空,账户由用户自选并填入授权模板的零槽,跳过 b.u 相等校验。
    // 其余动作:当前 sr25519 的 AccountId32 与 signer public key 字节相同,只允许完全相等,不做归一化。
    if (!QrActions.isSelfAccountDomainAction(body.action) &&
        account.accountId != body.signerPublicKeyHex) {
      throw const OfflineSignException(
        OfflineSignErrorCode.accountMismatch,
        '签名请求中的公钥与所选账户不一致',
      );
    }

    final verification = verifyPayload(request);
    // 两色识别模型:只有 normal 绿色态才允许签名;reject 红色态绝不签名。
    switch (verification.status) {
      case SignDecisionStatus.normal:
        break;
      case SignDecisionStatus.reject:
        throw OfflineSignException(
          OfflineSignErrorCode.contentMismatch,
          verification.rejectReason ?? '签名请求已拒绝',
        );
    }

    final selfAccountId = QrActions.isSelfAccountDomainAction(body.action)
        ? _accountIdBytes(account.accountId)
        : null;
    final payloadBytes = QrSigner.signingBytesFor(
      body,
      selfAccountId: selfAccountId,
    );
    if (payloadBytes.isEmpty) {
      throw const OfflineSignException(
        OfflineSignErrorCode.invalidPayload,
        '签名负载为空,无法签名',
      );
    }

    final requestId = request.id!;
    final claimed = await SignedQrRequestStore.claim(
      requestId: requestId,
      expiresAt: request.expiresAt!,
    );
    if (!claimed) {
      throw const OfflineSignException(
        OfflineSignErrorCode.replayed,
        '该签名请求已处理或已过期，请生成新请求',
      );
    }

    late final List<int> signature;
    try {
      signature = await _walletManager.signForAccount(
        account.accountId,
        payloadBytes,
      );
    } catch (_) {
      await SignedQrRequestStore.release(requestId);
      rethrow;
    }

    return _signer.buildResponse(
      request: request,
      signatureHex: '0x${_toHex(signature)}',
      // 占号/换绑:请求 b.u 空,响应 b.u 用钱包自选账户带回,供 OnChina 取 account_id。
      signerPublicKeyHexOverride:
          QrActions.isSelfAccountDomainAction(body.action)
              ? account.accountId
              : null,
    );
  }

  /// 把规范 AccountId 文本(0x + 64 hex)转成 32 字节,供授权模板原位填槽。
  Uint8List _accountIdBytes(String accountIdHex) {
    final hex = accountIdHex.startsWith('0x')
        ? accountIdHex.substring(2)
        : accountIdHex;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  String _toHex(List<int> bytes) {
    const chars = '0123456789abcdef';
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer
        ..write(chars[(byte >> 4) & 0x0f])
        ..write(chars[byte & 0x0f]);
    }
    return buffer.toString();
  }
}
