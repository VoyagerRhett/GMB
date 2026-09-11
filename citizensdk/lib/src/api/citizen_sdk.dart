import 'package:flutter/foundation.dart';

import '../models/citizen_capability.dart';
import '../models/citizen_chain_state.dart';
import '../models/citizen_signing.dart';
import '../models/citizen_transaction.dart';
import '../models/citizen_wallet.dart';
import '../crypto/account_codec.dart';
import '../platform/citizen_sdk_flutter_codec.dart';
import '../platform/citizen_sdk_flutter_sessions.dart';
import '../platform/citizen_sdk_platform.dart';
import '../platform/flutter_citizen_sdk_platform.dart';
import 'citizen_chain.dart';
import 'citizen_qr.dart';
import 'citizen_sdk_error.dart';
import 'citizen_sdk_events.dart';
import 'citizen_transactions.dart';
import 'citizen_wallet.dart';

/// CitizenSDK 的唯一 Dart/Flutter 公共门面。
final class CitizenSdk {
  CitizenSdk._(this._session, CitizenSdkFlutterCodec codec)
    : chain = _CitizenChain(_session, codec),
      wallet = _CitizenWallet(_session, codec),
      signing = _CitizenSigning(_session, codec),
      qr = _CitizenQr(_session),
      transactions = _CitizenTransactions(_session, codec),
      history = _CitizenHistory(_session, codec);

  /// 打开当前受支持平台的 CitizenSDK session，但不隐式启动轻节点。
  ///
  /// Flutter 产品投影覆盖 Android、iOS、macOS、Linux 与 Windows；Linux 的两种
  /// 机器目标共用官方 linux 注册。全部使用相同的公开 API、固定
  /// tuple 方法和事件合同；同版原生插件缺失时失败关闭，不注入替代实现。
  /// Windows 宿主在构建时声明 CITIZENSDK_APPLICATION_ID；此入口不接收路径或秘密。
  static Future<CitizenSdk> open({int modules = CitizenSdkModules.full}) async {
    final codec = const CitizenSdkFlutterCodec();
    final platform = CitizenSdkPlatform.instance ?? _defaultPlatform();
    final session = await CitizenSdkFlutterSession.open(
      platform: platform,
      codec: codec,
      modules: modules,
    );
    return CitizenSdk._(session, codec);
  }

  static final CitizenSdkPlatform _defaultFlutterPlatform =
      FlutterCitizenSdkPlatform();

  static CitizenSdkPlatform _defaultPlatform() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      return _defaultFlutterPlatform;
    }
    throw const CitizenSdkException(
      code: CitizenSdkErrorCode.unsupported,
      message:
          'CitizenSDK Flutter binding 当前仅支持 Android、iOS、macOS、LinuxARM、LinuxAMD 与 Windows',
    );
  }

  final CitizenSdkFlutterSession _session;

  /// 已验证的公民链读取能力。
  final CitizenChain chain;

  /// 设备本地热钱包和账户管理，不包含公开签名门面。
  final CitizenWallet wallet;

  /// 独立签名能力；私钥只经设备安全金库受控使用。纯验签使用 [CitizenSigning.verify]。
  final CitizenSigning signing;

  /// QR_V1 协议、扫码签名会话和五端统一 ZXing-C++ 图像能力。
  final CitizenQr qr;

  /// 公民链交易构造、提交与观察能力。
  final CitizenTransactions transactions;

  /// 可独立于本地钱包使用的已确认交易历史能力。
  final CitizenHistory history;

  /// 当前 session 的类型化生命周期与请求事件。
  Stream<CitizenSdkEvent> get events => _session.events;

  /// 当前 session 生命周期快照。
  CitizenSdkLifecycle get lifecycle => _session.lifecycle;

  /// 启动当前 session 的公民链轻节点。
  Future<void> start() async {
    final value = await _session.invoke('start');
    final lifecycle = const CitizenSdkFlutterCodec().decodeLifecycle(value[0]);
    if (lifecycle != CitizenSdkLifecycle.running) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: 'CitizenSDK start 未进入 running',
      );
    }
  }

  /// 在完成 checkpoint 后有序停止当前 session 的轻节点。
  Future<void> stop() async {
    final value = await _session.invoke('stop');
    final lifecycle = const CitizenSdkFlutterCodec().decodeLifecycle(value[0]);
    if (lifecycle != CitizenSdkLifecycle.stopped) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: 'CitizenSDK stop 未进入 stopped',
      );
    }
  }

  /// 返回当前宿主事实对应的能力快照。
  Future<CitizenCapabilitySnapshot> getCapabilities() =>
      chain.getCapabilities();

  /// 关闭已停止的 session；只有原生侧完成结果释放和 destroy 后才完成。
  ///
  /// 若 session 正在运行，调用方必须先等待 [stop] 成功，不能用 [close]
  /// 绕过 checkpoint 与有序停止。
  Future<void> close() => _session.close();
}

