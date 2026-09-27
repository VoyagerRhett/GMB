import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart_scale_codec/polkadart_scale_codec.dart' as scale;
import 'package:substrate_metadata/substrate_metadata.dart' as metadata;

/// 本文件按准确区块的 Runtime metadata 投影 System 执行终态和 CitizenApp 业务转账事件；
/// 它不维护轻节点、扫描游标或 CitizenSDK 自有 execution history。
/// 按准确区块 metadata 解码的一次业务转账。
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

/// 事件向量中同一 extrinsic 的准确 System 执行结果。
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
  }) : transfers = List<CitizenChainTransferEvent>.unmodifiable(transfers),
       outcomes = Map<int, CitizenChainExtrinsicOutcome>.unmodifiable(outcomes);

  final List<CitizenChainTransferEvent> transfers;
  final Map<int, CitizenChainExtrinsicOutcome> outcomes;
}

/// 全块按准确 metadata 解码；任一错误必须使整块投影失败，进度不得推进。
/// 同一转账的 Balances.Transfer 与 TransferWithRemark 按事件顺序一对一合并，
/// 保持 Balances 事件索引为记录身份，禁止把同金额的独立转账合为一条。
final class CitizenChainTransactionEventDecoder {
  const CitizenChainTransactionEventDecoder();

  CitizenChainTransactionBlockEvents decode({
    required Uint8List eventsBytes,
    required Uint8List metadataBytes,
  }) {
    final input = scale.ByteInput(metadataBytes);
    final runtime = metadata.RuntimeMetadataPrefixed.codec
        .decode(input)
        .metadata;
    input.assertEndOfDataReached();
    final systemStorage = runtime.pallets
        .singleWhere((p) => p.name == 'System')
        .storage;
    final entry = systemStorage?.entries.singleWhere((e) => e.name == 'Events');
    if (entry == null ||
        entry.type.key != null ||
        entry.type.hashers.isNotEmpty) {
      throw const FormatException('metadata 缺少 System.Events 普通存储');
    }
    final codec = _EventCodecs(runtime).codec(entry.type.value);
    final eventInput = scale.ByteInput(eventsBytes);
    final decoded = codec.decode(eventInput);
    eventInput.assertEndOfDataReached();
    final raw = _normalize(decoded);
    if (raw is! List) throw const FormatException('System.Events 必须是事件向量');

    final transfers = <CitizenChainTransferEvent>[];
    final outcomes = <int, CitizenChainExtrinsicOutcome>{};
    for (var index = 0; index < raw.length; index++) {
      final record = raw[index] as Map;
      final extrinsicIndex = _extrinsicIndex(
        Map<String, dynamic>.from(record['phase'] as Map),
      );
      final event = record['event'] as Map;

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
            failureDescription: '链上执行失败',
          );
        }
        if (outcome != null) {
          if (outcomes.containsKey(extrinsicIndex)) {
            throw FormatException('extrinsic $extrinsicIndex 存在重复 System 执行终态');
          }
          outcomes[extrinsicIndex] = outcome;
        }
      }

      final onchain = event['OnchainTransaction'];
      if (onchain is Map && onchain.containsKey('TransferWithRemark')) {
        final fields = _namedFields(onchain['TransferWithRemark'], const [
          'from_account_id',
          'beneficiary_account_id',
          'amount',
          'remark',
        ], 'OnchainTransaction.TransferWithRemark');
        final from = _accountId(fields[0], 'from_account_id');
        final to = _accountId(fields[1], 'beneficiary_account_id');
        final amount = _positiveAmount(fields[2]);
        final matching = transfers.lastIndexWhere(
          (transfer) =>
              transfer.sourcePallet == 'Balances' &&
              transfer.extrinsicIndex == extrinsicIndex &&
              transfer.fromAccountId == from &&
              transfer.toAccountId == to &&
              transfer.amountFen == amount,
        );
        // Runtime 在 Currency::transfer 成功后才发备注事件，必须找到前序本金事件。
        if (matching < 0) {
          throw const FormatException('备注事件缺少同一执行中的前序转账事件');
        }
        transfers[matching] = CitizenChainTransferEvent(
          fromAccountId: from,
          toAccountId: to,
          amountFen: _positiveAmount(fields[2]),
          eventRecordIndex: transfers[matching].eventRecordIndex,
          extrinsicIndex: extrinsicIndex,
          sourcePallet: 'OnchainTransaction',
          remark: _remark(fields[3]),
        );
        continue;
      }

      final balances = event['Balances'];
      if (balances is Map && balances.containsKey('Transfer')) {
        final fields = _namedFields(balances['Transfer'], const [
          'from',
          'to',
          'amount',
        ], 'Balances.Transfer');
        transfers.add(
          CitizenChainTransferEvent(
            fromAccountId: _accountId(fields[0], 'from'),
            toAccountId: _accountId(fields[1], 'to'),
            amountFen: _positiveAmount(fields[2]),
            eventRecordIndex: index,
            extrinsicIndex: extrinsicIndex,
            sourcePallet: 'Balances',
          ),
        );
      }
    }
    return CitizenChainTransactionBlockEvents(
      transfers: transfers,
      outcomes: outcomes,
    );
  }

  List<Object?> _namedFields(Object? raw, List<String> names, String label) {
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
    if (raw is int && raw >= 0 && raw <= 0xffffffff) return raw;
    if (raw is BigInt && raw >= BigInt.zero && raw <= BigInt.from(0xffffffff)) {
      return raw.toInt();
    }
    if (raw is String) {
      final value = int.tryParse(raw);
      if (value != null && value >= 0 && value <= 0xffffffff) return value;
    }
    throw const FormatException('ApplyExtrinsic phase index 无效');
  }

  String _accountId(Object? raw, String field) {
    final bytes = raw is Uint8List
        ? raw
        : raw is List &&
              raw.every((value) => value is int && value >= 0 && value <= 255)
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
    if (value == null || value <= BigInt.zero || value >= (BigInt.one << 128)) {
      throw const FormatException('transfer amount 必须是正 u128');
    }
    return value.toString();
  }

  String? _remark(Object? raw) {
    final bytes = raw is Uint8List
        ? raw
        : raw is List &&
              raw.every((value) => value is int && value >= 0 && value <= 255)
        ? Uint8List.fromList(raw.cast<int>())
        : null;
    if (bytes == null || bytes.length > 99) {
      throw const FormatException('remark 必须是最多 99 字节的 Runtime bytes');
    }
    return bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
  }

  String _hexEncode(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// 保留整数与字节，枚举只转换结构，不经 JSON 或类型名猜测字段。
  Object? _normalize(Object? value) {
    if (value is MapEntry) return {value.key: _normalize(value.value)};
    if (value is Map) {
      return value.map((key, item) => MapEntry(key, _normalize(item)));
    }
    if (value is List) return value.map(_normalize).toList();
    return value;
  }
}

