import 'dart:async';

import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/compose/drafts/drafts_page.dart';
import 'package:citizenapp/8964/square_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingDraftStore implements SquareComposeDraftRepository {
  final Completer<List<SquareComposeDraft>> completer =
      Completer<List<SquareComposeDraft>>();

  @override
  Future<List<SquareComposeDraft>> list(String cidNumber) => completer.future;

  @override
  Future<void> delete(String cidNumber, String draftId) async {}

  @override
  Future<void> save(SquareComposeDraft draft) async {}

  @override
  Future<void> retryPendingFileCleanup({String? cidNumber}) async {}
}

class _CleanupFailureDraftStore implements SquareComposeDraftRepository {
  bool deleted = false;
  int retryCalls = 0;

  static const draft = SquareComposeDraft(
    draftId: 'draft-cleanup',
    cidNumber: 'CN220-CTZN2-100000001-2026',
    postType: SquarePostType.document,
    text: '待删除草稿',
    media: <SquareLocalMediaDraft>[],
    updatedAtMillis: 1,
  );

  @override
  Future<List<SquareComposeDraft>> list(String cidNumber) async => deleted
      ? const <SquareComposeDraft>[]
      : const <SquareComposeDraft>[draft];

  @override
  Future<void> delete(String cidNumber, String draftId) async {
    deleted = true;
    throw const SquareComposeDraftStoreException('媒体清理失败');
  }

  @override
  Future<void> retryPendingFileCleanup({String? cidNumber}) async {
    retryCalls += 1;
  }

  @override
  Future<void> save(SquareComposeDraft draft) async {}
}

void main() {
  testWidgets('本地草稿未返回时直接显示草稿箱且不使用整页转圈', (tester) async {
    final store = _PendingDraftStore();
    await tester.pumpWidget(
      MaterialApp(
        home: DraftsPage(
          cidNumber: 'CN220-CTZN2-100000001-2026',
          postType: SquarePostType.document,
          store: store,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('草稿箱'), findsOneWidget);
    expect(find.text('正在读取本地草稿'), findsOneWidget);
    expect(find.byKey(const ValueKey('drafts-load-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    store.completer.complete(const <SquareComposeDraft>[]);
    await tester.pumpAndSettle();
    expect(find.text('还没有草稿'), findsOneWidget);
    expect(find.byKey(const ValueKey('drafts-load-progress')), findsNothing);
  });

  testWidgets('草稿事实已删但媒体失败时显示可重试终态', (tester) async {
    final store = _CleanupFailureDraftStore();
    await tester.pumpWidget(
      MaterialApp(
        home: DraftsPage(
          cidNumber: _CleanupFailureDraftStore.draft.cidNumber,
          postType: SquarePostType.document,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待删除草稿'), findsOneWidget);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('草稿已删除，但本地媒体仍待清理'), findsOneWidget);
    expect(find.text('待删除草稿'), findsNothing);
    await tester.tap(find.text('重试清理'));
    await tester.pumpAndSettle();
    expect(store.retryCalls, 1);
    expect(find.text('本地媒体清理完成'), findsOneWidget);
  });
}