final class _CitizenChain implements CitizenChain {
  const _CitizenChain(this._session, this._codec);

  final CitizenSdkFlutterSession _session;
  final CitizenSdkFlutterCodec _codec;

  @override
  Future<CitizenCapabilitySnapshot> getCapabilities() async {
    final value = await _session.invoke('getCapabilities');
    return _codec.decodeCapabilities(value[0]);
  }

  @override
  Future<String> getGenesisHash() async {
    final value = await _session.invoke('getGenesisHash');
    return value[0]! as String;
  }

  @override
  Future<CitizenBlockRef> getFinalizedHead() async {
    final value = await _session.invoke('getFinalizedHead');
    return _codec.decodeBlock(value[0]);
  }

  @override
  Future<CitizenChainSyncStatus> getSyncStatus() async {
    final value = await _session.invoke('getSyncStatus');
    return _codec.decodeSyncStatus(value[0]);
  }

  @override
  Future<CitizenBlockRef> getBestHead() async {
    final value = await _session.invoke('getBestHead');
    return _codec.decodeBlock(value[0]);
  }

  @override
  Future<CitizenBlockRef> getFinalizedBlockAt(BigInt number) async {
    final value = await _session.invoke(
      'getFinalizedBlockAt',
      fields: <Object?>[number.toString()],
    );
    return _codec.decodeBlock(value[0]);
  }

  @override
  Future<CitizenBlockRef> resolveFinalizedBlock(
    String hash,
    BigInt number,
  ) async {
    final value = await _session.invoke(
      'resolveFinalizedBlock',
      fields: <Object?>[hash, number.toString()],
    );
    return _codec.decodeBlock(value[0]);
  }

  @override
  Future<CitizenBlockHeader> getBlockHeader(CitizenBlockRef block) async {
    final value = await _session.invoke(
      'getBlockHeader',
      fields: <Object?>[_codec.encodeBlock(block)],
    );
    return _codec.decodeBlockHeader(value[0]);
  }

  @override
  Future<CitizenBlockBody> getBlockBody(CitizenBlockRef block) async {
    final value = await _session.invoke(
      'getBlockBody',
      fields: <Object?>[_codec.encodeBlock(block)],
    );
    return _codec.decodeBlockBody(value[0]);
  }

  @override
  Future<CitizenRuntimeContext> getRuntimeContext(CitizenBlockRef block) async {
    final value = await _session.invoke(
      'getRuntimeContext',
      fields: <Object?>[_codec.encodeBlock(block)],
    );
    return _codec.decodeRuntimeContext(value[0]);
  }

  @override
  Future<Uint8List?> getStorage(CitizenBlockRef block, Uint8List key) async {
    final value = await _session.invoke(
      'getStorage',
      fields: <Object?>[_codec.encodeBlock(block), Uint8List.fromList(key)],
    );
    return _codec.decodeStorage(value[0]);
  }

  @override
  Future<List<Uint8List?>> getStorageBatch(
    CitizenBlockRef block,
    List<Uint8List> keys,
  ) async {
    final value = await _session.invoke(
      'getStorageBatch',
      fields: <Object?>[
        _codec.encodeBlock(block),
        keys.map(Uint8List.fromList).toList(growable: false),
      ],
    );
    return _codec.decodeStorageBatch(value[0]);
  }

  @override
  Future<Uint8List?> getSystemEvents(CitizenBlockRef finalizedBlock) async {
    final value = await _session.invoke(
      'getSystemEvents',
      fields: <Object?>[_codec.encodeBlock(finalizedBlock)],
    );
    return _codec.decodeStorage(value[0]);
  }

  @override
  Future<CitizenChainState> exportState() async {
    final value = await _session.invoke('exportState');
    return _codec.decodeChainState(value[0]);
  }

  @override
  Future<void> importState(CitizenChainState state) async {
    await _session.invoke(
      'importState',
      fields: <Object?>[
        state.formatVersion,
        _codec.encodeBlock(state.finalized),
        Uint8List.fromList(state.database),
      ],
    );
  }

