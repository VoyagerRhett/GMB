import 'dart:async';
import 'package:citizenapp/my/creator/creator_page.dart';
import 'package:citizenapp/my/creator/creator_service.dart';
import 'package:citizenapp/my/creator/models/creator_overview.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingCreatorService implements CreatorService {
  final Completer<CreatorPageData> completer = Completer<CreatorPageData>();

  @override
  Future<CreatorPageData> load({String? expectedCidNumber}) => completer.future;

  @override
  Future<CreatorDisplaySnapshot?> readDisplaySnapshot(String cidNumber) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 后台刷新失败不能清掉已经提交的首帧展示态。
class _FailingCreatorService implements CreatorService {
  int loadCalls = 0;

  @override
  Future<CreatorDisplaySnapshot?> readDisplaySnapshot(String cidNumber) async =>
      null;

  @override
  Future<CreatorPageData> load({String? expectedCidNumber}) async {
    loadCalls++;
    throw Exception('设备子钥签名校验失败');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SnapshotCreatorService extends _PendingCreatorService {
  _SnapshotCreatorService(this.snapshot);

  final CreatorDisplaySnapshot snapshot;

  @override
  Future<CreatorDisplaySnapshot?> readDisplaySnapshot(String cidNumber) async =>
      snapshot;
}

void main() {
  const cidNumber = 'CN220-CTZN2-100000001-2026';

  testWidgets('无会员首帧直接显示订阅门禁且不等待后台刷新', (tester) async {
    final service = _PendingCreatorService();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPage(
          service: service,
          initialCidNumber: cidNumber,
          initialMembershipDecision:
              MembershipDisplayDecision.inactiveConfirmed,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('创作者'), findsOneWidget);
    expect(find.text('去订阅平台会员'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.completer.complete(CreatorPageData.gated());
  });

  testWidgets('有会员首帧直接显示创作者页且不等待后台刷新', (tester) async {
    final service = _PendingCreatorService();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPage(
          service: service,
          initialCidNumber: cidNumber,
          initialMembershipDecision: MembershipDisplayDecision.activeConfirmed,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('我的创作者会员'), findsOneWidget);
    expect(find.text('已开通'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.completer.complete(
      CreatorPageData.active(
        plan: CreatorPlan.empty(cidNumber),
        overview: CreatorOverview.zero,
      ),
    );
  });

  testWidgets('无会员时只显示明确订阅门禁，不显示同步第三态', (tester) async {
    final service = _PendingCreatorService();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPage(
          service: service,
          initialCidNumber: cidNumber,
          initialMembershipDecision: MembershipDisplayDecision.inactiveConfirmed,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('去订阅平台会员'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.completer.complete(
      CreatorPageData.active(
        plan: CreatorPlan.empty(cidNumber),
        overview: CreatorOverview.zero,
      ),
    );
  });

  group('CreatorTier JSON', () {
    test('toJson/fromJson 往返（分口径）', () {
      const tier = CreatorTier(
        tierId: 't1',
        tierName: '铁杆粉丝',
        pricesFen: {
          BillingPeriod.monthly: 990,
          BillingPeriod.yearly: 9900,
        },
      );
      final json = tier.toJson();
      expect(json['prices_fen'], {'monthly': 990, 'yearly': 9900});

      final back = CreatorTier.fromJson(json);
      expect(back.tierId, 't1');
      expect(back.tierName, '铁杆粉丝');
      expect(back.priceFenOf(BillingPeriod.monthly), 990);
      expect(back.priceFenOf(BillingPeriod.yearly), 9900);
      expect(back.hasPeriod(BillingPeriod.quarterly), isFalse);
    });

    test('fromJson 丢弃非法/非正价格', () {
      final tier = CreatorTier.fromJson({
        'tier_id': 't2',
        'tier_name': 'x',
        'prices_fen': {'monthly': 0, 'quarterly': -5, 'yearly': 100, 'bad': 9},
      });
      expect(tier.hasPeriod(BillingPeriod.monthly), isFalse);
      expect(tier.hasPeriod(BillingPeriod.quarterly), isFalse);
      expect(tier.priceFenOf(BillingPeriod.yearly), 100);
    });
  });

  group('CreatorPlan', () {
    test('fromJson 解析档位列表', () {
      final plan = CreatorPlan.fromJson({
        'creator_cid_number': 'acc',
        'updated_at': 123,
        'tiers': [
          {
            'tier_id': 'a',
            'tier_name': '基础',
            'prices_fen': {'monthly': 500},
          },
        ],
      });
      expect(plan.creatorCidNumber, 'acc');
      expect(plan.updatedAt, 123);
      expect(plan.tiers, hasLength(1));
      expect(plan.tiers.first.priceFenOf(BillingPeriod.monthly), 500);
    });

    test('empty 构造无档位', () {
      final plan = CreatorPlan.empty('acc');
      expect(plan.isEmpty, isTrue);
      expect(CreatorPlan.maxTiers, 10);
    });
  });

  test('展示快照的新鲜度分别约束会员与创作者数据', () {
    const nowMs = 1000000;
    final gated = CreatorDisplaySnapshot(
      cidNumber: cidNumber,
      data: CreatorPageData.gated(),
      membershipFetchedAtMs: nowMs - 1000,
      creatorFetchedAtMs: 0,
    );
    expect(gated.isFresh(nowMs), isTrue, reason: '门禁态不需要创作者档位时间戳');

    final active = CreatorDisplaySnapshot(
      cidNumber: cidNumber,
      data: CreatorPageData.active(
        plan: CreatorPlan.empty(cidNumber),
        overview: CreatorOverview.zero,
      ),
      membershipFetchedAtMs: nowMs - 1000,
      creatorFetchedAtMs: 0,
    );
    expect(active.isFresh(nowMs), isFalse);
  });

  testWidgets('后台刷新失败保留有会员首帧且不插入等待或错误页', (tester) async {
    final service = _FailingCreatorService();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPage(
          service: service,
          initialCidNumber: cidNumber,
          initialMembershipDecision: MembershipDisplayDecision.activeConfirmed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.loadCalls, 1);
    expect(find.text('重试'), findsNothing);
    expect(find.text('已开通'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);
    expect(find.textContaining('设备子钥签名校验失败'), findsNothing);
  });

  testWidgets('本地创作者快照先于未完成远端请求显示真实档位', (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final service = _SnapshotCreatorService(
      CreatorDisplaySnapshot(
        cidNumber: cidNumber,
        data: CreatorPageData.active(
          plan: const CreatorPlan(
            creatorCidNumber: cidNumber,
            tiers: [
              CreatorTier(
                tierId: 'local',
                tierName: '本地会员档',
                pricesFen: {BillingPeriod.monthly: 990},
              ),
            ],
            updatedAt: 1,
          ),
          overview: const CreatorOverview(
            subscriberCount: 7,
            monthIncomeFen: 1234,
            tierCount: 1,
          ),
        ),
        membershipFetchedAtMs: nowMs,
        creatorFetchedAtMs: nowMs,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPage(
          service: service,
          initialCidNumber: cidNumber,
          initialMembershipDecision: MembershipDisplayDecision.activeConfirmed,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('本地会员档'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);
  });
}
