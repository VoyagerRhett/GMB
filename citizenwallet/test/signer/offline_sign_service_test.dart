import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizenwallet/wallet/wallet_mini_secret.dart';
import 'package:citizenwallet/chain/chain_constants.dart';
import 'package:citizenwallet/wallet/native_sr25519.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenwallet/signer/offline_sign_service.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/signer/qr_signer.dart';
import 'package:citizenwallet/isar/wallet_isar.dart';
import 'package:citizenwallet/wallet/wallet_manager.dart';

/// 给纯 call_data 拼上真实 SigningPayload 扩展尾(与节点端 build_signing_payload
/// 布局一致)。decoder 的两色识别要求链上 payload 必带合法尾,裸 call_data 拒签。
String _withSigningTailHex(
  String callDataHex, {
  String genesisHash = ChainConstants.genesisHash,
  int specVersion = 1,
  int transactionVersion = ChainConstants.transactionVersion,
}) {
  final genesis = _hexToBytes(genesisHash);
  final tail = <int>[
    0x00, // era: immortal
    0x04, // Compact(nonce=1)
    0x00, // Compact(tip=0)
    0x00, // CheckMetadataHash mode=Disabled
    ..._u32Le(specVersion),
    ..._u32Le(transactionVersion),
    ...genesis,
    ...genesis, // immortal: birth hash = genesis hash
    0x00, // CheckMetadataHash Option::None
  ];
  return '0x${_toHex([..._hexToBytes(callDataHex), ...tail])}';
}

