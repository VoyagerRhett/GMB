import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:citizenapp/transaction/offchain-transaction/pages/clearing_bank_settings_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_directory.dart';
import '../support/fake_citizen_sdk.dart';

/// `ClearingBankSettingsPage` 基础渲染测试。
///
/// 默认状态不主动读取链上清算行目录;测试只断言:
/// - AppBar 标题「设置清算行」可见
/// - 顶部搜索框(TextField)存在,hint 为「搜索清算行」
/// - 空态提示「暂无结果」可见
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const accountId =
      '0x0000000000000000000000000000000000000000000000000000000000000000';
  const ss58Address = '5DummyAddress';

  testWidgets('renders AppBar title, search field and empty hint',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClearingBankSettingsPage(
          accountId: accountId,
          ss58Address: ss58Address,
          directory: ClearingBankDirectory(chain: TestCitizenChain()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置清算行'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('搜索清算行'), findsOneWidget);
    expect(find.text('暂无结果'), findsOneWidget);
  });
}