/// 只把该区块 System.Events 可达的 portable 类型接到官方 SCALE codec。
/// 字段名、类型引用、枚举索引均来自 metadata，不使用上游便利入口的类型名别名。
final class _EventCodecs {
  _EventCodecs(metadata.RuntimeMetadata runtime)
    : _types = {for (final type in runtime.types) type.id: type.type} {
    if (_types.length != runtime.types.length) {
      throw const FormatException('metadata 类型编号重复');
    }
  }
  final Map<int, metadata.TypeMetadata> _types;
  final _codecs = <int, scale.Codec>{};

  scale.Codec codec(int id) {
    id = _resolveType(id);
    final cached = _codecs[id];
    if (cached != null) return cached;
    final type = _types[id];
    if (type == null) throw const FormatException('metadata 类型引用不存在');
    final proxy = scale.ProxyCodec();
    _codecs[id] = proxy;
    final definition = type.typeDef;
    proxy.codec = switch (definition) {
      metadata.TypeDefPrimitive() =>
        scale.Registry().getCodec(definition.primitive.name.toLowerCase()) ??
            (throw const FormatException('事件包含不支持的 primitive')),
      metadata.TypeDefComposite() => _fields(definition.fields),
      metadata.TypeDefVariant() => _variants(definition.variants),
      metadata.TypeDefSequence() => scale.SequenceCodec(codec(definition.type)),
      metadata.TypeDefArray() => scale.ArrayCodec(
        codec(definition.type),
        definition.length,
      ),
      metadata.TypeDefTuple() => scale.TupleCodec(
        definition.fields.map(codec).toList(),
      ),
      metadata.TypeDefCompact() => scale.CompactBigIntCodec.codec,
      metadata.TypeDefBitSequence() => _bits(definition),
      _ => throw const FormatException('事件包含不支持的 portable 类型'),
    };
    return proxy;
  }

  /// SCALE 的单未命名字段包装不增加字节，也不增加解码值的层级。
  /// 在创建代理前解析到承载类型，避免 ProxyCodec 套 ProxyCodec；
  /// 只拒绝不经过真实容器的纯包装循环，容器递归仍复用已登记代理。
  int _resolveType(int id) {
    final visited = <int>{};
    while (true) {
      if (!visited.add(id)) {
        throw const FormatException('metadata 存在纯包装循环');
      }
      final type = _types[id];
      if (type == null) throw const FormatException('metadata 类型引用不存在');
      final definition = type.typeDef;
      if (definition is! metadata.TypeDefComposite ||
          definition.fields.length != 1 ||
          definition.fields.single.name != null) {
        return id;
      }
      id = definition.fields.single.type;
    }
  }

  scale.Codec _fields(List<metadata.Field> fields) {
    if (fields.isEmpty) return scale.NullCodec.codec;
    if (fields.every((field) => field.name == null)) {
      if (fields.length == 1) return codec(fields.single.type);
      return scale.TupleCodec(
        fields.map((field) => codec(field.type)).toList(),
      );
    }
    if (fields.any((field) => field.name == null) ||
        fields.map((field) => field.name).toSet().length != fields.length) {
      throw const FormatException('metadata 命名字段不完整或重复');
    }
    return scale.CompositeCodec({
      for (final field in fields) field.name!: codec(field.type),
    });
  }

  scale.Codec _variants(List<metadata.Variant> variants) {
    if (variants.map((v) => v.index).toSet().length != variants.length ||
        variants.map((v) => v.name).toSet().length != variants.length) {
      throw const FormatException('metadata 枚举索引或名称重复');
    }
    return scale.ComplexEnumCodec.sparse({
      for (final variant in variants)
        variant.index: MapEntry(variant.name, _fields(variant.fields)),
    });
  }

  scale.Codec _bits(metadata.TypeDefBitSequence definition) {
    final store = _types[definition.bitStoreType]?.typeDef;
    final order = _types[definition.bitOrderType]?.path.lastOrNull;
    if (store is! metadata.TypeDefPrimitive ||
        !['U8', 'U16', 'U32', 'U64'].contains(store.primitive.name) ||
        (order != 'Lsb0' && order != 'Msb0')) {
      throw const FormatException('metadata 位序类型无效');
    }
    return scale.BitSequenceCodec(
      scale.BitStore.values.singleWhere(
        (value) => value.name == store.primitive.name,
      ),
      order == 'Lsb0' ? scale.BitOrder.LSB : scale.BitOrder.MSB,
    );
  }
}
