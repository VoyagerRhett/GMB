import 'dart:async';

import 'package:citizenapp/chat/chat_entry.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingContacts implements UserContactService {

  final Completer<List<UserContact>> completer = Completer<List<UserContact>>();

  @override
  Future<List<UserContact>> getContacts() => completer.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('通讯录未返回时直接显示建群表单并禁用创建', (tester) async {
    final contacts = _PendingContacts();
    await tester.pumpWidget(
      MaterialApp(home: GroupCreatePage(contactService: contacts)),
    );
    await tester.pump();

    expect(find.text('新建群聊'), findsOneWidget);
    expect(find.text('群名称'), findsOneWidget);
    expect(find.text('选择成员'), findsOneWidget);
    expect(find.text('正在读取本地通讯录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-create-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final create = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '创建'),
    );
    expect(create.onPressed, isNull);

    contacts.completer.complete(const <UserContact>[]);
    await tester.pumpAndSettle();
    expect(find.text('通讯录为空,先在「我的 → 通讯录」添加联系人'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-create-load-progress')),
      findsNothing,
    );
  });
}
