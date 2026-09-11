import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/citizen_qr.dart';
import '../api/citizen_sdk_error.dart';
import '../api/citizen_sdk_events.dart';
import '../crypto/account_codec.dart';
import '../models/citizen_account.dart';
import '../models/citizen_capability.dart';
import '../models/citizen_chain_state.dart';
import '../models/citizen_signing.dart';
import '../models/citizen_transaction.dart';
import '../models/citizen_wallet.dart';

/// Method/Event channel v1 的固定长度、固定位置 tuple 编码器。
///
/// StandardMessageCodec 会在 Kotlin 收到数据前折叠 Map 重复键，因此 v1 完全禁止 Map，且不
/// 提供兼容旁路。每一层 List 都校验精确长度、位置类型和枚举闭集；任何偏差均失败关闭。
final class CitizenSdkFlutterCodec {
  const CitizenSdkFlutterCodec();

  static const int protocolVersion = 1;
  static const int maximumSessionIdCodeUnits = 128;
  static const int maximumAdditionalWalletAccounts = 1989;
  static const int maximumWalletCatalogAccounts = 3980;
  static const int maximumDefaultAccountChangeAccounts = 256;
  static const int maximumBalanceAccounts = 1990;
  static const int maximumSigningPayloadBytes = 16 * 1024 * 1024;
  static const int maximumStorageKeyBytes = 4 * 1024;
  static const int maximumStorageBatchKeys = 1024;
  static const int maximumStorageBatchKeyBytes = 1024 * 1024;
  static const int maximumHeaderDigestBytes = 1024 * 1024;
  static const int maximumBlockBodyExtrinsics = 16 * 1024;
  static const int maximumBlockBodyBytes = 64 * 1024 * 1024;
  static const int maximumRuntimeMetadataBytes = 64 * 1024 * 1024;
  static const int maximumTransactionCallDataBytes = 1024 * 1024;
  static const int maximumExportedStateBytes = 256 * 1024;
  static const int maximumQrTextBytes = 2331;
  static const int maximumQrReviewPayloadBytes = 1920;
  static const int maximumQrImageBytes = 16 * 1024 * 1024;

  static const Set<String> methods = <String>{
    'open',
    'start',
    'stop',
    'close',
    'getCapabilities',
    'getFinalizedHead',
    'getSyncStatus',
    'getBestHead',
    'getFinalizedBlockAt',
    'resolveFinalizedBlock',
    'getBlockHeader',
    'getBlockBody',
    'getRuntimeContext',
    'getStorage',
    'getStorageBatch',
    'getSystemEvents',
    'exportState',
    'importState',
    'getGenesisHash',
    'getAccountBalance',
    'getAccountBalances',
    'getAccountNonce',
    'getFeeSnapshot',
    'getWalletProfile',
    'viewAccountPrivateKey',
    'getWalletState',
    'importColdAccountId',
    'importColdAccountSs58',
    'reorderWalletAccountsWithoutDefaultChange',
    'renameAccount',
    'deleteAccount',
    'createWallet',
    'importWallet',
    'addWalletAccounts',
    'setActiveWalletAccount',
    'renameWalletAccount',
    'deleteWalletAccount',
    'deleteWallet',
    'reconcileWalletCleanup',
    'signWalletPayload',
    'beginSigning',
    'consumeExternalSignature',
    'cancelSigning',
    'beginDefaultAccountChange',
    'consumeDefaultAccountChange',
    'verifySignature',
    'prepareTransaction',
    'cancelPreparedTransaction',
    'executePreparedTransaction',
    'consumePreparedTransactionQrResponse',
    'cancelPreparedTransactionExecution',
    'getTransactionHistory',
    'syncTransactionHistory',
    'qrParse',
    'qrCreateSignRequest',
    'qrConsumeSignResponse',
    'qrCancelSignRequest',
    'qrEncodeAccountId',
    'qrDecodeLuminance',
    'qrEncode',
    'qrScan',
    'signQrRequest',
  };

