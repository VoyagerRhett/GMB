import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('根实例只打开并启动一个完整 CitizenSDK session', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('CitizenSdkModules.full'));
    expect(RegExp(r'CitizenSdk\.open\(').allMatches(source), hasLength(1));
    expect(RegExp(r'citizenSdk\.start\(').allMatches(source), hasLength(1));
  });

  test('CitizenApp 生产源码不再包含旧钱包与本机 sr25519 实现', () {
    const removed = <String>[
      'lib/wallet/core/wallet_manager.dart',
      'lib/wallet/core/default_account_service.dart',
      'lib/wallet/core/native_sr25519.dart',
      'lib/wallet/core/hardware_bound_seed_vault.dart',
      'lib/wallet/pages/create_wallet_flow.dart',
      'lib/wallet/pages/import_wallet_page.dart',
      'lib/wallet/widgets/add_account_sheet.dart',
    ];
    for (final path in removed) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });
}
