import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:polkadart/scale_codec.dart' show ByteOutput;

import 'package:citizenapp/citizen/shared/pallet_registry.dart';

/// 创作者链上付款档位中的周期价格。
class CreatorPeriodPriceInput {
  const CreatorPeriodPriceInput({
    required this.billingPeriod,
    required this.priceFen,
  });

  final String billingPeriod;
  final BigInt priceFen;
}

/// 创作者覆盖式提交的链上付款档位；档位名与价格在同一交易中原子写入链上。
class CreatorTierInput {
  const CreatorTierInput({
    required this.tierId,
    required this.tierName,
    required this.pricesFen,
  });

  final String tierId;
  final String tierName;
  final List<CreatorPeriodPriceInput> pricesFen;
}

/// finalized `Subscriptions` 中的平台或创作者付款计划。
class ChainSubscriptionPlan {
  const ChainSubscriptionPlan.platform(this.membershipLevel)
      : kind = 'platform',
        tierId = null,
        billingPeriod = null;

  const ChainSubscriptionPlan.creator(this.tierId, this.billingPeriod)
      : kind = 'creator',
        membershipLevel = null;

  final String kind;
  final String? membershipLevel;
  final String? tierId;
  final String? billingPeriod;
}

/// 链上订阅真态；所有时间字段均为 UTC Unix 毫秒时间戳。
class ChainSubscriptionState {
  const ChainSubscriptionState({
    required this.plan,
    required this.startedAt,
    required this.lastChargedAt,
    required this.lastChargedPriceFen,
    required this.paidUntil,
    required this.status,
    required this.authorizedPriceFen,
    required this.suspendReason,
  });

  final ChainSubscriptionPlan plan;
  final int startedAt;
  final int lastChargedAt;
  final BigInt lastChargedPriceFen;
  final int paidUntil;
  final String status;

  /// 订阅者已授权用于自动续费的价格；创作者改价后据此提示重新签名。
  final BigInt authorizedPriceFen;

  /// 挂起原因：`needReconsent` / `insufficientBalance` /
  /// `identityBindingUnavailable` / `null`（非挂起态）。
  final String? suspendReason;

  /// Active 与已签名取消但仍在已付周期内的 Cancelled 都继续提供权益；
  /// suspended / issuerPaused 暂停期无权益。
  bool isEffectiveAt(int chainNowMs) =>
      (status == 'active' || status == 'cancelled') && chainNowMs < paidUntil;
}

/// 同一 finalized 区块上的订阅状态与共识时间戳，避免本机时钟参与权益判断。
class FinalizedSubscriptionSnapshot {
  const FinalizedSubscriptionSnapshot({
    required this.state,
    required this.chainNowMs,
    required this.block,
  });

  final ChainSubscriptionState? state;
  final int chainNowMs;
  final CitizenBlockRef block;

  String get blockHashHex => block.hash;
}

/// finalized `CreatorPlans` 中的单个链上付款档位。
class ChainCreatorTier {
  const ChainCreatorTier({
    required this.tierId,
    required this.tierName,
    required this.pricesFen,
  });

  final String tierId;

  /// runtime 升级前已经存在的付款计划可能暂时没有链上名称。
  final String? tierName;
  final Map<String, BigInt> pricesFen;
}

/// 一次账户签名交易 finalized 后的最小定位；Cloudflare 按哈希从该区块取得交易。
typedef FinalizedSubscriptionTransaction = ({
  String txHash,
  int usedNonce,
  String blockHashHex,
});

/// SquarePost 订阅 SCALE 与标准热钱包 extrinsic 入口。
///
/// CitizenApp 只提交需要账户签名的订阅、取消、换档和创作者档位管理。首次扣款后的
/// 真实公历到期时间及后续自动扣款全部由 runtime 根据共识时间戳完成。
class SubscriptionChain {
  const SubscriptionChain({
    required CitizenChain chain,
    required CitizenTransactions transactions,
  })  : _chain = chain,
        _transactions = transactions;

