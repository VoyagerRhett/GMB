import 'dart:async';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'chat_product_policy.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/qr/scan_dispatch_flow.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_page.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/identity_register_guide.dart';
import 'package:citizenapp/wallet/core/wallet_manager.dart';
import 'package:citizenapp/wallet/widgets/wallet_qr_dialog.dart';

typedef CitizenChatDownloadAttachmentCallback = Future<ChatDownloadedAttachment>
    Function(
  String conversationId,
  String controlPlaintext,
);
typedef CitizenChatResolveMediaPathsCallback = Future<Map<String, String>>
    Function(
  String conversationId,
  List<ChatContent> contents,
);
typedef ChatResolvePeerAddressCallback = Future<String> Function(
    String peerUserId);

/// CitizenApp 的产品宿主薄层；完整会话页面与通用交互由 TataChatSDK 提供。
class CitizenChatPage extends StatelessWidget {
  CitizenChatPage({
    super.key,
    required this.conversationId,
    required this.ownerUserId,
    required this.accountId,
    required this.peerUserId,
    required this.title,
    this.isGroup = false,
    ChatStore? store,
    this.onSendText,
    this.onSendMedia,
    this.onSendSticker,
    this.onDownloadAttachment,
    this.onResolveMediaPaths,
    this.pickMedia,
    this.onSync,
    this.onStartRealtime,
    this.onDeleteConversation,
    this.onMarkRead,
    this.resolvePeerAddress,
    this.initialProfile,
    this.initialProfileMedia,
    this.profileApi,
    this.profileCache,
    this.profileMediaCache,
    this.sessionProvider,
  }) : store = store ?? ChatStore();

  final String conversationId;
  final String ownerUserId;
  final String accountId;
  final String peerUserId;
  final String title;
  final bool isGroup;
  final ChatStore store;
  final ChatSendTextCallback? onSendText;
  final ChatSendMediaCallback? onSendMedia;
  final ChatSendStickerCallback? onSendSticker;
  final CitizenChatDownloadAttachmentCallback? onDownloadAttachment;
  final CitizenChatResolveMediaPathsCallback? onResolveMediaPaths;
  final ChatPickMediaCallback? pickMedia;
  final ChatSyncCallback? onSync;
  final ChatStartRealtimeCallback? onStartRealtime;
  final ChatDeleteConversationCallback? onDeleteConversation;
  final ChatMarkReadCallback? onMarkRead;
  final ChatResolvePeerAddressCallback? resolvePeerAddress;
  final CitizenProfile? initialProfile;
  final CitizenProfileMediaSnapshot? initialProfileMedia;
  final CitizenProfileApi? profileApi;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquareSessionProvider? sessionProvider;

  @override
  Widget build(BuildContext context) {
    return ChatConversationPage(
      conversationId: conversationId,
      currentUserId: ownerUserId,
      accountId: accountId,
      peerUserId: peerUserId,
      title: title,
      isGroup: isGroup,
      store: store,
      host: _citizenConversationHost(
        peerUserId: peerUserId,
        title: title,
        isGroup: isGroup,
        resolvePeerAddress: resolvePeerAddress,
        initialProfile: initialProfile,
        initialProfileMedia: initialProfileMedia,
        profileApi: profileApi,
        profileCache: profileCache,
        profileMediaCache: profileMediaCache,
        sessionProvider: sessionProvider,
      ),
      onSendText: onSendText,
      onSendMedia: onSendMedia,
      onSendSticker: onSendSticker,
      onDownloadAttachment: onDownloadAttachment == null
          ? null
          : (controlPlaintext) =>
              onDownloadAttachment!(conversationId, controlPlaintext),
      onResolveMediaPaths: onResolveMediaPaths == null
          ? null
          : (contents) => onResolveMediaPaths!(conversationId, contents),
      pickMedia: pickMedia,
      onSync: onSync,
      onStartRealtime: onStartRealtime,
      onDeleteConversation: onDeleteConversation,
      onMarkRead: onMarkRead,
    );
  }
}

class _CitizenChatConversationHost extends ChatConversationHost {
  const _CitizenChatConversationHost({
    required super.style,
    required super.mediaLimits,
    required super.canSend,
    required super.unavailableMessage,
    required super.errorMessage,
    required super.headerBuilder,
    required super.resolveUser,
    super.groupSenderBuilder,
    super.onTransfer,
    super.actionIconBuilder,
  });

  @override
  String attachmentTooLargeMessage(ChatMessageKind kind) =>
      '文件超出当前会员单个附件上限（${ChatMediaLimits.currentLimitLabel}）';
}

ChatConversationHost _citizenConversationHost({
  required String peerUserId,
  required String title,
  required bool isGroup,
  ChatResolvePeerAddressCallback? resolvePeerAddress,
  CitizenProfile? initialProfile,
  CitizenProfileMediaSnapshot? initialProfileMedia,
  CitizenProfileApi? profileApi,
  CitizenProfileCache? profileCache,
  CitizenProfileMediaCache? profileMediaCache,
  SquareSessionProvider? sessionProvider,
}) {
  const style = ChatViewStyle(
    backgroundColor: AppTheme.scaffoldBg,
    surfaceColor: AppTheme.surfaceCard,
    primaryColor: AppTheme.primary,
    accentColor: AppTheme.accent,
    textPrimaryColor: AppTheme.textPrimary,
    textSecondaryColor: AppTheme.textSecondary,
    textTertiaryColor: AppTheme.textTertiary,
    scaler: AppLayout.scaled,
  );
  return _CitizenChatConversationHost(
    style: style,
    mediaLimits: const CitizenChatMediaLimitPolicy(),
    canSend: ChatMediaLimits.chatAuthorizedFor,
    unavailableMessage: (userId) {
      final resolved = ChatMediaLimits.authorizationResolvedFor(userId) &&
          ChatMediaLimits.resolvedFor(userId);
      return resolved ? '尚未开通会员，订阅任一会员后即可使用聊天' : '暂时无法验证会员状态，请稍后重试';
    },
    errorMessage: chatUserErrorMessage,
    headerBuilder: (context, header) => _CitizenChatHeader(
      peerUserId: header.peerUserId,
      title: header.title,
      isGroup: header.isGroup,
      initialProfile: initialProfile,
      initialProfileMedia: initialProfileMedia,
      profileApi: profileApi,
      profileCache: profileCache,
      profileMediaCache: profileMediaCache,
      sessionProvider: sessionProvider,
    ),
    resolveUser: (userId, currentUserId, group) async => User(
      id: userId,
      name: userId == currentUserId
          ? '我'
          : ProfilePresentation.forIdentityKey(userId).resolveDisplayName(
              publicName: !group && userId == peerUserId ? title : null,
            ),
    ),
    groupSenderBuilder: (context, userId) => Username(
      userId: userId,
      style: TextStyle(
        fontSize: AppLayout.scaled(context, 11),
        color: AppTheme.textSecondary,
      ),
    ),
    onTransfer: (context, targetUserId) async {
      final String ss58Address;
      if (resolvePeerAddress != null) {
        ss58Address = await resolvePeerAddress(targetUserId);
      } else {
        final binding = await CitizenIdentityChainReader()
            .readBindingByCidNumber(targetUserId);
        if (binding == null) {
          throw StateError('对方 CID 当前没有有效钱包绑定');
        }
        ss58Address = ss58FromAccountIdText(binding.accountIdText);
      }
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => OnchainPaymentPage(initialToAddress: ss58Address),
        ),
      );
    },
    actionIconBuilder: (context, action, color, size) {
      if (action != ChatComposerAction.transfer) return null;
      return Image.asset(
        'assets/icons/gmb-mark.png',
        key: const ValueKey('chat-action-transfer-gmb-mark'),
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      );
    },
  );
}