SignRequestEnvelope _buildTestRequest({
  required String requestId,
  required String signerPublicKey,
  required String payloadHex,
  required int action,
  int? expiresAt,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return QrEnvelope<SignRequestBody>(
    kind: QrKind.signRequest,
    id: requestId,
    expiresAt: expiresAt ?? now + 90,
    body: SignRequestBody.fromHex(
      action: action,
      signerPublicKeyHex: signerPublicKey,
      payloadHex: payloadHex,
    ),
  );
}

List<int> _u64Le(int value) =>
    List<int>.generate(8, (index) => (value >> (index * 8)) & 0xff);

List<int> _u32Le(int value) =>
    List<int>.generate(4, (index) => (value >> (index * 8)) & 0xff);

List<int> _compactU32(int value) {
  if (value < 64) return <int>[value << 2];
  final encoded = (value << 2) | 1;
  return <int>[encoded & 0xff, (encoded >> 8) & 0xff];
}

List<int> _scaleString(String value) {
  final bytes = value.codeUnits;
  return <int>[..._compactU32(bytes.length), ...bytes];
}

List<int> _squareDeviceBindPayload({
  required String cidNumber,
  required String accountId,
  required int issuedAtMillis,
}) => <int>[
  ..._scaleString(cidNumber),
  ..._u64Le(4),
  ..._scaleString(accountId),
  ..._scaleString('04${'ab' * 64}'),
  ..._u64Le(issuedAtMillis),
];

List<int> _squareAccountActionPayload({
  required String accountId,
  required int expiresAt,
  String action = 'cancel_membership',
}) => <int>[
  ..._scaleString(action),
  ..._scaleString(accountId),
  ..._scaleString('sqa_test'),
  ..._u64Le(expiresAt * 1000),
];

List<int> _occupyAuthorizationTemplate(String cid, int expiresAt) => [
  ..._hexToBytes(ChainConstants.genesisHash),
  cid.length << 2,
  ...cid.codeUnits,
  ...List<int>.filled(32, 0),
  ..._u64Le(0),
  ..._u64Le(expiresAt),
];

List<int> _rebindAuthorizationTemplate(String cid, int expiresAt) => [
  ..._hexToBytes(ChainConstants.genesisHash),
  cid.length << 2,
  ...cid.codeUnits,
  ...List<int>.filled(32, 0x55),
  ...List<int>.filled(32, 0),
  ..._u64Le(7),
  ..._u64Le(expiresAt),
];

List<int> _switchDefaultAccountPayload({
  required String currentDefaultAccountId,
  required int expiresAt,
}) => [
  ..._hexToBytes(ChainConstants.genesisHash),
  ..._hexToBytes(currentDefaultAccountId),
  2 << 2,
  ...List<int>.filled(32, 0x55),
  ..._hexToBytes(currentDefaultAccountId),
  ..._u64Le(expiresAt),
  ...List<int>.filled(16, 0x66),
];

/// 中文注释：全部产品端复用同一份 SCALE 发布载荷，参数化只替换闭集身份，
/// 字段顺序、签名域和防重放字段始终与生产 QR_V1 合同一致。
List<int> _publishAuthorizationPayload({
  required String product,
  required String platform,
  required int expiresAt,
}) => <int>[
  ..._scaleString(product),
  ..._scaleString(platform),
  ..._scaleString('1.2.3'),
  ...List<int>.generate(20, (index) => index + 1),
  ...List<int>.generate(32, (index) => index + 21),
  ..._scaleString(product == 'citizenchatserver' ? '' : 'deployment-stable-1'),
  ..._u64Le(expiresAt),
  ...List<int>.filled(32, 0x66),
];

void main() {
  group('OfflineSignService', () {
    late _FakeWalletManager walletManager;
    late OfflineSignService service;
    late Account signingAccount;

    setUp(() async {
      await WalletIsar.instance.resetForTest();
      walletManager = _FakeWalletManager();
      service = OfflineSignService(walletManager: walletManager);
      signingAccount = await walletManager.ensureAccount();
    });

    tearDown(() => WalletIsar.instance.resetForTest());

    test('首次绑定/换绑仅接受完整授权模板且展示防重放字段', () {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      const cid = 'CN220-CTZN2-198805200-2026';
      final occupyRequest = _buildTestRequest(
        requestId: 'offline-cid-occupy-template',
        signerPublicKey: '',
        payloadHex: '0x${_toHex(_occupyAuthorizationTemplate(cid, expiresAt))}',
        action: QrActions.citizenOccupy,
        expiresAt: expiresAt,
      );
      final occupy = service.verifyPayload(occupyRequest);
      expect(occupy.status, SignDecisionStatus.normal);
      expect(
        occupy.decoded?.fields['genesis_hash'],
        ChainConstants.genesisHash,
      );
      expect(occupy.decoded?.fields['expected_binding_revision'], '0');
      expect(occupy.decoded?.fields['expires_at'], expiresAt.toString());

      final rebindRequest = _buildTestRequest(
        requestId: 'offline-cid-rebind-template',
        signerPublicKey: '',
        payloadHex: '0x${_toHex(_rebindAuthorizationTemplate(cid, expiresAt))}',
        action: QrActions.citizenRebind,
        expiresAt: expiresAt,
      );
      final rebind = service.verifyPayload(rebindRequest);
      expect(rebind.status, SignDecisionStatus.normal);
      expect(rebind.decoded?.fields['current_account_id'], '0x${'55' * 32}');
      expect(rebind.decoded?.fields['expected_binding_revision'], '7');
    });

    test('域签名拒绝 envelope expiry 不一致和已废弃的 CID-only 载荷', () {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      const cid = 'CN220-CTZN2-198805200-2026';
      final mismatch = _buildTestRequest(
        requestId: 'offline-cid-expiry-mismatch',
        signerPublicKey: '',
        payloadHex: '0x${_toHex(_occupyAuthorizationTemplate(cid, expiresAt))}',
        action: QrActions.citizenOccupy,
        expiresAt: expiresAt + 1,
      );
      expect(service.verifyPayload(mismatch).status, SignDecisionStatus.reject);
      expect(service.verifyPayload(mismatch).rejectReason, contains('过期时间'));

      final legacy = _buildTestRequest(
        requestId: 'offline-cid-legacy-payload',
        signerPublicKey: '',
        payloadHex: '0x${_toHex([cid.length << 2, ...cid.codeUnits])}',
        action: QrActions.citizenOccupy,
        expiresAt: expiresAt,
      );
      expect(service.verifyPayload(legacy).status, SignDecisionStatus.reject);
    });

    test('默认账户切换只接受原默认冷账户和一致期限，并使用 0x21 出签', () async {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      final payload = _switchDefaultAccountPayload(
        currentDefaultAccountId: signingAccount.accountId,
        expiresAt: expiresAt,
      );
      final request = _buildTestRequest(
        requestId: 'offline-switch-default-account',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.switchDefaultAccount,
        expiresAt: expiresAt,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.actionLabel, '切换默认账户');
      expect(
        verification.decoded?.fields['current_default_account_id'],
        signingAccount.accountId,
      );

      final response = await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );
      expect(
        _verifySr25519(
          signerPublicKeyHex: response.body.signerPublicKeyHex,
          message: QrSigner.signingBytesFor(request.body),
          signatureHex: response.body.signatureHex,
        ),
        isTrue,
      );

      final mismatchedExpiry = _buildTestRequest(
        requestId: 'offline-switch-default-expiry',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.switchDefaultAccount,
        expiresAt: expiresAt + 1,
      );
      expect(
        service.verifyPayload(mismatchedExpiry).status,
        SignDecisionStatus.reject,
      );
    });

    test('发布授权严格绑定外层期限、使用 0x24 域且同一请求只能签一次', () async {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      final payload = _publishAuthorizationPayload(
        product: 'citizenchatserver',
        platform: 'cloudflare',
        expiresAt: expiresAt,
      );
      final request = _buildTestRequest(
        requestId: 'offline-publish-authorization',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.publish,
        expiresAt: expiresAt,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.actionLabel, '生产发布授权');
      expect(verification.decoded?.fields['product_id'], 'citizenchatserver');
      expect(verification.decoded?.fields['platform'], 'cloudflare');
      expect(verification.decoded?.fields['previous_deployment_id'], '');
      expect(
        verification.decoded?.summary,
        '授权发布 公民聊天服务 1.2.3 到 Cloudflare；不授权回滚或删除资源',
      );

      final response = await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );
      expect(
        _verifySr25519(
          signerPublicKeyHex: response.body.signerPublicKeyHex,
          message: QrSigner.signingBytesFor(request.body),
          signatureHex: response.body.signatureHex,
        ),
        isTrue,
      );
      await expectLater(
        service.signParsedRequest(
          accountId: signingAccount.accountId,
          request: request,
        ),
        throwsA(
          isA<OfflineSignException>().having(
            (error) => error.code,
            'code',
            OfflineSignErrorCode.replayed,
          ),
        ),
      );

      final mismatch = _buildTestRequest(
        requestId: 'offline-publish-expiry-mismatch',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.publish,
        expiresAt: expiresAt + 1,
      );
      expect(service.verifyPayload(mismatch).status, SignDecisionStatus.reject);
      expect(service.verifyPayload(mismatch).rejectReason, contains('过期时间'));
    });

    test('设备子钥绑定复用 0x1C，且只接受载荷账户和签发时间一致的请求', () async {
      const cid = 'CN220-CTZN2-198805200-2026';
      final issuedAtMillis = DateTime.now().millisecondsSinceEpoch;
      final payload = _squareDeviceBindPayload(
        cidNumber: cid,
        accountId: signingAccount.accountId,
        issuedAtMillis: issuedAtMillis,
      );
      final request = _buildTestRequest(
        requestId: 'offline-square-device-bind',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.squareDeviceBind,
        expiresAt: issuedAtMillis ~/ 1000 + 120,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.actionLabel, '设备子钥绑定');
      expect(verification.decoded?.fields['cid_number'], cid);
      final response = await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );
      expect(
        _verifySr25519(
          signerPublicKeyHex: response.body.signerPublicKeyHex,
          message: QrSigner.signingBytesFor(request.body),
          signatureHex: response.body.signatureHex,
        ),
        isTrue,
      );

      final mismatchedExpiry = _buildTestRequest(
        requestId: 'offline-square-device-bind-expiry',
        signerPublicKey: signingAccount.accountId,
        payloadHex: '0x${_toHex(payload)}',
        action: QrActions.squareDeviceBind,
        expiresAt: request.expiresAt! + 1,
      );
      expect(
        service.verifyPayload(mismatchedExpiry).status,
        SignDecisionStatus.reject,
      );
    });

    test('首次绑定按所选账户签署精确授权并在响应带回 account_id', () async {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      const cid = 'CN220-CTZN2-198805200-2026';
      final request = _buildTestRequest(
        requestId: 'offline-cid-occupy-sign',
        signerPublicKey: '',
        payloadHex: '0x${_toHex(_occupyAuthorizationTemplate(cid, expiresAt))}',
        action: QrActions.citizenOccupy,
        expiresAt: expiresAt,
      );
      final response = await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );
      expect(response.body.signerPublicKeyHex, signingAccount.accountId);
      final signingBytes = QrSigner.signingBytesFor(
        request.body,
        selfAccountId: Uint8List.fromList(
          _hexToBytes(signingAccount.accountId),
        ),
      );
      expect(
        _verifySr25519(
          signerPublicKeyHex: response.body.signerPublicKeyHex,
          message: signingBytes,
          signatureHex: response.body.signatureHex,
        ),
        isTrue,
      );
    });

    test('signParsedRequest should sign normal internal_vote (统一入口)', () async {
      // 所有管理员投票走 InternalVote(20).cast(0)
      // payload = [0x14][0x00][u64 LE proposal_id=1][Personal=0][approve=1] + 扩展尾
      final payloadHex = _withSigningTailHex('0x140001000000000000000001');
      final request = _buildTestRequest(
        requestId: 'offline-req-test-0001',
        signerPublicKey: signingAccount.accountId,
        payloadHex: payloadHex,
        action: QrActions.internalVote,
      );

      final payloadBytes = _hexToBytes(payloadHex);

      final response = await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );

      expect(walletManager.signCallCount, 1);
      expect(response.id, request.id);
      expect(response.body.signerPublicKeyHex, signingAccount.accountId);
      expect(
        _verifySr25519(
          signerPublicKeyHex: response.body.signerPublicKeyHex,
          message: Uint8List.fromList(payloadBytes),
          signatureHex: response.body.signatureHex,
        ),
        isTrue,
      );
    });

    test('同一请求 id 到期前只能签名一次', () async {
      final payloadHex = _withSigningTailHex('0x140001000000000000000001');
      final request = _buildTestRequest(
        requestId: 'offline-replay-test-0001',
        signerPublicKey: signingAccount.accountId,
        payloadHex: payloadHex,
        action: QrActions.internalVote,
      );

      await service.signParsedRequest(
        accountId: signingAccount.accountId,
        request: request,
      );

      expect(
        () => service.signParsedRequest(
          accountId: signingAccount.accountId,
          request: request,
        ),
        throwsA(
          isA<OfflineSignException>().having(
            (e) => e.code,
            'code',
            OfflineSignErrorCode.replayed,
          ),
        ),
      );
      expect(walletManager.signCallCount, 1);
    });

    test('signParsedRequest 拒绝 action 与 payload 不一致', () async {
      // decode 成功但 QR action 和 decoded.action 不一致 → 红色拒签。
      final payloadHex = _withSigningTailHex('0x1400070000000000000001');
      final request = _buildTestRequest(
        requestId: 'offline-req-test-action-mismatch',
        signerPublicKey: signingAccount.accountId,
        payloadHex: payloadHex,
        action: QrActions.jointVote,
      );

      expect(
        () => service.signParsedRequest(
          accountId: signingAccount.accountId,
          request: request,
        ),
        throwsA(
          isA<OfflineSignException>().having(
            (e) => e.code,
            'code',
            OfflineSignErrorCode.contentMismatch,
          ),
        ),
      );
      expect(walletManager.signCallCount, 0);
    });

    test('verifyPayload decodes transfer payload', () {
      // OnchainTransaction::transfer_with_remark: pallet=4, call=0。
      // beneficiary 32B, amount u128_le, remark 空 Vec。
      final request = _buildTestRequest(
        requestId: 'offline-req-test-known',
        signerPublicKey: signingAccount.accountId,
        // call_data: [04][00][dest 32B][u128_le(1)][Vec(0)] → 0.01 GMB
        payloadHex: _withSigningTailHex(
          '0x0400aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0100000000000000000000000000000000',
        ),
        action: QrActions.transferWithRemark,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.canSign, isTrue);
      expect(verification.actionLabel, '转账');
      expect(verification.decoded, isNotNull);
      expect(verification.decoded!.action, 'transfer');
      expect(
        verification.decoded!.reviewFields['genesis_hash'],
        ChainConstants.genesisHash,
      );
      expect(verification.decoded!.reviewFields['spec_version'], '1');
      expect(verification.decoded!.reviewFields['transaction_version'], '0');
    });

    test('链交易严格拒绝错创世、错交易版本和裸 call data，但不锁 spec_version', () {
      const callData =
          '0x0400aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0100000000000000000000000000000000';

      SignDecisionStatus verify(String payloadHex) => service
          .verifyPayload(
            _buildTestRequest(
              requestId: 'offline-chain-context-${payloadHex.hashCode}',
              signerPublicKey: signingAccount.accountId,
              payloadHex: payloadHex,
              action: QrActions.transferWithRemark,
            ),
          )
          .status;

      expect(
        verify(_withSigningTailHex(callData, genesisHash: '0x${'99' * 32}')),
        SignDecisionStatus.reject,
      );
      expect(
        verify(_withSigningTailHex(callData, transactionVersion: 1)),
        SignDecisionStatus.reject,
      );
      expect(verify(callData), SignDecisionStatus.reject);

      final highSpec = service.verifyPayload(
        _buildTestRequest(
          requestId: 'offline-chain-high-spec',
          signerPublicKey: signingAccount.accountId,
          payloadHex: _withSigningTailHex(callData, specVersion: 9876),
          action: QrActions.transferWithRemark,
        ),
      );
      expect(highSpec.status, SignDecisionStatus.normal);
      expect(highSpec.decoded?.reviewFields['spec_version'], '9876');
    });

    test('verifyPayload accepts exact SquarePost platform price action', () {
      const cid = 'GZ018-SFGYR-201206100-2026';
      final cidBytes = cid.codeUnits;
      const role = 'GENESIS_PRODUCT_MANAGER';
      final roleBytes = role.codeUnits;
      final price = List<int>.filled(16, 0)..[0] = 100;
      final payloadHex = _withSigningTailHex(
        '0x${_toHex([34, 5, cidBytes.length << 2, ...cidBytes, roleBytes.length << 2, ...roleBytes, 2, ...price])}',
      );
      final request = _buildTestRequest(
        requestId: 'offline-platform-price',
        signerPublicKey: signingAccount.accountId,
        payloadHex: payloadHex,
        action: QrActions.proposeSetPlatformPrice,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.actionLabel, '发起平台会员调价提案');
      expect(verification.decoded!.fields['membership_level'], '薪火会员');
    });

    test('verifyPayload accepts exact SquarePost Cold subscription action', () {
      final price = List<int>.filled(16, 0)
        ..[0] = 0x7c
        ..[1] = 0x15
        ..[2] = 0x09;
      final request = _buildTestRequest(
        requestId: 'offline-square-subscribe',
        signerPublicKey: signingAccount.accountId,
        payloadHex: _withSigningTailHex(
          '0x${_toHex([34, 1, 0, 0, 1, ...price])}',
        ),
        action: QrActions.subscribe,
      );

      final verification = service.verifyPayload(request);
      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.actionLabel, '订阅会员');
      expect(verification.decoded?.fields['issuer'], '平台');
      expect(verification.decoded?.fields['membership_level'], '民主会员');
      expect(verification.decoded?.fields['expected_price_fen'], contains('分'));
    });

    test(
      'verifyPayload rejects platform price payload with mismatched action',
      () {
        const cid = 'GZ018-SFGYR-201206100-2026';
        final cidBytes = cid.codeUnits;
        const role = 'GENESIS_PRODUCT_MANAGER';
        final roleBytes = role.codeUnits;
        final price = List<int>.filled(16, 0)..[0] = 100;
        final request = _buildTestRequest(
          requestId: 'offline-platform-price-mismatch',
          signerPublicKey: signingAccount.accountId,
          payloadHex: _withSigningTailHex(
            '0x${_toHex([34, 5, cidBytes.length << 2, ...cidBytes, roleBytes.length << 2, ...roleBytes, 0, ...price])}',
          ),
          action: QrActions.transferWithRemark,
        );

        final verification = service.verifyPayload(request);
        expect(verification.status, SignDecisionStatus.reject);
        expect(verification.rejectReason, contains('不匹配'));
      },
    );

    test('verifyPayload 拒绝普通链交易 32 字节 hash-only payload', () {
      final request = _buildTestRequest(
        requestId: 'offline-req-test-hash-only-reject',
        signerPublicKey: signingAccount.accountId,
        payloadHex:
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        action: QrActions.privateInstitutionGovernance,
      );

      final verification = service.verifyPayload(request);

      expect(verification.status, SignDecisionStatus.reject);
      expect(verification.canSign, isFalse);
      expect(verification.actionLabel, '发起私权机构治理');
      expect(verification.rejectReason, contains('普通链交易不能只签 32 字节哈希'));
    });

    test('verifyPayload 拒绝未登记 action', () {
      final request = _buildTestRequest(
        requestId: 'offline-req-test-unknown-action',
        signerPublicKey: signingAccount.accountId,
        payloadHex: _withSigningTailHex('0x1400010000000000000001'),
        action: 0x7fff,
      );

      final verification = service.verifyPayload(request);

      expect(verification.status, SignDecisionStatus.reject);
      expect(verification.actionLabel, isNull);
      expect(verification.rejectReason, contains('未登记的签名动作'));
    });

    test('verifyPayload 允许 Cold 对同账户广场动作按 0x1D 域签名', () {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      final request = _buildTestRequest(
        requestId: 'offline-req-test-square-action',
        signerPublicKey: signingAccount.accountId,
        payloadHex:
            '0x${_toHex(_squareAccountActionPayload(accountId: signingAccount.accountId, expiresAt: expiresAt))}',
        action: QrActions.squareAccountAction,
        expiresAt: expiresAt,
      );

      final verification = service.verifyPayload(request);

      expect(verification.status, SignDecisionStatus.normal);
      expect(verification.canSign, isTrue);
      expect(verification.actionLabel, '广场账户动作签名');
      expect(
        verification.decoded?.fields['account_id'],
        signingAccount.accountId,
      );
      expect(QrSigner.signingBytesFor(request.body), hasLength(32));
    });

    test('verifyPayload 拒绝广场动作载荷账户与请求签名账户不一致', () {
      final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
      final request = _buildTestRequest(
        requestId: 'offline-req-square-account-mismatch',
        signerPublicKey: signingAccount.accountId,
        payloadHex:
            '0x${_toHex(_squareAccountActionPayload(accountId: '0x${'ab' * 32}', expiresAt: expiresAt))}',
        action: QrActions.squareAccountAction,
        expiresAt: expiresAt,
      );

      final verification = service.verifyPayload(request);

      expect(verification.status, SignDecisionStatus.reject);
      expect(verification.rejectReason, contains('账户或过期时间'));
    });

    test('signParsedRequest should reject wrong signer public key', () async {
      final request = _buildTestRequest(
        requestId: 'offline-req-test-0002',
        signerPublicKey:
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        payloadHex: '0x0102',
        action: QrActions.login,
      );

      expect(
        () => service.signParsedRequest(
          accountId: signingAccount.accountId,
          request: request,
        ),
        throwsA(
          isA<OfflineSignException>().having(
            (e) => e.code,
            'code',
            OfflineSignErrorCode.accountMismatch,
          ),
        ),
      );
    });

    test('signParsedRequest should reject unknown account', () async {
      final request = _buildTestRequest(
        requestId: 'offline-req-test-unknown-account',
        signerPublicKey: signingAccount.accountId,
        payloadHex: _withSigningTailHex('0x140001000000000000000001'),
        action: QrActions.internalVote,
      );

      expect(
        () => service.signParsedRequest(
          accountId:
              '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0',
          request: request,
        ),
        throwsA(
          isA<OfflineSignException>().having(
            (e) => e.code,
            'code',
            OfflineSignErrorCode.accountNotFound,
          ),
        ),
      );
    });
  });
}