  final CitizenChain _chain;
  final CitizenTransactions _transactions;

  static const int _squarePostPalletIndex = PalletRegistry.squarePostPallet;
  static const int _subscribeCallIndex = PalletRegistry.subscribeCall;
  static const int _cancelCallIndex = PalletRegistry.cancelSubscriptionCall;
  static const int _setCreatorPlansCallIndex =
      PalletRegistry.setCreatorPlansCall;
  static const int _changePlanCallIndex =
      PalletRegistry.changeSubscriptionPlanCall;
  static const int _updateCreatorTierNameCallIndex =
      PalletRegistry.updateCreatorTierNameCall;

  static const int _issuerPlatformTag = 0;
  static const int _issuerCreatorTag = 1;
  static const int _planPlatformTag = 0;
  static const int _planCreatorTag = 1;

  static int membershipLevelByte(String level) => switch (level) {
        'freedom' => 0,
        'democracy' => 1,
        'spark' => 2,
        _ => throw ArgumentError('未知平台会员档：$level'),
      };

  static int billingPeriodByte(String period) => switch (period) {
        'monthly' => 0,
        'quarterly' => 1,
        'yearly' => 2,
        _ => throw ArgumentError('未知订阅周期：$period'),
      };

  Future<FinalizedSubscriptionTransaction> subscribePlatform({
    required Uint8List signerPublicKey,
    required String level,
    required BigInt expectedPriceFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildSubscribePlatformCall(
          membershipLevelByte(level),
          expectedPriceFen,
        ),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  Future<FinalizedSubscriptionTransaction> subscribeCreator({
    required Uint8List signerPublicKey,
    required String creatorCidNumber,
    required String tierId,
    required String billingPeriod,
    required BigInt expectedPriceFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildSubscribeCreatorCall(
          creatorCidNumber,
          tierId,
          billingPeriod,
          expectedPriceFen,
        ),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  Future<FinalizedSubscriptionTransaction> cancelPlatform({
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildCancelPlatformCall(),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  Future<FinalizedSubscriptionTransaction> cancelCreator({
    required Uint8List signerPublicKey,
    required String creatorCidNumber,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildCancelCreatorCall(creatorCidNumber),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  Future<FinalizedSubscriptionTransaction> changePlatformPlan({
    required Uint8List signerPublicKey,
    required String level,
    required BigInt expectedPriceFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildChangePlatformPlanCall(
          membershipLevelByte(level),
          expectedPriceFen,
        ),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  Future<FinalizedSubscriptionTransaction> changeCreatorPlan({
    required Uint8List signerPublicKey,
    required String creatorCidNumber,
    required String tierId,
    required String billingPeriod,
    required BigInt expectedPriceFen,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildChangeCreatorPlanCall(
          creatorCidNumber,
          tierId,
          billingPeriod,
          expectedPriceFen,
        ),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  /// 创作者一次签名覆盖链上付款档位；Cloudflare 保存展示字段时不得再索要业务签名。
  Future<FinalizedSubscriptionTransaction> setCreatorPlans({
    required Uint8List signerPublicKey,
    required List<CreatorTierInput> tiers,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildSetCreatorPlansCall(tiers),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  /// 只更新既有档位名称，不改变价格、订阅授权或续费状态。
  Future<FinalizedSubscriptionTransaction> updateCreatorTierName({
    required Uint8List signerPublicKey,
    required String tierId,
    required String tierName,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) =>
      _submitFinalized(
        callData: buildUpdateCreatorTierNameCall(tierId, tierName),
        signerPublicKey: signerPublicKey,
        externalSigning: externalSigning,
      );

  /// 在同一个 finalized 区块读取订阅真态与 `Timestamp.Now`。
  Future<FinalizedSubscriptionSnapshot> fetchSubscriptionSnapshot({
    required String subscriberCidNumber,
    String? creatorCidNumber,
  }) async {
    final block = await _chain.getFinalizedHead();
    final subscriptionKey = buildSubscriptionStorageKey(
      subscriberCidNumber,
      creatorCidNumber,
    );
    final timestampKey = buildStorageValueKey('Timestamp', 'Now');
    final values = await _chain.getStorageBatch(
      block,
      <Uint8List>[subscriptionKey, timestampKey],
    );
    final timestamp = values[1];
    if (timestamp == null || timestamp.length != 8) {
      throw const FormatException('finalized Timestamp.Now 缺失或编码不合法');
    }
    return FinalizedSubscriptionSnapshot(
      state: values[0] == null ? null : decodeSubscriptionState(values[0]!),
      chainNowMs: _readUnsignedLittleEndian(timestamp, 0, 8).toInt(),
      block: block,
    );
  }

  /// 在同一个 finalized 区块读取创作者付款档位及其链上名称。
  Future<List<ChainCreatorTier>> fetchCreatorPlans(
    String creatorCidNumber,
  ) async {
    final block = await _chain.getFinalizedHead();
    return fetchCreatorPlansAtBlock(creatorCidNumber, block);
  }

  /// 在调用方已经确认的 finalized 区块读取创作者档位。
  ///
  /// 创作者页先在某一 finalized 区块读取会员资格，再把同一区块哈希传入本方法，避免
  /// 页面刷新期间重复取区块头，或把两个不同高度的会员态和创作者档位拼成一个快照。
  Future<List<ChainCreatorTier>> fetchCreatorPlansAtBlock(
    String creatorCidNumber,
    CitizenBlockRef block,
  ) async {
    final key = buildCreatorPlansStorageKey(creatorCidNumber);
    final data = await _chain.getStorage(block, key);
    if (data == null) return const <ChainCreatorTier>[];
    final priceTiers = decodeCreatorPlans(data);
    final encodedNames = await _chain.getStorageBatch(
      block,
      <Uint8List>[
        for (final tier in priceTiers)
          buildCreatorTierNameStorageKey(creatorCidNumber, tier.tierId),
      ],
    );
    return List.unmodifiable([
      for (var index = 0; index < priceTiers.length; index++)
        ChainCreatorTier(
          tierId: priceTiers[index].tierId,
          tierName: encodedNames[index] == null
              ? null
              : decodeCreatorTierName(encodedNames[index]!),
          pricesFen: priceTiers[index].pricesFen,
        ),
    ]);
  }

  Future<FinalizedSubscriptionTransaction> _submitFinalized({
    required Uint8List callData,
    required Uint8List signerPublicKey,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    ) externalSigning,
  }) async {
    final prepared = await _transactions.prepareTransaction(
      signerPublicKey,
      callData,
    );
    final started = await _transactions.executePreparedTransaction(
      prepared.preparationId,
    );
    CitizenTransactionExecutionCompleted completed;
    if (started is CitizenTransactionExternalSigningPending) {
      final response = await externalSigning(started);
      if (response == null) {
        await _transactions.cancelPreparedTransactionExecution(
          started.executionId,
        );
        throw StateError('订阅交易签名已取消');
      }
      completed = await _transactions.consumePreparedTransactionQrResponse(
        started.executionId,
        response,
      );
    } else {
      completed = started as CitizenTransactionExecutionCompleted;
    }
    if (completed.resolution !=
            CitizenTransactionResolution.finalizedSuccess ||
        completed.execution == null) {
      throw StateError(completed.poolRejectionReason ?? '订阅交易执行失败');
    }
    return (
      txHash: _hexPrefixed(completed.transactionHash),
      usedNonce: prepared.nonce.toInt(),
      blockHashHex: completed.execution!.block.hash,
    );
  }

  static Uint8List buildSubscribePlatformCall(
    int levelByte,
    BigInt expectedPriceFen,
  ) {
    final output = _call(_subscribeCallIndex)
      ..pushByte(_issuerPlatformTag)
      ..pushByte(_planPlatformTag)
      ..pushByte(levelByte)
      ..write(_u128LittleEndian(expectedPriceFen));
    return output.toBytes();
  }

  static Uint8List buildSubscribeCreatorCall(
    String creatorCidNumber,
    String tierId,
    String billingPeriod,
    BigInt expectedPriceFen,
  ) {
    final output = _call(_subscribeCallIndex);
    _writeCreatorIssuerAndPlan(output, creatorCidNumber, tierId, billingPeriod);
    output.write(_u128LittleEndian(expectedPriceFen));
    return output.toBytes();
  }

  static Uint8List buildCancelPlatformCall() =>
      (_call(_cancelCallIndex)..pushByte(_issuerPlatformTag)).toBytes();

  static Uint8List buildCancelCreatorCall(String creatorCidNumber) {
    final output = _call(_cancelCallIndex)..pushByte(_issuerCreatorTag);
    _writeCidNumber(output, creatorCidNumber);
    return output.toBytes();
  }

  static Uint8List buildChangePlatformPlanCall(
    int levelByte,
    BigInt expectedPriceFen,
  ) =>
      (_call(_changePlanCallIndex)
            ..pushByte(_issuerPlatformTag)
            ..pushByte(_planPlatformTag)
            ..pushByte(levelByte)
            ..write(_u128LittleEndian(expectedPriceFen)))
          .toBytes();

  static Uint8List buildChangeCreatorPlanCall(
    String creatorCidNumber,
    String tierId,
    String billingPeriod,
    BigInt expectedPriceFen,
  ) {
    final output = _call(_changePlanCallIndex);
    _writeCreatorIssuerAndPlan(output, creatorCidNumber, tierId, billingPeriod);
    output.write(_u128LittleEndian(expectedPriceFen));
    return output.toBytes();
  }

  static Uint8List buildSetCreatorPlansCall(List<CreatorTierInput> tiers) {
    final output = _call(_setCreatorPlansCallIndex);
    _writeCompactLength(output, tiers.length);
    for (final tier in tiers) {
      _writeBytes(output, Uint8List.fromList(tier.tierId.codeUnits));
      _writeTierName(output, tier.tierName);
      _writeCompactLength(output, tier.pricesFen.length);
      for (final price in tier.pricesFen) {
        output.pushByte(billingPeriodByte(price.billingPeriod));
        output.write(_u128LittleEndian(price.priceFen));
      }
    }
    return output.toBytes();
  }

  @visibleForTesting
  static Uint8List buildUpdateCreatorTierNameCall(
    String tierId,
    String tierName,
  ) {
    final output = _call(_updateCreatorTierNameCallIndex);
    _writeBytes(output, Uint8List.fromList(tierId.codeUnits));
    _writeTierName(output, tierName);
    return output.toBytes();
  }

  static ByteOutput _call(int callIndex) => ByteOutput()
    ..pushByte(_squarePostPalletIndex)
    ..pushByte(callIndex);

  static void _writeCreatorIssuerAndPlan(
    ByteOutput output,
    String creatorCidNumber,
    String tierId,
    String billingPeriod,
  ) {
    output.pushByte(_issuerCreatorTag);
    _writeCidNumber(output, creatorCidNumber);
    output.pushByte(_planCreatorTag);
    _writeBytes(output, Uint8List.fromList(tierId.codeUnits));
    output.pushByte(billingPeriodByte(billingPeriod));
  }

  static void _writeCidNumber(ByteOutput output, String cidNumber) {
    final bytes = Uint8List.fromList(utf8.encode(cidNumber));
    if (bytes.isEmpty || bytes.length > 32) {
      throw ArgumentError('cid_number 的 UTF-8 长度必须为 1-32 字节');
    }
    _writeCompactLength(output, bytes.length);
    output.write(bytes);
  }

  static Uint8List _encodedCidNumber(String cidNumber) {
    final output = ByteOutput();
    _writeCidNumber(output, cidNumber);
    return output.toBytes();
  }

  static void _writeBytes(ByteOutput output, Uint8List value) {
    if (value.isEmpty ||
        value.length > 32 ||
        value.any((byte) => byte > 0x7f)) {
      throw ArgumentError('tier_id 必须为 1-32 字节 ASCII');
    }
    _writeCompactLength(output, value.length);
    output.write(value);
  }

  static void _writeTierName(ByteOutput output, String tierName) {
    final bytes = Uint8List.fromList(utf8.encode(tierName));
    _validateTierName(tierName, bytes.length, _argumentTierName);
    _writeCompactLength(output, bytes.length);
    output.write(bytes);
  }

  static Never _argumentTierName(String message) =>
      throw ArgumentError(message);

  static Never _formatTierName(String message) =>
      throw FormatException(message);

  static void _validateTierName(
    String tierName,
    int byteLength,
    Never Function(String) fail,
  ) {
    if (tierName.isEmpty || tierName.trim() != tierName) {
      fail('tier_name 不得为空或含首尾空白');
    }
    if (tierName.runes.length > 20 || byteLength > 80) {
      fail('tier_name 最多 20 个 Unicode 标量且最多 80 个 UTF-8 字节');
    }
    if (tierName.runes.any(
      (value) => value <= 0x1f || (value >= 0x7f && value <= 0x9f),
    )) {
      fail('tier_name 不得含控制字符');
    }
  }

  static void _writeCompactLength(ByteOutput output, int length) {
    if (length < 0 || length >= 1 << 14) {
      throw ArgumentError('当前 SCALE 紧凑长度只接受 0-16383');
    }
    if (length < 1 << 6) {
      output.pushByte(length << 2);
      return;
    }
    final encoded = (length << 2) | 0x01;
    output
      ..pushByte(encoded & 0xff)
      ..pushByte(encoded >> 8);
  }

  static Uint8List _u128LittleEndian(BigInt value) {
    if (value <= BigInt.zero) throw ArgumentError('订阅金额必须大于 0');
    final out = Uint8List(16);
    var remaining = value;
    for (var index = 0; index < out.length; index++) {
      out[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    if (remaining != BigInt.zero) throw ArgumentError('金额超出 u128 范围');
    return out;
  }

  /// `Subscriptions[(subscriber, issuer)]` 的 Blake2_128Concat 单键布局。
  @visibleForTesting
  static Uint8List buildSubscriptionStorageKey(
    String subscriberCidNumber,
    String? creatorCidNumber,
  ) {
    final raw = BytesBuilder(copy: false)
      ..add(_encodedCidNumber(subscriberCidNumber))
      ..addByte(
        creatorCidNumber == null ? _issuerPlatformTag : _issuerCreatorTag,
      );
    if (creatorCidNumber != null) {
      raw.add(_encodedCidNumber(creatorCidNumber));
    }
    return _storageMapKey('SquarePost', 'Subscriptions', raw.takeBytes());
  }

  /// `CreatorPlans[creator_cid_number]` 的 Blake2_128Concat 单键布局。
  @visibleForTesting
  static Uint8List buildCreatorPlansStorageKey(String creatorCidNumber) =>
      _storageMapKey(
        'SquarePost',
        'CreatorPlans',
        _encodedCidNumber(creatorCidNumber),
      );

  /// `CreatorTierNames[creator_cid_number][tier_id]` 的双 Blake2_128Concat 布局。
  @visibleForTesting
  static Uint8List buildCreatorTierNameStorageKey(
    String creatorCidNumber,
    String tierId,
  ) {
    final encodedTierId = ByteOutput();
    _writeBytes(encodedTierId, Uint8List.fromList(tierId.codeUnits));
    return _storageDoubleMapKey(
      'SquarePost',
      'CreatorTierNames',
      _encodedCidNumber(creatorCidNumber),
      encodedTierId.toBytes(),
    );
  }

  @visibleForTesting
  static Uint8List buildStorageValueKey(String pallet, String storage) =>
      Uint8List.fromList([
        ...Hasher.twoxx128.hashString(pallet),
        ...Hasher.twoxx128.hashString(storage),
      ]);

  static Uint8List _storageMapKey(
    String pallet,
    String storage,
    Uint8List keyData,
  ) =>
      Uint8List.fromList([
        ...buildStorageValueKey(pallet, storage),
        ...Hasher.blake2b128.hash(keyData),
        ...keyData,
      ]);

  static Uint8List _storageDoubleMapKey(
    String pallet,
    String storage,
    Uint8List firstKeyData,
    Uint8List secondKeyData,
  ) =>
      Uint8List.fromList([
        ...buildStorageValueKey(pallet, storage),
        ...Hasher.blake2b128.hash(firstKeyData),
        ...firstKeyData,
        ...Hasher.blake2b128.hash(secondKeyData),
        ...secondKeyData,
      ]);

  /// 严格解码 `SubscriptionState`；截断、非法枚举和尾随字节直接报错，禁止降级成无订阅。
  @visibleForTesting
  static ChainSubscriptionState decodeSubscriptionState(Uint8List data) {
    final reader = _ScaleReader(data);
    final plan = _readPlan(reader);
    final startedAt = reader.u64();
    final lastChargedAt = reader.u64();
    final lastChargedPriceFen = reader.u128();
    final paidUntil = reader.u64();
    final status = switch (reader.byte()) {
      0 => 'active',
      1 => 'cancelled',
      2 => 'terminated',
      3 => 'suspended',
      4 => 'issuerPaused',
      _ => throw const FormatException('subscription_status 枚举不合法'),
    };
    final authorizedPriceFen = reader.u128();
    final suspendTag = reader.byte();
    final String? suspendReason;
    if (suspendTag == 0) {
      suspendReason = null;
    } else if (suspendTag == 1) {
      suspendReason = switch (reader.byte()) {
        0 => 'needReconsent',
        1 => 'insufficientBalance',
        2 => 'identityBindingUnavailable',
        _ => throw const FormatException('suspend_reason 枚举不合法'),
      };
    } else {
      throw const FormatException('suspend_reason Option 枚举不合法');
    }
    reader.requireEnd();
    if (paidUntil <= lastChargedAt) {
      throw const FormatException('paid_until 必须晚于最近扣款时间');
    }
    return ChainSubscriptionState(
      plan: plan,
      startedAt: startedAt,
      lastChargedAt: lastChargedAt,
      lastChargedPriceFen: lastChargedPriceFen,
      paidUntil: paidUntil,
      status: status,
      authorizedPriceFen: authorizedPriceFen,
      suspendReason: suspendReason,
    );
  }

  /// 严格解码 `CreatorTiers`；价格、周期和 tier_id 全部来自 finalized 链上真态。
  @visibleForTesting
  static List<ChainCreatorTier> decodeCreatorPlans(Uint8List data) {
    final reader = _ScaleReader(data);
    final count = reader.compactLength(max: 10, allowZero: true);
    final tiers = <ChainCreatorTier>[];
    final tierIds = <String>{};
    for (var index = 0; index < count; index++) {
      final tierId = reader.ascii(maxLength: 32);
      if (!tierIds.add(tierId)) {
        throw const FormatException('链上 creator tier_id 重复');
      }
      final priceCount = reader.compactLength(max: 3);
      final prices = <String, BigInt>{};
      for (var priceIndex = 0; priceIndex < priceCount; priceIndex++) {
        final period = switch (reader.byte()) {
          0 => 'monthly',
          1 => 'quarterly',
          2 => 'yearly',
          _ => throw const FormatException('billing_period 枚举不合法'),
        };
        final price = reader.u128();
        if (price <= BigInt.zero || prices.containsKey(period)) {
          throw const FormatException('链上创作者周期价格不合法');
        }
        prices[period] = price;
      }
      tiers.add(
        ChainCreatorTier(tierId: tierId, tierName: null, pricesFen: prices),
      );
    }
    reader.requireEnd();
    return List.unmodifiable(tiers);
  }

  /// 严格解码独立 `CreatorTierNames` storage；缺失由调用方表达为 null。
  @visibleForTesting
  static String decodeCreatorTierName(Uint8List data) {
    final reader = _ScaleReader(data);
    final tierName = reader.utf8String(maxByteLength: 80);
    reader.requireEnd();
    _validateTierName(tierName, utf8.encode(tierName).length, _formatTierName);
    return tierName;
  }

  static ChainSubscriptionPlan _readPlan(_ScaleReader reader) {
    final tag = reader.byte();
    if (tag == _planPlatformTag) {
      final level = switch (reader.byte()) {
        0 => 'freedom',
        1 => 'democracy',
        2 => 'spark',
        _ => throw const FormatException('membership_level 枚举不合法'),
      };
      return ChainSubscriptionPlan.platform(level);
    }
    if (tag == _planCreatorTag) {
      final tierId = reader.ascii(maxLength: 32);
      final period = switch (reader.byte()) {
        0 => 'monthly',
        1 => 'quarterly',
        2 => 'yearly',
        _ => throw const FormatException('billing_period 枚举不合法'),
      };
      return ChainSubscriptionPlan.creator(tierId, period);
    }
    throw const FormatException('subscription plan 枚举不合法');
  }

  static BigInt _readUnsignedLittleEndian(
    Uint8List data,
    int offset,
    int length,
  ) {
    if (offset < 0 || length < 0 || offset + length > data.length) {
      throw const FormatException('无符号整数 SCALE 数据截断');
    }
    var value = BigInt.zero;
    for (var index = length - 1; index >= 0; index--) {
      value = (value << 8) | BigInt.from(data[offset + index]);
    }
    return value;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static String _hexPrefixed(Uint8List bytes) => '0x${_hex(bytes)}';
}

class _ScaleReader {
  _ScaleReader(this.data);

  final Uint8List data;
  int offset = 0;

  int byte() {
    if (offset >= data.length) throw const FormatException('SCALE 数据截断');
    return data[offset++];
  }

  int compactLength({required int max, bool allowZero = false}) {
    final first = byte();
    final mode = first & 0x03;
    final int length;
    if (mode == 0) {
      length = first >> 2;
    } else if (mode == 1) {
      length = ((byte() << 8) | first) >> 2;
      if (length < 1 << 6) {
        throw const FormatException('SCALE 紧凑长度不是最短编码');
      }
    } else {
      throw const FormatException('紧凑长度编码超出当前协议边界');
    }
    if ((!allowZero && length == 0) || length > max) {
      throw const FormatException('紧凑长度不合法');
    }
    return length;
  }

  String ascii({required int maxLength}) {
    final length = compactLength(max: maxLength);
    if (offset + length > data.length) {
      throw const FormatException('SCALE 字节串截断');
    }
    final bytes = data.sublist(offset, offset + length);
    offset += length;
    if (bytes.any((value) => value > 0x7f)) {
      throw const FormatException('tier_id 必须为 ASCII');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }

  String utf8String({required int maxByteLength}) {
    final length = compactLength(max: maxByteLength);
    if (offset + length > data.length) {
      throw const FormatException('SCALE UTF-8 字节串截断');
    }
    final bytes = data.sublist(offset, offset + length);
    offset += length;
    return utf8.decode(bytes, allowMalformed: false);
  }

  int u64() =>
      SubscriptionChain._readUnsignedLittleEndian(data, _take(8), 8).toInt();

  BigInt u128() =>
      SubscriptionChain._readUnsignedLittleEndian(data, _take(16), 16);

  int _take(int length) {
    final start = offset;
    if (start + length > data.length) {
      throw const FormatException('SCALE 整数截断');
    }
    offset += length;
    return start;
  }

  void requireEnd() {
    if (offset != data.length) throw const FormatException('SCALE 存在尾随字节');
  }
}
