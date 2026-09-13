import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/ui/app_theme.dart';

const _accountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';

/// 已注册:resolve 返回带链上闭环快照的身份。
class _RegisteredCache implements FinalizedIdentityResolver {
  @override
  Future<FinalizedIdentity?> resolve() async => FinalizedIdentity(
        accountId: _accountId,
        ss58Address: 'ss58-demo',
        snapshot: CitizenIdentityChainSnapshot(
          cidNumber: 'CN220-CTZN2-100000001-2026',
          accountId: Uint8List(32),
          bindingRevision: 1,
          votingIdentity: null,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 未注册:resolve 命中缓存但快照为空(链读结论=全账户未占号,回退账户0)。
class _UnregisteredCache implements FinalizedIdentityResolver {
  @override
  Future<FinalizedIdentity?> resolve() async => const FinalizedIdentity(
        accountId: _accountId,
        ss58Address: 'ss58-demo',
        snapshot: null,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 链读失败:fail-closed,绝不冒充"未注册"。
class _ThrowingCache implements FinalizedIdentityResolver {
  @override
  Future<FinalizedIdentity?> resolve() async => throw Exception('链读失败');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 注册流程 fake:余额充足,占号直接成功。与 myid_page_test 同款口径。
class _FlowService implements MyIdService {
  int registerCalls = 0;

  @override
  Future<List<CitizenWalletStateAccount>> listBindableAccounts() async =>
      const <CitizenWalletStateAccount>[];

  @override
  Future<({BigInt balanceFen, BigInt requiredFen})>
      fetchRegistrationAffordability(String bindAccountId) async => (
            requiredFen: BigInt.from(121),
            balanceFen: BigInt.from(10000),
          );

  @override
  Future<String> registerAnonymousCid({
    required BuildContext? context,
    required String institution,
    String? bindAccountId,
  }) async {
    registerCalls++;
    return 'CN220-CTZN2-100000009-2026';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 挂一个按钮驱动 [ensureCidRegisteredOrPrompt],把返回值收进 [results]。
Widget _harness(
  List<bool> results,
  MyIdService service,
  FinalizedIdentityResolver resolver,
) {
  return Provider<FinalizedIdentityResolver>.value(
    value: resolver,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              results.add(
                await ensureCidRegisteredOrPrompt(
                  context,
                  myIdService: service,
                ),
              );
            },
            child: const Text('触发动作'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('已注册 → 放行返回 true,不弹注册面板', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      _harness(results, _FlowService(), _RegisteredCache()),
    );

    await tester.tap(find.text('触发动作'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.text('确认注册'), findsNothing);
  });

  testWidgets('未注册 → 就地弹统一注册面板并返回 false', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      _harness(results, _FlowService(), _UnregisteredCache()),
    );

    await tester.tap(find.text('触发动作'));
    await tester.pumpAndSettle();

    // 弹的是「注册身份」统一底部面板(确认按钮为证);面板挂起期间动作被拦,
    // future 尚未返回。
    expect(find.text('确认注册'), findsOneWidget);
    expect(results, isEmpty);

    // 用户点遮罩取消 → 动作以 false 收尾(注册后由用户重新触发,不自动续跑)。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('未注册 → 面板内确认占号:只提交一次，缓存收敛归服务层', (tester) async {
    final cache = _UnregisteredCache();
    final service = _FlowService();
    final results = <bool>[];
    await tester.pumpWidget(_harness(results, service, cache));

    await tester.tap(find.text('触发动作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认注册'));
    await tester.pumpAndSettle();

    expect(service.registerCalls, 1);
    // Widget 流程不抢在 finalized 闭环前失效缓存或广播；MyIdService 在完整闭环成立后
    // 统一执行，相关“一次失效 + 一次 revision”由 myid_service_test 单独钉死。
    expect(find.textContaining('身份 CID 已注册'), findsOneWidget);
  });

  testWidgets('身份链读失败 → fail-closed 提示,不弹面板不放行', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      _harness(results, _FlowService(), _ThrowingCache()),
    );

    await tester.tap(find.text('触发动作'));
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.text('确认注册'), findsNothing);
    expect(find.text('暂时无法验证身份，请稍后重试'), findsOneWidget);
  });
}
