import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
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
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/ui/app_theme.dart';

const _accountId =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _contactAddress = 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT';
const _contactAccountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';

/// 联系人身份主键 CID 号。通讯录关系按 cid_number 建立，页面直接用它索引公开资料。
const _contactCidNumber = 'CN220-CTZN2-100000001-2026';
final _ownerAccount = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  accountId: _accountId,
  ss58Address: 'ss58-owner',
  name: '默认账户',
  createdAtMillis: BigInt.one,
  isDefault: true,
);

AccountDataBinding _ownerBinding() => AccountDataBinding(
  genesisHash: '0x${'11' * 32}',
  cidNumber: 'CN220-CTZN2-100000009-2026',
  accountId: _accountId,
  bindingRevision: 1,
);
const _contact = UserContact(
  cidNumber: _contactCidNumber,
  accountId: _contactAccountId,
  ss58Address: _contactAddress,
  contactRemark: '张三',
  createdAt: 1,
  updatedAt: 2,
);
const _profile = CitizenProfile(
  accountId: _contactAccountId,
  displayName: 'Rhett',
  bio: '建设一个可信、自由的社会',
  avatarObjectKey: null,
  bannerObjectKey: null,
  cidNumber: _contactCidNumber,
  isCertified: true,
  identityLevel: 'voting',
  membershipLevel: 'democracy',
  membershipActive: true,
  following: 1,
  followers: 2,
  mutualFollowing: 1,
  posts: 3,
  campaigns: 0,
  videos: 1,
  articles: 1,
  isFollowing: false,
  isFollowedBy: false,
  isNotifying: false,
  updatedAt: 2,
);

class _FakeContacts implements UserContactService {
  @override
  final ValueNotifier<ContactSyncState> syncState =
      ValueNotifier<ContactSyncState>(
        const ContactSyncState(phase: ContactSyncPhase.idle),
      );

  List<UserContact> contacts = <UserContact>[_contact];

  /// `getContacts` 调用次数。未注册时必须为 0——通讯录属主就是 CID,
  /// 没有 CID 连读都不该读(读了必抛 WalletAuthException 并落成假的「空通讯录」)。
  int getContactsCalls = 0;

  @override
  Future<String> getAccountId() async => _accountId;

  @override
  Future<List<UserContact>> getContacts() async {
    getContactsCalls++;
    return contacts;
  }

  @override
  Future<List<UserContact>> refreshContactBindings() async => contacts;

  @override
  Future<UserContact> resolveCurrentContact(String cidNumber) async =>
      contacts.singleWhere((contact) => contact.cidNumber == cidNumber);

  @override
  Future<List<UserContact>> sync() async {
    syncState.value = const ContactSyncState(phase: ContactSyncPhase.synced);
    return contacts;
  }

  @override
  Future<ContactSyncState> readSyncState() async =>
      const ContactSyncState(phase: ContactSyncPhase.synced);

  @override
  Future<List<UserContact>> renameContact(
    String cidNumber,
    String contactRemark,
  ) async {
    contacts = <UserContact>[
      _contact.copyWith(contactRemark: contactRemark, updatedAt: 3),
    ];
    return contacts;
  }

