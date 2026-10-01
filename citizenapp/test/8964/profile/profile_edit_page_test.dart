import 'package:citizenapp/isar/user_isar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/profile/profile_edit_page.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';

import '../../support/isar_test_env.dart';

import 'fake_profile.dart';

class _FakeProfileCache extends CitizenProfileCache {
  bool failNext = false;
  bool wrote = false;
  int attempts = 0;
  @override
  Future<CitizenProfile> finishUpdate(String cidNumber) async {
    attempts++;
    if (failNext) {
      failNext = false;
      throw StateError('本地写入失败');
    }
    final profile = await super.finishUpdate(cidNumber);
    wrote = true;
    return profile;
  }
}

class _NoReadSession extends FakeSessionProvider {
  _NoReadSession() : super(null);
  int calls = 0;
  @override
  Future<SquareSession?> ensureSession() async {
    calls++;
    return null;
  }
}

Widget _wrap(
  FakeProfileApi api, {
  SquareSessionProvider? sessionProvider,
  _FakeProfileCache? cache,
}) {
  return MaterialApp(
    home: CitizenProfileEditPage(
      cidNumber: sampleProfile().cidNumber!,
      initialProfile: sampleProfile(displayName: '旧名', bio: '旧签名'),
      api: api,
      cache: cache ?? _FakeProfileCache(),
      sessionProvider:
          sessionProvider ??
          FakeSessionProvider(
            SquareSession(
              sessionToken: 'test',
              cidNumber: sampleProfile().cidNumber!,
              bindingRevision: 1,
              accountId: kOwner,
              expiresAt: 4102444800000,
            ),
          ),
    ),
  );
}

// 保存要等待真实数据库事务完成；虚拟时钟的settle不能推进原生IO。
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('保存'));
  await tester.pump();
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();
  // Isar使用真实异步IO；在Widget虚拟时钟启动前打开数据库，避免把未完成的打开任务带入tearDown。
  setUp(() async {
    await UserIsar.instance.db();
  });
  testWidgets('编辑页仅查看和输入不建立会话，点击保存才请求一次', (tester) async {
    final session = _NoReadSession();
    final api = FakeProfileApi(sampleProfile());
    await tester.pumpWidget(_wrap(api, sessionProvider: session));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '本地输入');
    await tester.pump();
    expect(session.calls, 0);
    expect(api.lastUpdate, isNull);
    await _save(tester);
    expect(session.calls, 1);
    expect(api.lastUpdate, isNull);
  });
  testWidgets('远端成功而本地失败保留页面，再次保存只重试本地', (tester) async {
    final api = FakeProfileApi(sampleProfile());
    final cache = _FakeProfileCache()..failNext = true;
    await tester.pumpWidget(_wrap(api, cache: cache));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(api.lastUpdate, isNotNull);
    expect(find.text('远端已保存，本机收尾未完成，点击保存可恢复'), findsOneWidget);
    expect(cache.attempts, 1);
    api.lastUpdate = null;
    await _save(tester);
    expect(cache.attempts, 2);
    expect(cache.wrote, isTrue);
    expect(api.lastUpdate, isNull);
  });

  testWidgets('prefills display name and bio from the profile', (tester) async {
    await tester.pumpWidget(_wrap(FakeProfileApi(sampleProfile())));
    await tester.pumpAndSettle();

    expect(find.text('旧名'), findsOneWidget);
    expect(find.text('旧签名'), findsOneWidget);
  });

  testWidgets('saving sends the edited fields to the api', (tester) async {
    final api = FakeProfileApi(sampleProfile());
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '新名');
    await tester.enterText(find.byType(TextField).at(1), '新签名');
    await _save(tester);

    expect(api.lastUpdate, {'display_name': '新名', 'bio': '新签名'});
  });

  testWidgets('save without a hot wallet shows guidance and skips the call', (
    tester,
  ) async {
    final api = FakeProfileApi(sampleProfile());
    await tester.pumpWidget(
      _wrap(api, sessionProvider: FakeSessionProvider(null)),
    );
    await tester.pumpAndSettle();

    await _save(tester);

    expect(api.lastUpdate, isNull);
    expect(find.text('请先在「我的 → 我的钱包」创建热钱包'), findsOneWidget);
  });
}
