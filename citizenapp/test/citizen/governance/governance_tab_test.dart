// 治理 tab 视图(ADR-028 P2)测试 —— 替代旧 governance_list_page_test。
// 机构改由统一目录按机构码加载(注入 seeded fake 仓库),分组/折叠/拖拽 UI 保持。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/citizen/governance/governance_tab.dart';
import 'package:citizenapp/citizen/governance/whitepaper_page.dart';
import 'package:citizenapp/citizen/citizen_tab_page.dart';
import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/legislation/legislation_tab.dart';
import 'package:citizenapp/citizen/public/data/public_institution_dto.dart';
import 'package:citizenapp/citizen/public/data/public_institution_repository.dart';
import 'package:citizenapp/ui/app_layout.dart';
import '../public/fake_public_institution_store.dart';
import '../../support/isar_test_env.dart';

/// 构造统一机构(helper 纯函数测试用)。
Institution _inst(String name, String cid, String code) => Institution(
  cidNumber: cid,
  cidFullName: name,
  cidShortName: name,
  institutionCode: code,
);

PublicInstitutionDto _dto(String name, String cid, String code) =>
    PublicInstitutionDto.fromJson(<String, dynamic>{
      'cid_number': cid,
      'cid_full_name': name,
      'cid_short_name': name,
      'institution_code': code,
      'province_code': '',
      'city_code': '',
      'account_count': 1,
    });

class _PendingInstitutionRepository extends InstitutionRepository {
  _PendingInstitutionRepository(PublicInstitutionRepository directory)
    : super(directory: directory);

  final Completer<List<Institution>> completer = Completer<List<Institution>>();

  @override
  Future<List<Institution>> listByCodes(Set<String> institutionCodes) =>
      completer.future;
}

class _FakeGovernanceInstitutionOrderStore
    extends GovernanceInstitutionOrderStore {
  _FakeGovernanceInstitutionOrderStore({this.councils = const <String>[]});

  List<String> councils;
  List<String> banks = const <String>[];

  @override
  Future<GovernanceInstitutionOrder> read() async => GovernanceInstitutionOrder(
    provincialCouncilCidNumbers: councils,
    provincialBankCidNumbers: banks,
  );

  @override
  Future<void> writeProvincialCouncilCidNumbers(List<String> cidNumbers) async {
    councils = List<String>.of(cidNumbers);
  }

  @override
  Future<void> writeProvincialBankCidNumbers(List<String> cidNumbers) async {
    banks = List<String>.of(cidNumbers);
  }
}

