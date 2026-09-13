import 'package:citizenapp/my/membership/subscription_chain.dart' show ChainCreatorTier;

/// 订阅周期。创作者每档可只开其中部分周期。
enum BillingPeriod { monthly, quarterly, yearly }

/// 周期与后端/链一致的字符串键（后端 D1 / 链上统一用这些值，不用枚举序号）。
extension BillingPeriodKey on BillingPeriod {
  String get key => switch (this) {
        BillingPeriod.monthly => 'monthly',
        BillingPeriod.quarterly => 'quarterly',
        BillingPeriod.yearly => 'yearly',
      };

  /// 展示用中文短名（前端展示层用）。
  String get label => switch (this) {
        BillingPeriod.monthly => '每月',
        BillingPeriod.quarterly => '每季',
        BillingPeriod.yearly => '每年',
      };

  static BillingPeriod? tryParse(String value) => switch (value) {
        'monthly' => BillingPeriod.monthly,
        'quarterly' => BillingPeriod.quarterly,
        'yearly' => BillingPeriod.yearly,
        _ => null,
      };
}

/// 创作者单个会员档：tier_id、tier_name 与周期价格均以 finalized 链状态为真源。
///
/// 价格一律以「分」为后端/链单一口径存储；展示与输入的「元」换算只发生在 UI 边界。

class CreatorTier {
  const CreatorTier({
    required this.tierId,
    required this.tierName,
    required this.pricesFen,
  });

  /// 档位稳定 id（CreatorPlans 链上引用；用于编辑、删除定位与订阅关联）。
  final String tierId;

  /// 档名（创作者自定义，如「铁杆粉丝」）。
  final String tierName;

  /// 各周期价（分，公民币）；由 finalized CreatorPlans 读取。
  final Map<BillingPeriod, int> pricesFen;

  bool hasPeriod(BillingPeriod period) => pricesFen.containsKey(period);

  int? priceFenOf(BillingPeriod period) => pricesFen[period];

  CreatorTier copyWith({String? tierName, Map<BillingPeriod, int>? pricesFen}) {
    return CreatorTier(
      tierId: tierId,
      tierName: tierName ?? this.tierName,
      pricesFen: pricesFen ?? this.pricesFen,
    );
  }

  Map<String, Object?> toJson() => {
        'tier_id': tierId,
        'tier_name': tierName,
        // 后端一律分：{'monthly': 990, 'yearly': 9900}
        'prices_fen': {
          for (final entry in pricesFen.entries) entry.key.key: entry.value,
        },
      };

  factory CreatorTier.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices_fen'];
    final prices = <BillingPeriod, int>{};
    if (rawPrices is Map) {
      for (final entry in rawPrices.entries) {
        final period = BillingPeriodKey.tryParse(entry.key.toString());
        final fen = entry.value;
        if (period != null && fen is int && fen > 0) {
          prices[period] = fen;
        }
      }
    }
    return CreatorTier(
      tierId: json['tier_id']?.toString() ?? '',
      tierName: json['tier_name']?.toString() ?? '',
      pricesFen: prices,
    );
  }
}

/// 仅以 finalized 链上档位构造业务态；Cloudflare 只提供投影时间等非授权元数据。
CreatorPlan mergeCreatorPlanWithChain({
  required String creatorCidNumber,
  required CreatorPlan? displayPlan,
  required List<ChainCreatorTier> chainTiers,
}) {
  final tiers = <CreatorTier>[];
  for (final tier in chainTiers) {
    final prices = <BillingPeriod, int>{};
    for (final entry in tier.pricesFen.entries) {
      final period = BillingPeriodKey.tryParse(entry.key);
      if (period != null) prices[period] = entry.value.toInt();
    }
    tiers.add(
      CreatorTier(
        tierId: tier.tierId,
        tierName: tier.tierName ?? '',
        pricesFen: prices,
      ),
    );
  }
  return CreatorPlan(
    creatorCidNumber: creatorCidNumber,
    tiers: List.unmodifiable(tiers),
    updatedAt: displayPlan?.updatedAt ?? 0,
  );
}

/// 创作者会员计划（一名创作者的全部档位，≤ [maxTiers]）。

class CreatorPlan {
  const CreatorPlan({
    required this.creatorCidNumber,
    required this.tiers,
    required this.updatedAt,
  });

  /// 创作者身份主键（CID 号，对齐 worker `creator_cid_number`）。
  final String creatorCidNumber;

  /// 有序档位集合，≤ [maxTiers]。
  final List<CreatorTier> tiers;

  /// Cloudflare 侧最近更新时间（unix 毫秒），仅展示与并发参考。
  final int updatedAt;

  /// 单创作者档位数量硬上限（客户端护栏，BFF 兜底）。
  static const int maxTiers = 10;

  bool get isEmpty => tiers.isEmpty;

  static CreatorPlan empty(String creatorCidNumber) => CreatorPlan(
        creatorCidNumber: creatorCidNumber,
        tiers: const [],
        updatedAt: 0,
      );

  List<Map<String, Object?>> tiersJson() =>
      tiers.map((tier) => tier.toJson()).toList(growable: false);

  factory CreatorPlan.fromJson(Map<String, dynamic> json) {
    final rawTiers = json['tiers'];
    final tiers = <CreatorTier>[];
    if (rawTiers is List) {
      for (final item in rawTiers) {
        if (item is Map<String, dynamic>) {
          tiers.add(CreatorTier.fromJson(item));
        }
      }
    }
    return CreatorPlan(
      creatorCidNumber: json['creator_cid_number']?.toString() ?? '',
      tiers: tiers,
      updatedAt: json['updated_at'] is int ? json['updated_at'] as int : 0,
    );
  }
}