  @override
  Future<CitizenAccountBalance> getAccountBalance(String accountId) async {
    final value = await _session.invoke(
      'getAccountBalance',
      fields: <Object?>[accountId],
    );
    final balance = _codec.decodeBalance(value[0]);
    if (balance.accountId != accountId) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: '余额响应账户与请求账户不一致',
      );
    }
    return balance;
  }

  @override
  Future<List<CitizenAccountBalance>> getAccountBalances(
    List<String> accountIds,
  ) async {
    _requireCount(
      accountIds.length,
      minimum: 0,
      maximum: CitizenSdkFlutterCodec.maximumBalanceAccounts,
      label: '批量余额 accountIds',
    );
    // 固定 await 前的请求顺序；不能让调用方后续变更列表改变响应关联依据。
    final requested = List<String>.unmodifiable(accountIds);
    final value = await _session.invoke(
      'getAccountBalances',
      fields: <Object?>[requested],
    );
    final balances = _codec.decodeBalances(value[0]);
    if (balances.length != requested.length) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: '批量余额响应数量与请求不一致',
      );
    }
    for (var index = 0; index < requested.length; index += 1) {
      if (balances[index].accountId != requested[index]) {
        throw const CitizenSdkException(
          code: CitizenSdkErrorCode.decode,
          message: '批量余额响应账户未保持请求顺序或重复项',
        );
      }
    }
    return balances;
  }

  @override
  Future<CitizenAccountNonce> getAccountNonce(String accountId) async {
    final value = await _session.invoke(
      'getAccountNonce',
      fields: <Object?>[accountId],
    );
    final nonce = _codec.decodeNonce(value[0]);
    if (nonce.accountId != accountId) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: 'nonce 响应账户与请求账户不一致',
      );
    }
    return nonce;
  }

  @override
  Future<CitizenFeeSnapshot> getFeeSnapshot() async {
    final value = await _session.invoke('getFeeSnapshot');
    return _codec.decodeFeeSnapshot(value[0]);
  }
}

final class _CitizenWallet implements CitizenWallet {
  const _CitizenWallet(this._session, this._codec);

  final CitizenSdkFlutterSession _session;
  final CitizenSdkFlutterCodec _codec;

  @override
  Future<CitizenWalletProfile?> getProfile() async {
    final value = await _session.invoke('getWalletProfile');
    return _codec.decodeWalletProfile(value[0]);
  }

  @override
  Future<CitizenWalletState> getState() async {
    final value = await _session.invoke('getWalletState');
    return _codec.decodeWalletState(value[0]);
  }

