import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/chat/chat_entry.dart';
import 'package:citizenapp/chat/chat_product_policy.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/ui/app_theme.dart';

const _ownerUserId = 'CN220-CTZN2-100000001-2026';
const _peerUserId = 'CN220-CTZN2-100000002-2026';
const _carolCidNumber = 'CN220-CTZN2-100000003-2026';
const _peerAccountId =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _peerProfile = CitizenProfile(
  accountId: _peerAccountId,
  displayName: '会员用户',
  bio: '公开签名',
  avatarObjectKey: 'profile/$_peerUserId/avatar',
  bannerObjectKey: null,
  cidNumber: _peerUserId,
  isCertified: true,
  identityLevel: 'voting',
  membershipLevel: 'democracy',
  membershipActive: true,
  following: 0,
  followers: 0,
  mutualFollowing: 0,
  posts: 0,
  campaigns: 0,
  videos: 0,
  articles: 0,
  isFollowing: false,
  isFollowedBy: false,
  isNotifying: false,
  updatedAt: 2,
);

void main() {
  setUp(() => ChatMediaLimits.applyMembershipLevel('freedom'));
  tearDown(() => ChatMediaLimits.applyMembershipLevel(null));

  testWidgets('本地会话未返回时直接显示聊天页面且不使用整页转圈', (tester) async {
    final store = _PendingChatStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('搜索会话、联系人和聊天记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-sync-progress')), findsOneWidget);
    final searchTopBefore = tester.getTopLeft(find.text('搜索会话、联系人和聊天记录')).dy;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('chat-sync-progress'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('chat-add-button'))).dy,
      ),
    );
    expect(find.text('正在读取本地会话'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    store.completer.complete(const <ChatConversationPreview>[]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-sync-progress')), findsNothing);
    expect(tester.getTopLeft(find.text('搜索会话、联系人和聊天记录')).dy, searchTopBefore);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('未注册身份显示统一注册引导,不读加密存储不报底层异常', (tester) async {
    final store = _FakeChatStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: '',
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 统一引导态(标题 + 注册按钮),不是错误横幅。
    expect(find.text('尚未注册'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.textContaining('尚未激活'), findsNothing);
    // 短路铁证:加密会话存储一次都不读——其密钥绑定解析对未注册身份必抛
    // WalletAuthException,读了就会以错误横幅盖住引导。
    expect(store.readPreviewCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('聊天记录未返回时直接显示会话页和输入区域', (tester) async {
    final store = _PendingMessagesStore();
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '张三',
          store: store,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('张三'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-peer-profile-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-expression-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-page-progress')), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('暂无消息'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    store.completer.complete(const <ChatStoredMessage>[]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-page-progress')), findsNothing);
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('暂无消息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('本地聊天记录未返回前不闪现空态，返回后直接显示历史消息', (tester) async {
    final store = _PendingMessagesStore();
    final readThrough = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '张三',
          store: store,
          onMarkRead: (millis) async => readThrough.add(millis),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('暂无消息'), findsNothing);

    store.completer.complete(<ChatStoredMessage>[
      ChatStoredMessage(
        messageId: 'env-history',
        conversationId: 'dm:me:peer',
        direction: 'incoming',
        senderUserId: _peerUserId,
        recipientUserId: _ownerUserId,
        messageKind: ChatMessageKind.text,
        deliveryState: ChatMessageDeliveryState.receivedByDevice,
        createdAtMillis: 1000,
        plaintext: ChatPayloadCodec.encode(ChatContent.text('历史消息')),
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('暂无消息'), findsNothing);
    expect(find.text('历史消息'), findsOneWidget);
    expect(readThrough, <int>[1000]);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('首次本地记录显示后静默重试不占用状态线且不二次读取', (tester) async {
    final retry = Completer<int>();
    final store = _FakeChatStore(
      messages: [
        ChatStoredMessage(
          messageId: 'env-fast-first-frame',
          conversationId: 'dm:me:peer',
          direction: 'incoming',
          senderUserId: _peerUserId,
          recipientUserId: _ownerUserId,
          messageKind: ChatMessageKind.text,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
          createdAtMillis: 1000,
          plaintext: ChatPayloadCodec.encode(ChatContent.text('立即显示的记录')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '张三',
          store: store,
          onSync: () => retry.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('立即显示的记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-page-progress')), findsNothing);
    expect(store.readMessagesCount, 1);

    await tester.pump(const Duration(milliseconds: 300));
    expect(store.readMessagesCount, 1, reason: '待发送队列尚未完成也不得重复解密首屏');

    retry.complete(0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.readMessagesCount, 1, reason: '静默补发结束只更新内部投递事实');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('媒体路径解析未完成时文字记录和媒体占位先显示', (tester) async {
    final paths = Completer<Map<String, String>>();
    List<ChatContent>? requestedContents;
    final store = _FakeChatStore(
      messages: [
        ChatStoredMessage(
          messageId: 'env-text-before-media',
          conversationId: 'dm:alice-wallet:bob-wallet',
          direction: 'incoming',
          senderUserId: _peerUserId,
          recipientUserId: _ownerUserId,
          messageKind: ChatMessageKind.text,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
          createdAtMillis: 1000,
          plaintext: ChatPayloadCodec.encode(ChatContent.text('媒体前先显示文字')),
        ),
        _mediaStored(
          id: 'delayed',
          kind: ChatMessageKind.image,
          mime: 'image/jpeg',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
          onResolveMediaPaths: (conversationId, contents) {
            requestedContents = contents;
            return paths.future;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('媒体前先显示文字'), findsOneWidget);
    expect(find.text('接收中…'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-page-progress')), findsNothing);
    expect(requestedContents?.single.attachmentId, 'att-delayed');
    expect(store.readMessagesCount, 1);

    paths.complete(const <String, String>{});
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.readMessagesCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('聊天窗口顶部直接使用传入的真实头像和会员徽章', (tester) async {
    const avatarPath = '/cached/chat/avatar.webp';
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '旧昵称',
          store: _FakeChatStore(),
          initialProfile: _peerProfile,
          initialProfileMedia: const CitizenProfileMediaSnapshot(
            avatarPath: avatarPath,
          ),
          profileApi: _FakeProfileApi(_peerProfile),
          profileCache: const _MemoryProfileCache(_peerProfile),
          profileMediaCache: _MemoryProfileMediaCache(
            const CitizenProfileMediaSnapshot(avatarPath: avatarPath),
          ),
          sessionProvider: _FakeProfileSessionProvider(),
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(find.text('会员用户'), findsOneWidget);
    expect(find.text('旧昵称'), findsNothing);
    expect(avatar.imagePath, avatarPath);
    expect(avatar.membershipLevel, 'democracy');
    expect(avatar.membershipActive, isTrue);
    expect(avatar.showBadge, isTrue);

    await tester.tap(find.byKey(const ValueKey('chat-peer-profile-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final profilePage = tester.widget<UserProfilePage>(
      find.byType(UserProfilePage),
    );
    expect(profilePage.initialProfile?.membershipLevel, 'democracy');
    expect(profilePage.initialProfile?.membershipActive, isTrue);
    expect(profilePage.initialProfileMedia?.avatarPath, avatarPath);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('连续文字发送在网络 Future 完成前立即显示且键盘保持焦点', (tester) async {
    final pendingSends = <Completer<void>>[];
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '张三',
          store: _FakeChatStore(),
          onSendText: (text) {
            submitted.add(text);
            final pending = Completer<void>();
            pendingSends.add(pending);
            return pending.future;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final input = find.byKey(const ValueKey('chat-text-input'));
    await tester.tap(input);
    await tester.enterText(input, '第一条');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.enterText(input, '第二条');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(submitted, <String>['第一条', '第二条']);
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    final textField = tester.widget<TextField>(input);
    expect(textField.controller?.text, isEmpty);
    expect(textField.focusNode?.hasFocus, isTrue, reason: '键盘发送后必须继续输入');

    for (final pending in pendingSends) {
      pending.complete();
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('聊天标题误传账户时仍按对方 CID 生成稳定默认昵称', (tester) async {
    const peerUserId = 'CN220-CTZN2-100000002-2026';
    const peerAccount = 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT';
    final store = _FakeChatStore();
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:$_ownerUserId:$peerUserId',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: peerUserId,
          title: peerAccount,
          store: store,
          onSync: () async => 0,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // flutter_chat_ui 的空列表动画会在首次稳定布局后再排一个 50ms timer。
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(ProfilePresentation.forIdentityKey(peerUserId).fallbackName),
      findsOneWidget,
    );
    expect(find.text(peerAccount), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('隐藏 Chat Tab 不初始化，进入后 init/resume 只同步一次', (tester) async {
    final selectedTab = ValueNotifier<int>(0);
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: _FakeChatStore(),
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
            selectedTab: selectedTab,
            tabIndex: 2,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(runtime.syncCount, 0);

    selectedTab.value = 2;
    await tester.pump(const Duration(milliseconds: 100));
    expect(runtime.syncCount, 1);

    // 一次 pause/resume 可以同步一次；同一 resume burst 不得创建两条链。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(runtime.syncCount, 2);

    selectedTab.dispose();
  });

  testWidgets('聊天 Tab 按 CID 身份渲染会话列表', (tester) async {
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:bob-wallet',
          title: 'Bob',
          peerUserId: 'CN220-CTZN2-100000002-2026',
          lastMessage: 'hello',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          unreadCount: 1,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(_peerAccountId), findsNothing);
    expect(find.text('hello'), findsOneWidget);
    expect(
      store.lastAccountFilter,
      '0x1111111111111111111111111111111111111111111111111111111111111111',
    );
    expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    expect(find.byIcon(Icons.qr_code_2_rounded), findsNothing);
    final tile = find.byKey(
      const ValueKey('chat-conversation-dm:alice-wallet:bob-wallet'),
    );
    final cardDecoration = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: tile, matching: find.byType(DecoratedBox)),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.border != null);
    expect((cardDecoration.border! as Border).top.color, AppTheme.borderLight);
  });

  testWidgets('聊天卡片联合显示私人备注、公开昵称、真实头像和会员徽章', (tester) async {
    const avatarPath = '/cached/chat-list/avatar.webp';
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:owner:peer',
          title: '旧昵称',
          peerUserId: _peerUserId,
          lastMessage: '',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            profileApi: _FakeProfileApi(_peerProfile),
            profileCache: const _MemoryProfileCache(_peerProfile),
            profileMediaCache: _MemoryProfileMediaCache(
              const CitizenProfileMediaSnapshot(avatarPath: avatarPath),
            ),
            sessionProvider: _FakeProfileSessionProvider(),
            contactService: _FakeContactService(<UserContact>[
              const UserContact(
                cidNumber: _peerUserId,
                accountId: _peerAccountId,
                ss58Address: 'test-address',
                contactRemark: '同事',
                createdAt: 1,
                updatedAt: 1,
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(find.text('同事（会员用户）'), findsOneWidget);
    expect(find.text(_peerUserId), findsNothing);
    expect(find.text('暂无消息'), findsOneWidget);
    expect(find.text('旧昵称'), findsNothing);
    expect(avatar.imagePath, avatarPath);
    expect(avatar.membershipLevel, 'democracy');
    expect(avatar.membershipActive, isTrue);
    expect(avatar.showBadge, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('进会话点贴纸 → 接线到 runtime.sendSticker(peer/conv/pack/sticker 正确)', (
    tester,
  ) async {
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
    );
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:bob-wallet',
          title: 'Bob',
          peerUserId: _peerUserId,
          lastMessage: 'hi',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.sent,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 点会话进入 SDK 完整会话页。
    await tester.tap(find.text('Bob'));
    await tester.pump(const Duration(milliseconds: 400)); // 路由转场
    await tester.pump(const Duration(milliseconds: 100));

    // 点贴纸开关 → 面板 → 选 grinning_face。
    await tester.tap(find.byKey(const ValueKey('chat-expression-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-expression-sticker')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sticker-grinning_face')));
    await tester.pump(const Duration(milliseconds: 100));

    // 委托四参逐字正确(named 参数不会换位,守的是漏接/错映射的回归)。
    expect(runtime.sentStickers.single, [
      _peerUserId,
      'dm:alice-wallet:bob-wallet',
      'fluent3d',
      'grinning_face',
    ]);
    expect(
      runtime.retryScopes,
      contains((
        recipientUserId: _peerUserId,
        conversationId: 'dm:alice-wallet:bob-wallet',
      )),
      reason: '进入私聊只能重试当前对端的当前会话队列',
    );
    expect(runtime.realtimeRetryOutgoingOnConnect, contains(false));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('聊天 Tab deletes one local conversation after confirmation', (
    tester,
  ) async {
    final allowPhysicalDelete = Completer<void>();
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:bob-wallet',
          title: 'Bob',
          peerUserId: _peerUserId,
          lastMessage: 'hello',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.sent,
        ),
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:carol-wallet',
          title: 'Carol',
          peerUserId: _carolCidNumber,
          lastMessage: 'keep',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.sent,
        ),
      ],
    );
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      onDeleteConversation: (conversationId) async {
        await allowPhysicalDelete.future;
        await store.deleteConversation(
          _ownerUserId,
          conversationId,
          bindingToken: const ChatBindingFenceToken(
            ownerUserId: _ownerUserId,
            bindingRevision: 1,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            keyDomain:
                '0x4242424242424242424242424242424242424242424242424242424242424242',
            generation: 1,
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.text('Bob'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('删除聊天记录'), findsOneWidget);
    expect(find.text('确定删除这台设备上的聊天记录？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pump();

    expect(store.deletedConversationIds, isEmpty, reason: '后台物理删除仍被测试门闩阻塞');
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Carol'), findsOneWidget);

    allowPhysicalDelete.complete();
    await tester.pumpAndSettle();
    expect(store.deletedConversationIds, ['dm:alice-wallet:bob-wallet']);
  });

  testWidgets('聊天窗口确认删除后立即返回且路由重载不恢复待清理卡片', (tester) async {
    final allowPhysicalDelete = Completer<void>();
    var deleteCalls = 0;
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:bob-wallet',
          title: 'Bob',
          peerUserId: _peerUserId,
          lastMessage: 'hello',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.sent,
        ),
      ],
      messages: [
        ChatStoredMessage(
          messageId: 'env-window-delete',
          conversationId: 'dm:alice-wallet:bob-wallet',
          direction: 'incoming',
          senderUserId: _peerUserId,
          recipientUserId: _ownerUserId,
          messageKind: ChatMessageKind.text,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
          createdAtMillis: 1000,
          plaintext: ChatPayloadCodec.encode(ChatContent.text('hello')),
        ),
      ],
    );
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      onDeleteConversation: (conversationId) async {
        deleteCalls += 1;
        await allowPhysicalDelete.future;
        await store.deleteConversation(
          _ownerUserId,
          conversationId,
          bindingToken: const ChatBindingFenceToken(
            ownerUserId: _ownerUserId,
            bindingRevision: 1,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            keyDomain:
                '0x4242424242424242424242424242424242424242424242424242424242424242',
            generation: 1,
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(
        const ValueKey('chat-conversation-dm:alice-wallet:bob-wallet'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CitizenChatPage), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(find.text('聊天暂时无法使用，请稍后重试'), findsNothing);
    expect(
      find.byType(CitizenChatPage),
      findsNothing,
      reason: '确认后聊天窗口必须立即关闭',
    );
    expect(find.text('Bob'), findsNothing, reason: '后台删除未完成时路由重载也不得恢复卡片');
    expect(store.deletedConversationIds, isEmpty);

    allowPhysicalDelete.complete();
    await tester.pumpAndSettle();
    expect(store.deletedConversationIds, ['dm:alice-wallet:bob-wallet']);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('聊天 Tab 鉴权仍要求当前绑定钱包账户', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: _FakeChatStore(),
            cidNumber: _ownerUserId,
            accountId: '',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('请先在「我的 → 我的钱包」添加钱包账户'), findsOneWidget);
  });

  testWidgets('聊天 Tab 打开后自动重试本机发送队列', (tester) async {
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
    );
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(runtime.syncCount, 1);
    // 首次本地读立即出首屏；发送队列重试完成后再读一次以合并最新状态。
    expect(store.readPreviewCount, 2);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(runtime.syncCount, 2);
    expect(store.readPreviewCount, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('本地空会话先结束加载，静默后台服务不得阻塞首屏', (tester) async {
    final retryCompleter = Completer<int>();
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      retryCompleter: retryCompleter,
    );
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(runtime.syncCount, 1);
    expect(find.text('暂无会话'), findsOneWidget);
    expect(find.text('正在读取本地会话'), findsNothing);
    expect(find.byKey(const ValueKey('chat-sync-progress')), findsNothing);
    expect(find.textContaining('正在连接'), findsNothing);

    store.replaceConversations([
      ChatConversationPreview(
        conversationId: 'dm:alice-wallet:bob-wallet',
        title: 'Bob',
        peerUserId: _peerUserId,
        lastMessage: '后台补发完成后的本地结果',
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2),
        unreadCount: 0,
        deliveryState: ChatMessageDeliveryState.receivedByDevice,
      ),
    ]);
    retryCompleter.complete(0);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('后台补发完成后的本地结果'), findsOneWidget);
    expect(find.textContaining('正在连接'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('后台聊天服务失败保留已显示的本地会话且不显示连接文案', (tester) async {
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      retryError: StateError('测试后台服务失败'),
    );
    final store = _FakeChatStore(
      conversations: [
        ChatConversationPreview(
          conversationId: 'dm:alice-wallet:bob-wallet',
          title: 'Bob',
          peerUserId: _peerUserId,
          lastMessage: '本地会话必须保留',
          lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          unreadCount: 0,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('本地会话必须保留'), findsOneWidget);
    expect(find.text('正在读取本地会话'), findsNothing);
    expect(find.textContaining('正在连接'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('聊天 Tab uses realtime notice before polling fallback', (
    tester,
  ) async {
    final runtime = _FakeRuntime(
      address:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      enableRealtime: true,
    );
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: store,
            cidNumber: _ownerUserId,
            accountId:
                '0x1111111111111111111111111111111111111111111111111111111111111111',
            runtime: runtime,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(runtime.syncCount, 1);
    expect(runtime.realtimeStartCount, 1);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(runtime.syncCount, 1);

    await runtime.realtimeNotice?.call();
    await tester.pump();

    expect(runtime.syncCount, 2);
    expect(store.readPreviewCount, greaterThanOrEqualTo(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(runtime.realtimeStopCount, 1);
  });

  testWidgets('聊天页打开后自动重试本机发送队列', (tester) async {
    var syncCount = 0;
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
          onSync: () async {
            syncCount += 1;
            return 0;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(syncCount, 1);
    expect(store.readMessagesCount, greaterThanOrEqualTo(1));

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(syncCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('聊天页 uses realtime notice before polling fallback', (
    tester,
  ) async {
    var syncCount = 0;
    var realtimeStopCount = 0;
    Future<void> Function()? realtimeNotice;
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
          onSync: () async {
            syncCount += 1;
            return 0;
          },
          onStartRealtime: ({required onNotice, onDisconnected}) async {
            realtimeNotice = onNotice;
            return () async {
              realtimeStopCount += 1;
            };
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(syncCount, 1);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(syncCount, 1);

    await realtimeNotice?.call();
    await tester.pump();

    expect(syncCount, 1, reason: 'Realtime 入站通知只重读本地当前会话，不重复发起网络补发');
    expect(store.readMessagesCount, greaterThanOrEqualTo(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(realtimeStopCount, 1);
  });

  testWidgets('历史坏密文隔离提示在心跳刷新期间保持稳定且有效消息不消失', (tester) async {
    final message = ChatStoredMessage(
      messageId: 'env-readable',
      conversationId: 'dm:me:peer',
      direction: 'incoming',
      senderUserId: _peerUserId,
      recipientUserId: _ownerUserId,
      messageKind: ChatMessageKind.text,
      deliveryState: ChatMessageDeliveryState.receivedByDevice,
      createdAtMillis: 1000,
      plaintext: ChatPayloadCodec.encode(ChatContent.text('仍然可见的消息')),
    );
    final store = _IntegrityRefreshStore(message);
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:me:peer',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: '张三',
          store: store,
          onSync: () async => 0,
          onStartRealtime: ({required onNotice, onDisconnected}) async =>
              () async {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notice = find.text('部分本机历史消息无法验证，其他记录已正常显示');
    final readable = find.text('仍然可见的消息');
    expect(notice, findsOneWidget);
    expect(readable, findsOneWidget);
    final initialTop = tester.getTopLeft(readable).dy;

    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(notice, findsOneWidget, reason: '后台刷新开始时不得先移除提示造成页面上下抖动');
    expect(tester.getTopLeft(readable).dy, initialTop);

    store.completeHeartbeat();
    await tester.pump();
    expect(notice, findsOneWidget);
    expect(readable, findsOneWidget);
    expect(tester.getTopLeft(readable).dy, initialTop);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('聊天页相册动作发送选择的加密媒体', (tester) async {
    ChatMediaDraft? sentMedia;
    ChatMediaLocalCommitNotifier? localCommitted;
    final network = Completer<void>();
    final store = _FakeChatStore();

    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
          pickMedia: () async => const ChatMediaDraft(
            kind: ChatMessageKind.file,
            fileName: 'note.txt',
            contentType: 'text/plain',
            sourcePath: '/tmp/note.txt',
            byteSize: 3,
          ),
          onSendMedia: (media, {onLocalCommitted}) async {
            sentMedia = media;
            localCommitted = onLocalCommitted;
            await network.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-actions-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-action-gallery')));
    await tester.pump();

    expect(sentMedia?.kind, ChatMessageKind.file);
    expect(sentMedia?.fileName, 'note.txt');
    expect(sentMedia?.sourcePath, '/tmp/note.txt');
    expect(sentMedia?.byteSize, 3);
    expect(find.text('note.txt'), findsOneWidget, reason: '媒体网络未完成也必须先显示本地气泡');

    await localCommitted?.call();
    network.complete();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('聊天页 taps a file message to save the received media', (
    tester,
  ) async {
    final store = _FakeChatStore(
      messages: [
        ChatStoredMessage(
          messageId: 'env-attachment',
          conversationId: 'dm:alice-wallet:bob-wallet',
          direction: 'incoming',
          senderUserId: _peerUserId,
          recipientUserId: _ownerUserId,
          messageKind: ChatMessageKind.file,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
          createdAtMillis: 3000,
          plaintext: ChatPayloadCodec.encode(
            ChatContent.media(
              kind: ChatMessageKind.file,
              attachmentId: 'att-1',
              fileName: 'photo.txt',
              mime: 'text/plain',
              byteSize: 3,
              cipherKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              cipherByteSize: 19,
              cipherSha256:
                  '0000000000000000000000000000000000000000000000000000000000000000',
            ),
          ),
        ),
      ],
    );
    String? downloadedPlaintext;

    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
          onDownloadAttachment: (conversationId, controlPlaintext) async {
            downloadedPlaintext = controlPlaintext;
            return const ChatDownloadedAttachment(
              attachmentId: 'att-1',
              fileName: 'photo.txt',
              contentType: 'text/plain',
              clearByteSize: 3,
              filePath: '/tmp/photo.txt',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('photo.txt'));
    await tester.pumpAndSettle();

    expect(
      ChatPayloadCodec.decode(downloadedPlaintext!).kind,
      ChatMessageKind.file,
    );
    expect(find.text('已保存：photo.txt'), findsOneWidget);
  });

  testWidgets('聊天页 deletes local conversation from menu and returns', (
    tester,
  ) async {
    final allowPhysicalDelete = Completer<void>();
    var deleteCalls = 0;
    final store = _FakeChatStore(
      messages: [
        ChatStoredMessage(
          messageId: 'env-delete-ui',
          conversationId: 'dm:alice-wallet:bob-wallet',
          direction: 'incoming',
          senderUserId: _peerUserId,
          recipientUserId: _ownerUserId,
          messageKind: ChatMessageKind.text,
          deliveryState: ChatMessageDeliveryState.receivedByDevice,
          createdAtMillis: 1000,
          plaintext: ChatPayloadCodec.encode(ChatContent.text('hello')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CitizenChatPage(
                        conversationId: 'dm:alice-wallet:bob-wallet',
                        ownerUserId: _ownerUserId,
                        accountId:
                            '0x1111111111111111111111111111111111111111111111111111111111111111',
                        peerUserId: _peerUserId,
                        title: 'Bob',
                        store: store,
                        onDeleteConversation: () async {
                          deleteCalls += 1;
                          await allowPhysicalDelete.future;
                          await store.deleteConversation(
                            _ownerUserId,
                            'dm:alice-wallet:bob-wallet',
                            bindingToken: const ChatBindingFenceToken(
                              ownerUserId: _ownerUserId,
                              bindingRevision: 1,
                              accountId:
                                  '0x1111111111111111111111111111111111111111111111111111111111111111',
                              keyDomain:
                                  '0x4242424242424242424242424242424242424242424242424242424242424242',
                              generation: 1,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('打开聊天'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开聊天'));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除聊天记录'));
    await tester.pumpAndSettle();

    expect(find.text('确定删除这台设备上的聊天记录？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pump();

    expect(deleteCalls, 1);
    expect(store.deletedConversationIds, isEmpty, reason: '窗口关闭不得等待后台清理');
    expect(find.text('打开聊天'), findsOneWidget);

    allowPhysicalDelete.complete();
    await tester.pumpAndSettle();
    expect(store.deletedConversationIds, ['dm:alice-wallet:bob-wallet']);
  });

  testWidgets('聊天页把未到达的图片/视频消息渲染为「接收中」占位', (tester) async {
    // 无本机路径(未注入 onResolveMediaPaths)→ source 为空 → 走 hasFile==false 占位分支。
    final store = _FakeChatStore(
      messages: [
        _mediaStored(
          id: 'img',
          kind: ChatMessageKind.image,
          mime: 'image/jpeg',
        ),
        _mediaStored(id: 'vid', kind: ChatMessageKind.video, mime: 'video/mp4'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 图片、视频两条都在"接收中"占位;误反转 hasFile 会去解码空路径而非占位。
    expect(find.text('接收中…'), findsNWidgets(2));
    // 视频占位带播放图标,与图片占位区分。
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('聊天页视频占位从 metadata 读取 blurhash 渲染封面', (tester) async {
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    final store = _FakeChatStore(
      messages: [
        _mediaStored(
          id: 'vid',
          kind: ChatMessageKind.video,
          mime: 'video/mp4',
          blurhash: hash,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CitizenChatPage(
          conversationId: 'dm:alice-wallet:bob-wallet',
          ownerUserId: _ownerUserId,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          peerUserId: _peerUserId,
          title: 'Bob',
          store: store,
        ),
      ),
    );
    // 不用 pumpAndSettle:BlurHash 内部异步解码;只需确认封面 widget 已入树。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 视频封面用 metadata['blurhash'];若误读 message.blurhash(VideoMessage 无此字段)
    // 则渲染空 Container,BlurHash 不出现。
    expect(find.byKey(const ValueKey('chat-video-blurhash')), findsOneWidget);
    // Chat 首帧已经入树时会安排 250ms 的初始滚动，推进到定时器结束，
    // 避免把组件库的正常滚动任务泄漏到下一条测试。
    await tester.pump(const Duration(milliseconds: 300));
  });

  // ---- 顶栏改造：搜索框 + 加号 5 入口 ----

  const self =
      '0x1111111111111111111111111111111111111111111111111111111111111111';

  Future<void> pumpTab(WidgetTester tester, {ChatEntryOpeners? openers}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTab(
            store: _FakeChatStore(),
            cidNumber: _ownerUserId,
            accountId: self,
            runtime: _FakeRuntime(address: self),
            openers: openers,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 菜单开合有动画，但聊天页有 15s 轮询定时器，用 pumpAndSettle 会被推着走，
  /// 因此一律用固定步长 pump。
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('顶部为搜索框、右上角为加号，旧「新建群聊」卡片已删', (tester) async {
    await pumpTab(tester);

    expect(find.text('搜索会话、联系人和聊天记录'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('新建群聊'), findsNothing);
    expect(find.byIcon(Icons.group_add_outlined), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('点加号弹出扫一扫/收付款/发私信/发群聊/加好友五项', (tester) async {
    await pumpTab(tester);
    await openMenu(tester);

    for (final label in ['扫一扫', '收付款', '发私信', '发群聊', '加好友']) {
      expect(find.text(label), findsOneWidget, reason: '缺少菜单项 $label');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('加号弹窗每项在基准视口下约 40 逻辑像素高', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTab(tester);
    await openMenu(tester);

    final rows = <Finder>[];
    for (final label in ['扫一扫', '收付款', '发私信', '发群聊', '加好友']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, closeTo(40, 0.5));
      rows.add(row);
    }
    expect(
      tester.getCenter(rows.last).dy - tester.getCenter(rows.first).dy,
      closeTo(160, 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('扫一扫用扫码 svg（不是二维码图标）、发私信用聊天 tab 同款图标', (tester) async {
    await pumpTab(tester);
    await openMenu(tester);

    // 扫一扫必须与「交易 → 扫一扫」同一份 scan-line.svg。
    final svg = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    expect(
      svg.any((item) {
        final loader = item.bytesLoader;
        return loader is SvgAssetLoader &&
            loader.assetName == 'assets/icons/scan-line.svg';
      }),
      isTrue,
      reason: '扫一扫应使用 assets/icons/scan-line.svg 扫码图标',
    );
    // 防回归：不得再用 Material 的二维码图标顶替扫码图标。
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    expect(find.byIcon(Icons.qr_code_rounded), findsNothing);
    // 发私信与底部导航「聊天」tab 同一个图标。
    expect(find.byIcon(Icons.textsms_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('五项分别路由到对应动作', (tester) async {
    final fired = <String>[];
    await pumpTab(
      tester,
      openers: ChatEntryOpeners(
        openScan: (_) async => fired.add('scan'),
        openReceivePay: (_) async => fired.add('receivePay'),
        openSendMessage: (_) async => fired.add('sendMessage'),
        openCreateGroup: (_) async => fired.add('createGroup'),
        openAddFriend: (_) async => fired.add('addFriend'),
      ),
    );

    for (final label in ['扫一扫', '收付款', '发私信', '发群聊', '加好友']) {
      await openMenu(tester);
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(fired, [
      'scan',
      'receivePay',
      'sendMessage',
      'createGroup',
      'addFriend',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('点搜索框进入聊天搜索页', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('搜索会话、联系人和聊天记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ChatSearchPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

ChatStoredMessage _mediaStored({
  required String id,
  required ChatMessageKind kind,
  required String mime,
  String? blurhash,
}) {
  return ChatStoredMessage(
    messageId: 'env-$id',
    conversationId: 'dm:alice-wallet:bob-wallet',
    direction: 'incoming',
    senderUserId: _peerUserId,
    recipientUserId: _ownerUserId,
    messageKind: kind,
    deliveryState: ChatMessageDeliveryState.receivedByDevice,
    createdAtMillis: 3000,
    plaintext: ChatPayloadCodec.encode(
      ChatContent.media(
        kind: kind,
        attachmentId: 'att-$id',
        fileName: kind == ChatMessageKind.video ? 'v.mp4' : 'p.jpg',
        mime: mime,
        byteSize: 100,
        width: 800,
        height: 600,
        blurhash: blurhash,
        cipherKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        cipherByteSize: 116,
        cipherSha256:
            '1111111111111111111111111111111111111111111111111111111111111111',
      ),
    ),
  );
}

class _FakeChatStore extends ChatStore {
  _FakeChatStore({
    List<ChatConversationPreview> conversations = const [],
    List<ChatStoredMessage> messages = const [],
  })  : _conversations = List<ChatConversationPreview>.from(conversations),
        _messages = List<ChatStoredMessage>.from(messages);

  final List<ChatConversationPreview> _conversations;
  final List<ChatStoredMessage> _messages;
  String? lastAccountFilter;
  int readPreviewCount = 0;
  int readMessagesCount = 0;
  final List<String> deletedConversationIds = <String>[];

  void replaceConversations(List<ChatConversationPreview> conversations) {
    _conversations
      ..clear()
      ..addAll(conversations);
  }

  @override
  Future<List<ChatConversationPreview>> readConversationPreviews({
    required String ownerUserId,
    required String currentAccountId,
  }) async {
    readPreviewCount += 1;
    lastAccountFilter = currentAccountId;
    return List<ChatConversationPreview>.from(_conversations);
  }

  @override
  Future<List<ChatStoredMessage>> readMessages({
    required String ownerUserId,
    required String currentAccountId,
    required String conversationId,
  }) async {
    readMessagesCount += 1;
    return _messages
        .where((message) => message.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<ChatMessageDisplayBatch> readMessagesForDisplay({
    required String ownerUserId,
    required String currentAccountId,
    required String conversationId,
  }) async {
    // 测试替身必须走当前聊天窗口读取契约，同时保留子类对旧读取入口的可控 Future。
    final messages = await readMessages(
      ownerUserId: ownerUserId,
      currentAccountId: currentAccountId,
      conversationId: conversationId,
    );
    return ChatMessageDisplayBatch(
      messages: messages,
      integrityFailureCount: 0,
    );
  }

  @override
  Future<void> deleteConversation(
    String ownerUserId,
    String conversationId, {
    required ChatBindingFenceToken bindingToken,
  }) async {
    deletedConversationIds.add(conversationId);
    _conversations.removeWhere(
      (conversation) => conversation.conversationId == conversationId,
    );
    _messages.removeWhere(
      (message) => message.conversationId == conversationId,
    );
  }

  @override
  Future<int> outboundQueueCount(String ownerUserId) async {
    return 0;
  }
}

class _PendingChatStore extends _FakeChatStore {
  final Completer<List<ChatConversationPreview>> completer =
      Completer<List<ChatConversationPreview>>();

  @override
  Future<List<ChatConversationPreview>> readConversationPreviews({
    required String ownerUserId,
    required String currentAccountId,
  }) =>
      completer.future;
}

class _PendingMessagesStore extends _FakeChatStore {
  final Completer<List<ChatStoredMessage>> completer =
      Completer<List<ChatStoredMessage>>();

  @override
  Future<List<ChatStoredMessage>> readMessages({
    required String ownerUserId,
    required String currentAccountId,
    required String conversationId,
  }) =>
      completer.future;
}

class _IntegrityRefreshStore extends _FakeChatStore {
  _IntegrityRefreshStore(this.message)
      : super(messages: <ChatStoredMessage>[message]);

  final ChatStoredMessage message;
  final Completer<ChatMessageDisplayBatch> _heartbeat =
      Completer<ChatMessageDisplayBatch>();
  var _reads = 0;

  @override
  Future<ChatMessageDisplayBatch> readMessagesForDisplay({
    required String ownerUserId,
    required String currentAccountId,
    required String conversationId,
  }) {
    _reads += 1;
    if (_reads == 1) {
      return Future<ChatMessageDisplayBatch>.value(
        ChatMessageDisplayBatch(
          messages: <ChatStoredMessage>[message],
          integrityFailureCount: 1,
        ),
      );
    }
    return _heartbeat.future;
  }

  void completeHeartbeat() {
    if (_heartbeat.isCompleted) return;
    _heartbeat.complete(
      ChatMessageDisplayBatch(
        messages: <ChatStoredMessage>[message],
        integrityFailureCount: 1,
      ),
    );
  }
}

class _FakeProfileApi extends CitizenProfileApi {
  _FakeProfileApi(this.profile);

  final CitizenProfile profile;

  @override
  Future<CitizenProfile> fetchProfile(
    String cidNumber, {
    SquareSession? session,
  }) async =>
      profile;
}

class _FakeContactService extends UserContactService {
  _FakeContactService(this.contacts) : super(autoSync: false);

  final List<UserContact> contacts;

  @override
  Future<List<UserContact>> getContacts() async => contacts;
}

class _MemoryProfileCache extends CitizenProfileCache {
  const _MemoryProfileCache(this.profile);

  final CitizenProfile profile;

  @override
  Future<CitizenProfile?> read(String cidNumber) async => profile;

  @override
  Future<void> write(CitizenProfile profile) async {}
}

class _MemoryProfileMediaCache extends CitizenProfileMediaCache {
  _MemoryProfileMediaCache(this.snapshot);

  final CitizenProfileMediaSnapshot snapshot;

  @override
  Future<CitizenProfileMediaSnapshot> read(CitizenProfile profile) async =>
      snapshot;

  @override
  Future<CitizenProfileMediaSnapshot> refresh({
    required CitizenProfile profile,
    required String? avatarUrl,
    required String? bannerUrl,
    required Map<String, String>? headers,
  }) async =>
      snapshot;
}

class _FakeProfileSessionProvider extends SquareSessionProvider {
  @override
  Future<SquareSession?> ensureSession() async => SquareSession(
        sessionToken: 'profile-token',
        cidNumber: _ownerUserId,
        bindingRevision: 1,
        accountId:
            '0x1111111111111111111111111111111111111111111111111111111111111111',
        expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      );
}

class _FakeRuntime extends ChatSdk {
  _FakeRuntime({
    required this.address,
    this.enableRealtime = false,
    this.onDeleteConversation,
    this.retryCompleter,
    this.retryError,
  }) : super(host: createCitizenChatRuntimeHost());

  final String address;
  final bool enableRealtime;
  final Future<void> Function(String conversationId)? onDeleteConversation;
  final Completer<int>? retryCompleter;
  final Object? retryError;
  int syncCount = 0;
  int realtimeStartCount = 0;
  int realtimeStopCount = 0;
  final List<({String? recipientUserId, String? conversationId})> retryScopes =
      [];
  final List<bool> realtimeRetryOutgoingOnConnect = [];
  Future<void> Function()? realtimeNotice;
  Future<void> Function()? realtimeDisconnected;
  // 记录贴纸发送接线的四参,验证 chat_tab 委托到 runtime.sendSticker 无换位/漏接。
  final List<List<String>> sentStickers = <List<String>>[];

  @override
  Future<String?> readAccountId() async {
    return address;
  }

  @override
  Future<String?> readUserId() async => _ownerUserId;

  @override
  Future<List<ChatDeliveryResult>> sendSticker({
    required String peerUserId,
    required String conversationId,
    required String packId,
    required String stickerId,
  }) async {
    sentStickers.add([peerUserId, conversationId, packId, stickerId]);
    return const [];
  }

  @override
  Future<int> retryOutgoing({
    String? recipientUserId,
    String? conversationId,
  }) async {
    syncCount += 1;
    retryScopes.add((
      recipientUserId: recipientUserId,
      conversationId: conversationId,
    ));
    final error = retryError;
    if (error != null) {
      throw error;
    }
    final completer = retryCompleter;
    if (completer != null) {
      return completer.future;
    }
    return 0;
  }

  @override
  Future<void> deleteLocalConversation(String conversationId) async {
    final deleter = onDeleteConversation;
    if (deleter == null) {
      throw StateError('测试未注入 ChatSdk 会话删除入口');
    }
    await deleter(conversationId);
  }

  @override
  Future<Future<void> Function()?> startRealtimeSync({
    required Future<void> Function() onNotice,
    Future<void> Function()? onDisconnected,
    Future<void> Function(Map<String, dynamic> signal)? onSignal,
    bool retryOutgoingOnConnect = true,
  }) async {
    realtimeStartCount += 1;
    realtimeRetryOutgoingOnConnect.add(retryOutgoingOnConnect);
    realtimeNotice = onNotice;
    realtimeDisconnected = onDisconnected;
    if (!enableRealtime) {
      return null;
    }
    return () async {
      realtimeStopCount += 1;
    };
  }
}
