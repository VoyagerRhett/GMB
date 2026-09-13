import 'package:citizen_sdk/citizen_sdk.dart';

/// CitizenApp 测试只为本用例覆盖实际调用的 CitizenChain 方法。
/// 未覆盖的公开能力一律失败，禁止测试伪造隐式默认链事实。
class TestCitizenChain implements CitizenChain {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenChain.${invocation.memberName} 未配置');
  }
}

/// CitizenTransactions 的严格测试基类；每个业务用例必须明确给出
/// prepare/execute/consume/cancel 中它真正依赖的结果。
class TestCitizenTransactions implements CitizenTransactions {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'CitizenTransactions.${invocation.memberName} 未配置',
    );
  }
}

/// CitizenHistory 的严格测试基类。
class TestCitizenHistory implements CitizenHistory {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenHistory.${invocation.memberName} 未配置');
  }
}

/// CitizenSdkWallet 的严格测试基类。
class TestCitizenSdkWallet implements CitizenSdkWallet {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('CitizenSdkWallet.${invocation.memberName} 未配置');
  }
}
