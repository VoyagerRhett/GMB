import 'dart:collection';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('交易顶栏只用整组颜色表达连接状态', (tester) async {
    final snapshots = Queue<CitizenChainSyncStatus>.from([
      _snapshot(
        isSyncing: true,
        isUsable: false,
      ),
      _snapshot(
        isSyncing: false,
        isUsable: true,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChainProgressBanner(
            showInlineStatus: true,
            pollInterval: const Duration(milliseconds: 10),
            // 轮询常驻:队列耗尽后复用最后一份快照,模拟链稳定期。
            progressLoader: () async => snapshots.length > 1
                ? snapshots.removeFirst()
                : snapshots.first,
          ),
        ),
      ),
    );
    await tester.pump();

    var chainLabel = tester.widget<Text>(find.text('公民链'));
    var finalizedLabel = tester.widget<Text>(find.text('最终区块 0'));
    expect(chainLabel.style?.color, AppTheme.info);
    expect(finalizedLabel.style?.color, AppTheme.info);
    expect(find.textContaining('更新中'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    chainLabel = tester.widget<Text>(find.text('公民链'));
    finalizedLabel = tester.widget<Text>(find.text('最终区块 33'));
    expect(chainLabel.style?.color, AppTheme.success);
    expect(finalizedLabel.style?.color, AppTheme.success);
    expect(find.textContaining('已更新'), findsNothing);
  });

  testWidgets('交易顶栏读取失败时整组变红但不显示失败文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChainProgressBanner(
            showInlineStatus: true,
            progressLoader: () async => throw StateError('offline'),
          ),
        ),
      ),
    );
    await tester.pump();

    final chainLabel = tester.widget<Text>(find.text('公民链'));
    final finalizedLabel = tester.widget<Text>(find.text('最终区块 —'));
    expect(chainLabel.style?.color, AppTheme.danger);
    expect(finalizedLabel.style?.color, AppTheme.danger);
    expect(find.textContaining('连接失败'), findsNothing);
  });

  testWidgets('交易顶栏在极大字体下不反向缩字且保留完整无障碍语义', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(53 / 17),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ChainProgressBanner(
            showInlineStatus: true,
            progressLoader: () async => _snapshot(
              isSyncing: false,
              isUsable: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final banner = find.byKey(
      const ValueKey<String>('transaction-chain-status-inline'),
    );
    expect(
      find.descendant(of: banner, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('公民链连接正常，最终区块 33'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('其他页面只读取状态且不渲染任何连接状态', (tester) async {
    CitizenChainSyncStatus? receivedProgress;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChainProgressBanner(
            progressLoader: () async => _snapshot(
              isSyncing: false,
              isUsable: true,
            ),
            onProgressChanged: (progress) => receivedProgress = progress,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(receivedProgress?.finalized.number, BigInt.from(33));
    expect(
      find.byKey(
        const ValueKey<String>('transaction-chain-status-inline'),
      ),
      findsNothing,
    );
    expect(find.text('公民链'), findsNothing);
    expect(find.textContaining('最终区块'), findsNothing);
  });

  testWidgets('不可见状态读取常驻轮询,regular 后仍继续跟进链尖', (tester) async {
    final snapshots = Queue<CitizenChainSyncStatus>.from([
      _snapshot(
        isSyncing: false,
        isUsable: false,
      ),
      _snapshot(
        isSyncing: true,
        isUsable: false,
      ),
      _snapshot(
        isSyncing: false,
        isUsable: true,
      ),
    ]);
    var loadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChainProgressBanner(
            pollInterval: const Duration(milliseconds: 10),
            progressLoader: () async {
              loadCount += 1;
              // 队列耗尽后复用最后一份 regular 快照,模拟链稳定期持续轮询。
              return snapshots.length > 1
                  ? snapshots.removeFirst()
                  : snapshots.first;
            },
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.textContaining('轻节点'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(find.textContaining('轻节点'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(find.textContaining('轻节点'), findsNothing);
    expect(loadCount, 3);

    // 轮询常驻:regular(isUsable)后仍按 pollInterval 继续跟进,
    // 顶部最终区块高度才能自动更新、不依赖下拉刷新。
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(loadCount, greaterThan(3));
  });
}

CitizenChainSyncStatus _snapshot({
  required bool isSyncing,
  required bool isUsable,
}) {
  const finalizedHash =
      '0xe3985a35f8668d74f1552be80e1e4c5c01fcce7f7c757cc0cf254ec21a1d2d9c';
  // UI 状态夹具使用合成哈希，不绑定任何真实创世版本。
  final finalizedNumber = isUsable ? BigInt.from(33) : BigInt.zero;
  return CitizenChainSyncStatus(
    peerCount: BigInt.from(5),
    isSyncing: isSyncing,
    isUsable: isUsable,
    best: CitizenBlockRef(
      hash: finalizedHash,
      number: BigInt.from(33),
      finality: CitizenBlockFinality.best,
    ),
    finalized: CitizenBlockRef(
      hash: finalizedHash,
      number: finalizedNumber,
      finality: CitizenBlockFinality.finalized,
    ),
  );
}
