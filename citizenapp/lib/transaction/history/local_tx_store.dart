import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';

/// 本机钱包交易流水存储服务。
///
/// 这里保存的是“钱包进入本机 App 之后”的余额变化流水。
/// 链上账户唯一性用 accountId，单条流水唯一性用 recordKey。
class LocalTxStore {
  static const String statusPending = 'pending';
  static const String statusInBlock = 'inBlock';
  static const String statusFinalized = 'finalized';
  static const String statusFailed = 'failed';

  static String requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  static String normalizeBlockHash(String blockHash) {
    return blockHash.startsWith('0x')
        ? blockHash.toLowerCase()
        : '0x${blockHash.toLowerCase()}';
  }

  /// 本机提交交易的唯一身份键：`accountId:tx:txHash`。
  ///
  /// 键与状态无关：一笔交易全程只有这一条记录，状态在其上就地流转
  /// pending → inBlock → finalized，绝不 re-key、绝不另建第二条。
  static String submitRecordKey(String accountId, String txHash) {
    return '${requireAccountId(accountId)}:tx:${txHash.toLowerCase()}';
  }

  static String blockEventRecordKey(
    String accountId,
    String blockHash,
    int eventIndex,
  ) {
    return '${requireAccountId(accountId)}:${normalizeBlockHash(blockHash)}:$eventIndex';
  }

  static String fenFromYuan(double amountYuan) {
    return BigInt.from((amountYuan * 100).round()).toString();
  }

  static double fenToYuan(String amountFen) {
    return BigInt.parse(amountFen).toDouble() / 100.0;
  }

  static String negateFen(String amountFen) {
    final value = BigInt.parse(amountFen);
    return (-value).toString();
  }

