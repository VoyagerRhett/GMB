import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/profile/widgets/creator_subscribe_button.dart';
import 'package:citizenapp/8964/subscribe/creator_subscribe_service.dart';
import 'package:citizenapp/8964/services/square_api_client.dart'
    show SquareSession;
import 'package:citizenapp/my/creator/creator_api.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';

import 'fake_profile.dart';

/// 只覆盖订阅按钮的 CitizenServe 投影门禁：服务端返回有效档位才显示，其余隐藏。
class _FakeSubscribeService implements CreatorSubscribeService {
  _FakeSubscribeService({required this.view, this.throwView = false});

  final CreatorView view;
  final bool throwView;

  @override
  Future<CreatorView> fetchView(
    SquareSession session,
    String creatorCidNumber,
  ) async {
    if (throwView) throw const CreatorApiException('service unavailable');
    return view;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _plan = CreatorPlan.fromJson({
  'creator_cid_number': 'CN001-CTZN-000000001-2026',
  'tiers': [
    {
      'tier_id': 't1',
      'tier_name': '支持者',
      'prices_fen': {'monthly': 299},
    },
  ],
  'updated_at': 1,
});

CreatorSubscriptionState _activeCreatorSubscription() =>
    const CreatorSubscriptionState(
      tierId: 't1',
      billingPeriod: 'monthly',
      subscriptionStatus: 'active',
      paidUntil: 9999999999999,
      active: true,
    );

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool creatorActive,
    bool hasTiers = true,
    CreatorSubscriptionState? subscriberState,
    bool throwCreator = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorSubscribeButton(
            creatorCidNumber: 'CN001-CTZN-000000001-2026',
            service: _FakeSubscribeService(
              view: CreatorView(
                plan: creatorActive && hasTiers ? _plan : null,
                subscription: subscriberState,
              ),
              throwView: throwCreator,
            ),
            sessionProvider: FakeSessionProvider(fakeSession()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有档 且 创作者平台会员 active → 显示订阅按钮', (tester) async {
    await pump(tester, creatorActive: true);
    expect(find.text('订阅'), findsOneWidget);
  });

  testWidgets('已订阅时页头仍只显示单一入口，二级操作收入底部面板', (tester) async {
    await pump(
      tester,
      creatorActive: true,
      subscriberState: _activeCreatorSubscription(),
    );

    expect(find.text('订阅'), findsOneWidget);
    expect(find.text('更换会员档'), findsNothing);
    expect(find.text('取消订阅'), findsNothing);

    await tester.tap(find.text('订阅'));
    await tester.pumpAndSettle();

    expect(find.text('更换会员档'), findsOneWidget);
    expect(find.text('取消订阅'), findsOneWidget);
  });

  testWidgets('CitizenServe 不返回创作者有效档位时隐藏', (tester) async {
    await pump(tester, creatorActive: false);
    expect(find.text('订阅'), findsNothing);
  });

  testWidgets('CitizenServe 创作者投影读取失败时隐藏（fail-closed）', (tester) async {
    await pump(tester, creatorActive: true, throwCreator: true);
    expect(find.text('订阅'), findsNothing);
  });

  testWidgets('无档 → 隐藏（既有行为不回归）', (tester) async {
    await pump(tester, creatorActive: true, hasTiers: false);
    expect(find.text('订阅'), findsNothing);
  });
}