bool _verifySr25519({
  required String signerPublicKeyHex,
  required Uint8List message,
  required String signatureHex,
}) {
  // 与生产同一条原生路径（全仓 sr25519 唯一实现）。
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

List<int> _hexToBytes(String input) {
  final text = (input.startsWith('0x') || input.startsWith('0X'))
      ? input.substring(2)
      : input;
  if (text.isEmpty || text.length.isOdd) return const <int>[];
  return List<int>.generate(
    text.length ~/ 2,
    (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16),
    growable: false,
  );
}

String _toHex(List<int> bytes) {
  const chars = '0123456789abcdef';
  final buf = StringBuffer();
  for (final b in bytes) {
    buf
      ..write(chars[(b >> 4) & 0x0f])
      ..write(chars[b & 0x0f]);
  }
  return buf.toString();
}

/// 假 WalletManager:按账户提供签名（不触存储/生物识别）。
class _FakeWalletManager extends WalletManager {
  static const int _ss58 = 2027;
  static const String _mnemonic =
      'bottom drive obey lake curtain smoke basket hold race lonely fit walk';

  Account? _account;
  String? _miniSecretHex;
  int signCallCount = 0;

  Future<Account> ensureAccount() async {
    final existing = _account;
    if (existing != null) {
      return existing;
    }
    final miniSecret = await WalletMiniSecret.fromMnemonic(_mnemonic);
    final pair = Keyring.sr25519.fromSeed(Uint8List.fromList(miniSecret));
    pair.ss58Format = _ss58;
    // 中文注释：测试账户公钥与签名必须走生产唯一的原生 schnorrkel 实现；
    // 禁止用第三方纯 Dart keyring 出签、再拿原生实现验签形成双口径夹具。
    final accountId = '0x${_toHex(NativeSr25519.publicKeyOf(miniSecret))}';
    _miniSecretHex = _toHex(miniSecret);
    _account = Account(
      masterId: accountId,
      accountIndex: 0,
      accountId: accountId,
      ss58Address: pair.address,
      accountName: '账户0',
      createdAtMillis: 0,
    );
    return _account!;
  }

  @override
  Future<Account?> getAccountByAccountId(String accountId) async {
    final account = await ensureAccount();
    return account.accountId == accountId ? account : null;
  }

  @override
  Future<Uint8List> signForAccount(String accountId, Uint8List payload) async {
    signCallCount += 1;
    final account = await ensureAccount();
    if (accountId != account.accountId) {
      throw const WalletAuthException('未找到指定账户');
    }
    return NativeSr25519.sign(_hexToBytes(_miniSecretHex!), payload);
  }
}