/// seeded fake 仓库:目录按机构码返回 NRC/PRC/PRB 测试机构。
Future<InstitutionRepository> _buildRepo({
  required List<({String name, String cid})> councils,
  required List<({String name, String cid})> banks,
}) async {
  final store = FakePublicInstitutionStore();
  await store.upsertInstitutions([
    _dto('国家储备委员会', 'nrc', 'NRC'),
    for (final c in councils) _dto(c.name, c.cid, 'PRC'),
    for (final b in banks) _dto(b.name, b.cid, 'PRB'),
  ], catalogVersion: 'v');
  return InstitutionRepository(
    directory: PublicInstitutionRepository(store: store),
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<({String name, String cid})> councils,
  required List<({String name, String cid})> banks,
  GovernanceInstitutionOrderStore? orderStore,
  WidgetBuilder? whitepaperPageBuilder,
  double width = 420,
}) async {
  final repo = await _buildRepo(councils: councils, banks: banks);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 900,
          child: GovernanceTab(
            repository: repo,
            orderStore: orderStore ?? _FakeGovernanceInstitutionOrderStore(),
            whitepaperPageBuilder: whitepaperPageBuilder,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  useIsolatedIsar();
  late List<({String name, String cid})> councils;
  late List<({String name, String cid})> banks;

  setUp(() {
    councils = const [
      (name: '甲省储委会', cid: 'prc-a'),
      (name: '乙省储委会', cid: 'prc-b'),
      (name: '丙省储委会', cid: 'prc-c'),
    ];
    banks = const [(name: '甲省储行', cid: 'prb-a'), (name: '乙省储行', cid: 'prb-b')];
  });

  test('applyGovernanceInstitutionOrder 使用本机顺序并把新增机构补到末尾', () {
    final source = [
      _inst('甲省储委会', 'prc-a', 'PRC'),
      _inst('乙省储委会', 'prc-b', 'PRC'),
      _inst('丙省储委会', 'prc-c', 'PRC'),
    ];
    final ordered = applyGovernanceInstitutionOrder(source, const [
      'prc-b',
      'missing',
      'prc-a',
      'prc-b',
    ]);
    expect(ordered.map((i) => i.cidNumber), ['prc-b', 'prc-a', 'prc-c']);
  });

  testWidgets('公民首页删除重复标题并把五段导航上移', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 390,
          height: 844,
          child: CitizenTabPage(proposalContent: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('公民'), findsNothing);
    for (final label in ['提案', '立法', '选举', '治理', '公权']) {
      expect(find.text(label), findsOneWidget);
    }
    // 二级导航进入原页面标题区域，不再被“公民”标题占据一整行。
    expect(tester.getTopLeft(find.text('提案')).dy, lessThan(45));
    expect(find.text('提案动态'), findsOneWidget);
    expect(find.text('待我投票 0'), findsOneWidget);
  });

  test('reorderGovernanceInstitutions 按拖拽目标位置重排', () {
    final source = [
      _inst('甲省储委会', 'prc-a', 'PRC'),
      _inst('乙省储委会', 'prc-b', 'PRC'),
      _inst('丙省储委会', 'prc-c', 'PRC'),
    ];
    final reordered = reorderGovernanceInstitutions(source, 0, 2);
    expect(reordered.map((i) => i.cidNumber), ['prc-b', 'prc-c', 'prc-a']);
  });

  test('GovernanceInstitutionOrderStore 在 UserIsar 保存两类用户顺序', () async {
    const store = GovernanceInstitutionOrderStore();
    await store.writeProvincialCouncilCidNumbers(const ['prc-b', 'prc-a']);
    await store.writeProvincialBankCidNumbers(const ['prb-b', 'prb-a']);

    final order = await store.read();
    expect(order.provincialCouncilCidNumbers, ['prc-b', 'prc-a']);
    expect(order.provincialBankCidNumbers, ['prb-b', 'prb-a']);
  });

  testWidgets('目录未返回时直接显示治理结构且不使用整页转圈', (tester) async {
    final repository = _PendingInstitutionRepository(
      PublicInstitutionRepository(store: FakePublicInstitutionStore()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 900,
            child: GovernanceTab(
              repository: repository,
              orderStore: _FakeGovernanceInstitutionOrderStore(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('治理机构'), findsNothing);
    expect(find.text('《公民链白皮书》'), findsOneWidget);
    expect(find.text('正在读取治理机构'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('governance_national_card_placeholder')),
      findsOneWidget,
    );
    expect(find.text('省储委会（0）'), findsOneWidget);
    expect(find.text('省储行（0）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('governance-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('白皮书与国家储委会位于同一行且等宽等高', (tester) async {
    await _pumpPage(tester, councils: councils, banks: banks);

    final whitepaper = find.byKey(
      const ValueKey<String>('citizen-whitepaper-card'),
    );
    final national = find.byKey(const ValueKey('governance_national_card_nrc'));
    expect(whitepaper, findsOneWidget);
    expect(find.text('《公民链白皮书》'), findsOneWidget);
    expect(find.text('《链白皮书》'), findsNothing);
    final whitepaperTitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('citizen-whitepaper-title')),
    );
    expect(whitepaperTitle.maxLines, 1);
    expect(whitepaperTitle.softWrap, isFalse);
    final titleFittedBox = tester.widget<FittedBox>(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('citizen-whitepaper-title')),
        matching: find.byType(FittedBox),
      ),
    );
    expect(titleFittedBox.fit, BoxFit.scaleDown);
    expect(find.text('治理机构'), findsNothing);
    expect(
      tester.getTopLeft(whitepaper).dy,
      closeTo(tester.getTopLeft(national).dy, 0.01),
    );
    expect(tester.getSize(whitepaper), tester.getSize(national));
    expect(tester.getSize(whitepaper).height, inInclusiveRange(57, 66));
    final nationalIcon = find.descendant(
      of: national,
      matching: find.byIcon(Icons.account_balance),
    );
    expect(nationalIcon, findsOneWidget);
    expect(
      tester.getCenter(nationalIcon).dx,
      lessThan(tester.getCenter(find.text('国家储备委员会')).dx),
    );
  });

  testWidgets('点击白皮书卡在 App 内进入阅读页', (tester) async {
    await _pumpPage(
      tester,
      councils: councils,
      banks: banks,
      whitepaperPageBuilder: (_) => const Scaffold(body: Text('白皮书阅读页')),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('citizen-whitepaper-card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('白皮书阅读页'), findsOneWidget);
  });

  test('白皮书 WebView 只允许官网唯一主文档导航', () {
    expect(isCitizenWhitepaperNavigationAllowed(citizenWhitepaperUrl), isTrue);
    expect(
      isCitizenWhitepaperNavigationAllowed(
        '$citizenWhitepaperUrl#node-configuration',
      ),
      isTrue,
    );
    expect(
      isCitizenWhitepaperNavigationAllowed('http://www.crcfrcn.com/whitepaper'),
      isFalse,
    );
    expect(
      isCitizenWhitepaperNavigationAllowed('https://crcfrcn.com/whitepaper'),
      isFalse,
    );
    expect(
      isCitizenWhitepaperNavigationAllowed('https://www.crcfrcn.com/'),
      isFalse,
    );
    expect(
      isCitizenWhitepaperNavigationAllowed(
        'https://www.crcfrcn.com@attacker.example/whitepaper',
      ),
      isFalse,
    );
  });

  testWidgets('省储委会默认展开、省储行默认收起，国家储委会保持展示', (tester) async {
    await _pumpPage(tester, councils: councils, banks: banks);
    expect(find.text('国家储备委员会'), findsOneWidget);
    expect(find.text('甲省储委会'), findsOneWidget);
    expect(find.text('甲省储行'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialCouncil'),
        ),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialBank'),
        ),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('省储委会（3）')).dy,
      lessThan(tester.getTopLeft(find.text('甲省储委会')).dy),
    );
    expect(
      tester.getTopLeft(find.text('省储行（2）')).dy,
      greaterThan(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('governance-institution-scroll-view')),
            )
            .dy,
      ),
    );
  });

  testWidgets('320 宽度和放大字体下两张顶部卡保持等高且不溢出', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpPage(tester, councils: councils, banks: banks, width: 320);
    final whitepaper = find.byKey(
      const ValueKey<String>('citizen-whitepaper-card'),
    );
    final national = find.byKey(const ValueKey('governance_national_card_nrc'));
    expect(tester.getSize(whitepaper), tester.getSize(national));
    expect(tester.getTopLeft(whitepaper).dx, greaterThanOrEqualTo(0));
    expect(tester.getTopRight(national).dx, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('治理与立法首行卡片高度及距子Tab顶部距离完全一致', (tester) async {
    await _pumpPage(tester, councils: councils, banks: banks);
    final governanceRect = tester.getRect(
      find.byKey(const ValueKey<String>('citizen-whitepaper-card')),
    );
    final legislationRepository = await _buildRepo(
      councils: const [],
      banks: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 900,
            child: LegislationTab(repository: legislationRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final legislationRect = tester.getRect(
      find.byKey(const ValueKey<String>('citizen-constitution-card')),
    );
    expect(legislationRect.height, governanceRect.height);
    expect(legislationRect.top, governanceRect.top);
    expect(
      legislationRect.height,
      closeTo(
        AppLayout.scaledValue(AppLayout.citizenSubtabFirstRowHeight),
        0.01,
      ),
    );
    expect(
      legislationRect.top,
      closeTo(AppLayout.citizenSubtabFirstRowTopInset, 0.01),
    );
  });

  testWidgets('两个分类互斥展开且滚动区只渲染当前分类卡片', (tester) async {
    await _pumpPage(tester, councils: councils, banks: banks);
    final councilHeader = find.text('省储委会（3）');
    final bankHeader = find.text('省储行（2）');
    final scrollView = find.byKey(
      const ValueKey('governance-institution-scroll-view'),
    );

    await tester.tap(
      find.byKey(const ValueKey('governance_section_toggle_provincialCouncil')),
    );
    await tester.pumpAndSettle();
    expect(find.text('甲省储委会'), findsNothing);
    expect(find.text('甲省储行'), findsNothing);
    expect(
      tester.getTopLeft(councilHeader).dy,
      lessThan(tester.getTopLeft(bankHeader).dy),
    );
    expect(
      tester.getBottomRight(bankHeader).dy,
      lessThan(tester.getTopLeft(scrollView).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey('governance_section_toggle_provincialBank')),
    );
    await tester.pumpAndSettle();
    expect(find.text('甲省储委会'), findsNothing);
    expect(find.text('乙省储委会'), findsNothing);
    expect(find.text('甲省储行'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialCouncil'),
        ),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialBank'),
        ),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(councilHeader).dy,
      lessThan(tester.getTopLeft(bankHeader).dy),
    );
    expect(
      tester.getTopLeft(bankHeader).dy,
      lessThan(tester.getTopLeft(find.text('甲省储行')).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey('governance_section_toggle_provincialCouncil')),
    );
    await tester.pumpAndSettle();
    expect(find.text('甲省储委会'), findsOneWidget);
    expect(find.text('甲省储行'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialCouncil'),
        ),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('governance_section_toggle_provincialBank'),
        ),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
  });

  testWidgets('滚动两个分类的43张卡片时顶部双卡和分类标题始终固定', (tester) async {
    final manyCouncils = List.generate(
      43,
      (index) => (name: '第${index + 1}省储委会', cid: 'prc-$index'),
    );
    final manyBanks = List.generate(
      43,
      (index) => (name: '第${index + 1}省储行', cid: 'prb-$index'),
    );
    await _pumpPage(tester, councils: manyCouncils, banks: manyBanks);

    final whitepaper = find.byKey(
      const ValueKey<String>('citizen-whitepaper-card'),
    );
    final national = find.byKey(const ValueKey('governance_national_card_nrc'));
    final councilHeader = find.text('省储委会（43）');
    final bankHeader = find.text('省储行（43）');
    final firstCouncilCard = find.text('第1省储委会');
    final fixedTop = <double>[
      tester.getTopLeft(whitepaper).dy,
      tester.getTopLeft(national).dy,
      tester.getTopLeft(councilHeader).dy,
      tester.getTopLeft(bankHeader).dy,
    ];
    final firstCouncilCardTop = tester.getTopLeft(firstCouncilCard).dy;

    await tester.drag(
      find.byKey(const ValueKey('governance-institution-scroll-view')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(<double>[
      tester.getTopLeft(whitepaper).dy,
      tester.getTopLeft(national).dy,
      tester.getTopLeft(councilHeader).dy,
      tester.getTopLeft(bankHeader).dy,
    ], fixedTop);
    expect(
      tester.getTopLeft(firstCouncilCard).dy,
      lessThan(firstCouncilCardTop),
    );

    await tester.tap(
      find.byKey(const ValueKey('governance_section_toggle_provincialBank')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第1省储委会'), findsNothing);
    final firstBankCard = find.text('第1省储行');
    final fixedBankTop = <double>[
      tester.getTopLeft(whitepaper).dy,
      tester.getTopLeft(national).dy,
      tester.getTopLeft(councilHeader).dy,
      tester.getTopLeft(bankHeader).dy,
    ];
    final firstBankCardTop = tester.getTopLeft(firstBankCard).dy;

    await tester.drag(
      find.byKey(const ValueKey('governance-institution-scroll-view')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(<double>[
      tester.getTopLeft(whitepaper).dy,
      tester.getTopLeft(national).dy,
      tester.getTopLeft(councilHeader).dy,
      tester.getTopLeft(bankHeader).dy,
    ], fixedBankTop);
    expect(tester.getTopLeft(firstBankCard).dy, lessThan(firstBankCardTop));
  });

  testWidgets('展开后按本机保存顺序展示，不做管理员优先自动排序', (tester) async {
    final orderStore = _FakeGovernanceInstitutionOrderStore(
      councils: const ['prc-b', 'prc-a'],
    );
    await _pumpPage(
      tester,
      councils: councils,
      banks: banks,
      orderStore: orderStore,
    );
    final first = tester.getTopLeft(find.text('乙省储委会'));
    final second = tester.getTopLeft(find.text('甲省储委会'));
    expect(first.dx, lessThan(second.dx));
  });

  testWidgets('长按拖拽省储委会后保存本机排序', (tester) async {
    final orderStore = _FakeGovernanceInstitutionOrderStore();
    await _pumpPage(
      tester,
      councils: councils.take(2).toList(),
      banks: banks,
      orderStore: orderStore,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('甲省储委会')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 120));
    await gesture.moveTo(tester.getCenter(find.text('乙省储委会')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(orderStore.councils, ['prc-b', 'prc-a']);
  });
}
