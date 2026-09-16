import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart/polkadart.dart' show Events, RuntimeMetadata;

/// 本文件按准确区块的 Runtime metadata 投影 System 执行终态和 CitizenApp 业务转账事件；
/// 它不维护轻节点、扫描游标或 CitizenSDK 自有 execution history。
/// One CitizenApp business transfer decoded from exact-block Runtime metadata.
final class CitizenChainTransferEvent {
  const CitizenChainTransferEvent({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountFen,
    required this.eventRecordIndex,
    required this.extrinsicIndex,
    required this.sourcePallet,
    this.remark,
  });

  final String fromAccountId;
  final String toAccountId;
  final String amountFen;
  final int eventRecordIndex;
  final int? extrinsicIndex;
  final String sourcePallet;
  final String? remark;
}

/// Exact System outcome for one extrinsic in the decoded event vector.
final class CitizenChainExtrinsicOutcome {
  const CitizenChainExtrinsicOutcome({
    required this.extrinsicIndex,
    required this.succeeded,
    this.failureDescription,
  });

  final int extrinsicIndex;
  final bool succeeded;
  final String? failureDescription;
}

final class CitizenChainTransactionBlockEvents {
  CitizenChainTransactionBlockEvents({
    required List<CitizenChainTransferEvent> transfers,
    required Map<int, CitizenChainExtrinsicOutcome> outcomes,
  })  : transfers = List<CitizenChainTransferEvent>.unmodifiable(transfers),
        outcomes =
            Map<int, CitizenChainExtrinsicOutcome>.unmodifiable(outcomes);

  final List<CitizenChainTransferEvent> transfers;
  final Map<int, CitizenChainExtrinsicOutcome> outcomes;
}

/// CitizenApp's strict metadata-based decoder for transaction business events.
///
/// This decoder intentionally has no fixed-index, offset-scanning or nonce
/// fallback. If the exact Runtime metadata cannot decode the whole event vector,
/// the block is rejected; CitizenApp does not maintain an independent scan cursor.
final class CitizenChainTransactionEventDecoder {
  const CitizenChainTransactionEventDecoder();

  CitizenChainTransactionBlockEvents decode({
    required Uint8List eventsBytes,
    required RuntimeMetadata metadata,
    required String eventsStorageKeyHex,
  }) {
    final events = Events.fromJson({
      'changes': [
        [eventsStorageKeyHex, '0x${_hexEncode(eventsBytes)}'],
      ],
    }, metadata.chainInfo);

    final transfers = <CitizenChainTransferEvent>[];
    final outcomes = <int, CitizenChainExtrinsicOutcome>{};
    for (var index = 0; index < events.eventRecord.length; index++) {
      final record = events.eventRecord[index];
      final extrinsicIndex = _extrinsicIndex(record.phase);
      final event = record.event;

      final system = event['System'];
      if (system is Map && extrinsicIndex != null) {
        CitizenChainExtrinsicOutcome? outcome;
        if (system.containsKey('ExtrinsicSuccess')) {
          outcome = CitizenChainExtrinsicOutcome(
            extrinsicIndex: extrinsicIndex,
            succeeded: true,
          );
        } else if (system.containsKey('ExtrinsicFailed')) {
          outcome = CitizenChainExtrinsicOutcome(
            extrinsicIndex: extrinsicIndex,
            succeeded: false,
            failureDescription: system['ExtrinsicFailed'].toString(),
          );
        }
        if (outcome != null) {
          if (outcomes.containsKey(extrinsicIndex)) {
            throw FormatException(
              'extrinsic $extrinsicIndex 存在重复 System 执行终态',
            );
          }
          outcomes[extrinsicIndex] = outcome;
        }
      }

      final onchain = event['OnchainTransaction'];
      if (onchain is Map && onchain.containsKey('TransferWithRemark')) {
        final fields = _namedFields(
          onchain['TransferWithRemark'],
          const ['from', 'beneficiary', 'amount', 'remark'],
          'OnchainTransaction.TransferWithRemark',
        );
        transfers.add(CitizenChainTransferEvent(
          fromAccountId: _accountId(fields[0], 'from'),
          toAccountId: _accountId(fields[1], 'beneficiary'),
          amountFen: _positiveAmount(fields[2]),
          eventRecordIndex: index,
          extrinsicIndex: extrinsicIndex,
          sourcePallet: 'OnchainTransaction',
          remark: _remark(fields[3]),
        ));
        continue;
      }

      final balances = event['Balances'];
      if (balances is Map && balances.containsKey('Transfer')) {
        final fields = _namedFields(
          balances['Transfer'],
          const ['from', 'to', 'amount'],
          'Balances.Transfer',
        );
        transfers.add(CitizenChainTransferEvent(
          fromAccountId: _accountId(fields[0], 'from'),
          toAccountId: _accountId(fields[1], 'to'),
          amountFen: _positiveAmount(fields[2]),
          eventRecordIndex: index,
          extrinsicIndex: extrinsicIndex,
          sourcePallet: 'Balances',
        ));
      }
    }
    return CitizenChainTransactionBlockEvents(
      transfers: transfers,
      outcomes: outcomes,
    );
  }

  List<Object?> _namedFields(
    Object? raw,
    List<String> names,
    String label,
  ) {
    if (raw is! Map) {
      throw FormatException('$label 必须由 metadata 解码为命名字段');
    }
    final values = <Object?>[];
    for (final name in names) {
      if (!raw.containsKey(name)) {
        throw FormatException('$label 缺少字段 $name');
      }
      values.add(raw[name]);
    }
    return values;
  }

  int? _extrinsicIndex(Map<String, dynamic> phase) {
    final raw = phase['ApplyExtrinsic'];
    if (raw == null) return null;
    if (raw is int && raw >= 0) return raw;
    if (raw is BigInt && raw >= BigInt.zero && raw <= BigInt.from(0xffffffff)) {
      return raw.toInt();
    }
    if (raw is String) {
      final value = int.tryParse(raw);
      if (value != null && value >= 0) return value;
    }
    throw const FormatException('ApplyExtrinsic phase index 无效');
  }

  String _accountId(Object? raw, String field) {
    final bytes = raw is Uint8List
        ? raw
        : raw is List
            ? Uint8List.fromList(raw.cast<int>())
            : null;
    if (bytes == null || bytes.length != 32) {
      throw FormatException('$field 必须是 32 字节 AccountId');
    }
    return '0x${_hexEncode(bytes)}';
  }

  String _positiveAmount(Object? raw) {
    final value = switch (raw) {
      BigInt value => value,
      int value => BigInt.from(value),
      String value => BigInt.tryParse(value),
      _ => null,
    };
    if (value == null || value <= BigInt.zero) {
      throw const FormatException('transfer amount 必须是正 u128');
    }
    return value.toString();
  }

  String? _remark(Object? raw) {
    final bytes = raw is Uint8List
        ? raw
        : raw is List
            ? Uint8List.fromList(raw.cast<int>())
            : null;
    if (bytes == null || bytes.length > 99) {
      throw const FormatException('remark 必须是最多 99 字节的 Runtime bytes');
    }
    return bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
  }

  String _hexEncode(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