  @override
  Future<CitizenWalletState> importColdAccount({
    String? accountId,
    String? ss58Address,
    required String name,
  }) async {
    if ((accountId == null) == (ss58Address == null)) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: 'accountId 与 ss58Address 必须且只能提供一个',
      );
    }
    final normalizedName = name.trim();
    final method = accountId != null
        ? 'importColdAccountId'
        : 'importColdAccountSs58';
    final identity = accountId ?? ss58Address!;
    final value = await _session.invoke(
      method,
      fields: <Object?>[identity, normalizedName],
    );
    return _codec.decodeWalletState(value[0]);
  }

  @override
  Future<CitizenWalletState> reorderAccountsWithoutDefaultChange({
    required BigInt expectedRevision,
    required List<String> accountIds,
  }) async {
    final value = await _session.invoke(
      'reorderWalletAccountsWithoutDefaultChange',
      fields: <Object?>[
        expectedRevision.toString(),
        List<String>.unmodifiable(accountIds),
      ],
    );
    return _codec.decodeWalletState(value[0]);
  }

  @override
  Future<CitizenDefaultAccountChangeOutcome> beginDefaultAccountChange({
    required BigInt expectedRevision,
    required List<String> accountIds,
    int ttlSeconds = 90,
  }) async {
    final value = await _session.invoke(
      'beginDefaultAccountChange',
      fields: <Object?>[
        expectedRevision.toString(),
        List<String>.unmodifiable(accountIds),
        ttlSeconds,
      ],
    );
    return _codec.decodeDefaultAccountChangeOutcome(value[0]);
  }

  @override
  Future<CitizenDefaultAccountChangeCompleted> consumeDefaultAccountChange({
    required String sessionId,
    required String response,
  }) async {
    final value = await _session.invoke(
      'consumeDefaultAccountChange',
      fields: <Object?>[sessionId, response],
    );
    final outcome = _codec.decodeDefaultAccountChangeOutcome(value[0]);
    if (outcome is! CitizenDefaultAccountChangeCompleted) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: '默认账户签名消费后未返回 completed',
      );
    }
    return outcome;
  }

  @override
  Future<void> viewAccountPrivateKey(String accountId) async {
    await _session.invoke(
      'viewAccountPrivateKey',
      fields: <Object?>[accountId],
    );
  }

  @override
  Future<CitizenWalletProfile> create({
    CitizenWalletWordCount wordCount = CitizenWalletWordCount.words12,
  }) async {
    final value = await _session.invoke(
      'createWallet',
      fields: <Object?>[wordCount.value],
    );
    return _requireProfile(value[0], '创建');
  }

  @override
  Future<CitizenWalletProfile> importWallet() async {
    final value = await _session.invoke('importWallet');
    return _requireProfile(value[0], '导入');
  }

  @override
  Future<CitizenWalletProfile> addAccounts(List<int> indices) async {
    _requireCount(
      indices.length,
      minimum: 1,
      maximum: CitizenSdkFlutterCodec.maximumAdditionalWalletAccounts,
      label: '追加账户 indices',
    );
    final value = await _session.invoke(
      'addWalletAccounts',
      fields: <Object?>[List<int>.unmodifiable(indices)],
    );
    return _requireProfile(value[0], '追加账户');
  }

  @override
  Future<CitizenWalletProfile> setActiveAccount(String accountId) async {
    final value = await _session.invoke(
      'setActiveWalletAccount',
      fields: <Object?>[accountId],
    );
    return _requireProfile(value[0], '切换账户');
  }

  @override
  Future<CitizenWalletState> renameAccount({
    required String accountId,
    required String name,
  }) async {
    if (name.length > 128) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: '账户名称原始输入不能超过 128 个 UTF-16 code unit',
      );
    }
    final normalizedName = name.trim();
    final value = await _session.invoke(
      'renameAccount',
      fields: <Object?>[accountId, normalizedName],
    );
    return _codec.decodeWalletState(value[0]);
  }

  @override
  Future<CitizenWalletState> deleteAccount(String accountId) async {
    final value = await _session.invoke(
      'deleteAccount',
      fields: <Object?>[accountId],
    );
    return _codec.decodeWalletState(value[0]);
  }

  @override
  Future<void> delete() async {
    final value = await _session.invoke('deleteWallet');
    if (_codec.decodeWalletProfile(value[0]) != null) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: 'deleteWallet 完成后仍返回钱包 profile',
      );
    }
  }

  @override
  Future<CitizenWalletProfile?> reconcileCleanup() async {
    final value = await _session.invoke('reconcileWalletCleanup');
    return _codec.decodeWalletProfile(value[0]);
  }

  CitizenWalletProfile _requireProfile(Object? raw, String operation) {
    final profile = _codec.decodeWalletProfile(raw);
    if (profile == null) {
      throw CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: '$operation完成但没有公开钱包 profile',
      );
    }
    return profile;
  }
}

/// 独立密码学控制面：验签无需金库，签名只引用 SDK 安全建立的账户秘密。
abstract interface class CitizenSigning {
  /// 使用已就绪 chain 的可信 metadata 审阅，原生确认后执行现有安全签名。
  /// 必须显式启用 qr+signing+chain；不会隐式启动链，不返回内部 Review 句柄。
  Future<CitizenQrSigned> signQrRequest(String signRequest);

  Future<CitizenWalletSignature> sign({
    required String accountId,
    required Uint8List payload,
  });

  /// Routes a generic opaque intent using the account's persisted hot/cold mode.
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent);

  /// Verifies and consumes exactly one instance-local external signing response.
  Future<CitizenSigningCompleted> consumeExternalSignature({
    required String sessionId,
    required String response,
  });

  Future<bool> cancel(String sessionId);

  /// 无状态纯验签，无需 open、模块实例、事件订阅、链数据库或设备金库。
  ///
  /// 仅编码公开输入，密码学验证由五端共同使用的 Rust 实现完成。
  static Future<bool> verify({
    required String accountId,
    required Uint8List signature,
    required Uint8List payload,
  }) async {
    const codec = CitizenSdkFlutterCodec();
    final arguments = codec.encodeVerification(
      accountId: accountId,
      signature: signature,
      payload: payload,
    );
    final platform =
        CitizenSdkPlatform.instance ?? CitizenSdk._defaultPlatform();
    return codec.decodeVerification(
      await platform.invoke('verifySignature', arguments),
    );
  }
}