/// 公民资料标题只负责产品资料读取和主页入口，不持有消息运行逻辑。
class _CitizenChatHeader extends StatefulWidget {
  const _CitizenChatHeader({
    required this.peerUserId,
    required this.title,
    required this.isGroup,
    this.initialProfile,
    this.initialProfileMedia,
    this.profileApi,
    this.profileCache,
    this.profileMediaCache,
    this.sessionProvider,
  });

  final String peerUserId;
  final String title;
  final bool isGroup;
  final CitizenProfile? initialProfile;
  final CitizenProfileMediaSnapshot? initialProfileMedia;
  final CitizenProfileApi? profileApi;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquareSessionProvider? sessionProvider;

  @override
  State<_CitizenChatHeader> createState() => _CitizenChatHeaderState();
}

class _CitizenChatHeaderState extends State<_CitizenChatHeader> {
  late final CitizenProfileApi _profileApi =
      widget.profileApi ?? CitizenProfileApi();
  late final CitizenProfileCache _profileCache =
      widget.profileCache ?? const CitizenProfileCache();
  late final CitizenProfileMediaCache _profileMediaCache =
      widget.profileMediaCache ?? CitizenProfileMediaCache();
  late final SquareSessionProvider _sessionProvider =
      widget.sessionProvider ?? SquareSessionProvider.instance;
  CitizenProfile? _profile;
  CitizenProfileMediaSnapshot _media = const CitizenProfileMediaSnapshot();
  SquareSession? _session;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _media = widget.initialProfileMedia ?? const CitizenProfileMediaSnapshot();
    _resolved = widget.initialProfile != null;
    CitizenProfileCache.revision.addListener(_onRevision);
    if (!widget.isGroup) unawaited(_load());
  }

  @override
  void dispose() {
    CitizenProfileCache.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    final event = CitizenProfileCache.revision.value;
    if (event?.cidNumber == widget.peerUserId) unawaited(_readCache());
  }

  Future<void> _readCache() async {
    final profile = await _profileCache.read(widget.peerUserId);
    if (profile == null) return;
    final media = await _profileMediaCache.read(profile);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _media = media;
      _resolved = true;
    });
  }

  Future<void> _load() async {
    if (_profile == null) await _readCache();
    try {
      final session = await _sessionProvider.ensureSession();
      final profile = await _profileApi.fetchProfile(
        widget.peerUserId,
        session: session,
      );
      final media = await _profileMediaCache.read(profile);
      if (!mounted) return;
      setState(() {
        _session = session;
        _profile = profile;
        _media = media;
        _resolved = true;
      });
      await _profileCache.write(profile);
    } on Exception {
      // 产品资料不可用不阻断 SDK 消息页，继续显示缓存或稳定占位。
    }
  }

  Future<void> _openProfile() async {
    if (widget.isGroup || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          cidNumber: widget.peerUserId,
          isSelf: false,
          initialProfile: _profile,
          initialProfileMedia: _media,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGroup) {
      return Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final name = ProfilePresentation.forIdentityKey(
      widget.peerUserId,
    ).resolveDisplayName(publicName: _profile?.displayName ?? widget.title);
    return InkWell(
      key: const ValueKey('chat-peer-profile-entry'),
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
      onTap: _openProfile,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(
            seed: widget.peerUserId,
            size: AppLayout.scaled(context, 36),
            imagePath: _media.avatarPath,
            imageUrl: _profile?.avatarObjectKey?.trim().isNotEmpty == true
                ? _profileApi.mediaUrl(
                    _profile!.avatarObjectKey!,
                    updatedAt: _profile!.updatedAt,
                  )
                : null,
            imageHeaders: _session == null
                ? null
                : <String, String>{
                    'authorization': 'Bearer ${_session!.sessionToken}',
                  },
            userImageSet: _resolved
                ? _profile?.avatarObjectKey?.trim().isNotEmpty == true
                : true,
            identityLevel: _profile?.identityLevel,
            membershipLevel: _profile?.membershipLevel,
            membershipActive: _profile?.membershipActive ?? false,
            showBadge: _resolved,
          ),
          SizedBox(width: AppLayout.scaled(context, 9)),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 17),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _shortAccount(widget.peerUserId),
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shortAccount(String value) {
  if (value.length <= 16) {
    return value;
  }
  return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
}

typedef ChatSendTextFactory = ChatSendTextCallback? Function(
    String peerUserId, String conversationId);
typedef ChatSyncFactory = ChatSyncCallback? Function(String peerUserId);
typedef ChatSendMediaFactory = ChatSendMediaCallback? Function(
    String peerUserId, String conversationId);
typedef ChatDownloadAttachmentFactory = CitizenChatDownloadAttachmentCallback?
    Function(String peerUserId);

/// 聊天页加号菜单 5 个动作的可注入入口。
///
/// 默认全为 null，各动作走真实实现；测试整体替换后即可断言路由，
/// 而不会真的拉起相机、建群页或通讯录（它们会触发 Isar / ChatSdk / 相机）。
class ChatEntryOpeners {
  const ChatEntryOpeners({
    this.openScan,
    this.openReceivePay,
    this.openSendMessage,
    this.openCreateGroup,
    this.openAddFriend,
  });

  /// 扫一扫 = 交易·扫一扫统一分派（扫到用户码按收款人进入转账）。
  final ChatEntryOpener? openScan;

  /// 收付款 = 展示本账户账户码（收款码 `k=4` 生成方待实现）。
  final ChatEntryOpener? openReceivePay;

  /// 发私信 = 通讯录单选后直开私聊。
  final ChatEntryOpener? openSendMessage;

  /// 发群聊 = 通讯录多选（≥2 人）建群。
  final ChatEntryOpener? openCreateGroup;

  /// 加好友 = 扫对方二维码写入本人通讯录。
  final ChatEntryOpener? openAddFriend;
}

/// 加号菜单单个动作的入口签名；默认钱包等依赖一律由真实实现内部解析，
/// 注入替身时不触碰 WalletManager / Isar / 相机。
typedef ChatEntryOpener = Future<void> Function(BuildContext context);

/// 公民“聊天”Tab。
///
/// 顶部为搜索框（进入 [ChatSearchPage]），右上角加号弹出 5 个入口：
/// 扫一扫 / 收付款 / 发私信 / 发群聊 / 加好友。会话列表在其下方。
class ChatTab extends StatefulWidget {
  ChatTab({
    super.key,
    ChatStore? store,
    WalletManager? walletManager,
    this.cidNumber,
    this.accountId,
    this.sendTextFactory,
    this.sendMediaFactory,
    this.downloadAttachmentFactory,
    this.syncFactory,
    this.runtime,
    this.selectedTab,
    this.tabIndex = 2,
    this.openers,
    this.profileApi,
    this.profileCache,
    this.profileMediaCache,
    this.sessionProvider,
    this.contactService,
    this.subscriptionService,
  })  : store = store ?? ChatStore(),
        walletManager = walletManager ?? WalletManager();

  final ChatStore store;
  final WalletManager walletManager;
  final String? cidNumber;
  final String? accountId;
  final ChatSendTextFactory? sendTextFactory;
  final ChatSendMediaFactory? sendMediaFactory;
  final ChatDownloadAttachmentFactory? downloadAttachmentFactory;
  final ChatSyncFactory? syncFactory;
  final ChatSdk? runtime;
  final ValueListenable<int>? selectedTab;
  final int tabIndex;

  /// 加号菜单动作入口；仅测试注入，正式运行为 null 走真实实现。
  final ChatEntryOpeners? openers;
  final CitizenProfileApi? profileApi;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquareSessionProvider? sessionProvider;
  final UserContactService? contactService;
  final SubscriptionService? subscriptionService;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  List<ChatConversationPreview> _conversations = const [];
  // 用户确认删除后先从所有页面读取结果中屏蔽该会话；物理清理即使仍在
  // 等待文件 lease，轮询、Realtime 或路由返回重载也不得把卡片重新插回。
  final Set<String> _conversationDeletesInFlight = <String>{};
  late final CitizenProfileApi _profileApi =
      widget.profileApi ?? CitizenProfileApi();
  late final CitizenProfileCache _profileCache =
      widget.profileCache ?? const CitizenProfileCache();
  late final CitizenProfileMediaCache _profileMediaCache =
      widget.profileMediaCache ?? CitizenProfileMediaCache();
  late final SquareSessionProvider _sessionProvider =
      widget.sessionProvider ?? SquareSessionProvider.instance;
  late final SubscriptionService _subscriptionService =
      widget.subscriptionService ?? SubscriptionService();
  late final UserContactService _contactService = widget.contactService ??
      UserContactService(walletManager: widget.walletManager);
  final Map<String, CitizenProfile> _peerProfiles = <String, CitizenProfile>{};
  final Map<String, CitizenProfileMediaSnapshot> _peerProfileMedia =
      <String, CitizenProfileMediaSnapshot>{};
  final Set<String> _resolvedPeerCidNumbers = <String>{};
  final Map<String, String> _peerContactRemarks = <String, String>{};
  SquareSession? _profileSession;
  String _cidNumber = '';
  String _accountId = '';
  bool _loading = true;
  String? _error;

  late final ChatConversationListController _listController;

  bool get _isTabSelected =>
      widget.selectedTab == null ||
      widget.selectedTab!.value == widget.tabIndex;

  bool get _isActive => _listController.isActive;

  @override
  void initState() {
    super.initState();
    _listController = ChatConversationListController(
      onCoordinate: () => _reload(syncFirst: true),
      onRefresh: _syncAndRefresh,
      onStartRealtime: _startRealtime,
    );
    _listController.start(visible: _isTabSelected);
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
    widget.selectedTab?.addListener(_onSelectedTabChanged);
    WalletManager.walletsRevision.addListener(_onWalletsChanged);
    CitizenProfileCache.revision.addListener(_onProfileRevision);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestCoordinate());
  }

  @override
  void didUpdateWidget(covariant ChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      oldWidget.selectedTab?.removeListener(_onSelectedTabChanged);
      widget.selectedTab?.addListener(_onSelectedTabChanged);
      _onSelectedTabChanged();
    }
  }

  @override
  void dispose() {
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    CitizenProfileCache.revision.removeListener(_onProfileRevision);
    WalletManager.walletsRevision.removeListener(_onWalletsChanged);
    widget.selectedTab?.removeListener(_onSelectedTabChanged);
    _listController.dispose();
    super.dispose();
  }

  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (mounted && event != null && event.cidNumber == _cidNumber) {
      setState(() {});
    }
  }

  void _onProfileRevision() {
    final event = CitizenProfileCache.revision.value;
    if (!mounted || event == null) return;
    final matches = _conversations.any(
      (preview) => !preview.isGroup && preview.peerUserId == event.cidNumber,
    );
    if (!matches) return;
    unawaited(_readCachedPeerProfiles(_conversations, force: true));
  }

  void _onSelectedTabChanged() {
    _listController.setVisible(_isTabSelected);
    if (_isActive) {
      _requestCoordinate();
    } else {
      _pauseSync();
    }
  }

  /// init、进入 Tab、App resume 全部汇入同一个 coordinator；同一时刻只允许
  /// 一个 reload/sync 链，避免系统 UI 导致 lifecycle 抖动时重复初始化。
  void _requestCoordinate() => _listController.requestCoordinate();

  Future<void> _onWalletsChanged() async {
    // 先廉价比对(纯 Isar 读):默认聊天身份没变的钱包操作(重命名/导入
    // 未置顶钱包)不触发发送队列重试,避免整页转圈与无谓网络请求。
    final identity = await _readIdentity();
    if (!mounted ||
        (identity.accountId == _accountId &&
            identity.cidNumber == _cidNumber)) {
      return;
    }
    if (_accountId.isNotEmpty) {
      await widget.runtime?.invalidateAccount(_accountId);
    }
    _profileSession = null;
    _pauseSync();
    _requestCoordinate();
  }

  /// 本地加载世代号。切默认钱包后并发 reload 乱序完成时，旧身份不得覆写
  /// 新身份；网络与 MLS 后台任务由 SDK 列表控制器的内部世代隔离。
  int _reloadGeneration = 0;

  List<ChatConversationPreview> _withoutDeletingConversations(
    Iterable<ChatConversationPreview> conversations,
  ) =>
      conversations
          .where(
            (preview) =>
                !_conversationDeletesInFlight.contains(preview.conversationId),
          )
          .toList(growable: false);

  Future<void> _reload({bool syncFirst = false}) async {
    if (!_isActive) {
      return;
    }
    final generation = ++_reloadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    String? serviceAccountId;
    String? serviceCidNumber;
    try {
      final identity = await _readIdentity();
      final activeWallet = widget.accountId ?? identity.accountId;
      final ownerUserId = widget.cidNumber ?? identity.cidNumber;
      if (!_isActive) {
        return;
      }
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        if (_cidNumber != ownerUserId) {
          // 私人备注属于当前 CID；切换身份时先同步清空，禁止旧身份备注闪现。
          _peerContactRemarks.clear();
        }
        _cidNumber = ownerUserId;
        _accountId = activeWallet;
      });
      unawaited(_ensureChatEntitlement(ownerUserId, generation));
      if (ownerUserId.isEmpty) {
        // 默认账户未注册 CID 是合法状态；禁止回退到其他账户，必须在此
        // 短路。会话存储读取第一步就要解析密钥绑定,对未注册身份必抛
        // WalletAuthException,catch 成 _error 横幅后会盖住注册引导;轮询/realtime
        // 同样是注定失败的空转。渲染层 `_cidNumber.isEmpty` 分支显示统一注册引导。
        _pauseSync();
        return;
      }
      // 本地阶段只读 ChatIsar。发送队列、Realtime、MLS、FCM 与唤醒端点
      // 全部在本地结果显示后静默执行，不得延长本地加载提示。
      final conversations = await widget.store.readConversationPreviews(
        ownerUserId: ownerUserId,
        currentAccountId: activeWallet,
      );
      if (!mounted || !_isActive || generation != _reloadGeneration) {
        return;
      }
      final visible = _withoutDeletingConversations(conversations);
      setState(() {
        _conversations = visible;
      });
      unawaited(_hydratePeerProfiles(visible));
      if (activeWallet.isNotEmpty) {
        serviceAccountId = activeWallet;
        serviceCidNumber = ownerUserId;
      }
    } catch (error) {
      if (mounted && generation == _reloadGeneration) {
        setState(() {
          _error = chatUserErrorMessage(error);
        });
      }
    } finally {
      if (mounted && generation == _reloadGeneration) {
        setState(() {
          _loading = false;
        });
      }
    }
    if (serviceAccountId != null && serviceCidNumber != null) {
      if (syncFirst) {
        _listController.synchronizeScope(serviceAccountId);
      } else if (mounted && _isActive && generation == _reloadGeneration) {
        // 二级页返回只需恢复既有轮询/Realtime，不重复执行首次补发链。
        _configurePolling(serviceAccountId);
      }
    }
  }

  /// 当前 CID 在身份鉴权时读取一次 CitizenServe；聊天列表和窗口复用统一本地缓存。
  /// 结果由 [ChatMediaLimits] 绑定 CID，切换钱包后旧 CID 权益不能复用。
  Future<void> _ensureChatEntitlement(
    String cidNumber,
    int reloadGeneration,
  ) async {
    if (cidNumber.isEmpty) return;
    // 展示先恢复上一次服务端确认的本地快照，避免每次进入页面先显示无会员；
    // 随后的服务端鉴权仍由 authorizeMembership 在同一登录会话内严格去重一次。
    await _subscriptionService.readDisplaySnapshot(cidNumber);
    if (mounted &&
        reloadGeneration == _reloadGeneration &&
        cidNumber == _cidNumber) {
      setState(() {});
    }
    try {
      final session = _profileSession ?? await _sessionProvider.ensureSession();
      if (session == null || session.cidNumber.trim() != cidNumber) return;
      _profileSession = session;
      await _subscriptionService.authorizeMembership(session);
    } on Exception {
      // 展示仍可复用本地快照，但发送授权必须由本次会话的 CitizenServe 结果确认。
      ChatMediaLimits.markAuthorizationUnavailable(cidNumber);
    }
    if (mounted &&
        reloadGeneration == _reloadGeneration &&
        cidNumber == _cidNumber) {
      setState(() {});
    }
  }

  /// 本地首屏完成后静默收敛聊天服务。该 Future 不进入页面 loading/error，
  /// 服务失败时保留已经显示的本地列表，由后续轮询或下一次进入页面重试。
  Iterable<String> _directPeerCidNumbers(
    List<ChatConversationPreview> conversations,
  ) sync* {
    final seen = <String>{};
    for (final preview in conversations) {
      final cidNumber = preview.peerUserId.trim();
      if (!preview.isGroup && cidNumber.isNotEmpty && seen.add(cidNumber)) {
        yield cidNumber;
      }
    }
  }

  /// Chat UI 只按 CID 联合读取 UserIsar 公开资料；不会向 ChatIsar 增加头像、昵称或会员列。
  Future<void> _readCachedPeerProfiles(
    List<ChatConversationPreview> conversations, {
    bool force = false,
  }) async {
    await Future.wait(
      _directPeerCidNumbers(conversations).map((cidNumber) async {
        if (!force && _resolvedPeerCidNumbers.contains(cidNumber)) return;
        final profile = await _profileCache.read(cidNumber);
        if (profile == null) return;
        _peerProfiles[cidNumber] = profile;
        _peerProfileMedia[cidNumber] = await _profileMediaCache.read(profile);
        _resolvedPeerCidNumbers.add(cidNumber);
      }),
    );
    if (mounted && force) setState(() {});
  }

  /// 会话标题先用 ChatIsar 已有预览立即显示；公开资料缓存随后把中性头像替换为真实
  /// 头像。缓存读取或网络失败都不能阻塞聊天列表，也不能回退成旧默认头像。
  Future<void> _hydratePeerProfiles(
    List<ChatConversationPreview> conversations,
  ) async {
    unawaited(_hydrateContactRemarks(conversations));
    try {
      await _readCachedPeerProfiles(conversations);
      if (mounted) setState(() {});
      await _refreshPeerProfiles(conversations);
    } on Exception {
      // 公开资料是 Chat UI 的联合展示数据；失败不影响加密会话本身。
    }
  }

  /// 通讯录备注是本机私人数据，只与当前 CID 下的直接会话联合展示。读取失败不阻塞
  /// ChatIsar 首屏，也不允许用 CID 代替昵称回退到界面。
  Future<void> _hydrateContactRemarks(
    List<ChatConversationPreview> conversations,
  ) async {
    final ownerUserId = _cidNumber;
    if (ownerUserId.isEmpty) return;
    final peers = _directPeerCidNumbers(conversations).toSet();
    try {
      final contacts = await _contactService.getContacts();
      if (!mounted || _cidNumber != ownerUserId) return;
      final remarks = <String, String>{
        for (final contact in contacts)
          if (peers.contains(contact.cidNumber) &&
              contact.contactRemark.trim().isNotEmpty)
            contact.cidNumber: contact.contactRemark.trim(),
      };
      setState(() {
        _peerContactRemarks
          ..removeWhere((cidNumber, _) => peers.contains(cidNumber))
          ..addAll(remarks);
      });
    } on Exception {
      // 通讯录不可用不影响消息收发；卡片继续显示公开昵称或稳定默认昵称。
    }
  }

  /// 对端公开资料按四个 CID 一组刷新，防止大聊天列表产生无界请求；会员展示只采用
  /// CitizenServe 当前 D1 结果；本人的聊天授权统一由会员缓存与服务端 D1 门禁处理。
  Future<void> _refreshPeerProfiles(
    List<ChatConversationPreview> conversations,
  ) async {
    final cidNumbers = _directPeerCidNumbers(conversations).toList();
    if (cidNumbers.isEmpty || !mounted) return;
    try {
      _profileSession ??= await _sessionProvider.ensureSession();
    } on Exception {
      return;
    }
    for (var offset = 0; offset < cidNumbers.length; offset += 4) {
      final end =
          offset + 4 < cidNumbers.length ? offset + 4 : cidNumbers.length;
      final batch = cidNumbers.sublist(offset, end);
      await Future.wait(
        batch.map((cidNumber) async {
          try {
            final profile = await _profileApi.fetchProfile(
              cidNumber,
              session: _profileSession,
            );
            _peerProfiles[cidNumber] = profile;
            _resolvedPeerCidNumbers.add(cidNumber);
            _peerProfileMedia[cidNumber] = await _profileMediaCache.read(
              profile,
            );
            await _profileCache.write(profile);
            final avatarKey = profile.avatarObjectKey?.trim();
            if (avatarKey == null ||
                avatarKey.isEmpty ||
                _profileSession == null) {
              return;
            }
            final media = await _profileMediaCache.refresh(
              profile: profile,
              avatarUrl: _profileApi.mediaUrl(
                avatarKey,
                updatedAt: profile.updatedAt,
              ),
              bannerUrl: null,
              headers: <String, String>{
                'authorization': 'Bearer ${_profileSession!.sessionToken}',
              },
            );
            if (_peerProfiles[cidNumber]?.updatedAt == profile.updatedAt) {
              _peerProfileMedia[cidNumber] = media;
            }
          } on Exception {
            // Chat 继续使用本机资料或中性占位，单个公开资料失败不影响会话可用性。
          }
        }),
      );
      if (mounted) setState(() {});
    }
  }

  Future<bool> _retryOutgoingSilently() async {
    if (!_isActive) {
      return false;
    }
    final runtime = widget.runtime;
    if (runtime == null) {
      return true;
    }
    try {
      await runtime.retryOutgoing();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _configurePolling(String activeWallet) {
    if (!_isActive || activeWallet.isEmpty || widget.runtime == null) {
      _pauseSync();
      return;
    }
    _listController.configureScope(activeWallet);
  }

  Future<Future<void> Function()?> _startRealtime(
    String activeWallet, {
    required Future<void> Function() onNotice,
    Future<void> Function()? onDisconnected,
  }) async {
    final runtime = widget.runtime;
    if (!_isActive || runtime == null || _accountId != activeWallet) {
      return null;
    }
    return runtime.startRealtimeSync(
      onNotice: onNotice,
      onDisconnected: onDisconnected,
    );
  }

  Future<bool> _syncAndRefresh(String accountId) async {
    if (!_isActive || _accountId != accountId) return false;
    final retried = await _retryOutgoingSilently();
    final conversations = await widget.store.readConversationPreviews(
      ownerUserId: _cidNumber,
      currentAccountId: accountId,
    );
    if (!mounted || !_isActive || _accountId != accountId) return false;
    final visible = _withoutDeletingConversations(conversations);
    setState(() {
      _conversations = visible;
    });
    unawaited(_hydratePeerProfiles(visible));
    return retried;
  }

  void _pauseSync() {
    _listController.pause();
  }

  Future<({String cidNumber, String accountId})> _readIdentity() async {
    if (widget.cidNumber != null && widget.accountId != null) {
      return (cidNumber: widget.cidNumber!, accountId: widget.accountId!);
    }
    final runtime = widget.runtime;
    if (runtime != null) {
      final current = await runtime.readCurrentUser();
      if (current.accountId.isNotEmpty) {
        return (cidNumber: current.userId, accountId: current.accountId);
      }
    }
    final identity = await CurrentUserContext.instance.resolve();
    return (
      cidNumber: identity?.cidNumber ?? '',
      accountId: identity?.accountId ?? '',
    );
  }

  Future<void> _deleteLocalConversation(String conversationId) {
    final runtime = widget.runtime;
    if (runtime != null) {
      return runtime.deleteLocalConversation(conversationId);
    }
    return Future<void>.error(
      StateError('删除 Chat 会话必须由持久 binding fence Runtime 协调'),
    );
  }

  /// 逻辑删除先于物理删除完成：调用本方法的同步阶段立刻移除卡片并登记过滤，
  /// 返回的 Future 只代表后台 Store/附件清理。成功后解除过滤；失败才恢复
  /// 本地真值并显示错误，不能让页面因等待内部锁而停在不可操作状态。
  Future<void> _deleteConversationInBackground(String conversationId) async {
    if (!_conversationDeletesInFlight.add(conversationId)) return;
    if (mounted) {
      setState(() {
        _conversations = _conversations
            .where((item) => item.conversationId != conversationId)
            .toList(growable: false);
        _error = null;
      });
    }
    try {
      await _deleteLocalConversation(conversationId);
      // 物理删除完成后再读一次真值；在这次读取结束前继续保留过滤标记，
      // 防止与路由返回重载竞速的旧快照把卡片短暂插回。
      if (mounted) await _reload();
      _conversationDeletesInFlight.remove(conversationId);
    } catch (error) {
      _conversationDeletesInFlight.remove(conversationId);
      if (mounted) {
        await _reload();
        if (mounted) {
          setState(() {
            _error = chatUserErrorMessage(error);
          });
        }
      }
    }
  }

  Future<void> _confirmAndDeleteConversation(
    ChatConversationPreview preview,
  ) async {
    final confirmed = await _confirmDeleteConversationList(context);
    if (!confirmed || !mounted) {
      return;
    }
    unawaited(_deleteConversationInBackground(preview.conversationId));
  }

  void _openConversation(ChatConversationPreview preview) {
    if (!_requireChatIdentity()) return;
    if (!_requireChatMembership()) return;
    if (preview.isGroup) {
      openGroupChat(
        context,
        groupId: preview.conversationId,
        title: preview.title,
        onDeleteConversation: () =>
            _deleteConversationInBackground(preview.conversationId),
      ).then((_) => _reload());
      return;
    }
    _openDirectConversation(preview);
  }

  void _openCreateGroup() {
    if (!_requireChatIdentity()) return;
    if (!_requireChatMembership()) return;
    final opener = widget.openers?.openCreateGroup;
    if (opener != null) {
      unawaited(opener(context));
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GroupCreatePage()))
        .then((_) => _reload());
  }

  /// 没有默认钱包账户时统一提示并拦截；冷热钱包均可作为当前账户。
  bool _requireAccount() {
    if (_accountId.isEmpty) {
      setState(() => _error = '请先在「我的 → 我的钱包」添加钱包账户');
      return false;
    }
    return true;
  }

  /// 页面浏览直接开放；私信、群聊、加好友等动作发生时再严格要求热钱包与 CID。
  ///
  /// 未注册不再打错误横幅,而是就地弹全 App 统一注册面板;占号成功后
  /// coordinator 回刷进正常聊天,原动作由用户重新触发(不自动续跑)。
  bool _requireChatIdentity() {
    if (!_requireAccount()) return false;
    if (_cidNumber.isEmpty) {
      unawaited(
        startCidRegistrationFlow(context).then((registered) {
          if (registered && mounted) _requestCoordinate();
        }),
      );
      return false;
    }
    return true;
  }

  bool _requireChatMembership() {
    if (ChatMediaLimits.chatAuthorizedFor(_cidNumber)) return true;
    setState(() {
      _error = ChatMediaLimits.authorizationResolvedFor(_cidNumber) &&
              ChatMediaLimits.resolvedFor(_cidNumber)
          ? '尚未开通会员，订阅任一会员后即可使用聊天'
          : '暂时无法验证会员状态，请稍后重试';
    });
    return false;
  }

  /// 加号菜单动作分派。
  Future<void> _onEntryAction(_ChatEntryAction action) async {
    switch (action) {
      case _ChatEntryAction.scan:
        await _openScan();
      case _ChatEntryAction.receivePay:
        await _openReceivePay();
      case _ChatEntryAction.sendMessage:
        await _openSendMessage();
      case _ChatEntryAction.createGroup:
        _openCreateGroup();
      case _ChatEntryAction.addFriend:
        await _openAddFriend();
    }
  }

  /// 扫一扫 = 交易·扫一扫统一分派；扫到用户码按收款人进入转账。
  Future<void> _openScan() async {
    final opener = widget.openers?.openScan;
    if (opener != null) {
      await opener(context);
      return;
    }
    final wallet = await widget.walletManager.getDefaultWallet();
    if (!mounted) return;
    await openScanDispatchFlow(context: context, paymentWallet: wallet);
  }

  /// 收付款 = 展示本账户账户码（`k=5`），他人扫码后按账户向我转账。
  ///
  /// 本入口最终归属是收款码（`k=4`，带金额与备注、临时有效），当前其生成方尚未实现，
  /// 暂出账户码；收款码落地时只切这一处，码型契约由共享 QR registry 固定。
  Future<void> _openReceivePay() async {
    if (!_requireAccount()) return;
    final opener = widget.openers?.openReceivePay;
    if (opener != null) {
      await opener(context);
      return;
    }
    final wallet = await widget.walletManager.getDefaultWallet();
    if (!mounted) return;
    if (wallet == null) {
      setState(() => _error = '请先在「我的 → 我的钱包」添加钱包账户');
      return;
    }
    await showWalletQrDialog(
      context,
      accountId: wallet.accountId,
      accountName: wallet.walletName,
    );
  }

  /// 发私信 = 通讯录单选，点联系人直接开私聊。
  Future<void> _openSendMessage() async {
    if (!_requireChatIdentity()) return;
    if (!_requireChatMembership()) return;
    final opener = widget.openers?.openSendMessage;
    if (opener != null) {
      await opener(context);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            const ContactBookPage(mode: ContactPickMode.pickForMessage),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  /// 加好友 = 扫对方二维码写入本人密文通讯录。
  Future<void> _openAddFriend() async {
    if (!_requireChatIdentity()) return;
    final opener = widget.openers?.openAddFriend;
    if (opener != null) {
      await opener(context);
      return;
    }
    await scanAndAddContact(context);
  }

  /// 搜索 = 进入独立搜索页；透传 store 与账户，避免搜索页重复解析依赖。
  Future<void> _openSearch() async {
    if (!_requireChatIdentity()) return;
    if (!_requireChatMembership()) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatSearchPage(
          store: widget.store,
          cidNumber: _cidNumber,
          accountId: _accountId,
        ),
      ),
    );
  }

  void _openGroupManage(ChatConversationPreview preview) {
    if (!_requireChatMembership()) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => GroupManagePage(
              groupId: preview.conversationId,
              cidNumber: _cidNumber,
            ),
          ),
        )
        .then((_) => _reload());
  }

  void _openDirectConversation(ChatConversationPreview preview) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) => CitizenChatPage(
              conversationId: preview.conversationId,
              ownerUserId: _cidNumber,
              accountId: _accountId,
              peerUserId: preview.peerUserId,
              title: preview.title,
              store: widget.store,
              onSendText: widget.sendTextFactory?.call(
                    preview.peerUserId,
                    preview.conversationId,
                  ) ??
                  (widget.runtime == null
                      ? null
                      : (text) => widget.runtime!.sendText(
                            peerUserId: preview.peerUserId,
                            conversationId: preview.conversationId,
                            text: text,
                          )),
              onSendMedia: widget.sendMediaFactory?.call(
                    preview.peerUserId,
                    preview.conversationId,
                  ) ??
                  (widget.runtime == null
                      ? null
                      : (media, {onLocalCommitted}) =>
                          widget.runtime!.sendMedia(
                            peerUserId: preview.peerUserId,
                            conversationId: preview.conversationId,
                            media: media,
                            onLocalCommitted: onLocalCommitted,
                          )),
              onSendSticker: widget.runtime == null
                  ? null
                  : (packId, stickerId) => widget.runtime!.sendSticker(
                        peerUserId: preview.peerUserId,
                        conversationId: preview.conversationId,
                        packId: packId,
                        stickerId: stickerId,
                      ),
              onResolveMediaPaths: widget.runtime == null
                  ? null
                  : (String conversationId, List<ChatContent> contents) =>
                      widget.runtime!.resolveCachedMediaPaths(
                        conversationId: conversationId,
                        contents: contents,
                      ),
              onDownloadAttachment:
                  widget.downloadAttachmentFactory?.call(preview.peerUserId) ??
                      (widget.runtime == null
                          ? null
                          : (String conversationId, String controlPlaintext) =>
                              widget.runtime!.downloadAttachment(
                                conversationId: conversationId,
                                controlPlaintext: controlPlaintext,
                              )),
              onSync: widget.syncFactory?.call(preview.peerUserId) ??
                  (widget.runtime == null
                      ? null
                      : () => widget.runtime!.retryOutgoing(
                            conversationId: preview.conversationId,
                            recipientUserId: preview.peerUserId,
                          )),
              onStartRealtime: widget.runtime == null
                  ? null
                  : ({required onNotice, onDisconnected}) =>
                      widget.runtime!.startRealtimeSync(
                        onNotice: onNotice,
                        onDisconnected: onDisconnected,
                        retryOutgoingOnConnect: false,
                      ),
              onDeleteConversation: () =>
                  _deleteConversationInBackground(preview.conversationId),
              onMarkRead: widget.runtime == null
                  ? null
                  : (readThroughMillis) => widget.runtime!.markConversationRead(
                        conversationId: preview.conversationId,
                        readThroughMillis: readThroughMillis,
                      ),
              initialProfile: _peerProfiles[preview.peerUserId],
              initialProfileMedia: _peerProfileMedia[preview.peerUserId],
              profileApi: _profileApi,
              profileCache: _profileCache,
              profileMediaCache: _profileMediaCache,
              sessionProvider: _sessionProvider,
            ),
          ),
        )
        .then((_) => _reload());
  }

  ChatConversationListItem _conversationItem(
    BuildContext context,
    ChatConversationPreview preview,
  ) {
    final profile = _peerProfiles[preview.peerUserId];
    final media = _peerProfileMedia[preview.peerUserId];
    final resolved = _resolvedPeerCidNumbers.contains(preview.peerUserId);
    final publicName = preview.isGroup
        ? preview.title
        : ProfilePresentation.forIdentityKey(
            preview.peerUserId,
          ).resolveDisplayName(
            publicName: profile?.displayName ?? preview.title,
          );
    final remark = _peerContactRemarks[preview.peerUserId]?.trim() ?? '';
    final title = !preview.isGroup && remark.isNotEmpty
        ? '$remark（$publicName）'
        : publicName;
    final leading = preview.isGroup
        ? CircleAvatar(
            radius: AppLayout.scaled(context, 22),
            backgroundColor: AppTheme.primary.withAlpha(20),
            child: const Icon(Icons.groups_outlined, color: AppTheme.primary),
          )
        : ProfileAvatar(
            size: AppLayout.scaled(context, 44),
            seed: preview.peerUserId,
            imagePath: media?.avatarPath,
            imageUrl: profile?.avatarObjectKey?.trim().isNotEmpty == true
                ? _profileApi.mediaUrl(
                    profile!.avatarObjectKey!,
                    updatedAt: profile.updatedAt,
                  )
                : null,
            imageHeaders: _profileSession == null
                ? null
                : <String, String>{
                    'authorization': 'Bearer ${_profileSession!.sessionToken}',
                  },
            userImageSet: resolved
                ? profile?.avatarObjectKey?.trim().isNotEmpty == true
                : true,
            identityLevel: profile?.identityLevel,
            membershipLevel: profile?.membershipLevel,
            membershipActive: profile?.membershipActive ?? false,
            showBadge: resolved,
          );
    return ChatConversationListItem(
      id: preview.conversationId,
      title: title,
      subtitle: preview.lastMessage,
      updatedAt: preview.lastUpdatedAt,
      unreadCount: preview.unreadCount,
      leading: leading,
      onTap: () => _openConversation(preview),
      onDelete: () => _confirmAndDeleteConversation(preview),
      onLongPress: preview.isGroup ? () => _openGroupManage(preview) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    const style = ChatViewStyle(
      backgroundColor: AppTheme.scaffoldBg,
      surfaceColor: AppTheme.surfaceCard,
      borderColor: AppTheme.borderLight,
      primaryColor: AppTheme.primary,
      textPrimaryColor: AppTheme.textPrimary,
      textSecondaryColor: AppTheme.textSecondary,
      textTertiaryColor: AppTheme.textTertiary,
      menuColor: Color(0xFF66727D),
      scaler: AppLayout.scaled,
    );
    final Widget? unavailable = _accountId.isEmpty
        ? const ChatConversationPlaceholder(
            message: '请先在「我的 → 我的钱包」添加钱包账户',
            style: style,
          )
        : _cidNumber.isEmpty
            ? IdentityRegisterGuide(
                description: '注册后即可使用聊天与通讯录。',
                onRegistered: _requestCoordinate,
              )
            : null;
    return ChatConversationOverview(
      header: ChatSectionHeader<_ChatEntryAction>(
        onAction: _onEntryAction,
        style: style,
        actions: [
          for (final item in _chatEntryItems)
            ChatHeaderAction<_ChatEntryAction>(
              value: item.action,
              label: item.label,
              icon: item.asset != null
                  ? SvgPicture.asset(
                      item.asset!,
                      width: AppLayout.scaled(context, 18),
                      height: AppLayout.scaled(context, 18),
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(
                      item.icon,
                      size: AppLayout.scaled(context, 20),
                      color: Colors.white,
                    ),
            ),
        ],
      ),
      onRefresh: () => _reload(syncFirst: true),
      onSearch: () => unawaited(_openSearch()),
      items: [
        for (final preview in _conversations)
          _conversationItem(context, preview),
      ],
      loading: _loading,
      errorMessage: _error,
      unavailable: unavailable,
      style: style,
    );
  }
}

/// 加号菜单的 5 个动作。
enum _ChatEntryAction { scan, receivePay, sendMessage, createGroup, addFriend }

/// 加号菜单的一项：图标 + 文案。
///
/// [asset] 与 [icon] 二选一：扫一扫必须用与「交易 → 扫一扫」同一份
/// `assets/icons/scan-line.svg`（扫码图标），不能拿 Material 的二维码图标顶替。
class _ChatEntryItem {
  const _ChatEntryItem(this.action, this.label, {this.icon, this.asset});

  final _ChatEntryAction action;
  final String label;
  final IconData? icon;
  final String? asset;
}

const List<_ChatEntryItem> _chatEntryItems = [
  _ChatEntryItem(
    _ChatEntryAction.scan,
    '扫一扫',
    asset: 'assets/icons/scan-line.svg',
  ),
  _ChatEntryItem(
    _ChatEntryAction.receivePay,
    '收付款',
    icon: Icons.payments_outlined,
  ),
  // 与底部导航「聊天」tab 同一个图标，保持同一语义同一形。
  _ChatEntryItem(
    _ChatEntryAction.sendMessage,
    '发私信',
    icon: Icons.textsms_outlined,
  ),
  _ChatEntryItem(
    _ChatEntryAction.createGroup,
    '发群聊',
    icon: Icons.group_outlined,
  ),
  _ChatEntryItem(
    _ChatEntryAction.addFriend,
    '加好友',
    icon: Icons.person_add_alt_1_outlined,
  ),
];

Future<bool> _confirmDeleteConversationList(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除聊天记录'),
      content: const Text('确定删除这台设备上的聊天记录？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 群聊打开器；测试可注入替身，正式运行走 [openGroupChat]。
typedef GroupChatOpener = Future<void> Function(
  BuildContext context, {
  required String groupId,
  required String title,
});

/// 聊天搜索页：一个输入框，三段结果 —— 会话 / 联系人 / 聊天记录。
///
/// - 会话与联系人在内存里过滤（进页时一次性载入，数据量小）。
/// - 聊天记录走 [ChatStore.searchMessages] 跨会话检索本机已解密消息。
/// - 点任一结果都复用既有打开收口：群聊 [openGroupChat]、单聊 [openDirectChat]，
///   不在本页复刻 ChatConversationPage 装配。
/// - 聊天记录命中当前**只打开所在会话**，不定位到具体消息（消息级锚点需
///   ChatConversationPage 支持滚动定位，单列后续任务）。
class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({
    super.key,
    this.store,
    this.contactService,
    this.cidNumber,
    this.accountId,
    this.directChatOpener,
    this.groupChatOpener,
  });

  final ChatStore? store;
  final UserContactService? contactService;

  /// 当前永久身份主键；不传则页面只读本地当前用户快照。
  final String? cidNumber;

  /// 当前身份账户（CID 绑定账户）；不传则页面自行读取。
  final String? accountId;
  final DirectChatOpener? directChatOpener;
  final GroupChatOpener? groupChatOpener;

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  late final ChatStore _store = widget.store ?? ChatStore();
  late final UserContactService _contactService =
      widget.contactService ?? UserContactService();
  final TextEditingController _controller = TextEditingController();

  String _accountId = '';
  String _cidNumber = '';
  List<ChatConversationPreview> _conversations =
      const <ChatConversationPreview>[];
  List<UserContact> _contacts = const <UserContact>[];
  List<ChatStoredMessage> _messageHits = const <ChatStoredMessage>[];
  String _query = '';
  bool _loading = true;
  bool _searching = false;
  String? _error;

  /// 消息检索是异步的：用递增序号丢弃过期结果，
  /// 避免快速输入时旧关键词的结果覆盖新关键词的结果。
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final identity = widget.cidNumber != null && widget.accountId != null
          ? null
          : await CurrentUserContext.instance.resolve();
      final accountId = widget.accountId ?? identity?.accountId ?? '';
      final cidNumber = widget.cidNumber ?? identity?.cidNumber ?? '';
      final conversations = await _store.readConversationPreviews(
        ownerUserId: cidNumber,
        currentAccountId: accountId,
      );
      List<UserContact> contacts;
      try {
        contacts = await _contactService.getContacts();
      } on Exception {
        // 通讯录读失败只让「联系人」段为空，不阻塞会话与聊天记录搜索。
        contacts = const <UserContact>[];
      }
      if (!mounted) return;
      setState(() {
        _accountId = accountId;
        _cidNumber = cidNumber;
        _conversations = conversations;
        _contacts = contacts;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '本地聊天数据读取失败';
      });
    }
  }

  Future<void> _onQueryChanged(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      ++_searchSeq;
      setState(() {
        _query = query;
        _messageHits = const <ChatStoredMessage>[];
        _searching = false;
        _error = null;
      });
      return;
    }
    final seq = ++_searchSeq;
    setState(() {
      _query = query;
      _searching = true;
      _error = null;
    });
    try {
      final hits = await _store.searchMessages(
        ownerUserId: _cidNumber,
        currentAccountId: _accountId,
        keyword: query,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _messageHits = hits;
        _searching = false;
      });
    } on Exception {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _messageHits = const <ChatStoredMessage>[];
        _searching = false;
        _error = '聊天记录搜索失败';
      });
    }
  }

  List<ChatConversationPreview> get _conversationHits {
    if (_query.isEmpty) return const <ChatConversationPreview>[];
    final needle = _query.toLowerCase();
    return _conversations
        .where(
          (item) =>
              item.title.toLowerCase().contains(needle) ||
              item.lastMessage.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  List<UserContact> get _contactHits {
    if (_query.isEmpty) return const <UserContact>[];
    final needle = _query.toLowerCase();
    // 只匹配私人备注、CID 与账户：公开昵称要联网拉取，搜索页不引入网络依赖。
    return _contacts
        .where(
          (item) =>
              item.contactRemark.toLowerCase().contains(needle) ||
              item.cidNumber.toLowerCase().contains(needle) ||
              item.accountId.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  Future<void> _openConversation(ChatConversationPreview preview) async {
    if (preview.isGroup) {
      final opener = widget.groupChatOpener ?? openGroupChat;
      await opener(
        context,
        groupId: preview.conversationId,
        title: preview.title,
      );
      return;
    }
    final opener = widget.directChatOpener ?? openDirectChat;
    await opener(context, peerUserId: preview.peerUserId, title: preview.title);
  }

  Future<void> _openContact(UserContact contact) async {
    final opener = widget.directChatOpener ?? openDirectChat;
    final title = contact.contactRemark.isEmpty
        ? ProfilePresentation.forIdentityKey(contact.cidNumber).fallbackName
        : contact.contactRemark;
    await opener(context, peerUserId: contact.cidNumber, title: title);
  }

  /// 聊天记录命中：只打开消息所在会话，不定位到具体消息。
  Future<void> _openMessageHit(ChatStoredMessage message) async {
    ChatConversationPreview? preview;
    for (final item in _conversations) {
      if (item.conversationId == message.conversationId) {
        preview = item;
        break;
      }
    }
    if (preview == null) return;
    await _openConversation(preview);
  }

  @override
  Widget build(BuildContext context) {
    const style = ChatViewStyle(
      backgroundColor: AppTheme.scaffoldBg,
      textTertiaryColor: AppTheme.textTertiary,
      scaler: AppLayout.scaled,
    );
    return ChatSearchView(
      controller: _controller,
      query: _query,
      onQueryChanged: (value) => unawaited(_onQueryChanged(value)),
      onClear: () {
        _controller.clear();
        unawaited(_onQueryChanged(''));
      },
      loading: _loading,
      searching: _searching,
      error: _error,
      style: style,
      sections: [
        ChatSearchSection(
          title: '会话',
          items: [
            for (final item in _conversationHits)
              ChatSearchItem(
                key: ValueKey('search-conversation-${item.conversationId}'),
                leading: Icon(
                  item.isGroup ? Icons.groups_rounded : Icons.person_rounded,
                  color: AppTheme.textSecondary,
                ),
                title: item.title,
                subtitle: item.lastMessage,
                onTap: () => unawaited(_openConversation(item)),
              ),
          ],
        ),
        ChatSearchSection(
          title: '联系人',
          items: [
            for (final item in _contactHits)
              ChatSearchItem(
                key: ValueKey('search-contact-${item.cidNumber}'),
                leading: const Icon(
                  Icons.account_circle_rounded,
                  color: AppTheme.textSecondary,
                ),
                title: item.contactRemark.isEmpty
                    ? ProfilePresentation.forIdentityKey(
                        item.cidNumber,
                      ).fallbackName
                    : item.contactRemark,
                subtitle: item.cidNumber,
                onTap: () => unawaited(_openContact(item)),
              ),
          ],
        ),
        ChatSearchSection(
          title: '聊天记录',
          items: [
            for (final item in _messageHits)
              ChatSearchItem(
                key: ValueKey('search-message-${item.messageId}'),
                leading: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppTheme.textSecondary,
                ),
                title: ChatPayloadCodec.decode(item.plaintext ?? '').summary,
                onTap: () => unawaited(_openMessageHit(item)),
              ),
          ],
        ),
      ],
    );
  }
}

/// 建群页:输群名 + 从通讯录多选成员 → `createGroup`(创建者自动为 admin)。
class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key, this.runtime, this.contactService});

  final ChatSdk? runtime;
  final UserContactService? contactService;

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final TextEditingController _nameController = TextEditingController();
  late final UserContactService _contactService =
      widget.contactService ?? UserContactService();
  late final ChatSdk _runtime = widget.runtime ?? citizenChatRuntime;

  List<UserContact> _contacts = const <UserContact>[];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contacts = await _contactService.getContacts();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = chatUserErrorMessage(error, fallback: '加载通讯录失败，请稍后重试');
        _loading = false;
      });
    }
  }

  /// 发群聊最少 2 人(1 人应走「发私信」),群名非空方可创建。
  bool get _canCreate =>
      !_loading &&
      _nameController.text.trim().isNotEmpty &&
      _selected.length >= 2;

  Future<void> _create() async {
    if (!_canCreate || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final group = await _runtime.createGroup(
        name: _nameController.text.trim(),
        inviteeUserIds: _selected.toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await openGroupChat(context, groupId: group.groupId, title: group.name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = chatUserErrorMessage(error);
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChatGroupCreateView(
      nameController: _nameController,
      users: [
        for (final contact in _contacts)
          ChatSelectableUser(
            userId: contact.cidNumber,
            displayName: contact.contactRemark.isEmpty
                ? _shortCreateContact(contact.cidNumber)
                : contact.contactRemark,
            subtitle: _shortCreateContact(contact.cidNumber),
          ),
      ],
      selectedUserIds: _selected,
      onSelectionChanged: (userId, selected) => setState(() {
        if (selected) {
          _selected.add(userId);
        } else {
          _selected.remove(userId);
        }
      }),
      canCreate: _canCreate,
      onCreate: _create,
      loading: _loading,
      creating: _creating,
      error: _error,
      emptyMessage: '通讯录为空,先在「我的 → 通讯录」添加联系人',
      style: const ChatViewStyle(scaler: AppLayout.scaled),
    );
  }
}

String _shortCreateContact(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
}

/// 成员管理页:名册 + 加/删(仅 admin)+ 改群名(仅 admin)+ 退群(任何人)。
class GroupManagePage extends StatefulWidget {
  const GroupManagePage({
    super.key,
    required this.groupId,
    this.runtime,
    this.store,
    this.cidNumber,
  });

  final String groupId;
  final ChatSdk? runtime;
  final ChatStore? store;
  final String? cidNumber;

  @override
  State<GroupManagePage> createState() => _GroupManagePageState();
}

class _GroupManagePageState extends State<GroupManagePage> {
  late final ChatSdk _runtime = widget.runtime ?? citizenChatRuntime;
  late final ChatStore _store = widget.store ?? ChatStore();

  ChatGroup? _group;
  String _myCidNumber = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final identity = widget.cidNumber != null
          ? null
          : await CurrentUserContext.instance.resolve();
      final ownerUserId = widget.cidNumber ?? identity?.cidNumber ?? '';
      final group = await _store.readGroup(ownerUserId, widget.groupId);
      if (!mounted) return;
      setState(() {
        _myCidNumber = ownerUserId;
        _group = group;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = chatUserErrorMessage(error);
        _loading = false;
      });
    }
  }

  bool get _isAdmin => _group?.adminSet.contains(_myCidNumber) ?? false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = chatUserErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final name = await showChatRenameGroupDialog(
      context,
      currentName: _group?.name ?? '',
    );
    if (name != null && name.isNotEmpty) {
      await _run(
        () => _runtime.renameGroup(groupId: widget.groupId, name: name),
      );
    }
  }

  Future<void> _addMembers() async {
    final existing = _group?.memberCidNumbers.toSet() ?? <String>{};
    final selected = await _pickContacts(existing);
    if (selected != null && selected.isNotEmpty) {
      await _run(
        () => _runtime.addGroupMembers(
          groupId: widget.groupId,
          inviteeUserIds: selected,
        ),
      );
    }
  }

  Future<void> _leave() async {
    if (await showChatLeaveGroupDialog(context)) {
      await _run(() => _runtime.leaveGroup(widget.groupId));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<List<String>?> _pickContacts(Set<String> exclude) async {
    List<UserContact> contacts;
    try {
      contacts = await UserContactService().getContacts();
    } catch (_) {
      contacts = const <UserContact>[];
    }
    if (!mounted) return null;
    return showChatUserPickerDialog(
      context,
      users: [
        for (final contact in contacts)
          if (!exclude.contains(contact.cidNumber))
            ChatSelectableUser(
              userId: contact.cidNumber,
              displayName: contact.contactRemark.isEmpty
                  ? _shortManageContact(contact.cidNumber)
                  : contact.contactRemark,
              subtitle: _shortManageContact(contact.cidNumber),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    return ChatGroupManageView(
      title: group?.name ?? '群聊',
      members: [
        if (group != null)
          for (final member in group.roster)
            ChatGroupMemberItem(
              userId: member.cidNumber,
              displayName: _shortManageContact(member.cidNumber),
              isAdmin: member.isAdmin,
              canRemove: _isAdmin &&
                  member.cidNumber != _myCidNumber &&
                  member.cidNumber != group.creatorCidNumber,
              onRemove: () => _run(
                () => _runtime.removeGroupMembers(
                  groupId: widget.groupId,
                  targetUserIds: [member.cidNumber],
                ),
              ),
            ),
      ],
      isAdmin: _isAdmin,
      onRename: _rename,
      onAddMembers: _addMembers,
      onLeave: _leave,
      loading: _loading,
      busy: _busy,
      groupAvailable: group != null,
      error: _error,
      style: const ChatViewStyle(scaler: AppLayout.scaled),
    );
  }
}

String _shortManageContact(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
}

/// 打开群聊详情；产品身份解析留在 CitizenApp，完整页面链路由 SDK 路由组装。
Future<void> openGroupChat(
  BuildContext context, {
  required String groupId,
  required String title,
  ChatDeleteConversationCallback? onDeleteConversation,
}) async {
  final identity = await CurrentUserContext.instance.resolve();
  final accountId = identity?.accountId ?? '';
  final currentUserId = identity?.cidNumber ?? '';
  if (!context.mounted) return;
  if (accountId.isEmpty || currentUserId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在「我的 → 我的钱包」添加钱包账户')));
    }
    return;
  }
  await ChatConversationRoutes.openGroup(
    context,
    sdk: citizenChatRuntime,
    host: _citizenConversationHost(
      peerUserId: groupId,
      title: title,
      isGroup: true,
    ),
    currentUserId: currentUserId,
    accountId: accountId,
    groupId: groupId,
    title: title,
    onDeleteConversation: onDeleteConversation,
  );
}

typedef DirectChatOpener = Future<void> Function(
  BuildContext context, {
  required String peerUserId,
  required String title,
});

/// 打开私聊详情；产品身份与自聊门禁留在 CitizenApp，消息链路由 SDK 路由组装。
Future<void> openDirectChat(
  BuildContext context, {
  required String peerUserId,
  required String title,
}) async {
  final identity = await CurrentUserContext.instance.resolve();
  final accountId = identity?.accountId ?? '';
  final currentUserId = identity?.cidNumber ?? '';
  if (!context.mounted) return;
  if (accountId.isEmpty || currentUserId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加钱包账户并注册 CID')));
    }
    return;
  }
  if (peerUserId.trim() == currentUserId) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('不能和自己发起聊天')));
    }
    return;
  }
  await ChatConversationRoutes.openDirect(
    context,
    sdk: citizenChatRuntime,
    host: _citizenConversationHost(
      peerUserId: peerUserId,
      title: title,
      isGroup: false,
    ),
    currentUserId: currentUserId,
    accountId: accountId,
    peerUserId: peerUserId,
    title: title,
  );
}