  /// open 精确传递协议版本和模块集合；不接受省略模块的第二种格式。
  List<Object?> encodeOpen([int modules = CitizenSdkModules.full]) {
    if (modules <= 0 || modules > 0xffffffff) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        stage: CitizenSdkFailureStage.validation,
        message: 'modules 必须是非零 uint32',
      );
    }
    return <Object?>[protocolVersion, modules];
  }

  /// 唯一无会话请求；不含 session、requestSequence，也不接受 session 形状。
  List<Object?> encodeVerification({
    required String accountId,
    required Uint8List signature,
    required Uint8List payload,
  }) {
    final fields = <Object?>[accountId, signature, payload];
    try {
      _validateRequestFields('verifySignature', fields);
    } on CitizenSdkException catch (error) {
      throw CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        stage: CitizenSdkFailureStage.validation,
        message: error.message,
      );
    }
    return <Object?>[protocolVersion, ...fields];
  }

  bool decodeVerification(Object? raw) {
    final tuple = _tuple(raw, 2, '验签响应');
    _expectProtocol(tuple[0]);
    if (tuple[1] is! bool) throw _decodeFailure('验签结果必须为 bool');
    return tuple[1]! as bool;
  }

  List<Object?> encodeRequest({
    required String method,
    required String sessionId,
    required int requestSequence,
    List<Object?> fields = const <Object?>[],
  }) {
    if (method == 'open' ||
        method == 'verifySignature' ||
        !methods.contains(method)) {
      throw CitizenSdkException(
        code: CitizenSdkErrorCode.unsupported,
        stage: CitizenSdkFailureStage.admission,
        message: '未知或非法 session method：$method',
      );
    }
    try {
      if (!_validSessionId(sessionId) || requestSequence <= 0) {
        throw _decodeFailure('sessionId 和 requestSequence 非法');
      }
      _rejectMaps(fields, '$method 请求');
      _validateRequestFields(method, fields);
    } on CitizenSdkException catch (error) {
      // Request-shape and caller-field failures are invalid arguments. The
      // `decode` category is reserved for malformed native responses/events.
      throw CitizenSdkException(
        code: CitizenSdkErrorCode.invalidArgument,
        stage: CitizenSdkFailureStage.validation,
        message: error.message,
      );
    }
    return <Object?>[protocolVersion, sessionId, requestSequence, ...fields];
  }

  DecodedCitizenSdkResponse decodeResponse({
    required String method,
    required Object? raw,
    String? expectedSessionId,
    required int expectedRequestSequence,
  }) {
    final response = decodeResponseEnvelope(
      raw: raw,
      expectedSessionId: expectedSessionId,
      expectedRequestSequence: expectedRequestSequence,
      valueName: '$method value',
    );
    validateResponseValue(method, response.value);
    return response;
  }

  /// 只验证响应外壳和关联字段，不验证 method-specific value。
  ///
  /// `open` 必须先取得并记录原生 sessionId，随后才能验证 value；这样即使 value
  /// 损坏，Dart 仍可对已经创建的原生 session 发出一次受监督的 close，避免泄漏。
  DecodedCitizenSdkResponse decodeResponseEnvelope({
    required Object? raw,
    String? expectedSessionId,
    required int expectedRequestSequence,
    String valueName = '响应 value',
  }) {
    final tuple = _tuple(raw, 4, '响应');
    _expectProtocol(tuple[0]);
    final sessionId = _sessionId(tuple[1], 'sessionId');
    if (expectedSessionId != null && sessionId != expectedSessionId) {
      throw _decodeFailure('响应属于错误的 session');
    }
    final requestSequence = _nonNegativeInt(tuple[2], 'requestSequence');
    if (requestSequence != expectedRequestSequence) {
      throw _decodeFailure('响应 requestSequence 未精确回显');
    }
    final value = _list(tuple[3], valueName);
    _rejectMaps(value, valueName);
    return DecodedCitizenSdkResponse(
      sessionId: sessionId,
      requestSequence: requestSequence,
      value: value,
    );
  }

  /// 验证已经与 session/request 精确关联的 method-specific value。
  void validateResponseValue(String method, List<Object?> value) =>
      _validateResponseValue(method, value);

  DecodedCitizenSdkEvent decodeEvent(Object? raw) {
    final tuple = _eventTuple(raw);
    return _decodeEventTuple(tuple);
  }

  /// 先按顶层 sessionId 路由，再解码该 session 的事件内容。
  ///
  /// EventChannel 是进程级广播。其他 session 的 payload 即使损坏也不得毒化本
  /// session；协议版本、tuple 长度和 sessionId 本身仍必须可验证，否则无法安全路由。
  DecodedCitizenSdkEvent? decodeEventForSession(
    Object? raw,
    String expectedSessionId,
  ) {
    final tuple = _eventTuple(raw, rejectNestedMaps: false);
    final sessionId = _sessionId(tuple[1], 'sessionId');
    if (sessionId != expectedSessionId) return null;
    _rejectMaps(tuple, '事件');
    return _decodeEventTuple(tuple);
  }

  /// 仅提取进程级事件路由键；不查看 eventSequence、type 或 payload。
  String eventSessionIdForRouting(Object? raw) {
    final tuple = _eventTuple(raw, rejectNestedMaps: false);
    final sessionId = _sessionId(tuple[1], 'sessionId');
    return sessionId;
  }

  List<Object?> _eventTuple(Object? raw, {bool rejectNestedMaps = true}) {
    final tuple = _list(raw, '事件');
    _expectLength(tuple, 5, '事件');
    if (rejectNestedMaps) _rejectMaps(tuple, '事件');
    _expectProtocol(tuple[0]);
    return tuple;
  }

  DecodedCitizenSdkEvent _decodeEventTuple(List<Object?> tuple) {
    final sessionId = _sessionId(tuple[1], 'sessionId');
    final sequence = _positiveInt(tuple[2], 'eventSequence');
    final type = _string(tuple[3], 'event type');
    final payload = _list(tuple[4], 'event payload');
    _rejectMaps(payload, 'event payload');
    final event = switch (type) {
      'lifecycleChanged' => _decodeLifecycleEvent(sequence, payload),
      'historyChanged' => _decodeHistoryEvent(sequence, payload),
      'capabilitiesChanged' => _decodeCapabilitiesEvent(sequence, payload),
      _ => throw _decodeFailure('未知事件类型：$type'),
    };
    return DecodedCitizenSdkEvent(
      sessionId: sessionId,
      eventSequence: sequence,
      event: event,
    );
  }

  CitizenSdkException decodePlatformException(
    PlatformException error, {
    String? expectedMethod,
  }) {
    final tuple = _tuple(error.details, 7, '错误 details');
    _expectProtocol(tuple[0]);
    final sessionId = _nullableSessionId(tuple[1], 'sessionId');
    final requestSequence = _nullablePositiveInt(tuple[2], 'requestSequence');
    final numericCode = _positiveInt(tuple[3], 'errorCode');
    final code = switch (numericCode) {
      1 => CitizenSdkErrorCode.invalidArgument,
      2 => CitizenSdkErrorCode.invalidHandle,
      3 => CitizenSdkErrorCode.invalidState,
      4 => CitizenSdkErrorCode.unsupported,
      5 => CitizenSdkErrorCode.unavailable,
      6 => CitizenSdkErrorCode.notReady,
      7 => CitizenSdkErrorCode.notFound,
      8 => CitizenSdkErrorCode.conflict,
      9 => CitizenSdkErrorCode.integrity,
      10 => CitizenSdkErrorCode.authenticationCancelled,
      11 => CitizenSdkErrorCode.authenticationRequired,
      12 => CitizenSdkErrorCode.keyInvalidated,
      13 => CitizenSdkErrorCode.permissionDenied,
      14 => CitizenSdkErrorCode.storage,
      15 => CitizenSdkErrorCode.network,
      16 => CitizenSdkErrorCode.decode,
      17 => CitizenSdkErrorCode.timeout,
      18 => CitizenSdkErrorCode.busy,
      19 => CitizenSdkErrorCode.queueFull,
      20 => CitizenSdkErrorCode.internal,
      21 => CitizenSdkErrorCode.panic,
      22 => CitizenSdkErrorCode.cancelled,
      _ => throw _decodeFailure('未知 errorCode：$numericCode'),
    };
    final numericStage = _positiveInt(tuple[4], 'failureStage');
    final stage = switch (numericStage) {
      1 => CitizenSdkFailureStage.admission,
      2 => CitizenSdkFailureStage.validation,
      3 => CitizenSdkFailureStage.authentication,
      4 => CitizenSdkFailureStage.persistence,
      5 => CitizenSdkFailureStage.provider,
      6 => CitizenSdkFailureStage.verification,
      7 => CitizenSdkFailureStage.cancellation,
      8 => CitizenSdkFailureStage.teardown,
      _ => throw _decodeFailure('未知 failureStage'),
    };
    final method = _string(tuple[5], 'method');
    if (!methods.contains(method) ||
        (expectedMethod != null && method != expectedMethod)) {
      throw _decodeFailure('错误 method 不属于当前公开调用');
    }
    if (error.code != 'citizensdk.${code.name}') {
      throw _decodeFailure('PlatformException code 与 errorCode 不一致');
    }
    return CitizenSdkException(
      code: code,
      stage: stage,
      method: method,
      message: _nullableString(tuple[6], 'errorMessage') ?? code.name,
      sessionId: sessionId,
      requestSequence: requestSequence,
    );
  }

  CitizenSdkLifecycle decodeLifecycle(Object? raw) {
    final value = _string(raw, 'lifecycle');
    return CitizenSdkLifecycle.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => throw _decodeFailure('未知 lifecycle：$value'),
    );
  }

  CitizenBlockRef decodeBlock(Object? raw) {
    final tuple = _tuple(raw, 3, 'block');
    final finalityName = _string(tuple[2], 'block.finality');
    return CitizenBlockRef(
      hash: _hex32(tuple[0], 'block.hash'),
      number: _u64Decimal(tuple[1], 'block.number'),
      finality: CitizenBlockFinality.values.firstWhere(
        (candidate) => candidate.name == finalityName,
        orElse: () => throw _decodeFailure('未知 block.finality：$finalityName'),
      ),
    );
  }

  List<Object?> encodeBlock(CitizenBlockRef block) {
    final encoded = <Object?>[
      block.hash,
      block.number.toString(),
      block.finality.name,
    ];
    decodeBlock(encoded);
    return encoded;
  }

  CitizenChainSyncStatus decodeSyncStatus(Object? raw) {
    final tuple = _tuple(raw, 5, 'chain sync status');
    final status = CitizenChainSyncStatus(
      peerCount: _u64Decimal(tuple[0], 'sync.peerCount'),
      isSyncing: _boolean(tuple[1], 'sync.isSyncing'),
      isUsable: _boolean(tuple[2], 'sync.isUsable'),
      best: decodeBlock(tuple[3]),
      finalized: decodeBlock(tuple[4]),
    );
    if (status.best.finality != CitizenBlockFinality.best ||
        status.finalized.finality != CitizenBlockFinality.finalized ||
        status.finalized.number > status.best.number) {
      throw _decodeFailure('同步状态的 best/finalized 锚不一致');
    }
    return status;
  }

  CitizenBlockHeader decodeBlockHeader(Object? raw) {
    final tuple = _tuple(raw, 5, 'block header');
    final digest = _bytes(tuple[4], 'blockHeader.digest');
    if (digest.length > maximumHeaderDigestBytes) {
      throw _decodeFailure('blockHeader.digest 超过 1 MiB');
    }
    return CitizenBlockHeader(
      block: decodeBlock(tuple[0]),
      parentHash: _hex32(tuple[1], 'blockHeader.parentHash'),
      stateRoot: _hex32(tuple[2], 'blockHeader.stateRoot'),
      extrinsicsRoot: _hex32(tuple[3], 'blockHeader.extrinsicsRoot'),
      digest: digest,
    );
  }

  CitizenBlockBody decodeBlockBody(Object? raw) {
    final tuple = _tuple(raw, 2, 'block body');
    final values = _list(tuple[1], 'blockBody.extrinsics');
    if (values.length > maximumBlockBodyExtrinsics) {
      throw _decodeFailure('blockBody.extrinsics 超过 16384 项');
    }
    var total = 0;
    final extrinsics = <Uint8List>[];
    for (var index = 0; index < values.length; index++) {
      final bytes = _bytes(values[index], 'blockBody.extrinsics[$index]');
      if (bytes.isEmpty) throw _decodeFailure('block body 不允许空 extrinsic');
      total += bytes.length;
      if (total > maximumBlockBodyBytes) {
        throw _decodeFailure('block body 超过 64 MiB');
      }
      extrinsics.add(bytes);
    }
    return CitizenBlockBody(
      block: decodeBlock(tuple[0]),
      extrinsics: extrinsics,
    );
  }

  CitizenRuntimeContext decodeRuntimeContext(Object? raw) {
    final tuple = _tuple(raw, 4, 'runtime context');
    final metadata = _bytes(tuple[3], 'runtime.metadata');
    if (metadata.isEmpty || metadata.length > maximumRuntimeMetadataBytes) {
      throw _decodeFailure('runtime.metadata 必须为 1..64 MiB');
    }
    return CitizenRuntimeContext(
      block: decodeBlock(tuple[0]),
      specVersion: _u32Int(tuple[1], 'runtime.specVersion'),
      transactionVersion: _u32Int(tuple[2], 'runtime.transactionVersion'),
      metadata: metadata,
    );
  }

  Uint8List? decodeStorage(Object? raw) {
    if (raw == null) return null;
    return _bytes(raw, 'storage value');
  }

  List<Uint8List?> decodeStorageBatch(Object? raw) {
    final values = _list(raw, 'storage batch');
    if (values.length > maximumStorageBatchKeys) {
      throw _decodeFailure('storage batch 响应超过 1024 项');
    }
    var total = 0;
    final decoded = values.map((value) {
      final bytes = decodeStorage(value);
      total += bytes?.length ?? 0;
      if (total > maximumBlockBodyBytes) {
        throw _decodeFailure('storage batch 响应总长度超过 64 MiB');
      }
      return bytes;
    });
    return List<Uint8List?>.unmodifiable(decoded);
  }

  CitizenChainState decodeChainState(Object? raw) {
    final tuple = _tuple(raw, 3, 'chain state');
    final formatVersion = _u32Int(tuple[0], 'chainState.formatVersion');
    final finalized = decodeBlock(tuple[1]);
    final database = _bytes(tuple[2], 'chainState.database');
    if (formatVersion == 0 ||
        finalized.finality != CitizenBlockFinality.finalized ||
        database.isEmpty ||
        database.length > maximumExportedStateBytes) {
      throw _decodeFailure('chain state 的 finalized/database 无效');
    }
    return CitizenChainState(
      formatVersion: formatVersion,
      finalized: finalized,
      database: database,
    );
  }

  CitizenCapabilitySnapshot decodeCapabilities(Object? raw) {
    final tuple = _tuple(raw, 2, 'capability snapshot');
    final statusesRaw = _list(tuple[1], 'capability statuses');
    final statuses = <CitizenCapabilityStatus>[];
    for (var index = 0; index < statusesRaw.length; index++) {
      final status = _tuple(statusesRaw[index], 6, 'capability status[$index]');
      final nameText = _string(status[0], 'status.name');
      final reasonText = _string(status[5], 'status.reason');
      statuses.add(
        CitizenCapabilityStatus(
          name: CitizenCapabilityName.values.firstWhere(
            (candidate) => candidate.name == nameText,
            orElse: () => throw _decodeFailure('未知能力：$nameText'),
          ),
          supported: _boolean(status[1], 'status.supported'),
          available: _boolean(status[2], 'status.available'),
          enabled: _boolean(status[3], 'status.enabled'),
          ready: _boolean(status[4], 'status.ready'),
          reason: CitizenCapabilityReason.values.firstWhere(
            (candidate) => candidate.name == reasonText,
            orElse: () => throw _decodeFailure('未知能力原因：$reasonText'),
          ),
        ),
      );
      final decoded = statuses.last;
      if ((decoded.ready &&
              (!decoded.supported ||
                  !decoded.available ||
                  !decoded.enabled ||
                  decoded.reason != CitizenCapabilityReason.none)) ||
          (!decoded.ready && decoded.reason == CitizenCapabilityReason.none)) {
        throw _decodeFailure(
          '能力 ready 状态与 supported/available/enabled/reason 不一致',
        );
      }
    }
    try {
      return CitizenCapabilitySnapshot(
        revision: _u64Decimal(tuple[0], 'capability revision'),
        statuses: statuses,
      );
    } on ArgumentError catch (error) {
      throw _decodeFailure('能力快照不完整：$error');
    }
  }

  List<CitizenAccountBalance> decodeBalances(Object? raw) {
    final values = _list(raw, 'balances');
    if (values.length > maximumBalanceAccounts) {
      throw _decodeFailure('批量余额结果超过 1990 项');
    }
    final balances = values.map(decodeBalance).toList(growable: false);
    if (balances.isNotEmpty) {
      final anchor = balances.first.block;
      for (final balance in balances) {
        if (balance.block.hash != anchor.hash ||
            balance.block.number != anchor.number ||
            balance.block.finality != anchor.finality) {
          throw _decodeFailure('批量余额必须来自同一 finalized 块');
        }
      }
    }
    return List<CitizenAccountBalance>.unmodifiable(balances);
  }

  CitizenAccountBalance decodeBalance(Object? raw) {
    final tuple = _tuple(raw, 5, 'balance');
    final balance = CitizenAccountBalance(
      accountId: _hex32(tuple[0], 'balance.accountId'),
      block: decodeBlock(tuple[1]),
      freeFen: _u128Decimal(tuple[2], 'balance.freeFen'),
      reservedFen: _u128Decimal(tuple[3], 'balance.reservedFen'),
      totalFen: _u128Decimal(tuple[4], 'balance.totalFen'),
    );
    if (balance.block.finality != CitizenBlockFinality.finalized ||
        balance.freeFen + balance.reservedFen != balance.totalFen) {
      throw _decodeFailure('balance 的 finalized 块或 total 语义不一致');
    }
    return balance;
  }

  CitizenAccountNonce decodeNonce(Object? raw) {
    final tuple = _tuple(raw, 3, 'nonce');
    final nonce = CitizenAccountNonce(
      accountId: _hex32(tuple[0], 'nonce.accountId'),
      bestBlock: decodeBlock(tuple[1]),
      nonce: _u64Decimal(tuple[2], 'nonce.nonce'),
    );
    if (nonce.bestBlock.finality != CitizenBlockFinality.best) {
      throw _decodeFailure('nonce 必须锚定 best 块');
    }
    return nonce;
  }

  CitizenFeeSnapshot decodeFeeSnapshot(Object? raw) {
    final tuple = _tuple(raw, 4, 'fee snapshot');
    final feeRateParts = _nonNegativeInt(tuple[1], 'feeRateParts');
    if (feeRateParts == 0 || feeRateParts > 1000000000) {
      throw _decodeFailure('feeRateParts 必须是有效的正 Perbill');
    }
    final snapshot = CitizenFeeSnapshot(
      bestBlock: decodeBlock(tuple[0]),
      feeRateParts: feeRateParts,
      minimumFeeFen: _u128Decimal(tuple[2], 'minimumFeeFen'),
      existentialDepositFen: _u128Decimal(tuple[3], 'existentialDepositFen'),
    );
    if (snapshot.bestBlock.finality != CitizenBlockFinality.best) {
      throw _decodeFailure('fee snapshot 必须锚定 best 块');
    }
    if (snapshot.minimumFeeFen <= BigInt.zero) {
      throw _decodeFailure('minimumFeeFen 必须大于 0');
    }
    return snapshot;
  }

  CitizenWalletProfile? decodeWalletProfile(Object? raw) {
    if (raw == null) return null;
    final tuple = _tuple(raw, 6, 'wallet profile');
    final accountsRaw = _list(tuple[5], 'wallet accounts');
    final activeAccountId = _hex32(tuple[4], 'profile.activeAccountId');
    final accounts = <CitizenAccount>[];
    for (var index = 0; index < accountsRaw.length; index++) {
      final account = _tuple(accountsRaw[index], 6, 'account[$index]');
      final accountId = _hex32(account[1], 'account.accountId');
      final ss58Address = _string(account[2], 'account.ss58Address');
      final name = _string(account[3], 'account.name');
      if (!_validAccountName(name)) {
        throw _decodeFailure('公开账户名称必须已修剪、含 1..30 个 Unicode scalar 且无控制字符');
      }
      accounts.add(
        CitizenAccount(
          index: _accountIndex(account[0], 'account.index'),
          accountId: accountId,
          ss58Address: ss58Address,
          name: name,
          createdAtMillis: _u64Decimal(account[4], 'account.createdAtMillis'),
          isActive: _boolean(account[5], 'account.isActive'),
        ),
      );
      if (ss58Address != citizenSs58FromAccountId(accountId)) {
        throw _decodeFailure(
          'account.ss58Address 与 CitizenChain AccountId/prefix 2027 不一致',
        );
      }
    }
    final activeAccounts = accounts.where((account) => account.isActive);
    final accountIds = accounts.map((account) => account.accountId).toSet();
    final indices = accounts.map((account) => account.index).toSet();
    final masterAccountId = _hex32(tuple[3], 'profile.masterAccountId');
    final walletIndex = _u32Int(tuple[0], 'profile.walletIndex');
    if (accounts.isEmpty ||
        walletIndex != 0 ||
        activeAccounts.length != 1 ||
        activeAccounts.single.accountId != activeAccountId ||
        accountIds.length != accounts.length ||
        indices.length != accounts.length ||
        !accounts.any(
          (account) =>
              account.index == 0 && account.accountId == masterAccountId,
        )) {
      throw _decodeFailure('wallet profile 的账户闭集或 active/master 不一致');
    }
    final originText = _string(tuple[1], 'profile.origin');
    return CitizenWalletProfile(
      walletIndex: walletIndex,
      origin: CitizenWalletOrigin.values.firstWhere(
        (candidate) => candidate.name == originText,
        orElse: () => throw _decodeFailure('未知 wallet origin：$originText'),
      ),
      createdAtMillis: _u64Decimal(tuple[2], 'profile.createdAtMillis'),
      masterAccountId: masterAccountId,
      activeAccountId: activeAccountId,
      accounts: accounts,
    );
  }

  CitizenWalletState decodeWalletState(Object? raw) {
    final tuple = _tuple(raw, 3, 'wallet state');
    final revision = _u64Decimal(tuple[0], 'walletState.revision');
    final hotProfile = decodeWalletProfile(tuple[1]);
    final accountsRaw = _list(tuple[2], 'walletState.accounts');
    if (accountsRaw.length > maximumWalletCatalogAccounts) {
      throw _decodeFailure('统一钱包目录超过 3980 项');
    }
    final accounts = <CitizenWalletStateAccount>[];
    for (var index = 0; index < accountsRaw.length; index++) {
      final account = _tuple(
        accountsRaw[index],
        8,
        'walletState.account[$index]',
      );
      final signModeText = _string(account[0], 'stateAccount.signMode');
      final signMode = CitizenWalletSignMode.values.firstWhere(
        (candidate) => candidate.name == signModeText,
        orElse: () => throw _decodeFailure('未知钱包签名模式：$signModeText'),
      );
      final walletIndex = _u32Int(account[1], 'stateAccount.walletIndex');
      final accountIndex = account[2] == null
          ? null
          : _accountIndex(account[2], 'stateAccount.accountIndex');
      final accountId = _hex32(account[3], 'stateAccount.accountId');
      final ss58Address = _string(account[4], 'stateAccount.ss58Address');
      final name = _string(account[5], 'stateAccount.name');
      final isDefault = _boolean(account[7], 'stateAccount.isDefault');
      if (!_validAccountName(name) ||
          ss58Address != citizenSs58FromAccountId(accountId) ||
          isDefault != (index == 0) ||
          (signMode == CitizenWalletSignMode.hot &&
              (walletIndex != 0 || accountIndex == null)) ||
          (signMode == CitizenWalletSignMode.cold &&
              (walletIndex == 0 || accountIndex != null))) {
        throw _decodeFailure('统一钱包账户事实不一致');
      }
      accounts.add(
        CitizenWalletStateAccount(
          signMode: signMode,
          walletIndex: walletIndex,
          accountIndex: accountIndex,
          accountId: accountId,
          ss58Address: ss58Address,
          name: name,
          createdAtMillis: _u64Decimal(
            account[6],
            'stateAccount.createdAtMillis',
          ),
          isDefault: isDefault,
        ),
      );
    }
    final accountIds = accounts.map((account) => account.accountId).toSet();
    final coldWalletIndices = accounts
        .where((account) => account.signMode == CitizenWalletSignMode.cold)
        .map((account) => account.walletIndex)
        .toSet();
    final hotIds =
        hotProfile?.accounts.map((account) => account.accountId).toSet() ??
        const <String>{};
    final projectedHotIds = accounts
        .where((account) => account.signMode == CitizenWalletSignMode.hot)
        .map((account) => account.accountId)
        .toSet();
    if (accountIds.length != accounts.length ||
        coldWalletIndices.length !=
            accounts
                .where(
                  (account) => account.signMode == CitizenWalletSignMode.cold,
                )
                .length ||
        hotIds.length != projectedHotIds.length ||
        !hotIds.containsAll(projectedHotIds) ||
        !projectedHotIds.containsAll(hotIds)) {
      throw _decodeFailure('统一钱包目录的账户闭集不一致');
    }
    return CitizenWalletState(
      revision: revision,
      hotProfile: hotProfile,
      accounts: accounts,
    );
  }

  CitizenWalletSignature decodeSignature({
    required String accountId,
    required Object? raw,
  }) {
    final bytes = _bytes(raw, 'signature');
    if (bytes.length != 64) throw _decodeFailure('sr25519 signature 必须是 64 字节');
    return CitizenWalletSignature(accountId: accountId, bytes: bytes);
  }

  CitizenSigningOutcome decodeSigningOutcome(Object? raw) {
    final tuple = _tuple(raw, 7, 'signing outcome');
    final status = _string(tuple[0], 'signing.status');
    final accountId = _hex32(tuple[1], 'signing.accountId');
    final payloadHash = _hex32(tuple[2], 'signing.payloadHash');
    if (status == 'completed') {
      if (tuple[4] != null || tuple[5] != null || tuple[6] != null) {
        throw _decodeFailure('completed signing 不得携带 external session 字段');
      }
      final signature = _bytes(tuple[3], 'signing.signature');
      if (signature.length != 64) {
        throw _decodeFailure('completed signing 必须携带 64 字节签名');
      }
      return CitizenSigningCompleted(
        accountId: accountId,
        payloadHash: payloadHash,
        signature: signature,
      );
    }
    if (status == 'externalPending') {
      if (tuple[3] != null) {
        throw _decodeFailure('pending signing 不得提前携带签名');
      }
      final sessionId = _string(tuple[5], 'signing.sessionId');
      final request = _string(tuple[6], 'signing.transportRequest');
      if (!_validSessionId(sessionId) ||
          request.isEmpty ||
          request.length > maximumQrTextBytes) {
        throw _decodeFailure(
          'pending signing 的 session 或 transport request 无效',
        );
      }
      return CitizenExternalSigningPending(
        accountId: accountId,
        payloadHash: payloadHash,
        transport: CitizenExternalSignerTransport.qrV1,
        expiresAt: _u64Decimal(tuple[4], 'signing.expiresAt'),
        sessionId: sessionId,
        transportRequest: request,
      );
    }
    throw _decodeFailure('未知 signing outcome：$status');
  }

  CitizenDefaultAccountChangeOutcome decodeDefaultAccountChangeOutcome(
    Object? raw,
  ) {
    final tuple = _tuple(raw, 7, 'default account change');
    final status = _string(tuple[0], 'defaultChange.status');
    final current = _hex32(tuple[1], 'defaultChange.currentAccountId');
    final hash = _hex32(tuple[2], 'defaultChange.payloadHash');
    if (status == 'completed') {
      if (tuple[4] != null || tuple[5] != null || tuple[6] != null) {
        throw _decodeFailure('completed default change 不得携带 external 字段');
      }
      return CitizenDefaultAccountChangeCompleted(
        currentDefaultAccountId: current,
        payloadHash: hash,
        committedRevision: _u64Decimal(tuple[3], 'defaultChange.revision'),
      );
    }
    if (status == 'externalPending') {
      if (tuple[3] != null) {
        throw _decodeFailure('pending default change 不得携带 committed revision');
      }
      final sessionId = _string(tuple[5], 'defaultChange.sessionId');
      final request = _string(tuple[6], 'defaultChange.transportRequest');
      if (!_validSessionId(sessionId) ||
          request.isEmpty ||
          request.length > maximumQrTextBytes) {
        throw _decodeFailure(
          'pending default change 的 session 或 transport request 无效',
        );
      }
      return CitizenDefaultAccountChangePending(
        currentDefaultAccountId: current,
        payloadHash: hash,
        transport: CitizenExternalSignerTransport.qrV1,
        expiresAt: _u64Decimal(tuple[4], 'defaultChange.expiresAt'),
        sessionId: sessionId,
        transportRequest: request,
      );
    }
    throw _decodeFailure('未知 default account change outcome：$status');
  }

  CitizenTransactionHistoryPage decodeTransactionHistoryPage(Object? raw) {
    final tuple = _tuple(raw, 3, 'transactionHistoryPage');
    final page = CitizenTransactionHistoryPage(
      revision: _u64Decimal(tuple[0], 'transactionHistoryPage.revision'),
      records: _decodeList(
        tuple[1],
        'transactionHistoryPage.records',
        _decodeTransactionHistoryRecord,
      ),
      nextBeforeExecutionId: tuple[2] == null
          ? null
          : _hex16(tuple[2], 'transactionHistoryPage.nextBeforeExecutionId'),
    );
    final ids = page.records.map((record) => record.executionId).toSet();
    final hashes = page.records.map((record) => record.transactionHash).toSet();
    if (ids.length != page.records.length ||
        hashes.length != page.records.length) {
      throw _decodeFailure(
        'transaction history page 包含重复 executionId 或 transactionHash',
      );
    }
    if (page.nextBeforeExecutionId != null &&
        (page.records.isEmpty ||
            page.nextBeforeExecutionId != page.records.last.executionId)) {
      throw _decodeFailure('transaction history page 的 next cursor 不属于末条记录');
    }
    return page;
  }

  CitizenPreparedTransaction decodePreparedTransaction(Object? raw) {
    final tuple = _list(raw, 'preparedTransaction');
    _expectLength(tuple, 7, 'preparedTransaction');
    final preparationId = _string(
      tuple[0],
      'preparedTransaction.preparationId',
    );
    if (!RegExp(r'^0x[0-9a-f]{32}$').hasMatch(preparationId)) {
      throw _decodeFailure('preparedTransaction.preparationId 必须是 16 字节小写十六进制');
    }
    final source = _hex32(tuple[1], 'preparedTransaction.sourceAccountId');
    final callHash = _hex32(tuple[2], 'preparedTransaction.callDataHash');
    final runtimeSpec = _nonNegativeInt(
      tuple[4],
      'preparedTransaction.runtimeSpecNumber',
    );
    final transactionFormat = _nonNegativeInt(
      tuple[5],
      'preparedTransaction.transactionFormatNumber',
    );
    if (runtimeSpec > 0xffffffff || transactionFormat > 0xffffffff) {
      throw _decodeFailure('preparedTransaction runtime 数值必须是 uint32');
    }
    final bestBlock = decodeBlock(tuple[3]);
    if (bestBlock.finality != CitizenBlockFinality.best) {
      throw _decodeFailure('preparedTransaction.bestBlock 必须是 best 锚点');
    }
    return CitizenPreparedTransaction(
      preparationId: preparationId,
      sourceAccountId: citizenAccountIdBytes(source),
      callDataHash: citizenAccountIdBytes(callHash),
      bestBlock: bestBlock,
      runtimeSpecNumber: runtimeSpec,
      transactionFormatNumber: transactionFormat,
      nonce: _u64Decimal(tuple[6], 'preparedTransaction.nonce'),
    );
  }

  CitizenTransactionExecution decodeTransactionExecution(Object? raw) {
    final tuple = _tuple(raw, 10, 'transactionExecution');
    final status = _nonNegativeInt(tuple[0], 'transactionExecution.status');
    final executionId = _string(tuple[1], 'transactionExecution.executionId');
    if (!RegExp(r'^0x[0-9a-f]{32}$').hasMatch(executionId)) {
      throw _decodeFailure('transactionExecution.executionId 必须是 16 字节小写十六进制');
    }
    final source = citizenAccountIdBytes(
      _hex32(tuple[2], 'transactionExecution.sourceAccountId'),
    );
    final callHash = citizenAccountIdBytes(
      _hex32(tuple[3], 'transactionExecution.callDataHash'),
    );
    if (status == 1) {
      if (tuple[4] != null ||
          tuple[7] != null ||
          tuple[8] != null ||
          tuple[9] != null) {
        throw _decodeFailure('external pending 携带了 terminal 字段');
      }
      final expires = _u64Decimal(tuple[5], 'transactionExecution.expiresAt');
      final request = _string(tuple[6], 'transactionExecution.qrRequest');
      if (expires <= BigInt.zero ||
          utf8.encode(request).length < 1 ||
          utf8.encode(request).length > maximumQrTextBytes) {
        throw _decodeFailure('external pending QR_V1 字段无效');
      }
      return CitizenTransactionExternalSigningPending(
        executionId: executionId,
        sourceAccountId: source,
        callDataHash: callHash,
        qrRequest: request,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (expires * BigInt.from(1000)).toInt(),
          isUtc: true,
        ),
      );
    }
    if (status < 2 || status > 4 || tuple[5] != null || tuple[6] != null) {
      throw _decodeFailure('transaction terminal status/QR 字段无效');
    }
    final transactionHash = citizenAccountIdBytes(
      _hex32(tuple[4], 'transactionExecution.transactionHash'),
    );
    final execution = tuple[7] == null ? null : _decodeExecution(tuple[7]);
    final reason = tuple[8] == null
        ? null
        : _string(tuple[8], 'transactionExecution.reason');
    final replacement = tuple[9] == null
        ? null
        : citizenAccountIdBytes(
            _hex32(tuple[9], 'transactionExecution.replacementHash'),
          );
    final resolution = switch (status) {
      2 => CitizenTransactionResolution.finalizedSuccess,
      3 => CitizenTransactionResolution.finalizedFailed,
      4 => CitizenTransactionResolution.poolRejected,
      _ => throw _decodeFailure('transaction terminal status 无效'),
    };
    final valid = switch (resolution) {
      CitizenTransactionResolution.finalizedSuccess =>
        execution?.status == CitizenExecutionStatus.success &&
            reason == null &&
            replacement == null,
      CitizenTransactionResolution.finalizedFailed =>
        execution?.status == CitizenExecutionStatus.failed &&
            reason == null &&
            replacement == null,
      CitizenTransactionResolution.poolRejected =>
        execution == null && (reason?.trim().isNotEmpty ?? false),
    };
    if (!valid) throw _decodeFailure('transaction terminal 字段不一致');
    return CitizenTransactionExecutionCompleted(
      executionId: executionId,
      sourceAccountId: source,
      callDataHash: callHash,
      transactionHash: transactionHash,
      resolution: resolution,
      execution: execution,
      poolRejectionReason: reason,
      replacementHash: replacement,
    );
  }

  void _validateRequestFields(String method, List<Object?> fields) {
    switch (method) {
      case 'start':
      case 'stop':
      case 'close':
      case 'getCapabilities':
      case 'getFinalizedHead':
      case 'getSyncStatus':
      case 'getBestHead':
      case 'exportState':
      case 'getGenesisHash':
      case 'getFeeSnapshot':
      case 'getWalletProfile':
      case 'getWalletState':
      case 'importWallet':
      case 'deleteWallet':
      case 'reconcileWalletCleanup':
        _expectLength(fields, 0, '$method fields');
        return;
      case 'getFinalizedBlockAt':
        _expectLength(fields, 1, '$method fields');
        _u64Decimal(fields[0], '$method.number');
        return;
      case 'resolveFinalizedBlock':
        _expectLength(fields, 2, '$method fields');
        _hex32(fields[0], '$method.hash');
        _u64Decimal(fields[1], '$method.number');
        return;
      case 'getBlockHeader':
      case 'getBlockBody':
      case 'getRuntimeContext':
      case 'getSystemEvents':
        _expectLength(fields, 1, '$method fields');
        final block = decodeBlock(fields[0]);
        if (method == 'getSystemEvents' &&
            block.finality != CitizenBlockFinality.finalized) {
          throw _decodeFailure('getSystemEvents 只接受 finalized 块');
        }
        return;
      case 'getStorage':
        _expectLength(fields, 2, '$method fields');
        decodeBlock(fields[0]);
        final key = _bytes(fields[1], '$method.key');
        if (key.isEmpty || key.length > maximumStorageKeyBytes) {
          throw _decodeFailure('storage key 必须为 1..4 KiB');
        }
        return;
      case 'getStorageBatch':
        _expectLength(fields, 2, '$method fields');
        decodeBlock(fields[0]);
        final keys = _list(fields[1], '$method.keys');
        if (keys.isEmpty || keys.length > maximumStorageBatchKeys) {
          throw _decodeFailure('storage batch 必须包含 1..1024 个 key');
        }
        var total = 0;
        for (var index = 0; index < keys.length; index++) {
          final item = _bytes(keys[index], '$method.keys[$index]');
          if (item.isEmpty || item.length > maximumStorageKeyBytes) {
            throw _decodeFailure('storage batch key 必须为 1..4 KiB');
          }
          total += item.length;
          if (total > maximumStorageBatchKeyBytes) {
            throw _decodeFailure('storage batch key 总长度超过 1 MiB');
          }
        }
        return;
      case 'importState':
        _expectLength(fields, 3, '$method fields');
        _positiveInt(fields[0], '$method.formatVersion');
        final finalized = decodeBlock(fields[1]);
        final database = _bytes(fields[2], '$method.database');
        if (finalized.finality != CitizenBlockFinality.finalized ||
            database.isEmpty ||
            database.length > maximumExportedStateBytes) {
          throw _decodeFailure('importState 的 finalized/database 无效');
        }
        return;
      case 'deleteAccount':
        _expectLength(fields, 1, '$method fields');
        _hex32(fields[0], '$method.accountId');
        return;
      case 'getAccountBalance':
      case 'getAccountNonce':
      case 'viewAccountPrivateKey':
      case 'setActiveWalletAccount':
      case 'deleteWalletAccount':
        _expectLength(fields, 1, '$method fields');
        _hex32(fields[0], '$method.accountId');
        return;
      case 'getAccountBalances':
        _expectLength(fields, 1, 'getAccountBalances fields');
        final accountIds = _list(fields[0], 'getAccountBalances.accountIds');
        if (accountIds.length > maximumBalanceAccounts) {
          throw _decodeFailure('批量余额最多接受 1990 个账户');
        }
        for (final accountId in accountIds) {
          _hex32(accountId, 'getAccountBalances.accountId');
        }
        return;
      case 'createWallet':
        _expectLength(fields, 1, 'createWallet fields');
        final wordCount = _positiveInt(fields[0], 'wordCount');
        if (wordCount != 12 && wordCount != 18 && wordCount != 24) {
          throw _decodeFailure('wordCount 只能是 12、18 或 24');
        }
        return;
      case 'addWalletAccounts':
        _expectLength(fields, 1, 'addWalletAccounts fields');
        _validateIndices(fields[0]);
        return;
      case 'renameWalletAccount':
      case 'renameAccount':
        _expectLength(fields, 2, 'renameWalletAccount fields');
        _hex32(fields[0], 'renameWalletAccount.accountId');
        final name = _string(fields[1], 'renameWalletAccount.name');
        if (!_validAccountName(name)) {
          throw _decodeFailure('账户名称必须已修剪、含 1..30 个 Unicode scalar 且无控制字符');
        }
        return;
      case 'importColdAccountId':
        _expectLength(fields, 2, '$method fields');
        _hex32(fields[0], '$method.accountId');
        final idName = _string(fields[1], '$method.name');
        if (!_validAccountName(idName)) {
          throw _decodeFailure('账户名称必须已修剪、含 1..30 个 Unicode scalar 且无控制字符');
        }
        return;
      case 'importColdAccountSs58':
        _expectLength(fields, 2, '$method fields');
        final ss58 = _string(fields[0], '$method.ss58Address');
        final ss58Name = _string(fields[1], '$method.name');
        if (ss58.isEmpty || ss58.length > 64 || !_validAccountName(ss58Name)) {
          throw _decodeFailure('冷账户 SS58 或账户名称无效');
        }
        return;
      case 'reorderWalletAccountsWithoutDefaultChange':
        _expectLength(fields, 2, '$method fields');
        _u64Decimal(fields[0], '$method.expectedRevision');
        final ordered = _list(fields[1], '$method.accountIds');
        if (ordered.isEmpty || ordered.length > maximumWalletCatalogAccounts) {
          throw _decodeFailure('统一钱包重排必须包含 1..3980 个账户');
        }
        for (final accountId in ordered) {
          _hex32(accountId, '$method.accountId');
        }
        return;
      case 'signWalletPayload':
        _expectLength(fields, 2, 'signWalletPayload fields');
        _hex32(fields[0], 'signWalletPayload.accountId');
        final payload = _bytesView(fields[1], 'signWalletPayload.payload');
        if (payload.length > maximumSigningPayloadBytes) {
          throw _decodeFailure('签名 payload 不能超过 16 MiB');
        }
        return;
      case 'beginSigning':
        _expectLength(fields, 7, '$method fields');
        _hex32(fields[0], '$method.accountId');
        final signingPayload = _bytesView(fields[1], '$method.payload');
        if (signingPayload.isEmpty ||
            signingPayload.length > maximumSigningPayloadBytes) {
          throw _decodeFailure('通用签名 payload 必须包含 1..16 MiB 字节');
        }
        final transform = _string(fields[2], '$method.transform');
        final domain = _bytesView(fields[3], '$method.domain');
        if (transform == 'blake2Domain') {
          if (domain.isEmpty || domain.length > 32) {
            throw _decodeFailure('blake2Domain 必须包含 1..32 字节 domain');
          }
        } else if ((transform != 'raw' &&
                transform != 'substrateSigningPayload') ||
            domain.isNotEmpty) {
          throw _decodeFailure('签名 transform/domain 组合无效');
        }
        final transport = _string(fields[4], '$method.transport');
        if (transport != 'none' && transport != 'qrV1') {
          throw _decodeFailure('未知 external signer transport');
        }
        if (_nonNegativeInt(fields[5], '$method.opaqueAction') > 0xffff) {
          throw _decodeFailure('opaqueAction 必须是 uint16');
        }
        final signingTtl = _positiveInt(fields[6], '$method.ttlSeconds');
        if (signingTtl > 300) throw _decodeFailure('signing ttl 必须位于 1..300 秒');
        return;
      case 'consumeExternalSignature':
      case 'consumeDefaultAccountChange':
        _expectLength(fields, 2, '$method fields');
        final signingSession = _string(fields[0], '$method.sessionId');
        if (!_validSessionId(signingSession))
          throw _decodeFailure('signing sessionId 无效');
        _qrText(fields[1], '$method.response');
        return;
      case 'cancelSigning':
        _expectLength(fields, 1, '$method fields');
        if (!_validSessionId(_string(fields[0], '$method.sessionId'))) {
          throw _decodeFailure('signing sessionId 无效');
        }
        return;
      case 'beginDefaultAccountChange':
        _expectLength(fields, 3, '$method fields');
        _u64Decimal(fields[0], '$method.expectedRevision');
        final defaultOrder = _list(fields[1], '$method.accountIds');
        if (defaultOrder.isEmpty ||
            defaultOrder.length > maximumDefaultAccountChangeAccounts) {
          throw _decodeFailure('默认账户目标顺序必须包含 1..256 个账户');
        }
        for (final accountId in defaultOrder) {
          _hex32(accountId, '$method.accountId');
        }
        final defaultTtl = _positiveInt(fields[2], '$method.ttlSeconds');
        if (defaultTtl > 300) throw _decodeFailure('默认账户 ttl 必须位于 1..300 秒');
        return;
      case 'verifySignature':
        _expectLength(fields, 3, 'verifySignature fields');
        _hex32(fields[0], 'verifySignature.accountId');
        if (_bytesView(fields[1], 'verifySignature.signature').length != 64 ||
            _bytesView(fields[2], 'verifySignature.payload').length >
                maximumSigningPayloadBytes) {
          throw _decodeFailure('验签要求 64 字节签名及不超过 16 MiB 的消息');
        }
        return;
      case 'prepareTransaction':
        _expectLength(fields, 2, '$method fields');
        _hex32(fields[0], '$method.sourceAccountId');
        final callData = _bytesView(fields[1], '$method.callData');
        if (callData.isEmpty ||
            callData.length > maximumTransactionCallDataBytes) {
          throw _decodeFailure('prepareTransaction.callData 必须包含 1..1 MiB 字节');
        }
        return;
      case 'cancelPreparedTransaction':
        _expectLength(fields, 1, '$method fields');
        final preparationId = _string(fields[0], '$method.preparationId');
        if (!RegExp(r'^0x[0-9a-f]{32}$').hasMatch(preparationId)) {
          throw _decodeFailure('cancelPreparedTransaction.preparationId 无效');
        }
        return;
      case 'executePreparedTransaction':
      case 'cancelPreparedTransactionExecution':
        _expectLength(fields, 1, '$method fields');
        final id = _string(fields[0], '$method.id');
        if (!RegExp(r'^0x[0-9a-f]{32}$').hasMatch(id)) {
          throw _decodeFailure('$method id 无效');
        }
        return;
      case 'consumePreparedTransactionQrResponse':
        _expectLength(fields, 2, '$method fields');
        final id = _string(fields[0], '$method.executionId');
        final response = _string(fields[1], '$method.response');
        final responseBytes = utf8.encode(response).length;
        if (!RegExp(r'^0x[0-9a-f]{32}$').hasMatch(id) ||
            responseBytes < 1 ||
            responseBytes > maximumQrTextBytes) {
          throw _decodeFailure('$method 参数无效');
        }
        return;
      case 'getTransactionHistory':
        _expectLength(fields, 2, '$method fields');
        if (fields[0] != null) {
          _hex16(fields[0], '$method.beforeExecutionId');
        }
        final limit = _u32Int(fields[1], '$method.limit');
        if (limit < 1 || limit > 100) {
          throw _decodeFailure('$method.limit 必须在 1..100 范围内');
        }
        return;
      case 'syncTransactionHistory':
        _expectLength(fields, 0, '$method fields');
        return;
      case 'qrScan':
        _expectLength(fields, 0, '$method fields');
        return;
      case 'qrParse':
      case 'signQrRequest':
      case 'qrConsumeSignResponse':
        _expectLength(fields, 1, '$method fields');
        _qrText(fields[0], '$method.text');
        return;
      case 'qrCreateSignRequest':
        _expectLength(fields, 4, '$method fields');
        final action = _positiveInt(fields[0], '$method.action');
        if (action > 0xffff) throw _decodeFailure('二维码 action 必须是 uint16');
        _hex32(fields[1], '$method.signerAccountId');
        final review = _bytesView(fields[2], '$method.reviewPayload');
        if (review.isEmpty || review.length > maximumQrReviewPayloadBytes) {
          throw _decodeFailure('二维码 reviewPayload 必须包含 1..1920 字节');
        }
        final ttl = _positiveInt(fields[3], '$method.ttlSeconds');
        if (ttl > 300) throw _decodeFailure('二维码 ttlSeconds 必须位于 1..300');
        return;
      case 'qrCancelSignRequest':
        _expectLength(fields, 1, '$method fields');
        final requestId = _string(fields[0], '$method.requestId');
        if (requestId.length < 16 || requestId.length > 128) {
          throw _decodeFailure('二维码 requestId 长度无效');
        }
        return;
      case 'qrEncodeAccountId':
        _expectLength(fields, 1, '$method fields');
        _hex32(fields[0], '$method.accountId');
        return;
      case 'qrDecodeLuminance':
        _expectLength(fields, 4, '$method fields');
        final pixels = _bytesView(fields[0], '$method.data');
        final width = _positiveInt(fields[1], '$method.width');
        final height = _positiveInt(fields[2], '$method.height');
        final stride = _positiveInt(fields[3], '$method.rowStride');
        if (width > 4096 ||
            height > 4096 ||
            stride < width ||
            pixels.length > maximumQrImageBytes ||
            pixels.length < (height - 1) * stride + width) {
          throw _decodeFailure('二维码亮度帧尺寸或步长无效');
        }
        return;
      case 'qrEncode':
        _expectLength(fields, 2, '$method fields');
        _qrText(fields[0], '$method.text');
        final scale = _positiveInt(fields[1], '$method.scale');
        if (scale > 16) throw _decodeFailure('二维码 scale 必须位于 1..16');
        return;
      default:
        throw _decodeFailure('未知请求 method：$method');
    }
  }

  void _validateResponseValue(String method, List<Object?> value) {
    switch (method) {
      case 'viewAccountPrivateKey':
        // 安全查看只有空完成状态，拒绝任何秘密或内部句柄响应槽。
        _expectLength(value, 0, '$method value');
        return;
      case 'open':
        _expectLength(value, 2, 'open value');
        if (decodeLifecycle(value[0]) != CitizenSdkLifecycle.created ||
            _positiveInt(value[1], 'nextEventSequence') != 1) {
          throw _decodeFailure('open 必须从 created/eventSequence 1 开始');
        }
        return;
      case 'start':
      case 'stop':
      case 'close':
        _expectLength(value, 1, '$method value');
        decodeLifecycle(value[0]);
        return;
      case 'getCapabilities':
        _expectLength(value, 1, '$method value');
        decodeCapabilities(value[0]);
        return;
      case 'getFinalizedHead':
        _expectLength(value, 1, '$method value');
        if (decodeBlock(value[0]).finality != CitizenBlockFinality.finalized) {
          throw _decodeFailure('getFinalizedHead 必须返回 finalized 块');
        }
        return;
      case 'getSyncStatus':
        _expectLength(value, 1, '$method value');
        decodeSyncStatus(value[0]);
        return;
      case 'getBestHead':
        _expectLength(value, 1, '$method value');
        if (decodeBlock(value[0]).finality != CitizenBlockFinality.best) {
          throw _decodeFailure('getBestHead 必须返回 best 块');
        }
        return;
      case 'getFinalizedBlockAt':
      case 'resolveFinalizedBlock':
        _expectLength(value, 1, '$method value');
        if (decodeBlock(value[0]).finality != CitizenBlockFinality.finalized) {
          throw _decodeFailure('$method 必须返回 finalized 块');
        }
        return;
      case 'getBlockHeader':
        _expectLength(value, 1, '$method value');
        decodeBlockHeader(value[0]);
        return;
      case 'getBlockBody':
        _expectLength(value, 1, '$method value');
        decodeBlockBody(value[0]);
        return;
      case 'getRuntimeContext':
        _expectLength(value, 1, '$method value');
        decodeRuntimeContext(value[0]);
        return;
      case 'getStorage':
      case 'getSystemEvents':
        _expectLength(value, 1, '$method value');
        decodeStorage(value[0]);
        return;
      case 'getStorageBatch':
        _expectLength(value, 1, '$method value');
        decodeStorageBatch(value[0]);
        return;
      case 'exportState':
        _expectLength(value, 1, '$method value');
        decodeChainState(value[0]);
        return;
      case 'importState':
        _expectLength(value, 0, '$method value');
        return;
      case 'getGenesisHash':
        _expectLength(value, 1, '$method value');
        _hex32(value[0], 'genesisHash');
        return;
      case 'getAccountBalances':
        _expectLength(value, 1, '$method value');
        decodeBalances(value[0]);
        return;
      case 'getAccountBalance':
        _expectLength(value, 1, '$method value');
        decodeBalance(value[0]);
        return;
      case 'getAccountNonce':
        _expectLength(value, 1, '$method value');
        decodeNonce(value[0]);
        return;
      case 'getFeeSnapshot':
        _expectLength(value, 1, '$method value');
        decodeFeeSnapshot(value[0]);
        return;
      case 'getWalletProfile':
      case 'createWallet':
      case 'importWallet':
      case 'addWalletAccounts':
      case 'setActiveWalletAccount':
      case 'renameWalletAccount':
      case 'deleteWalletAccount':
      case 'deleteWallet':
      case 'reconcileWalletCleanup':
        _expectLength(value, 1, '$method value');
        decodeWalletProfile(value[0]);
        return;
      case 'getWalletState':
      case 'importColdAccountId':
      case 'importColdAccountSs58':
      case 'reorderWalletAccountsWithoutDefaultChange':
      case 'renameAccount':
      case 'deleteAccount':
        _expectLength(value, 1, '$method value');
        decodeWalletState(value[0]);
        return;
      case 'signWalletPayload':
        _expectLength(value, 1, '$method value');
        final signature = _bytes(value[0], 'signature');
        if (signature.length != 64) {
          throw _decodeFailure('sr25519 signature 必须是 64 字节');
        }
        return;
      case 'beginSigning':
      case 'consumeExternalSignature':
        _expectLength(value, 1, '$method value');
        decodeSigningOutcome(value[0]);
        return;
      case 'beginDefaultAccountChange':
      case 'consumeDefaultAccountChange':
        _expectLength(value, 1, '$method value');
        decodeDefaultAccountChangeOutcome(value[0]);
        return;
      case 'cancelSigning':
        _expectLength(value, 1, '$method value');
        _boolean(value[0], '$method.cancelled');
        return;
      case 'prepareTransaction':
        _expectLength(value, 1, '$method value');
        decodePreparedTransaction(value[0]);
        return;
      case 'executePreparedTransaction':
      case 'consumePreparedTransactionQrResponse':
        _expectLength(value, 1, '$method value');
        decodeTransactionExecution(value[0]);
        return;
      case 'cancelPreparedTransaction':
      case 'cancelPreparedTransactionExecution':
        _expectLength(value, 1, '$method value');
        if (value[0] != null) {
          throw _decodeFailure('$method value 必须是 null');
        }
        return;
      case 'getTransactionHistory':
      case 'syncTransactionHistory':
        _expectLength(value, 1, '$method value');
        decodeTransactionHistoryPage(value[0]);
        return;
      case 'qrParse':
      case 'qrScan':
      case 'qrDecodeLuminance':
      case 'signQrRequest':
        _expectLength(value, 1, '$method value');
        decodeQrDocument(value[0], signed: method == 'signQrRequest');
        return;
      case 'qrCreateSignRequest':
      case 'qrEncodeAccountId':
        _expectLength(value, 1, '$method value');
        _qrText(value[0], '$method.text');
        return;
      case 'qrConsumeSignResponse':
        _expectLength(value, 1, '$method value');
        if (_bytesView(value[0], '$method.signature').length != 64) {
          throw _decodeFailure('二维码消费结果必须是64字节绑定签名');
        }
        return;
      case 'qrCancelSignRequest':
        _expectLength(value, 1, '$method value');
        _boolean(value[0], '$method.cancelled');
        return;
      case 'qrEncode':
        _expectLength(value, 3, '$method value');
        final width = _positiveInt(value[0], '$method.width');
        final height = _positiveInt(value[1], '$method.height');
        final pixels = _bytesView(value[2], '$method.luminance');
        if (width > 4096 ||
            height > 4096 ||
            pixels.length != width * height ||
            pixels.length > maximumQrImageBytes) {
          throw _decodeFailure('二维码输出图像尺寸不一致');
        }
        return;
      default:
        throw _decodeFailure('未知响应 method：$method');
    }
  }

  /// 仅重建 Core 展开的公开结果；不解析 QR_V1、判断时效或重拼签名字节。
  CitizenQrDocument decodeQrDocument(Object? raw, {bool signed = false}) {
    final text = _string(raw, 'qr.document');
    if (utf8.encode(text).length > 65536) throw _decodeFailure('二维码结果超过64KiB');
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw _decodeFailure('二维码结果JSON无效');
    }
    if (decoded is! Map<String, dynamic>) throw _decodeFailure('二维码结果不是公开文档');
    final kind = _positiveInt(decoded['kind'], 'qr.kind');
    final keys = <String>{'kind', 'canonical_text'};
    if (kind == 1) {
      keys.addAll(<String>{
        'request_id',
        'expires_at',
        'action',
        'signer_account_id',
        'review_payload',
      });
    } else if (kind == 2) {
      keys.addAll(<String>{
        'request_id',
        'expires_at',
        'signer_account_id',
        'signature',
      });
    } else if (kind == 5) {
      keys.add('account_id');
    } else {
      throw _decodeFailure('二维码kind不在闭集');
    }
    if (signed) {
      if (kind != 2) throw _decodeFailure('签名结果必须是响应文档');
      keys.add('sign_request');
    }
    if (decoded.length != keys.length || !decoded.keys.every(keys.contains)) {
      throw _decodeFailure('二维码文档字段不符合Core闭集');
    }
    Uint8List bytes(Object? input, String field, int minimum, int maximum) {
      final hex = _string(input, field);
      if (!RegExp(r'^0x(?:[0-9a-f]{2})*$').hasMatch(hex)) {
        throw _decodeFailure('$field不是规范字节');
      }
      final count = (hex.length - 2) ~/ 2;
      if (count < minimum || count > maximum) {
        throw _decodeFailure('$field长度无效');
      }
      return Uint8List.fromList(<int>[
        for (var offset = 2; offset < hex.length; offset += 2)
          int.parse(hex.substring(offset, offset + 2), radix: 16),
      ]);
    }

    final requestId = kind == 5
        ? null
        : _string(decoded['request_id'], 'qr.requestId');
    if (requestId != null &&
        (requestId.length < 16 || requestId.length > 128)) {
      throw _decodeFailure('二维码requestId长度无效');
    }
    return CitizenQrDocument(
      kind: CitizenQrKind.values.singleWhere((value) => value.value == kind),
      canonicalText: _qrText(decoded['canonical_text'], 'qr.canonicalText'),
      requestId: requestId,
      expiresAt: kind == 5
          ? null
          : _positiveInt(decoded['expires_at'], 'qr.expiresAt'),
      action: kind == 1 ? _positiveInt(decoded['action'], 'qr.action') : null,
      signerAccountId: kind == 1 || kind == 2
          ? _hex32(decoded['signer_account_id'], 'qr.signerAccountId')
          : null,
      reviewPayload: kind == 1
          ? bytes(
              decoded['review_payload'],
              'qr.reviewPayload',
              1,
              maximumQrReviewPayloadBytes,
            )
          : null,
      signature: kind == 2
          ? bytes(decoded['signature'], 'qr.signature', 64, 64)
          : null,
      accountId: kind == 5
          ? _hex32(decoded['account_id'], 'qr.accountId')
          : null,
      signRequest: signed
          ? _qrText(decoded['sign_request'], 'qr.signRequest')
          : null,
    );
  }

  String _qrText(Object? raw, String name) {
    final value = _string(raw, name);
    final length = utf8.encode(value).length;
    if (length == 0 || length > maximumQrTextBytes) {
      throw _decodeFailure('$name 必须包含 1..2331 UTF-8 字节');
    }
    return value;
  }

  CitizenSdkHistoryChanged _decodeHistoryEvent(
    int sequence,
    List<Object?> payload,
  ) {
    _expectLength(payload, 0, 'historyChanged');
    return CitizenSdkHistoryChanged(sequence: sequence);
  }

  CitizenSdkLifecycleChanged _decodeLifecycleEvent(
    int sequence,
    List<Object?> payload,
  ) {
    _expectLength(payload, 1, 'lifecycle event');
    return CitizenSdkLifecycleChanged(
      sequence: sequence,
      lifecycle: decodeLifecycle(payload[0]),
    );
  }

  CitizenSdkCapabilitiesChanged _decodeCapabilitiesEvent(
    int sequence,
    List<Object?> payload,
  ) {
    _expectLength(payload, 1, 'capabilities event');
    return CitizenSdkCapabilitiesChanged(
      sequence: sequence,
      snapshot: decodeCapabilities(payload[0]),
    );
  }

  CitizenExecution _decodeExecution(Object? raw) {
    final tuple = _tuple(raw, 6, 'execution');
    final statusText = _string(tuple[0], 'execution.status');
    final execution = CitizenExecution(
      status: CitizenExecutionStatus.values.firstWhere(
        (candidate) => candidate.name == statusText,
        orElse: () => throw _decodeFailure('未知 execution status：$statusText'),
      ),
      block: decodeBlock(tuple[1]),
      extrinsicIndex: _u32Int(tuple[2], 'execution.extrinsicIndex'),
      dispatchVariant: _nullableU8Int(tuple[3], 'execution.dispatchVariant'),
      palletIndex: _nullableU8Int(tuple[4], 'execution.palletIndex'),
      errorIndex: _nullableU8Int(tuple[5], 'execution.errorIndex'),
    );
    final moduleFieldsPresent =
        execution.palletIndex != null && execution.errorIndex != null;
    final valid =
        execution.block.finality == CitizenBlockFinality.finalized &&
        (switch (execution.status) {
          CitizenExecutionStatus.success =>
            execution.dispatchVariant == null &&
                execution.palletIndex == null &&
                execution.errorIndex == null,
          CitizenExecutionStatus.failed =>
            execution.dispatchVariant != null &&
                ((execution.dispatchVariant == 3 && moduleFieldsPresent) ||
                    (execution.dispatchVariant != 3 &&
                        execution.palletIndex == null &&
                        execution.errorIndex == null)),
        });
    if (!valid) throw _decodeFailure('execution 的 finalized/dispatch 字段不一致');
    return execution;
  }

  CitizenTransactionHistoryRecord _decodeTransactionHistoryRecord(Object? raw) {
    final tuple = _tuple(raw, 11, 'transaction history record');
    final statusText = _string(tuple[4], 'transactionHistoryRecord.status');
    final record = CitizenTransactionHistoryRecord(
      executionId: _hex16(tuple[0], 'transactionHistoryRecord.executionId'),
      sourceAccountId: _hex32(
        tuple[1],
        'transactionHistoryRecord.sourceAccountId',
      ),
      callDataHash: _hex32(tuple[2], 'transactionHistoryRecord.callDataHash'),
      transactionHash: _hex32(
        tuple[3],
        'transactionHistoryRecord.transactionHash',
      ),
      status: CitizenTransactionHistoryStatus.values.firstWhere(
        (candidate) => candidate.name == statusText,
        orElse: () =>
            throw _decodeFailure('未知 transaction history status：$statusText'),
      ),
      block: tuple[5] == null ? null : decodeBlock(tuple[5]),
      execution: tuple[6] == null ? null : _decodeExecution(tuple[6]),
      replacementHash: tuple[7] == null
          ? null
          : _hex32(tuple[7], 'transactionHistoryRecord.replacementHash'),
      createdAtMillis: _u64Decimal(
        tuple[8],
        'transactionHistoryRecord.createdAtMillis',
      ),
      updatedAtMillis: _u64Decimal(
        tuple[9],
        'transactionHistoryRecord.updatedAtMillis',
      ),
      poolRejectionReason: _nullableString(
        tuple[10],
        'transactionHistoryRecord.poolRejectionReason',
      ),
    );
    final reasonPresent =
        record.poolRejectionReason?.trim().isNotEmpty ?? false;
    final finalizedExecutionMatches =
        record.block != null &&
        record.execution != null &&
        _sameBlock(record.block!, record.execution!.block);
    final valid = switch (record.status) {
      CitizenTransactionHistoryStatus.pending =>
        record.block == null &&
            record.execution == null &&
            record.replacementHash == null &&
            record.poolRejectionReason == null,
      CitizenTransactionHistoryStatus.inBlock =>
        record.block != null &&
            record.execution == null &&
            record.replacementHash == null &&
            record.poolRejectionReason == null,
      CitizenTransactionHistoryStatus.poolRejected =>
        record.block == null && record.execution == null && reasonPresent,
      CitizenTransactionHistoryStatus.finalizedSuccess =>
        record.block?.finality == CitizenBlockFinality.finalized &&
            record.execution?.status == CitizenExecutionStatus.success &&
            finalizedExecutionMatches &&
            record.replacementHash == null &&
            record.poolRejectionReason == null,
      CitizenTransactionHistoryStatus.finalizedFailed =>
        record.block?.finality == CitizenBlockFinality.finalized &&
            record.execution?.status == CitizenExecutionStatus.failed &&
            finalizedExecutionMatches &&
            record.replacementHash == null &&
            record.poolRejectionReason == null,
    };
    if (!valid || record.updatedAtMillis < record.createdAtMillis) {
      throw _decodeFailure('transaction history record 的状态或时间字段不一致');
    }
    return record;
  }

  List<T> _decodeList<T>(Object? raw, String name, T Function(Object?) decode) {
    final values = _list(raw, name);
    return List<T>.unmodifiable(values.map<T>(decode));
  }

  void _validateIndices(Object? raw) {
    final values = _list(raw, 'indices');
    if (values.isEmpty || values.length > maximumAdditionalWalletAccounts) {
      throw _decodeFailure('indices 必须包含 1..1989 项');
    }
    final indices = values
        .map<int>((value) => _accountIndex(value, 'account index'))
        .toList(growable: false);
    if (indices.any((index) => index == 0)) {
      throw _decodeFailure('追加账户 index 必须在 1..1989；0 是 master 锚点');
    }
    if (indices.toSet().length != indices.length) {
      throw _decodeFailure('indices 不能重复');
    }
  }

  void _expectProtocol(Object? raw) {
    // Dart numeric equality considers `1.0 == 1`. StandardMessageCodec keeps
    // integer and floating-point wire types distinct, so accepting a double
    // here would make Dart looser than the Kotlin and Swift projections.
    if (raw is! int || raw != protocolVersion) {
      throw _decodeFailure('不支持的 Flutter channel protocolVersion');
    }
  }

  bool _validSessionId(String value) =>
      value.isNotEmpty && value.length <= maximumSessionIdCodeUnits;

  String _sessionId(Object? raw, String name) {
    final value = _string(raw, name);
    if (!_validSessionId(value)) {
      throw _decodeFailure('$name 必须包含 1..128 个 UTF-16 code unit');
    }
    return value;
  }

  String? _nullableSessionId(Object? raw, String name) =>
      raw == null ? null : _sessionId(raw, name);

  List<Object?> _tuple(Object? raw, int length, String name) {
    final tuple = _list(raw, name);
    _expectLength(tuple, length, name);
    _rejectMaps(tuple, name);
    return tuple;
  }

  List<Object?> _list(Object? raw, String name) {
    if (raw is! List<Object?>) throw _decodeFailure('$name 必须是 List tuple');
    return raw;
  }

  void _expectLength(List<Object?> tuple, int length, String name) {
    if (tuple.length != length) {
      throw _decodeFailure('$name 长度必须精确为 $length');
    }
  }

  void _rejectMaps(Object? value, String path) {
    if (value is Map<Object?, Object?>) {
      throw _decodeFailure('$path 禁止 Map 编码');
    }
    if (value is List<Object?>) {
      for (var index = 0; index < value.length; index++) {
        _rejectMaps(value[index], '$path[$index]');
      }
    }
  }

  String _string(Object? raw, String name) {
    if (raw is! String) throw _decodeFailure('$name 必须是 String');
    return raw;
  }

  String? _nullableString(Object? raw, String name) =>
      raw == null ? null : _string(raw, name);

  bool _boolean(Object? raw, String name) {
    if (raw is! bool) throw _decodeFailure('$name 必须是 bool');
    return raw;
  }

  int _nonNegativeInt(Object? raw, String name) {
    if (raw is! int || raw < 0) throw _decodeFailure('$name 必须是非负 int');
    return raw;
  }

  int _positiveInt(Object? raw, String name) {
    final value = _nonNegativeInt(raw, name);
    if (value == 0) throw _decodeFailure('$name 必须大于 0');
    return value;
  }

  int? _nullablePositiveInt(Object? raw, String name) =>
      raw == null ? null : _positiveInt(raw, name);

  int _u32Int(Object? raw, String name) {
    final value = _nonNegativeInt(raw, name);
    if (value > 0xffffffff) throw _decodeFailure('$name 超出 u32');
    return value;
  }

  int _accountIndex(Object? raw, String name) {
    final value = _u32Int(raw, name);
    if (value > 1989) throw _decodeFailure('$name 超出 CitizenSDK 账户范围');
    return value;
  }

  bool _validAccountName(String name) {
    if (name.length > 128 ||
        name != name.trim() ||
        name.runes.isEmpty ||
        name.runes.length > 30) {
      return false;
    }
    return !name.runes.any(
      (scalar) => scalar <= 0x1f || (scalar >= 0x7f && scalar <= 0x9f),
    );
  }

  bool _sameBlock(CitizenBlockRef left, CitizenBlockRef right) =>
      left.hash == right.hash &&
      left.number == right.number &&
      left.finality == right.finality;

  int? _nullableU32Int(Object? raw, String name) =>
      raw == null ? null : _u32Int(raw, name);

  int? _nullableU8Int(Object? raw, String name) {
    if (raw == null) return null;
    final value = _u32Int(raw, name);
    if (value > 0xff) throw _decodeFailure('$name 超出 u8');
    return value;
  }

  BigInt _decimal(Object? raw, String name, int maximumDigits) {
    final value = _string(raw, name);
    if (value.length > maximumDigits) {
      throw _decodeFailure('$name 十进制位数超出上限');
    }
    if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw _decodeFailure('$name 必须是规范非负十进制字符串');
    }
    return BigInt.parse(value);
  }

  BigInt _u64Decimal(Object? raw, String name) {
    final value = _decimal(raw, name, 20);
    if (value > (BigInt.one << 64) - BigInt.one) {
      throw _decodeFailure('$name 超出 u64');
    }
    return value;
  }

  BigInt _u128Decimal(Object? raw, String name) {
    final value = _decimal(raw, name, 39);
    if (value > (BigInt.one << 128) - BigInt.one) {
      throw _decodeFailure('$name 超出 u128');
    }
    return value;
  }

  String _hex32(Object? raw, String name) {
    final value = _string(raw, name);
    if (value.length != 66 || !RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
      throw _decodeFailure('$name 必须是 0x 加 64 位小写十六进制');
    }
    return value;
  }

  String _hex16(Object? raw, String name) {
    final value = _string(raw, name);
    if (value.length != 34 || !RegExp(r'^0x[0-9a-f]{32}$').hasMatch(value)) {
      throw _decodeFailure('$name 必须是 0x 加 32 位小写十六进制');
    }
    return value;
  }

  Uint8List _bytes(Object? raw, String name) {
    return Uint8List.fromList(_bytesView(raw, name));
  }

  Uint8List _bytesView(Object? raw, String name) {
    if (raw is! Uint8List) throw _decodeFailure('$name 必须是 Uint8List');
    return raw;
  }

  CitizenSdkException _decodeFailure(String message) => CitizenSdkException(
    code: CitizenSdkErrorCode.decode,
    stage: CitizenSdkFailureStage.verification,
    message: message,
  );
}

final class DecodedCitizenSdkResponse {
  const DecodedCitizenSdkResponse({
    required this.sessionId,
    required this.requestSequence,
    required this.value,
  });

  final String sessionId;
  final int requestSequence;
  final List<Object?> value;
}

final class DecodedCitizenSdkEvent {
  const DecodedCitizenSdkEvent({
    required this.sessionId,
    required this.eventSequence,
    required this.event,
  });

  final String sessionId;
  final int eventSequence;
  final CitizenSdkEvent event;
}
