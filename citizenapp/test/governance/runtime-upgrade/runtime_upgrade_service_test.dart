import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_service.dart';
import '../../support/fake_citizen_sdk.dart';

void main() {
  Uint8List compactLength(int length) {
    if (length < 64) {
      return Uint8List.fromList([length << 2]);
    }
    if (length < 16384) {
      final encoded = (length << 2) | 0x01;
      return Uint8List.fromList([encoded & 0xff, (encoded >> 8) & 0xff]);
    }
    throw ArgumentError('测试辅助函数只覆盖 16KB 以下 Vec');
  }

  Uint8List compactBytes(Uint8List value) {
    return Uint8List.fromList([...compactLength(value.length), ...value]);
  }

  Uint8List storageValue(Uint8List proposalData) {
    return compactBytes(proposalData);
  }

  List<int> u32le(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  List<int> u64le(int value) => [...u32le(value), ...u32le(value >> 32)];

  List<int> powParams() => [
        ...u32le(1),
        1,
        0,
        ...u64le(360000),
        ...u32le(600),
        ...u64le(4),
        ...u64le(4),
      ];

  group('RuntimeUpgradeService 协议升级详情解码', () {
    test('解码带 rt-upg 前缀的协议升级提案摘要', () {
      final service = RuntimeUpgradeService(chain: TestCitizenChain(), transactions: TestCitizenTransactions());
      final actorCid =
          Uint8List.fromList(utf8.encode('ZS001-NRC0G-944805165-2026'));
      final proposer = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final reason = Uint8List.fromList(utf8.encode('升级协议参数'));
      final codeHash = Uint8List.fromList(List<int>.filled(32, 0xab));
      final paramsHash = Uint8List.fromList(List<int>.filled(32, 0xcd));
      final proposalData = Uint8List.fromList([
        ...utf8.encode('rt-upg'),
        ...compactBytes(actorCid),
        ...proposer,
        ...compactBytes(reason),
        ...codeHash,
        ...paramsHash,
        ...powParams(),
      ]);

      final decoded = service.decodeRuntimeUpgradeStorageValue(
        7,
        storageValue(proposalData),
      );

      expect(decoded, isNotNull);
      expect(decoded!.proposalId, 7);
      expect(decoded.actorCidNumber, 'ZS001-NRC0G-944805165-2026');
      expect(decoded.reason, '升级协议参数');
      expect(decoded.codeHashHex, List.filled(32, 'ab').join());
      expect(decoded.paramsVersion, 1);
      expect(decoded.targetBlockTimeMs, 360000);
      expect(decoded.adjustmentInterval, 600);
    });

    test('非 rt-upg 提案摘要不按协议升级解码', () {
      final service = RuntimeUpgradeService(chain: TestCitizenChain(), transactions: TestCitizenTransactions());
      final proposer = Uint8List.fromList(List<int>.filled(32, 1));
      final actorCid =
          Uint8List.fromList(utf8.encode('ZS001-NRC0G-944805165-2026'));
      final reason = Uint8List.fromList(utf8.encode('其他提案'));
      final codeHash = Uint8List.fromList(List<int>.filled(32, 0xcd));
      final proposalData = Uint8List.fromList([
        ...utf8.encode('other'),
        ...compactBytes(actorCid),
        ...proposer,
        ...compactBytes(reason),
        ...codeHash,
        ...Uint8List.fromList(List<int>.filled(32, 0xcd)),
        ...powParams(),
      ]);

      final decoded = service.decodeRuntimeUpgradeStorageValue(
        8,
        storageValue(proposalData),
      );

      expect(decoded, isNull);
    });

    test('带旧业务状态字段的协议升级摘要不再兼容', () {
      final service = RuntimeUpgradeService(chain: TestCitizenChain(), transactions: TestCitizenTransactions());
      final proposer = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final actorCid =
          Uint8List.fromList(utf8.encode('ZS001-NRC0G-944805165-2026'));
      final reason = Uint8List.fromList(utf8.encode('旧摘要'));
      final codeHash = Uint8List.fromList(List<int>.filled(32, 0xef));
      final proposalData = Uint8List.fromList([
        ...utf8.encode('rt-upg'),
        ...compactBytes(actorCid),
        ...proposer,
        ...compactBytes(reason),
        ...codeHash,
        ...Uint8List.fromList(List<int>.filled(32, 0xcd)),
        ...powParams(),
        0,
      ]);

      final decoded = service.decodeRuntimeUpgradeStorageValue(
        9,
        storageValue(proposalData),
      );

      expect(decoded, isNull);
    });
  });
}
