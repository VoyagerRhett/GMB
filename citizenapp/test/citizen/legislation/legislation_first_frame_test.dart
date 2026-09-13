import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/legislation/data/law_models.dart';
import 'package:citizenapp/citizen/legislation/data/legislation_api.dart';
import 'package:citizenapp/citizen/legislation/law_list_page.dart';
import 'package:citizenapp/citizen/legislation/law_reader_page.dart';
import 'package:citizenapp/citizen/legislation/legislation_tab.dart';
import 'package:citizenapp/citizen/public/data/public_institution_repository.dart';

import '../public/public_nav_harness.dart';
import '../../support/fake_citizen_sdk.dart';

class _PendingInstitutionRepository extends InstitutionRepository {
  _PendingInstitutionRepository(PublicInstitutionRepository directory)
      : super(directory: directory);

  final Completer<List<Institution>> completer = Completer<List<Institution>>();

  @override
  Future<List<Institution>> listByCodes(Set<String> institutionCodes) =>
      completer.future;
}

class _PendingLawListApi extends LegislationApi {
  _PendingLawListApi() : super(chain: TestCitizenChain());

  final Completer<List<int>> completer = Completer<List<int>>();

  @override
  Future<List<int>> listLaws(LawTier tier, int scopeCode) => completer.future;
}

class _PendingLawReaderApi extends LegislationApi {
  _PendingLawReaderApi() : super(chain: TestCitizenChain());

  final Completer<Law?> completer = Completer<Law?>();

  @override
  Future<Law?> localLaw(int lawId) => completer.future;
}

void main() {
  testWidgets('立法目录未返回时直接显示卡片和省导航且不使用整页转圈', (tester) async {
    final directory = await buildSeededRepo(
      provinceOrder: const [],
      institutions: const [],
    );
    final repository = _PendingInstitutionRepository(directory);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 900,
            child: LegislationTab(repository: repository),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('《公民宪法》'), findsOneWidget);
    expect(find.text('国家立法院'), findsOneWidget);
    expect(find.text('省市立法机构'), findsOneWidget);
    expect(find.text('中枢'), findsOneWidget);
    expect(find.text('正在读取立法机构'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('legislation-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('法律列表未返回时直接显示标题和内容区且不使用整页转圈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LawListPage(
          tier: LawTier.national,
          scopeCode: 0,
          title: '国家法律原文',
          api: _PendingLawListApi(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('国家法律原文'), findsOneWidget);
    expect(find.text('正在读取法律列表'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('law-list-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('法律正文未返回时直接显示阅读壳且不使用整页转圈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LawReaderPage(lawId: 0, api: _PendingLawReaderApi()),
      ),
    );
    await tester.pump();

    expect(find.text('法律'), findsOneWidget);
    expect(find.text('正在读取法律正文'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('law-reader-loading-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('law-reader-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
