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
    return WalletIsar.instance.read((isar) {
      return isar.localTxEntitys
          .where()
          .accountIdEqualTo(normalizedAccountId)
          .sortByCreatedAtMillisDesc()
          .offset(offset)
          .limit(limit)
          .findAll();
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
    return WalletIsar.instance.read((isar) {
      return isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
    });
  }

  /// 写入本机发起的普通转账记录。
  ///
  /// 交易池和区块事件可能先于页面本地写入返回。这里先查是否
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
        ..recordKey = existingEvent?.recordKey ?? pendingKey
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
        ..status = _mergeStatus(existingEvent?.status, statusPending)
        ..source = 'local_submit'
        ..txHash = normalizedTxHash
        ..usedNonce = usedNonce
        ..createdAtMillis = existingEvent?.createdAtMillis ?? createdAtMillis
        ..failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 写入链上区块转账事件；如能匹配本机发起记录，则更新原记录。
  ///
  /// (ADR-017 全端 finalized 单一口径)：本方法由只扫 finalized 链的
  /// ChainTxMonitor 调用，写入/升级的流水状态恒为 finalized(已确认)。收入
  /// (别人转入)没有本机 pending，只在对应区块 finalized 后用同一个区块事件
  /// 唯一键写入，避免“余额到账但无收入记录”。inBlock 进度态由交易提交
  /// watch 单独产生(见 [markLocalSubmitInBlock])，不在本路径。
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
        semanticExisting
          ..recordKey = semanticExisting.recordKey.contains(':tx:')
              ? recordKey
              : semanticExisting.recordKey
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
          ..status = _mergeStatus(semanticExisting.status, status)
          ..blockNumber = blockNumber
          ..blockHash = normalizedBlockHash
          ..eventIndex = semanticExisting.eventIndex ?? eventIndex
          ..extrinsicIndex = semanticExisting.extrinsicIndex ?? extrinsicIndex
          ..confirmedAtMillis = status == statusFinalized
              ? (confirmedAtMillis ?? now)
              : semanticExisting.confirmedAtMillis
          ..failureReason = null;
        await isar.localTxEntitys.put(semanticExisting);
        return;
      }

      // 本机发起转账会先写 pending，交易池 inBlock 回调可能先把它
      // 标成 inBlock。链上 Transfer 事件回来后，用同钱包、同收款人、同本金
      // 匹配并改成区块事件唯一键，避免列表里出现重复流水。
      final localSubmit = await _findMatchingLocalSubmitTransferInTxn(
        isar,
        accountId: normalizedAccountId,
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        transferAmountFen: transferAmountFen,
      );
      final entity = localSubmit ?? LocalTxEntity();
      entity
        ..recordKey = recordKey
        ..ss58Address = ss58Address
        ..accountId = normalizedAccountId
        ..type = 'transfer'
        ..amountDeltaFen = localSubmit?.amountDeltaFen ?? amountDeltaFen
        ..transferAmountFen = transferAmountFen
        ..counterpartySs58Address = counterpartySs58Address
        ..fromSs58Address = fromSs58Address
        ..toSs58Address = toSs58Address
        ..remark = _mergeRemark(remark, localSubmit?.remark)
        ..status = _mergeStatus(localSubmit?.status, status)
        ..source = localSubmit?.source ?? 'chain_event'
        ..blockNumber = blockNumber
        ..blockHash = normalizedBlockHash
        ..eventIndex = eventIndex
        ..extrinsicIndex = extrinsicIndex
        ..createdAtMillis = localSubmit?.createdAtMillis ?? now
        ..confirmedAtMillis =
            status == statusFinalized ? (confirmedAtMillis ?? now) : null
        ..failureReason = null;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 交易池回调显示交易已进入区块时，先把本机 pending 记录升级为 inBlock。
  ///
  /// 这里不把它直接改成 finalized；最终确认仍由 finalized 区块事件
  /// 写回，保留回滚边界。
  static Future<void> markLocalSubmitInBlock({
    required String accountId,
    required String txHash,
    String? blockHash,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
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

  /// 非最终区块被回滚(dropped / retracted)时恢复为待确认。
  ///
  /// `inBlock` 只是内部进度，未获得 finalized 前始终属于 UI 的“待确认”。
  /// **关键:保留 blockHash(不清空)** —— `dropped` 按设计不算失败,而 blockHash
  /// 是 ChainTxMonitor 确认判据一(锚比对)的定点锚;清空会让记录与锚路径失联。
  /// 锚可能过期无害：确认前会与最终链哈希比对；不一致时保持 pending，
  /// 等待 finalized 前向扫描找到准确块体和同 index System 终态。
  /// 不影响已最终性确认或明确失败的记录。
  static Future<void> markLocalSubmitPending({
    required String accountId,
    required String txHash,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null ||
          entity.status == statusFinalized ||
          entity.status == statusFailed) {
        return;
      }
      // 不清 blockHash:见上方文档,它是确认判据一的定点锚。
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
    required String failureReason,
  }) async {
    final recordKey = submitRecordKey(accountId, txHash);
    await WalletIsar.instance.writeTxn((isar) async {
      final entity = await isar.localTxEntitys
          .where()
          .recordKeyEqualTo(recordKey)
          .findFirst();
      if (entity == null || entity.status == statusFinalized) return;
      entity
        ..status = statusFailed
        ..failureReason = failureReason;
      await isar.localTxEntitys.put(entity);
    });
  }

  /// 按 txHash 精确认：把本机提交的**这一条**记录就地翻成 finalized（已确认）。
  ///
  /// 由 ChainTxMonitor 调用。recordKey 全程不变（始终 submitRecordKey），状态就地
  /// 流转，绝不另建第二条记录。块信息按来源可选：
  /// - 最终块里按 txHash 定位到（前向扫描 / 锚比对路径）→ 带 blockHash+blockNumber；
  /// 没有准确块体与同 index System 终态时不得调用本入口。
  static Future<void> markLocalSubmitFinalized({
    required String accountId,
    required String txHash,
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
      if (entity == null || entity.status == statusFinalized) return;
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

  /// 查询某钱包所有"未终态"的本机提交记录（待确认：pending / inBlock）。
  ///
  /// 供 ChainTxMonitor 扫每个最终块时，按 txHash 逐条核对是否已进最终块。
  static Future<List<LocalTxEntity>> queryOpenLocalSubmit(
    String accountId,
  ) async {
    final normalizedAccountId = requireAccountId(accountId);
    final all = await WalletIsar.instance.read((isar) {
      return isar.localTxEntitys
          .where()
          .accountIdEqualTo(normalizedAccountId)
          .findAll();
    });
    return all
        .where((r) =>
            r.source == 'local_submit' &&
            r.txHash != null &&
            r.txHash!.isNotEmpty &&
            (r.status == statusPending || r.status == statusInBlock))
        .toList();
  }

  /// 监听某账户交易记录的任何变更(增/改/删)。后台 [ChainTxMonitor] 把记录
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
      if (record.fromSs58Address == fromSs58Address &&
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
      if (record.fromSs58Address != fromSs58Address ||
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
      if (record.status == statusPending && record.source != 'local_submit') {
        continue;
      }
      return record;
    }
    return null;
  }

  /// 删除某个钱包本机记录周期内的所有交易流水和同步游标。
  static Future<void> deleteWalletLocalHistory(String accountId) async {
    final normalizedAccountId = requireAccountId(accountId);
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.localTxEntitys
          .filter()
          .accountIdEqualTo(normalizedAccountId)
          .deleteAll();
      await isar.walletTxSyncCursorEntitys
          .filter()
          .accountIdEqualTo(normalizedAccountId)
          .deleteAll();
    });
  }

  /// 清空所有钱包交易流水和同步游标。
  static Future<void> clearAllWalletLocalHistory() async {
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.localTxEntitys.clear();
      await isar.walletTxSyncCursorEntitys.clear();
    });
  }

  /// 确保钱包交易同步游标存在。
  static Future<WalletTxSyncCursorEntity> ensureCursor({
    required String ss58Address,
    required String accountId,
    required int trackingStartBlock,
    required int lastSyncedBlock,
  }) async {
    final normalizedAccountId = requireAccountId(accountId);
    final now = DateTime.now().millisecondsSinceEpoch;
    return WalletIsar.instance.writeTxn((isar) async {
      final existing = await isar.walletTxSyncCursorEntitys
          .filter()
          .accountIdEqualTo(normalizedAccountId)
          .findFirst();
      if (existing != null) {
        existing
          ..ss58Address = ss58Address
          ..updatedAtMillis = now;
        await isar.walletTxSyncCursorEntitys.put(existing);
        return existing;
      }
      final created = WalletTxSyncCursorEntity()
        ..ss58Address = ss58Address
        ..accountId = normalizedAccountId
        ..trackingStartBlock = trackingStartBlock
        ..lastSyncedBlock = lastSyncedBlock
        ..createdAtMillis = now
        ..updatedAtMillis = now;
      await isar.walletTxSyncCursorEntitys.put(created);
      return created;
    });
  }

  /// 读取当前监控钱包的同步游标；缺失的钱包会以指定区块作为本机起点。
  static Future<List<WalletTxSyncCursorEntity>> ensureCursorsForWallets({
    required Map<String, String> ss58AddressByAccountId,
    required int startBlock,
  }) async {
    final result = <WalletTxSyncCursorEntity>[];
    for (final entry in ss58AddressByAccountId.entries) {
      final cursor = await ensureCursor(
        ss58Address: entry.value,
        accountId: entry.key,
        trackingStartBlock: startBlock,
        lastSyncedBlock: startBlock,
      );
      result.add(cursor);
    }
    return result;
  }

  /// 标记钱包已经同步到某个 finalized 区块。
  static Future<void> markCursorSynced({
    required String accountId,
    required int blockNumber,
  }) async {
    final normalizedAccountId = requireAccountId(accountId);
    await WalletIsar.instance.writeTxn((isar) async {
      final cursor = await isar.walletTxSyncCursorEntitys
          .filter()
          .accountIdEqualTo(normalizedAccountId)
          .findFirst();
      if (cursor == null || cursor.lastSyncedBlock >= blockNumber) {
        return;
      }
      cursor
        ..lastSyncedBlock = blockNumber
        ..updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
      await isar.walletTxSyncCursorEntitys.put(cursor);
    });
  }

  /// 查询某个钱包的交易总数。
  static Future<int> countByAccountId(String accountId) async {
    final normalizedAccountId = requireAccountId(accountId);
    return WalletIsar.instance.read((isar) {
      return isar.localTxEntitys
          .where()
          .accountIdEqualTo(normalizedAccountId)
          .count();
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