  @override
  Future<List<UserContact>> deleteContact(String cidNumber) async {
    contacts = const <UserContact>[];
    return contacts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingContacts extends _FakeContacts {
  final Completer<List<UserContact>> completer = Completer<List<UserContact>>();

  @override
  Future<List<UserContact>> getContacts() => completer.future;
}

class _FakeProfileApi extends CitizenProfileApi {
  _FakeProfileApi(this.profile);

  final CitizenProfile profile;

  @override
  Future<CitizenProfile> fetchProfile(
    String cidNumber, {
    SquareSession? session,
  }) async => profile;
}

class _PendingProfileApi extends CitizenProfileApi {
  final Completer<CitizenProfile> completer = Completer<CitizenProfile>();

  @override
  Future<CitizenProfile> fetchProfile(
    String cidNumber, {
    SquareSession? session,
  }) => completer.future;
}

class _FakeSessionProvider implements SquareSessionProvider {
  @override
  Future<SquareSession?> ensureSession() async => SquareSession(
    sessionToken: 'token',
    cidNumber: "CN220-CTZN2-198805200-2026",
    bindingRevision: 1,
    accountId: _accountId,
    expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
  );

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    final session = await ensureSession();
    return SquareSessionResolution(SquareSessionStatus.ready, session: session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryProfileCache extends CitizenProfileCache {
  const _MemoryProfileCache(this.profile);

  final CitizenProfile? profile;

  @override
  Future<CitizenProfile?> read(String cidNumber) async => profile;

  @override
  Future<void> write(CitizenProfile profile) async {}
}

class _ThrowingProfileCache extends CitizenProfileCache {
  const _ThrowingProfileCache();

  @override
  Future<CitizenProfile?> read(String cidNumber) async =>
      throw StateError('cache unavailable');
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
  }) async => snapshot;
}

Widget _page({
  TargetPlatform platform = TargetPlatform.android,
  ContactPickMode mode = ContactPickMode.browse,
  CitizenProfile profile = _profile,
  CitizenProfileApi? profileApi,
  UserContactService? service,
  Map<String, CitizenProfile>? initialProfiles,
  CitizenProfileCache? profileCache,
  CitizenProfileMediaCache? profileMediaCache,
  DirectChatOpener? directChatOpener,
  Future<void> Function(BuildContext context, {required String toSs58Address})?
  transferOpener,
  CurrentUserContext? currentUserContext,
  Listenable? identityRevision,
}) => MaterialApp(
  theme: AppTheme.lightTheme.copyWith(platform: platform),
  home: ContactBookPage(
    mode: mode,
    service: service ?? _FakeContacts(),
    profileApi: profileApi ?? _FakeProfileApi(profile),
    profileCache: profileCache,
    profileMediaCache: profileMediaCache,
    sessionProvider: _FakeSessionProvider(),
    initialProfiles: initialProfiles ?? {_contactCidNumber: profile},
    directChatOpener: directChatOpener,
    transferOpener: transferOpener,
    currentUserContext: currentUserContext ?? _RegisteredIdentityCache(),
    identityRevision: identityRevision,
  ),
);

/// 身份账户缓存 fake:**已注册**。通讯录属主 = CID,页面对未注册身份整页显示注册
/// 引导,因此常规用例必须注入已注册身份,否则测的全是引导态。
/// `accountId` 仍返回 null,让点开他人主页时 `_resolveOwnAccount` 回退成「非本人」
/// (行为与迁移前一致);避免 instance 触发真链读/真 Isar。
class _RegisteredIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async =>
      CurrentUser(account: _ownerAccount, binding: _ownerBinding());
  @override
  Future<String?> accountId() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 未注册：当前默认账户的本地绑定为空，不回退到其他账户。
class _UnregisteredIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async =>
      CurrentUser(account: _ownerAccount, binding: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableIdentityCache implements CurrentUserContext {
  bool registered = false;

  @override
  Future<CurrentUser?> resolve() async => CurrentUser(
    account: _ownerAccount,
    binding: registered ? _ownerBinding() : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('本地通讯录未返回时直接显示页面结构且不使用整页转圈', (tester) async {
    final service = _PendingContacts();
    await tester.pumpWidget(_page(service: service));
    await tester.pump();

    expect(find.text('我的通讯录'), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-search')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('contacts-local-load-progress')),
      findsOneWidget,
    );
    expect(find.text('正在读取本地通讯录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.completer.complete(const <UserContact>[]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contacts-local-load-progress')),
      findsNothing,
    );
  });

  testWidgets('联系人卡以公开昵称为主并只展示备注与公民号', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('云端已同步'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('contact-card-$_contactCidNumber')),
        matching: find.text('Rhett'),
      ),
      findsOneWidget,
    );
    expect(find.text('备注：张三'), findsOneWidget);
    expect(find.text('公民号：$_contactCidNumber'), findsOneWidget);
    expect(find.textContaining('SS58：'), findsNothing);
    expect(find.text('建设一个可信、自由的社会'), findsNothing);
    expect(
      find.byKey(const ValueKey('contact-card-$_contactCidNumber')),
      findsOneWidget,
    );
  });

