import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/widgets/square_feed_tabs.dart';
import 'package:citizenapp/ui/app_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      );

  testWidgets('关注子 tab 有未读时显示红点数字', (tester) async {
    await tester.pumpWidget(
      wrap(SquareFeedTabs(
        selected: SquareFeedKind.recommended,
        followingUnread: 3,
        onChanged: (_) {},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('未读为 0 时不显示红点', (tester) async {
    await tester.pumpWidget(
      wrap(SquareFeedTabs(
        selected: SquareFeedKind.recommended,
        followingUnread: 0,
        onChanged: (_) {},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
  });

  testWidgets('未读超过 99 显示 99+', (tester) async {
    await tester.pumpWidget(
      wrap(SquareFeedTabs(
        selected: SquareFeedKind.recommended,
        followingUnread: 128,
        onChanged: (_) {},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('点击分类回调对应 feedKind', (tester) async {
    SquareFeedKind? tapped;
    await tester.pumpWidget(
      wrap(SquareFeedTabs(
        selected: SquareFeedKind.recommended,
        onChanged: (kind) => tapped = kind,
      )),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注'));
    expect(tapped, SquareFeedKind.following);
  });
}