  /// 写入或替换一条交易流水。
  static Future<void> upsert(LocalTxEntity entity) async {
    entity.accountId = requireAccountId(entity.accountId);
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 查询某个钱包的交易流水（按本机记录时间倒序）。
  static Future<List<LocalTxEntity>> queryByAccountId(
    String accountId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final normalizedAccountId = requireAccountId(accountId);
    return WalletIsar.instance.read((isar) async {
      final rows = await isar.localTxEntitys
          .where()
          .accountIdEqualTo(normalizedAccountId)
          .sortByCreatedAtMillisDesc()
          .findAll();
      return rows
          .where(_belongsToCurrentSdkIntegration)
          .skip(offset)
          .take(limit)
          .toList(growable: false);
    });
  }

  /// 查询某个钱包最近 N 条记录。
  static Future<List<LocalTxEntity>> queryRecentByAccountId(
    String accountId, {
    int limit = 5,
  }) async {
    return queryByAccountId(accountId, limit: limit);
  }

  /// 按 recordKey 查询单条记录（防重复用）。
  static Future<LocalTxEntity?> queryByRecordKey(String recordKey) async {
    return WalletIsar.instance.read((isar) async {
      final row = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      return row != null && _belongsToCurrentSdkIntegration(row) ? row : null;
    });
  }

  /// 写入本机发起的普通转账记录。
  ///
  /// SDK execution/history 和 finalized 业务事件可能先于页面本地写入返回。这里先查是否
  /// 已有同钱包、同发送方、同接收方、同本金的区块事件记录；若有，直接
  /// 合并手续费、txHash 和 nonce，避免“本金事件 + 本机扣费记录”显示两条。
  static Future<void> upsertLocalSubmitTransfer({
    required String ss58Address,
    required String accountId,
    required String txHash,
    required String amountDeltaFen,
    required String transferAmountFen,
    required String feeFen,
    required String counterpartySs58Address,
    required String fromSs58Address,
    required String toSs58Address,
    required String executionId,
    required String callDataHash,
    required int usedNonce,
    required int createdAtMillis,
    String? remark,
    String? blockHash,
  }) async {
    final normalizedAccountId = requireAccountId(accountId);
    final normalizedTxHash = txHash.toLowerCase();
    final pendingKey = submitRecordKey(normalizedAccountId, normalizedTxHash);
    final normalizedBlockHash = blockHash == null || blockHash.isEmpty
        ? null
        : normalizeBlockHash(blockHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final existingPending = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(pendingKey)
          .findFirst();
      if (existingPending != null) {
        existingPending
          ..ss58Address = ss58Address
          ..accountId = normalizedAccountId
          ..type = 'transfer'
          ..amountDeltaFen = amountDeltaFen
          ..transferAmountFen = transferAmountFen
          ..feeFen = feeFen
          ..counterpartySs58Address = counterpartySs58Address
          ..fromSs58Address = fromSs58Address
          ..toSs58Address = toSs58Address
          ..remark = _mergeRemark(remark, existingPending.remark)
          ..status = _mergeStatus(existingPending.status, statusPending)
          ..source = 'local_submit'
          ..txHash = normalizedTxHash
          ..executionId = executionId
          ..callDataHash = callDataHash
          ..usedNonce = usedNonce
          ..createdAtMillis = existingPending.createdAtMillis
          ..failureReason = null;
        await isar.localTxEntitys.put(existingPending);
        return;
      }

      final existingEvent = normalizedBlockHash == null
          ? null
          : await _findSemanticBlockTransferInTxn(
              isar,
              accountId: normalizedAccountId,
              blockNumber: null,
              blockHash: normalizedBlockHash,
              fromSs58Address: fromSs58Address,
              toSs58Address: toSs58Address,
              transferAmountFen: transferAmountFen,
              extrinsicIndex: null,
              eventIndex: null,
            );
      final entity = existingEvent ?? LocalTxEntity();
      entity
        // 一旦补入 SDK execution 事实，就改用且永久保持 submit key；
        // 后续 SDK history 才能按同一 txHash 原地推进这一条记录。
        ..recordKey = pendingKey
        ..ss58Address = ss58Address
        ..accountId = normalizedAccountId
        ..type = 'transfer'
        ..amountDeltaFen = amountDeltaFen
        ..transferAmountFen = transferAmountFen
        ..feeFen = feeFen
        ..counterpartySs58Address = counterpartySs58Address
        ..fromSs58Address = fromSs58Address
        ..toSs58Address = toSs58Address
        ..remark = _mergeRemark(remark, existingEvent?.remark)
        // 这是 SDK execution 记录；业务事件不能替 SDK 宣布交易终态。
        ..status = statusPending
        ..source = 'local_submit'
        ..txHash = normalizedTxHash
        ..executionId = executionId
        ..callDataHash = callDataHash
        ..usedNonce = usedNonce
        ..createdAtMillis = existingEvent?.createdAtMillis ?? createdAtMillis
        ..confirmedAtMillis = null
        ..failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 写入链上区块转账事件；如能匹配本机发起记录，则更新原记录。
  ///
  /// (ADR-017 全端 finalized 单一口径)：本方法由只扫 finalized 链的
  /// SDK finalized block 业务投影调用，写入状态恒为 finalized。收入
  /// (别人转入)没有本机 pending，只在对应区块 finalized 后用同一个区块事件
  /// 唯一键写入，避免“余额到账但无收入记录”。本机提交记录的 execution
  /// 状态只由 CitizenSDK history 推进，本业务事件路径不得覆盖。
  static Future<void> upsertBlockTransferEvent({
    required String ss58Address,
    required String accountId,
    required String recordKey,
    required String status,
    required String amountDeltaFen,
    required String transferAmountFen,
    required String fromSs58Address,
    required String toSs58Address,
    required String counterpartySs58Address,
    required int blockNumber,
    required String blockHash,
    required int eventIndex,
    int? extrinsicIndex,
    int? confirmedAtMillis,
    String? remark,
  }) async {
    final normalizedAccountId = requireAccountId(accountId);
    final normalizedBlockHash = normalizeBlockHash(blockHash);
    final now = DateTime.now().millisecondsSinceEpoch;
    await WalletIsar.instance.writeTxn((isar) async {
      final existing = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (existing != null) {
        existing
          ..status = _mergeStatus(existing.status, status)
          ..ss58Address = ss58Address
          ..accountId = normalizedAccountId
          ..transferAmountFen = existing.transferAmountFen ?? transferAmountFen
          ..fromSs58Address = existing.fromSs58Address ?? fromSs58Address
          ..toSs58Address = existing.toSs58Address ?? toSs58Address
          ..counterpartySs58Address =
              existing.counterpartySs58Address ?? counterpartySs58Address
          ..remark = _mergeRemark(remark, existing.remark)
          ..blockNumber = blockNumber
          ..blockHash = normalizedBlockHash
          ..eventIndex = eventIndex
          ..extrinsicIndex = extrinsicIndex ?? existing.extrinsicIndex
          ..confirmedAtMillis = status == statusFinalized
              ? (confirmedAtMillis ?? now)
              : existing.confirmedAtMillis
          ..source = 'sdk_finalized_event'
          ..failureReason = null;
        await isar.localTxEntitys.put(existing);
        return;
      }

      final semanticExisting = await _findSemanticBlockTransferInTxn(
        isar,
        accountId: normalizedAccountId,
        blockNumber: blockNumber,
        blockHash: normalizedBlockHash,
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        transferAmountFen: transferAmountFen,
        extrinsicIndex: extrinsicIndex,
        eventIndex: eventIndex,
      );
      if (semanticExisting != null) {
        final hasSdkExecution =
            semanticExisting.executionId?.isNotEmpty == true;
        semanticExisting
          ..ss58Address = ss58Address
          ..accountId = normalizedAccountId
          ..amountDeltaFen = semanticExisting.feeFen != null
              ? semanticExisting.amountDeltaFen
              : amountDeltaFen
          ..transferAmountFen =
              semanticExisting.transferAmountFen ?? transferAmountFen
          ..fromSs58Address =
              semanticExisting.fromSs58Address ?? fromSs58Address
          ..toSs58Address = semanticExisting.toSs58Address ?? toSs58Address
          ..counterpartySs58Address =
              semanticExisting.counterpartySs58Address ??
                  counterpartySs58Address
          ..remark = _mergeRemark(remark, semanticExisting.remark)
          ..status = hasSdkExecution
              ? semanticExisting.status
              : _mergeStatus(semanticExisting.status, status)
          ..blockNumber = blockNumber
          ..blockHash = normalizedBlockHash
          ..eventIndex = semanticExisting.eventIndex ?? eventIndex
          ..extrinsicIndex = semanticExisting.extrinsicIndex ?? extrinsicIndex
          ..confirmedAtMillis = !hasSdkExecution && status == statusFinalized
              ? (confirmedAtMillis ?? now)
              : semanticExisting.confirmedAtMillis
          ..source = hasSdkExecution
              ? 'local_submit'
              : 'sdk_finalized_event'
          ..failureReason = null;
        await isar.localTxEntitys.put(semanticExisting);
        return;
      }

      // 本机发起转账会先写 pending，SDK history 可能先把它标成 inBlock。
      // finalized Transfer 事件回来后，用同钱包、同收款人、同本金匹配，
      // 但永久保留 submit key，避免重复流水且不切断后续 SDK history 关联。
      final localSubmit = await _findMatchingLocalSubmitTransferInTxn(
        isar,
        accountId: normalizedAccountId,
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        transferAmountFen: transferAmountFen,
      );
      final entity = localSubmit ?? LocalTxEntity();
      entity
        ..recordKey = localSubmit?.recordKey ?? recordKey
        ..ss58Address = ss58Address
        ..accountId = normalizedAccountId
        ..type = 'transfer'
        ..amountDeltaFen = localSubmit?.amountDeltaFen ?? amountDeltaFen
        ..transferAmountFen = transferAmountFen
        ..counterpartySs58Address = counterpartySs58Address
        ..fromSs58Address = fromSs58Address
        ..toSs58Address = toSs58Address
        ..remark = _mergeRemark(remark, localSubmit?.remark)
        ..status = localSubmit?.status ?? status
        ..source = localSubmit?.source ?? 'sdk_finalized_event'
        ..blockNumber = blockNumber
        ..blockHash = normalizedBlockHash
        ..eventIndex = eventIndex
        ..extrinsicIndex = extrinsicIndex
        ..createdAtMillis = localSubmit?.createdAtMillis ?? now
        ..confirmedAtMillis = localSubmit != null
            ? localSubmit.confirmedAtMillis
            : status == statusFinalized
                ? (confirmedAtMillis ?? now)
                : null
        ..failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// CitizenSDK history 显示交易已进入区块时，把本机 pending 记录升级为 inBlock。
  ///
  /// 这里不把它直接改成 finalized；最终确认只能由 SDK history 的
  /// finalizedSuccess 写回，业务事件不能越权推进。
  static Future<void> markLocalSubmitInBlock({
    required String accountId,
    required String txHash,
    required String executionId,
    required String callDataHash,
    String? blockHash,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
          !_matchesSdkExecution(entity, executionId, callDataHash) ||
          entity.status == statusFinalized ||
          entity.status == statusFailed) {
        return;
      }
      entity.status = statusInBlock;
      if (blockHash != null && blockHash.isNotEmpty) {
        entity.blockHash = normalizeBlockHash(blockHash);
      }
      entity.failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 根据 CitizenSDK history 的 pending 事实保持待确认。
  ///
  /// `inBlock` 只是内部进度，未获得 finalized 前始终属于 UI 的“待确认”。
  /// 保留 SDK 已投影的区块锚点，最终状态只能由后续 SDK history 覆盖。
  static Future<void> markLocalSubmitPending({
    required String accountId,
    required String txHash,
    required String executionId,
    required String callDataHash,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
          !_matchesSdkExecution(entity, executionId, callDataHash) ||
          entity.status == statusFinalized ||
          entity.status == statusFailed) {
        return;
      }
      // 不清 blockHash：它是 SDK 已公开的 inBlock 进度事实。
      entity
        ..status = statusPending
        ..failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 把已签名提交、且被交易池明确拒绝的交易标记为失败。
  ///
  /// 连接中断、监听超时和未获最终性确认都不能调用本入口，避免把未知结果误报为失败。
  static Future<void> markLocalSubmitFailed({
    required String accountId,
    required String txHash,
    required String executionId,
    required String callDataHash,
    required String failureReason,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
          !_matchesSdkExecution(entity, executionId, callDataHash) ||
          entity.status == statusFinalized) {
        return;
      }
      entity
        ..status = statusFailed
        ..failureReason = failureReason;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 把 CitizenSDK 已核验的 finalizedSuccess 投影到对应 App 记录。
  static Future<void> markLocalSubmitFinalized({
    required String accountId,
    required String txHash,
    required String executionId,
    required String callDataHash,
    String? blockHash,
    int? blockNumber,
    int? extrinsicIndex,
    int? confirmedAtMillis,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    final now = DateTime.now().millisecondsSinceEpoch;
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
          !_matchesSdkExecution(entity, executionId, callDataHash) ||
          entity.status == statusFinalized) {
        return;
      }
      entity
        ..status = statusFinalized
        ..extrinsicIndex = extrinsicIndex ?? entity.extrinsicIndex
        ..confirmedAtMillis = confirmedAtMillis ?? now
        ..failureReason = null;
      if (blockHash != null && blockHash.isNotEmpty) {
        entity.blockHash = normalizeBlockHash(blockHash);
      }
      if (blockNumber != null) {
        entity.blockNumber = blockNumber;
      }
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 监听某账户交易记录的任何变更。SDK history 和 finalized 业务投影把记录
  /// 写成 finalized 后即触发,供交易列表页响应式重刷(见 TxAutoRefreshMixin),
  /// 取代"提交后延时 N 秒盲刷"。
  ///
  /// 返回的句柄已经在任何异步 `db()` / watcher 创建前同步登记到 [WalletIsar]；
  /// 应用锁擦除会主动取消并等待它真实释放，禁止原生 watcher 晚到挂回已关闭的库。
  static LocalTxAccountChangeSubscription listenAccountChanges(
    String accountId,
    void Function() onChanged, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final normalizedAccountId = requireAccountId(accountId);
    return LocalTxAccountChangeSubscription._listen(
      accountId: normalizedAccountId,
      onChanged: onChanged,
      onError: onError,
    );
  }

  static String _mergeStatus(String? current, String incoming) {
    final currentRank = _statusRank(current);
    final incomingRank = _statusRank(incoming);
    return incomingRank >= currentRank ? incoming : (current ?? incoming);
  }

  static String? _mergeRemark(String? incoming, String? existing) {
    final normalized = incoming == null || incoming.isEmpty ? null : incoming;
    return normalized ?? existing;
  }

  static int _statusRank(String? status) {
    switch (status) {
      case statusFinalized:
        return 4;
      case statusFailed:
        return 3;
      case statusInBlock:
        return 2;
      case statusPending:
        return 1;
      default:
        return 0;
    }
  }

  /// 旧 App 扫块/交易池记录不转换、不兼容、不进入新列表。
  /// 新本机提交必须有 SDK execution/call hash；被动收入只接受 SDK
  /// finalized event 投影的明确来源。
  static bool _belongsToCurrentSdkIntegration(LocalTxEntity entity) {
    if (entity.source == 'sdk_finalized_event') return true;
    return entity.source == 'local_submit' &&
        (entity.executionId?.isNotEmpty ?? false) &&
        (entity.callDataHash?.isNotEmpty ?? false);
  }

  /// SDK executionId 与 opaque callData hash 必须同时匹配本地业务记录；
  /// 仅碰巧相同的账户/交易哈希不得推进另一条业务记录的展示状态。
  static bool _matchesSdkExecution(
    LocalTxEntity entity,
    String executionId,
    String callDataHash,
  ) {
    return _belongsToCurrentSdkIntegration(entity) &&
        entity.executionId == executionId &&
        entity.callDataHash?.toLowerCase() == callDataHash.toLowerCase();
  }

  static Future<LocalTxEntity?> _findMatchingLocalSubmitTransferInTxn(
    Isar isar, {
    required String accountId,
    required String fromSs58Address,
    required String toSs58Address,
    required String transferAmountFen,
  }) async {
    final pending = await isar.localTxEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .typeEqualTo('transfer')
        .findAll();
    for (final record in pending) {
      if (_belongsToCurrentSdkIntegration(record) &&
          record.fromSs58Address == fromSs58Address &&
          record.toSs58Address == toSs58Address &&
          record.transferAmountFen == transferAmountFen &&
          record.source == 'local_submit' &&
          (record.status == statusPending || record.status == statusInBlock)) {
        return record;
      }
    }
    return null;
  }

  static Future<LocalTxEntity?> _findSemanticBlockTransferInTxn(
    Isar isar, {
    required String accountId,
    required int? blockNumber,
    required String? blockHash,
    required String fromSs58Address,
    required String toSs58Address,
    required String transferAmountFen,
    required int? extrinsicIndex,
    required int? eventIndex,
  }) async {
    final records = await isar.localTxEntitys
        .filter()
        .accountIdEqualTo(accountId)
        .typeEqualTo('transfer')
        .findAll();
    for (final record in records) {
      if (!_belongsToCurrentSdkIntegration(record) ||
          record.fromSs58Address != fromSs58Address ||
          record.toSs58Address != toSs58Address ||
          record.transferAmountFen != transferAmountFen) {
        continue;
      }
      if (blockHash != null && record.blockHash != null) {
        if (normalizeBlockHash(record.blockHash!) != blockHash) continue;
      }
      if (blockNumber != null &&
          record.blockNumber != null &&
          record.blockNumber != blockNumber) {
        continue;
      }
      if (extrinsicIndex != null &&
          record.extrinsicIndex != null &&
          record.extrinsicIndex != extrinsicIndex) {
        continue;
      }
      if (eventIndex != null &&
          record.eventIndex != null &&
          record.eventIndex != eventIndex) {
        continue;
      }
      if (record.status == statusPending && record.source != 'local_submit') {
        continue;
      }
      return record;
    }
    return null;
  }

  /// 删除某个账户的 CitizenApp 业务交易记录。
  /// SDK execution history 由 CitizenSDK 自己的删除和擦除合同管理。
  static Future<void> deleteWalletLocalHistory(String accountId) async {
    final normalizedAccountId = requireAccountId(accountId);
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.localTxEntitys
          .filter()
          .accountIdEqualTo(normalizedAccountId)
          .deleteAll();
    });
  }

  /// 清空所有 CitizenApp 业务交易记录。
  static Future<void> clearAllWalletLocalHistory() async {
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.localTxEntitys.clear();
    });
  }

  /// 查询某个钱包的交易总数。
  static Future<int> countByAccountId(String accountId) async {
    final normalizedAccountId = requireAccountId(accountId);
    return WalletIsar.instance.read((isar) async {
      final rows = await isar.localTxEntitys
          .where()
          .accountIdEqualTo(normalizedAccountId)
          .findAll();
      return rows.where(_belongsToCurrentSdkIntegration).length;
    });
  }
}

/// 交易流水 watcher 的可等待生命周期句柄。
///
/// 取得 WalletIsar lease、启动 watcher、取消 subscription 和释放 lease 被收敛为一个
/// 状态机。取消请求先同步落位，再等待尚未完成的启动；因此即使关闭发生在 `db()` 等待
/// 期间，启动路径也不会在关闭请求之后重新挂上 watcher。
class LocalTxAccountChangeSubscription {
  LocalTxAccountChangeSubscription._();

  WalletIsarConsumerLease? _lease;
  StreamSubscription<void>? _subscription;
  Future<void>? _startup;
  final Completer<void> _startupAssigned = Completer<void>();
  Future<_LocalTxCancellationOutcome>? _cancelInFlight;
  bool _cancelRequested = false;

  @visibleForTesting
  static Future<void> Function(StreamSubscription<void> subscription)?
      debugCancelSubscription;

  static LocalTxAccountChangeSubscription _listen({
    required String accountId,
    required void Function() onChanged,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final listener = LocalTxAccountChangeSubscription._();
    final callbackZone = Zone.current;

    // 必须先同步登记 lease；登记失败时尚未开始任何 db() 或 watcher 工作。
    listener._lease = WalletIsar.instance.registerExternalConsumer(
      listener.cancel,
    );
    if (listener._cancelRequested) {
      listener._startup = Future<void>.value();
    } else {
      // 原生 watcher 的启动与取消属于资源生命周期，不能被 UI 的 fake-async/页面
      // Zone 暂停；事件回调再显式送回调用方 Zone，保持 Flutter 状态更新边界不变。
      listener._startup = Zone.root.run(
        () => listener._start(
          accountId: accountId,
          onChanged: onChanged,
          onError: onError,
          callbackZone: callbackZone,
        ),
      );
    }
    listener._startupAssigned.complete();
    return listener;
  }

  void _reportError(
    Object error,
    StackTrace stackTrace,
    void Function(Object error, StackTrace stackTrace)? onError,
    Zone callbackZone,
  ) {
    final callback = onError;
    if (callback == null) {
      callbackZone.handleUncaughtError(error, stackTrace);
      return;
    }
    callbackZone.runGuarded(() => callback(error, stackTrace));
  }

  Future<void> _cancelSubscriptionAfterStartupFailure() async {
    final subscription = _subscription;
    if (subscription == null) {
      _releaseLease();
      return;
    }
    await _cancelNativeSubscription(subscription);
    _subscription = null;
    _releaseLease();
  }

  Future<void> _start({
    required String accountId,
    required void Function() onChanged,
    required void Function(Object error, StackTrace stackTrace)? onError,
    required Zone callbackZone,
  }) async {
    try {
      final isar = await WalletIsar.instance.db();
      if (_cancelRequested) return;

      final subscription = isar.localTxEntitys
          .where()
          .accountIdEqualTo(accountId)
          .watchLazy()
          .listen((_) => callbackZone.runGuarded(onChanged));
      _subscription = subscription;

      // 覆盖 lease 已取得、subscription 尚未赋值时收到关闭请求的竞态。
      if (_cancelRequested) {
        await _cancelNativeSubscription(subscription);
        _subscription = null;
      }
    } catch (error, stackTrace) {
      try {
        // 清理失败时故意保留 subscription 与 lease，让 WalletIsar 擦除可见失败并可重试。
        await _cancelSubscriptionAfterStartupFailure();
      } catch (cleanupError, cleanupStackTrace) {
        _reportError(
          cleanupError,
          cleanupStackTrace,
          onError,
          callbackZone,
        );
      }

      if (!_cancelRequested) {
        _reportError(error, stackTrace, onError, callbackZone);
      }
    }
  }

  /// 幂等且 single-flight：仅在启动任务和原生 subscription 均真实结束后释放 lease。
  Future<void> cancel() {
    _cancelRequested = true;
    var task = _cancelInFlight;
    if (task == null) {
      late final Future<_LocalTxCancellationOutcome> created;
      created = Zone.root.run(() async {
        try {
          await _cancel();
          return const _LocalTxCancellationOutcome.success();
        } on Object catch (error, stackTrace) {
          return _LocalTxCancellationOutcome.failure(error, stackTrace);
        }
      });
      _cancelInFlight = created;
      task = created;
      // created 永不以 error 完成，因此 root Zone 没有可泄漏的未观察异常。
      unawaited(created.then<void>((_) {
        if (identical(_cancelInFlight, created)) _cancelInFlight = null;
      }));
    }
    // 每个调用者在自己的 Zone 解包同一 outcome，保留原始堆栈并让失败可见。
    return task.then<void>((outcome) {
      final error = outcome.error;
      if (error != null) {
        Error.throwWithStackTrace(error, outcome.stackTrace!);
      }
    });
  }

  Future<void> _cancel() async {
    await _startupAssigned.future;
    await _startup;
    final subscription = _subscription;
    if (subscription != null) {
      await _cancelNativeSubscription(subscription);
      _subscription = null;
    }
    _releaseLease();
  }

  static Future<void> _cancelNativeSubscription(
    StreamSubscription<void> subscription,
  ) {
    final testCancel = debugCancelSubscription;
    return testCancel?.call(subscription) ?? subscription.cancel();
  }

  void _releaseLease() {
    final lease = _lease;
    if (lease == null) return;
    lease.release();
    _lease = null;
  }
}

class _LocalTxCancellationOutcome {
  const _LocalTxCancellationOutcome.success()
      : error = null,
        stackTrace = null;

  const _LocalTxCancellationOutcome.failure(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;
}