  testWidgets('联系人列表首帧直接使用公开资料与本机头像缓存', (tester) async {
    final profile = _profile.copyWith(
      avatarObjectKey: 'profile/$_contactCidNumber/avatar',
    );
    const avatarPath = '/cached/profile/avatar.webp';
    await tester.pumpWidget(
      _page(
        profile: profile,
        initialProfiles: const <String, CitizenProfile>{},
        profileCache: _MemoryProfileCache(profile),
        profileMediaCache: _MemoryProfileMediaCache(
          const CitizenProfileMediaSnapshot(avatarPath: avatarPath),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(avatar.imagePath, avatarPath);
    expect(avatar.userImageSet, isTrue);
    expect(avatar.membershipLevel, 'democracy');
    expect(avatar.membershipActive, isTrue);
    expect(avatar.showBadge, isTrue);
  });

  testWidgets('公开资料缓存故障不阻塞通讯录且未知态不显示旧头像徽章', (tester) async {
    final profileApi = _PendingProfileApi();
    await tester.pumpWidget(
      _page(
        initialProfiles: const <String, CitizenProfile>{},
        profileApi: profileApi,
        profileCache: const _ThrowingProfileCache(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('contact-card-$_contactCidNumber')),
      findsOneWidget,
    );
    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
    expect(avatar.userImageSet, isTrue);
    expect(avatar.showBadge, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Android 与 iOS 联系人卡的高度和操作图标一致', (tester) async {
    final sizes = <TargetPlatform, Size>{};
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.pumpWidget(_page(platform: platform));
      await tester.pumpAndSettle();
      sizes[platform] = tester.getSize(
        find.byKey(const ValueKey('contact-card-$_contactCidNumber')),
      );
      expect(tester.getSize(find.byIcon(Icons.more_vert)), const Size(24, 24));
    }

    expect(sizes[TargetPlatform.iOS], sizes[TargetPlatform.android]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索只匹配公开昵称、备注或公民号，不匹配账户地址', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('contact-search')),
      'Rhett',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('contact-card-$_contactCidNumber')),
        matching: find.text('Rhett'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('contact-search')),
      _contactAddress,
    );
    await tester.pump();
    expect(find.text('没有匹配的联系人'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('contact-search')),
      _contactAccountId,
    );
    await tester.pump();
    expect(find.text('没有匹配的联系人'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('contact-search')), '不存在');
    await tester.pump();
    expect(find.text('没有匹配的联系人'), findsOneWidget);
  });

  testWidgets('公开昵称缺失时显示默认昵称而不是把账户当昵称', (tester) async {
    final emptyProfile = _profile.copyWith(displayName: '');
    await tester.pumpWidget(_page(profile: emptyProfile));
    await tester.pumpAndSettle();

    final fallback = ProfilePresentation.forIdentityKey(
      _contactCidNumber,
    ).fallbackName;
    expect(find.text(fallback), findsOneWidget);
    expect(find.textContaining('SS58：'), findsNothing);
  });

  testWidgets('普通点击进入唯一 UserProfilePage', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rhett'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(UserProfilePage), findsOneWidget);
  });

  testWidgets('联系人菜单顺序正确且删除联系人使用红色文字', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    // 显式竖向图标保证 Android/iOS 一致，不依赖平台自适应默认值。
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    await tester.tap(find.byTooltip('联系人操作'));
    await tester.pumpAndSettle();

    final labels = <String>['转账', '私信', '修改备注', '删除联系人'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    final deleteText = tester.widget<Text>(find.text('删除联系人'));
    expect(deleteText.style?.color, AppTheme.danger);
  });

  testWidgets('修改私人备注可取消、保存中文或清空', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('联系人操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '李四');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('备注：张三'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('联系人操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '李四');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('备注：李四'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('转账打开链上支付并预填联系人钱包账户', (tester) async {
    String? openedToAddress;
    Future<void> opener(
      BuildContext context, {
      required String toSs58Address,
    }) async {
      openedToAddress = toSs58Address;
    }

    await tester.pumpWidget(_page(transferOpener: opener));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('联系人操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转账'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(openedToAddress, _contactAddress);
  });

  testWidgets('私信复用统一聊天入口并使用公开昵称', (tester) async {
    String? openedPeerCidNumber;
    String? openedTitle;
    Future<void> opener(
      BuildContext context, {
      required String peerUserId,
      required String title,
    }) async {
      // 注入只用于断言路由参数，不替代正式 openDirectChat 实现。
      openedPeerCidNumber = peerUserId;
      openedTitle = title;
    }

    await tester.pumpWidget(_page(directChatOpener: opener));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('联系人操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私信'));
    await tester.pump();

    expect(openedPeerCidNumber, _contactCidNumber);
    expect(openedTitle, 'Rhett');
  });

  testWidgets('发私信模式点联系人直接开私聊、无操作菜单', (tester) async {
    String? openedPeerCidNumber;
    String? openedTitle;
    Future<void> opener(
      BuildContext context, {
      required String peerUserId,
      required String title,
    }) async {
      openedPeerCidNumber = peerUserId;
      openedTitle = title;
    }

    await tester.pumpWidget(
      _page(mode: ContactPickMode.pickForMessage, directChatOpener: opener),
    );
    await tester.pumpAndSettle();

    // 选私信模式:不显示逐项操作菜单,点联系人卡即开私聊。
    expect(find.byTooltip('联系人操作'), findsNothing);
    await tester.tap(find.text('Rhett'));
    await tester.pump();

    expect(openedPeerCidNumber, _contactCidNumber);
    expect(openedTitle, 'Rhett');
  });

  testWidgets('未注册身份显示统一注册引导,且不读通讯录', (tester) async {
    final service = _FakeContacts();
    await tester.pumpWidget(
      _page(service: service, currentUserContext: _UnregisteredIdentityCache()),
    );
    await tester.pumpAndSettle();

    // 整页统一引导,不再是假的「空通讯录」。
    expect(find.text('尚未注册'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('还没有联系人'), findsNothing);
    expect(find.byKey(const ValueKey('contact-search')), findsNothing);

    // 短路铁证:通讯录一次都没读。
    expect(service.getContactsCalls, 0);
  });

  testWidgets('已注册身份正常展示通讯录(引导不误伤)', (tester) async {
    final service = _FakeContacts();
    await tester.pumpWidget(_page(service: service));
    await tester.pumpAndSettle();

    expect(find.text('尚未注册'), findsNothing);
    expect(find.byKey(const ValueKey('contact-search')), findsOneWidget);
    expect(service.getContactsCalls, greaterThan(0));
  });

  testWidgets('同一账户 finalized 注册广播后原地退出尚未注册页', (tester) async {
    final identityCache = _MutableIdentityCache();
    final revision = ValueNotifier<int>(0);
    final service = _FakeContacts();
    await tester.pumpWidget(
      _page(
        service: service,
        currentUserContext: identityCache,
        identityRevision: revision,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('尚未注册'), findsOneWidget);
    expect(service.getContactsCalls, 0);

    identityCache.registered = true;
    revision.value += 1;
    await tester.pumpAndSettle();

    expect(find.text('尚未注册'), findsNothing);
    expect(find.byKey(const ValueKey('contact-search')), findsOneWidget);
    expect(service.getContactsCalls, greaterThan(0));
  });
}
