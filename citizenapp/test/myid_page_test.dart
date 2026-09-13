import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/my/myid/myid_page.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

const MyIdState _votingState = MyIdState(
  tier: MyIdTier.voting,
  status: MyIdStatus.normal,
  votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
  cidNumber: 'CID-2026-0715',
  residenceDistrict: '中枢省 · 固市 · 和平镇',
  passportValidFrom: '2026-07-15',
  passportValidUntil: '2036-07-14',
);

const MyIdState _candidateState = MyIdState(
  tier: MyIdTier.candidate,
  status: MyIdStatus.normal,
  votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
  cidNumber: 'CID-2026-0715',
  residenceDistrict: '中枢省 · 固市 · 和平镇',
  passportValidFrom: '2026-07-15',
  passportValidUntil: '2036-07-14',
  familyName: '张',
  givenName: '三',
  citizenSexLabel: '男',
  birthDistrict: '中枢省 · 固市 · 和平镇',
  citizenBirthDate: '1992-05-18',
);

void main() {
  Finder card(MyIdTier tier) =>
      find.byKey(ValueKey<String>('passport-card-${tier.name}'));

  double cardTop(WidgetTester tester, MyIdTier tier) =>
      tester.getTopLeft(card(tier)).dy;

  Future<void> pumpPage(
    WidgetTester tester,
    MyIdState state, {
    Size? surfaceSize,
  }) async {
    if (surfaceSize != null) {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(home: MyIdPage(myIdService: _FakeMyIdService(state))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('三张身份卡始终存在且旧访客文案彻底删除', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));

    expect(find.text('身份·访客'), findsOneWidget);
    expect(find.text('公民身份 · 投票'), findsOneWidget);
    expect(find.text('公民身份 · 竞选'), findsOneWidget);
    // 旧文案零残留
    expect(find.text('匿名访客'), findsNothing);
    expect(find.text('注册身份·访客'), findsNothing);
    expect(find.text('公民 · 投票身份'), findsNothing);
    expect(find.text('公民 · 竞选身份'), findsNothing);
    expect(find.text('没有公民身份信息'), findsNothing);
    // 访客卡改用“匿名”小标签替代整段空态
    expect(find.byKey(const ValueKey<String>('passport-anonymous-tag')),
        findsOneWidget);
    expect(find.text('匿名'), findsOneWidget);
  });

  testWidgets('访客当前卡排第一且公民卡只显示字段名称', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));

    expect(cardTop(tester, MyIdTier.visitor),
        lessThan(cardTop(tester, MyIdTier.voting)));
    expect(cardTop(tester, MyIdTier.voting),
        lessThan(cardTop(tester, MyIdTier.candidate)));
    // 纯访客(无 CID)当前卡置顶但不挂「当前身份」徽章。
    expect(find.text('当前身份'), findsNothing);
    expect(find.byKey(const ValueKey<String>('current-identity-visitor')),
        findsNothing);
    expect(find.text('投票账户'), findsNWidgets(2));
    expect(find.text('公民姓名'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('投票身份卡置顶并且只有该卡显示真实值', (tester) async {
    await pumpPage(tester, _votingState);

    expect(cardTop(tester, MyIdTier.voting),
        lessThan(cardTop(tester, MyIdTier.visitor)));
    expect(cardTop(tester, MyIdTier.visitor),
        lessThan(cardTop(tester, MyIdTier.candidate)));
    expect(find.byKey(const ValueKey<String>('current-identity-voting')),
        findsOneWidget);
    expect(find.text('当前身份'), findsOneWidget);
    expect(find.text('w5BekTim…vMgf7o8E'), findsOneWidget);
    expect(find.text('CID-2026-0715'), findsOneWidget);
    expect(find.text('中枢省 · 固市 · 和平镇'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(find.text('2026年07月15日 至 2036年07月14日'), findsOneWidget);

    final candidateCard = card(MyIdTier.candidate);
    expect(
      find.descendant(of: candidateCard, matching: find.text('公民姓名')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidateCard, matching: find.text('CID-2026-0715')),
      findsNothing,
    );
  });

  testWidgets('竞选身份卡置顶并显示九项真实字段，投票卡不重复数据', (tester) async {
    await pumpPage(tester, _candidateState);

    expect(cardTop(tester, MyIdTier.candidate),
        lessThan(cardTop(tester, MyIdTier.visitor)));
    expect(cardTop(tester, MyIdTier.visitor),
        lessThan(cardTop(tester, MyIdTier.voting)));
    expect(find.byKey(const ValueKey<String>('current-identity-candidate')),
        findsOneWidget);
    expect(find.text('当前身份'), findsOneWidget);
    expect(find.text('w5BekTim…vMgf7o8E'), findsOneWidget);
    expect(find.text('CID-2026-0715'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('1992年05月18日'), findsOneWidget);

    final votingCard = card(MyIdTier.voting);
    expect(
      find.descendant(of: votingCard, matching: find.text('投票账户')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: votingCard, matching: find.text('CID-2026-0715')),
      findsNothing,
    );
    expect(
      find.descendant(of: votingCard, matching: find.text('w5BekTim…vMgf7o8E')),
      findsNothing,
    );
  });

  testWidgets('链读失败不降级访客，三卡都没有当前身份和真实值', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.visitor,
        status: MyIdStatus.queryFailed,
        errorMessage: '链上身份读取失败',
      ),
    );

    expect(find.text('链上身份读取失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('当前身份'), findsNothing);
    expect(find.text('身份·访客'), findsOneWidget);
    expect(find.text('注册身份·访客'), findsNothing);
    expect(find.text('公民身份 · 投票'), findsOneWidget);
    expect(find.text('公民身份 · 竞选'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('没有默认热钱包的纯访客不挂徽章但显示引导', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.visitor,
        errorMessage: '请先创建钱包',
      ),
    );

    expect(find.text('请先创建钱包'), findsOneWidget);
    // 纯访客(无 CID)不挂「当前身份」徽章。
    expect(find.byKey(const ValueKey<String>('current-identity-visitor')),
        findsNothing);
    expect(find.text('当前身份'), findsNothing);
    // 空态文案已删，访客卡改以“匿名”小标签呈现
    expect(find.text('没有公民身份信息'), findsNothing);
    expect(find.byKey(const ValueKey<String>('passport-anonymous-tag')),
        findsOneWidget);
  });

  testWidgets('过期和吊销只改变当前卡状态，不改变身份排序', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.voting,
        status: MyIdStatus.expired,
        votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
        cidNumber: 'CID-2026-0715',
        residenceDistrict: '中枢省 · 固市 · 和平镇',
        passportValidFrom: '2020-01-01',
        passportValidUntil: '2025-01-01',
      ),
    );

    expect(cardTop(tester, MyIdTier.voting),
        lessThan(cardTop(tester, MyIdTier.visitor)));
    expect(find.text('已过期'), findsOneWidget);
  });

  testWidgets('窄屏和长字段不会产生布局溢出', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.candidate,
        status: MyIdStatus.normal,
        votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
        cidNumber: 'CID-VERY-LONG-2026-0715-EXAMPLE',
        residenceDistrict: '中枢省 · 很长的城市名称 · 很长的乡镇名称',
        passportValidFrom: '2026-07-15',
        passportValidUntil: '2036-07-14',
        familyName: '这是一个用于验证窄屏自动换行的较长公民',
        givenName: '姓名',
        citizenSexLabel: '男',
        birthDistrict: '中枢省 · 很长的出生城市名称 · 很长的出生乡镇名称',
        citizenBirthDate: '1992-05-18',
      ),
      surfaceSize: const Size(320, 1600),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('公民身份 · 竞选'), findsOneWidget);
  });

  testWidgets('余额不足 → 不提交注册，先引导去链上充值', (tester) async {
    // 占号是自签自付的链上交易，余额不够连入池预检都过不了；先充值再注册。
    final service = _RegisterFlowService(balanceFen: 0);
    await tester.pumpWidget(MaterialApp(home: MyIdPage(myIdService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();

    expect(service.registerCalls, 0);
    expect(find.textContaining('余额不足'), findsOneWidget);
  });

  testWidgets('余额读取失败 → 既不提交也不跳充值，只提示重试(fail-closed)', (tester) async {
    final service = _RegisterFlowService(affordabilityThrows: true);
    await tester.pumpWidget(MaterialApp(home: MyIdPage(myIdService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();

    expect(service.registerCalls, 0);
    expect(find.textContaining('余额读取失败'), findsOneWidget);
    expect(find.text('链上充值'), findsNothing);
  });

  testWidgets('余额达标 → 正常提交注册', (tester) async {
    final service = _RegisterFlowService(balanceFen: 121);
    await tester.pumpWidget(MaterialApp(home: MyIdPage(myIdService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();

    expect(service.registerCalls, 1);
  });

  testWidgets('不出现已下线的登记、换钱包和扫码入口', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));
    expect(find.text('护照号'), findsNothing);
    expect(find.text('选择钱包'), findsNothing);
    expect(find.text('更换钱包'), findsNothing);
    expect(find.text('扫码签名'), findsNothing);
  });

  testWidgets('页面改名为「身份」,不再叫电子护照', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));
    expect(find.widgetWithText(AppBar, '身份'), findsOneWidget);
    expect(find.text('电子护照'), findsNothing);
  });

  testWidgets('纯访客右上是「注册」按钮,访客卡无 CID 行', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));
    expect(find.widgetWithText(TextButton, '注册'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '更换'), findsNothing);
    // 访客卡内不含 CID 行(其余卡的字段名不算)。
    expect(
      find.descendant(
        of: card(MyIdTier.visitor),
        matching: find.text('公民号'),
      ),
      findsNothing,
    );
  });

  testWidgets('匿名已注册:右上「更换」+ 访客卡显公民号,匿名标签仍在', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.visitor,
        votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
        cidNumber: 'CN000-CTZN1-000000001-2026',
      ),
    );
    expect(find.widgetWithText(TextButton, '更换'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '注册'), findsNothing);
    // 匿名已注册(有 CID)访客卡挂「当前身份」徽章。
    expect(find.text('当前身份'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('current-identity-visitor')),
        findsOneWidget);
    final visitorCard = card(MyIdTier.visitor);
    expect(
      find.descendant(of: visitorCard, matching: find.text('公民号')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: visitorCard,
        matching: find.text('CN000-CTZN1-000000001-2026'),
      ),
      findsOneWidget,
    );
    // 决策:不新增卡/色,访客卡仍是「身份·访客」+匿名标签。
    expect(find.byKey(const ValueKey<String>('passport-anonymous-tag')),
        findsOneWidget);
  });

  testWidgets('投票公民右上是「更换」按钮', (tester) async {
    await pumpPage(tester, _votingState);
    expect(find.widgetWithText(TextButton, '更换'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '注册'), findsNothing);
  });

  testWidgets('链读失败态右上不显示注册/更换按钮', (tester) async {
    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.visitor,
        status: MyIdStatus.queryFailed,
        errorMessage: '链上身份读取失败',
      ),
    );
    expect(find.widgetWithText(TextButton, '注册'), findsNothing);
    expect(find.widgetWithText(TextButton, '更换'), findsNothing);
  });

  testWidgets('身份卡 CID 字段统一显示「公民号」且完整保持单行', (tester) async {
    await pumpPage(tester, _votingState);
    final votingCard = card(MyIdTier.voting);
    final label = find.descendant(
      of: votingCard,
      matching: find.text('公民号'),
    );
    final value = find.descendant(
      of: votingCard,
      matching: find.text('CID-2026-0715'),
    );
    expect(label, findsOneWidget);
    final valueText = tester.widget<Text>(value);
    expect(valueText.maxLines, 1);
    expect(valueText.softWrap, isFalse);
    expect(
        tester.getTopLeft(value).dy, closeTo(tester.getTopLeft(label).dy, 1));
    expect(
      tester.getTopLeft(value).dx - tester.getTopRight(label).dx,
      lessThanOrEqualTo(8),
      reason: '公民号键值间距应保持紧凑',
    );
    expect(find.text('身份CID号'), findsNothing);
  });

  testWidgets('三类身份卡字段值紧随名称并保持左对齐', (tester) async {
    void expectCompactField(Finder identityCard, String label, String value) {
      final labelFinder = find.descendant(
        of: identityCard,
        matching: find.text(label),
      );
      final valueFinder = find.descendant(
        of: identityCard,
        matching: find.text(value),
      );
      expect(tester.widget<Text>(valueFinder).textAlign, TextAlign.left);
      final actualGap = tester.getTopLeft(valueFinder).dx -
          tester.getTopRight(labelFinder).dx;
      final expectedGap = AppLayout.scaled(tester.element(identityCard), 6);
      expect(actualGap, closeTo(expectedGap, 0.1));
    }

    await pumpPage(
      tester,
      const MyIdState(
        tier: MyIdTier.visitor,
        votingAccountId: 'w5BekTimvtfYZvFpkDzy7ypqUntPgTbjRFCt9weR8vMgf7o8E',
        cidNumber: 'CN000-CTZN1-000000001-2026',
      ),
    );
    expectCompactField(
      card(MyIdTier.visitor),
      '公民号',
      'CN000-CTZN1-000000001-2026',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, _votingState);
    expectCompactField(
      card(MyIdTier.voting),
      '公民号',
      'CID-2026-0715',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, _candidateState);
    expectCompactField(
      card(MyIdTier.candidate),
      '公民姓名',
      '张三',
    );
  });

  testWidgets('身份页支持下拉刷新', (tester) async {
    await pumpPage(tester, const MyIdState(tier: MyIdTier.visitor));
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}

/// 驱动注册前余额闸三分支的假 service：可配门槛、余额与链读失败。
class _RegisterFlowService implements MyIdService {
  _RegisterFlowService({
    this.balanceFen = 0,
    this.affordabilityThrows = false,
  });

  /// 门槛固定 121 分(链上最低费 10 + ED 111);本用例只驱动余额侧三分支。
  static const int requiredFen = 121;

  final int balanceFen;
  final bool affordabilityThrows;
  int registerCalls = 0;

  @override
  Future<MyIdState> getState() async => const MyIdState(tier: MyIdTier.visitor);

  @override
  Future<List<CitizenWalletStateAccount>> listBindableAccounts() async =>
      const <CitizenWalletStateAccount>[];

  @override
  Future<({BigInt balanceFen, BigInt requiredFen})>
      fetchRegistrationAffordability(String bindAccountId) async {
    if (affordabilityThrows) throw StateError('CitizenSDK 链状态未就绪');
    return (
      requiredFen: BigInt.from(requiredFen),
      balanceFen: BigInt.from(balanceFen),
    );
  }

  @override
  Future<String> registerAnonymousCid({
    required BuildContext? context,
    required String institution,
    String? bindAccountId,
  }) async {
    registerCalls++;
    return 'GD-CTZN1-8F3A2B';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMyIdService implements MyIdService {
  _FakeMyIdService(this.state);

  final MyIdState state;

  @override
  Future<MyIdState> getState() async => state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