final class _CitizenSigning implements CitizenSigning {
  const _CitizenSigning(this._session, this._codec);

  final CitizenSdkFlutterSession _session;
  final CitizenSdkFlutterCodec _codec;

  @override
  Future<CitizenQrSigned> signQrRequest(String signRequest) async {
    final value = await _session.invoke(
      'signQrRequest',
      fields: <Object?>[signRequest],
    );
    final document = _codec.decodeQrDocument(value[0], signed: true);
    final qrImage = await _CitizenQr(_session).encode(document.canonicalText);
    return CitizenQrSigned(
      canonicalText: document.canonicalText,
      qrImage: qrImage,
      requestId: document.requestId!,
      signerAccountId: document.signerAccountId!,
      signature: document.signature!,
      signRequest: document.signRequest!,
    );
  }

  @override
  Future<CitizenWalletSignature> sign({
    required String accountId,
    required Uint8List payload,
  }) async {
    if (payload.length > CitizenSdkFlutterCodec.maximumSigningPayloadBytes) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: '签名 payload 不能超过 16 MiB',
      );
    }
    final transportCopy = Uint8List.fromList(payload);
    try {
      final value = await _session.invoke(
        'signWalletPayload',
        fields: <Object?>[accountId, transportCopy],
      );
      return _codec.decodeSignature(accountId: accountId, raw: value[0]);
    } finally {
      transportCopy.fillRange(0, transportCopy.length, 0);
    }
  }

  @override
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent) async {
    final value = await _session.invoke(
      'beginSigning',
      fields: <Object?>[
        intent.accountId,
        Uint8List.fromList(intent.payload),
        intent.transform.kind.name,
        Uint8List.fromList(intent.transform.domain),
        intent.externalSignerTransport?.name ?? 'none',
        intent.opaqueAction,
        intent.ttlSeconds,
      ],
    );
    return _codec.decodeSigningOutcome(value[0]);
  }

  @override
  Future<CitizenSigningCompleted> consumeExternalSignature({
    required String sessionId,
    required String response,
  }) async {
    final value = await _session.invoke(
      'consumeExternalSignature',
      fields: <Object?>[sessionId, response],
    );
    final outcome = _codec.decodeSigningOutcome(value[0]);
    if (outcome is! CitizenSigningCompleted) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: 'external signature 消费后未返回 completed',
      );
    }
    return outcome;
  }

  @override
  Future<bool> cancel(String sessionId) async =>
      (await _session.invoke('cancelSigning', fields: <Object?>[sessionId]))[0]!
          as bool;
}

final class _CitizenQr implements CitizenQr {
  const _CitizenQr(this._session);

  final CitizenSdkFlutterSession _session;

  @override
  Future<CitizenQrDocument> scan() async {
    final value = await _session.invoke('qrScan');
    return const CitizenSdkFlutterCodec().decodeQrDocument(value[0]);
  }

  @override
  Future<CitizenQrDocument> parse(String text) async {
    final value = await _session.invoke('qrParse', fields: <Object?>[text]);
    return const CitizenSdkFlutterCodec().decodeQrDocument(value[0]);
  }

  @override
  Future<String> createSignRequest({
    required int action,
    required String signerAccountId,
    required Uint8List reviewPayload,
    int ttlSeconds = 120,
  }) async =>
      (await _session.invoke(
            'qrCreateSignRequest',
            fields: <Object?>[
              action,
              signerAccountId,
              Uint8List.fromList(reviewPayload),
              ttlSeconds,
            ],
          ))[0]!
          as String;

  @override
  Future<Uint8List> consumeSignResponse(String signResponse) async {
    final value = await _session.invoke(
      'qrConsumeSignResponse',
      fields: <Object?>[signResponse],
    );
    return Uint8List.fromList(value[0]! as Uint8List).asUnmodifiableView();
  }

  @override
  Future<bool> cancelSignRequest(String requestId) async =>
      (await _session.invoke(
            'qrCancelSignRequest',
            fields: <Object?>[requestId],
          ))[0]!
          as bool;

  @override
  Future<String> encodeAccountId(String accountId) async =>
      (await _session.invoke(
            'qrEncodeAccountId',
            fields: <Object?>[accountId],
          ))[0]!
          as String;

  @override
  Future<CitizenQrDocument> decodeLuminance({
    required Uint8List data,
    required int width,
    required int height,
    required int rowStride,
  }) async {
    final value = await _session.invoke(
      'qrDecodeLuminance',
      fields: <Object?>[Uint8List.fromList(data), width, height, rowStride],
    );
    return const CitizenSdkFlutterCodec().decodeQrDocument(value[0]);
  }

  @override
  Future<CitizenQrImage> encode(String text, {int scale = 4}) async {
    final value = await _session.invoke(
      'qrEncode',
      fields: <Object?>[text, scale],
    );
    return CitizenQrImage(
      width: value[0]! as int,
      height: value[1]! as int,
      luminance: value[2]! as Uint8List,
    );
  }
}

final class _CitizenTransactions implements CitizenTransactions {
  const _CitizenTransactions(this._session, this._codec);

  final CitizenSdkFlutterSession _session;
  final CitizenSdkFlutterCodec _codec;

  @override
  Future<CitizenPreparedTransaction> prepareTransaction(
    Uint8List sourceAccountId,
    Uint8List callData,
  ) async {
    if (sourceAccountId.length != 32) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: 'sourceAccountId 必须是 32 字节',
      );
    }
    if (callData.isEmpty ||
        callData.length >
            CitizenSdkFlutterCodec.maximumTransactionCallDataBytes) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: 'callData 必须包含 1..1 MiB 字节',
      );
    }
    final source = Uint8List.fromList(sourceAccountId);
    final call = Uint8List.fromList(callData);
    final value = await _session.invoke(
      'prepareTransaction',
      fields: <Object?>[citizenAccountIdFromBytes(source), call],
    );
    final prepared = _codec.decodePreparedTransaction(value[0]);
    if (!_bytesEqual(prepared.sourceAccountId, source)) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.integrity,
        message: 'transaction preparation source 与请求不一致',
      );
    }
    return prepared;
  }

  @override
  Future<void> cancelPreparedTransaction(String preparationId) async {
    await _session.invoke(
      'cancelPreparedTransaction',
      fields: <Object?>[preparationId],
    );
  }

  @override
  Future<CitizenTransactionExecution> executePreparedTransaction(
    String preparationId,
  ) async {
    final value = await _session.invoke(
      'executePreparedTransaction',
      fields: <Object?>[preparationId],
    );
    return _codec.decodeTransactionExecution(value[0]);
  }

  @override
  Future<CitizenTransactionExecutionCompleted>
  consumePreparedTransactionQrResponse(
    String executionId,
    String response,
  ) async {
    final value = await _session.invoke(
      'consumePreparedTransactionQrResponse',
      fields: <Object?>[executionId, response],
    );
    final completed = _codec.decodeTransactionExecution(value[0]);
    if (completed is! CitizenTransactionExecutionCompleted) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.integrity,
        message: 'QR_V1 response 未返回 transaction terminal',
      );
    }
    return completed;
  }

  @override
  Future<void> cancelPreparedTransactionExecution(String executionId) async {
    await _session.invoke(
      'cancelPreparedTransactionExecution',
      fields: <Object?>[executionId],
    );
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final class _CitizenHistory implements CitizenHistory {
  const _CitizenHistory(this._session, this._codec);

  final CitizenSdkFlutterSession _session;
  final CitizenSdkFlutterCodec _codec;

  @override
  Future<CitizenTransactionHistoryPage> getTransactionHistory({
    String? beforeExecutionId,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        message: '交易历史 limit 必须在 1..100 范围内',
      );
    }
    final value = await _session.invoke(
      'getTransactionHistory',
      fields: <Object?>[beforeExecutionId, limit],
    );
    return _codec.decodeTransactionHistoryPage(value[0]);
  }

  @override
  Future<CitizenTransactionHistoryPage> syncTransactionHistory() async {
    final value = await _session.invoke('syncTransactionHistory');
    return _codec.decodeTransactionHistoryPage(value[0]);
  }
}

void _requireCount(
  int count, {
  required int minimum,
  required int maximum,
  required String label,
}) {
  if (count < minimum || count > maximum) {
    throw CitizenSdkException(
      code: CitizenSdkErrorCode.invalidArgument,
      message: '$label 必须包含 $minimum..$maximum 项',
    );
  }
}
