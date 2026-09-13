import 'package:provider/provider.dart';

import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/widgets/identity_register_guide.dart';
import 'package:citizenapp/security/account_security_service.dart';

/// 通讯录页使用模式。
enum ContactPickMode {
  /// 常规浏览:点联系人进主页,卡片带「转账/私信/改名/删除」操作菜单。
  browse,

  /// 选收款人(交易页发起):点联系人即返回该联系人,由调用方预填收款地址。
  pickForTransfer,

  /// 选私信对象(聊天页「发私信」):点联系人直接打开一对一聊天,不带操作菜单与扫码入口。
  pickForMessage,
}

/// “我的通讯录”唯一页面。联系人关系本地优先、后台密文同步；公开头像、昵称、
/// 签名与身份徽章复用统一用户资料，点击后进入现有 [UserProfilePage]。
class ContactBookPage extends StatefulWidget {
  const ContactBookPage({
    super.key,
    this.mode = ContactPickMode.browse,
    this.service,
    this.profileApi,
    this.profileCache,
    this.profileMediaCache,
    this.sessionProvider,
    this.initialProfiles = const <String, CitizenProfile>{},
    this.directChatOpener,
    this.transferOpener,
    this.currentUserContext,
    this.identityRevision,
  });

  /// 页面模式:浏览 / 选收款人 / 选私信对象;不改变通讯录所属身份账户。
  final ContactPickMode mode;
  final UserContactService? service;
  final CitizenProfileApi? profileApi;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquareSessionProvider? sessionProvider;
  final Map<String, CitizenProfile> initialProfiles;
  final DirectChatOpener? directChatOpener;
  final CurrentUserContext? currentUserContext;
  final Listenable? identityRevision;

  /// 测试可替换页面打开器；正式运行始终进入现有链上支付页面。
  final Future<void> Function(
    BuildContext context, {
    required String toSs58Address,
  })?
  transferOpener;

  @override
  State<ContactBookPage> createState() => _ContactBookPageState();
}

class _ContactBookPageState extends State<ContactBookPage> {
  late final UserContactService _service;
  late final CitizenProfileApi _profileApi =
      widget.profileApi ?? CitizenProfileApi();
  late final CitizenProfileCache _profileCache =
      widget.profileCache ?? const CitizenProfileCache();
  late final CitizenProfileMediaCache _profileMediaCache =
      widget.profileMediaCache ?? CitizenProfileMediaCache();
  late final SquareSessionProvider _sessionProvider;
  late final CurrentUserContext _currentUserContext;
  Listenable? _identityRevision;
  bool _dependenciesReady = false;
  final TextEditingController _searchController = TextEditingController();

  List<UserContact> _contacts = const <UserContact>[];

  /// 公开资料按身份主键 CID 号缓存（键 = cid_number，与资料接口寻址一致）。
  final Map<String, CitizenProfile> _profiles = <String, CitizenProfile>{};
  final Map<String, CitizenProfileMediaSnapshot> _profileMedia =
      <String, CitizenProfileMediaSnapshot>{};
  final Set<String> _resolvedProfileCidNumbers = <String>{};

  SquareSession? _session;
  ContactSyncState _syncState = const ContactSyncState(
    phase: ContactSyncPhase.idle,
  );
  bool _loading = true;

  /// 当前钱包未注册 CID(合法状态,非故障)。置真时整页显示统一注册引导,
  /// 且**不读通讯录**——通讯录属主就是 CID,没有 CID 连读都不该读。
  bool _unregistered = false;
  String _query = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _profiles.addAll(widget.initialProfiles);
    _resolvedProfileCidNumbers.addAll(widget.initialProfiles.keys);
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injectedService = widget.service;
    final injectedSession = widget.sessionProvider;
    final injectedCurrentUser = widget.currentUserContext;
    if (injectedService != null &&
        injectedSession != null &&
        injectedCurrentUser != null) {
      _service = injectedService;
      _sessionProvider = injectedSession;
      _currentUserContext = injectedCurrentUser;
      _service.syncState.addListener(_onSyncStateChanged);
      _identityRevision = widget.identityRevision;
      _identityRevision?.addListener(_onIdentityChanged);
      _dependenciesReady = true;
      unawaited(_load());
      return;
    }
    final accountSecurity = context.read<AccountSecurityService>();
    _sessionProvider =
        widget.sessionProvider ?? context.read<SquareSessionProvider>();
    _currentUserContext =
        widget.currentUserContext ?? context.read<CurrentUserContext>();
    _service =
        widget.service ??
        UserContactService(
          accountSecurity: accountSecurity,
          currentUserContext: _currentUserContext,
          sessionProvider: _sessionProvider,
          chainReader: CitizenIdentityChainReader(
            chain: context.read<CitizenSdk>().chain,
          ),
        );
    _service.syncState.addListener(_onSyncStateChanged);
    _identityRevision = accountSecurity.revision;
    _identityRevision!.addListener(_onIdentityChanged);
    _dependenciesReady = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _service.syncState.removeListener(_onSyncStateChanged);
    _identityRevision?.removeListener(_onIdentityChanged);
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (mounted) setState(() => _syncState = _service.syncState.value);
  }

  /// CID finalized 后即使绑定账户没变也要退出“尚未注册”态；当前用户快照已在广播前
  /// 失效，此处重读即可得到新的 cid_number，不依赖当前注册引导的局部回调。
  void _onIdentityChanged() {
    if (mounted) unawaited(_load());
  }

  /// 只刷新通讯录中与事件 CID 匹配的公开资料，避免会员变化触发整本通讯录同步。
  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (!mounted || event == null) return;
    final matching = _contacts
        .where((contact) => contact.cidNumber == event.cidNumber)
        .toList(growable: false);
    if (matching.isEmpty) return;
    unawaited(_refreshMembershipProfiles(matching));
  }

  Future<void> _refreshMembershipProfiles(List<UserContact> contacts) async {
    try {
      await _refreshProfiles(contacts);
    } on Exception {
      // 会员徽章刷新属于公开资料软更新；失败保留当前卡片，下次进页继续重读。
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      // 未注册 CID 必须在此短路:通讯录属主 = CID,`getContacts()` 第一步
      // `_requireIdentityOwner()` 对未注册身份必抛 AccountSecurityException,catch 后
      // `_contacts` 保持空,渲染会落到「空通讯录」——把"你没注册"显示成"你没有联系人",
      // 与广场当初把权限态伪装成"加载失败"是同一类错误。
      // 本机缓存无绑定时由 ContactService 的 Cloudflare 会话恢复；这里绝不读链，
      // 也绝不扫描其它钱包账户。
      var identity = await _currentUserContext.resolve();
      if (!mounted || generation != _loadGeneration) return;
      if (identity == null) {
        setState(() {
          _unregistered = true;
          _contacts = const <UserContact>[];
          _loading = false;
        });
        return;
      }
      if (!identity.isRegistered) {
        try {
          await _sessionProvider.ensureSession();
          identity = await _currentUserContext.resolve();
        } on SquareApiException catch (error) {
          if (error.errorCode != 'cid_not_bound') rethrow;
        }
        if (!mounted || generation != _loadGeneration) return;
        if (identity == null || !identity.isRegistered) {
          setState(() {
            _unregistered = true;
            _contacts = const <UserContact>[];
            _loading = false;
          });
          return;
        }
      }
      if (_unregistered) setState(() => _unregistered = false);
      final contacts = await _service.getContacts();
      final syncState = await _service.readSyncState();
      if (!mounted || generation != _loadGeneration) return;
      await _loadCachedProfiles(contacts);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _contacts = contacts;
        _syncState = syncState;
        _loading = false;
      });
      await _refreshProfiles(contacts);
      if (!mounted || generation != _loadGeneration) return;
      try {
        final refreshed = await _service.refreshContactBindings();
        if (mounted && generation == _loadGeneration) {
          setState(() => _contacts = refreshed);
        }
      } on Exception {
        // 页面仍可离线展示 CID 关系；转账前会再次严格链读并禁止使用旧地址。
      }
      if (generation == _loadGeneration) await _sync();
    } on Exception catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _syncState = ContactSyncState(
          phase: ContactSyncPhase.failed,
          message: error.toString(),
        );
      });
    }
  }

  Future<void> _sync() async {
    final contacts = await _service.sync();
    if (!mounted) return;
    await _loadCachedProfiles(contacts);
    if (!mounted) return;
    setState(() => _contacts = contacts);
    await _refreshProfiles(contacts);
  }

  /// 联系人关系已强制携带永久 CID，公开资料无需再按 account_id 临时链读。
  CitizenProfile? _profileOf(UserContact contact) =>
      _profiles[contact.cidNumber];

  /// 联系人关系和公开资料缓存先在内存中完成同一首帧装配，再一次性显示列表；资料尚未
  /// 解析时保持中性占位，不能把“未知”误画成用户从未设置头像的内置照片。
  Future<void> _loadCachedProfiles(List<UserContact> contacts) async {
    await Future.wait(
      contacts.map((contact) async {
        final cidNumber = contact.cidNumber;
        try {
          final profile =
              _profiles[cidNumber] ?? await _profileCache.read(cidNumber);
          if (profile == null) return;
          _profiles[cidNumber] = profile;
          _resolvedProfileCidNumbers.add(cidNumber);
          try {
            _profileMedia[cidNumber] = await _profileMediaCache.read(profile);
          } on Object {
            // 资料 JSON 已解析时仍可显示真实昵称和徽章；单个媒体文件故障不阻塞联系人。
          }
        } on Object {
          // 单个公开资料缓存故障保持中性占位，不能阻塞整本本地通讯录。
        }
      }),
    );
  }

  /// 以四个一组有界刷新公开资料和真实媒体；D1 无会员行时直接不展示会员信息。
  Future<void> _refreshProfiles(List<UserContact> contacts) async {
    try {
      _session ??= await _sessionProvider.ensureSession();
    } on Exception {
      return;
    }
    for (var offset = 0; offset < contacts.length; offset += 4) {
      final end = offset + 4 < contacts.length ? offset + 4 : contacts.length;
      final batch = contacts.sublist(offset, end);
      await Future.wait(
        batch.map((contact) async {
          final cidNumber = contact.cidNumber;
          try {
            final profile = await _profileApi.fetchProfile(
              cidNumber,
              session: _session,
            );
            _profiles[cidNumber] = profile;
            _resolvedProfileCidNumbers.add(cidNumber);
            _profileMedia[cidNumber] = await _profileMediaCache.read(profile);
            await _profileCache.write(profile);
            final key = profile.avatarObjectKey?.trim();
            if (key != null && key.isNotEmpty) {
              final refreshed = await _profileMediaCache.refresh(
                profile: profile,
                avatarUrl: _profileApi.mediaUrl(
                  key,
                  updatedAt: profile.updatedAt,
                ),
                bannerUrl: null,
                headers: _session == null
                    ? null
                    : <String, String>{
                        'authorization': 'Bearer ${_session!.sessionToken}',
                      },
              );
              if (_profiles[cidNumber]?.updatedAt == profile.updatedAt) {
                _profileMedia[cidNumber] = refreshed;
              }
            }
          } on Exception {
            // 保留缓存或中性占位，单个用户资料失败不阻塞通讯录。
          }
        }),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _scanContactQr() async {
    // 复用统一「扫码加好友」收口(写库与提示在扫码页内完成),扫毕本地刷新。
    await scanAndAddContact(context);
    if (!mounted) return;
    final contacts = await _service.getContacts();
    if (!mounted) return;
    setState(() => _contacts = contacts);
    unawaited(_sync());
  }

  Future<void> _rename(UserContact contact) async {
    final formKey = GlobalKey<FormState>();
    var draftRemark = contact.contactRemark;
    final remark = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改私人备注'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: contact.contactRemark,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(hintText: '可留空'),
            onChanged: (value) => draftRemark = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(draftRemark.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (remark == null) return;
    final contacts = await _service.renameContact(contact.cidNumber, remark);
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _transfer(UserContact contact) async {
    final UserContact current;
    try {
      current = await _service.resolveCurrentContact(contact.cidNumber);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法确认联系人当前钱包：$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _contacts = [
        for (final item in _contacts)
          if (item.cidNumber == current.cidNumber) current else item,
      ];
    });
    if (widget.mode == ContactPickMode.pickForTransfer) {
      Navigator.of(context).pop(current);
      return;
    }
    final opener = widget.transferOpener;
    if (opener != null) {
      await opener(context, toSs58Address: current.ss58Address);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            OnchainPaymentPage(initialToAddress: current.ss58Address),
      ),
    );
  }

  Future<void> _message(UserContact contact) async {
    final profile = _profileOf(contact);
    final title = ProfilePresentation.forIdentityKey(
      contact.cidNumber,
    ).resolveDisplayName(publicName: profile?.displayName);
    final opener = widget.directChatOpener ?? openDirectChat;
    await opener(context, peerUserId: contact.cidNumber, title: title);
  }

  Future<void> _delete(UserContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除联系人'),
        content: Text('确定从通讯录删除“${_contactDisplayName(contact)}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final contacts = await _service.deleteContact(contact.cidNumber);
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _open(UserContact contact) async {
    switch (widget.mode) {
      case ContactPickMode.pickForTransfer:
        // 交易发起:把选中的联系人返回给收款栏。
        await _transfer(contact);
      case ContactPickMode.pickForMessage:
        // 发私信:点联系人直接打开与其的一对一聊天(复用统一私信收口)。
        await _message(contact);
      case ContactPickMode.browse:
        // 资料页按通讯录关系主键 cid_number 直接寻址。
        await _openProfile(contact);
    }
  }

  /// 打开联系人主页：通讯录只接受已经完成双向绑定解析的永久 CID。
  Future<void> _openProfile(UserContact contact) async {
    final cidNumber = contact.cidNumber;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          cidNumber: cidNumber,
          isSelf: false,
          initialProfile: _profiles[cidNumber],
          initialProfileMedia: _profileMedia[cidNumber],
          api: _profileApi,
          cache: _profileCache,
          mediaCache: _profileMediaCache,
          sessionProvider: _sessionProvider,
        ),
      ),
    );
  }

  List<UserContact> get _visibleContacts {
    final query = _query.trim().toLowerCase();
    final visible =
        _contacts
            .where((contact) {
              if (query.isEmpty) return true;
              final profile = _profileOf(contact);
              final publicName =
                  ProfilePresentation.forIdentityKey(contact.cidNumber)
                      .resolveDisplayName(publicName: profile?.displayName)
                      .toLowerCase();
              return contact.contactRemark.toLowerCase().contains(query) ||
                  contact.cidNumber.toLowerCase().contains(query) ||
                  publicName.contains(query);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => _contactDisplayName(a).compareTo(_contactDisplayName(b)),
          );
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleContacts;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text(
          widget.mode == ContactPickMode.pickForMessage ? '选择联系人' : '我的通讯录',
        ),
        centerTitle: true,
        actions: [
          // 纯选人(发私信)模式只保留选择,不提供扫码加联系人入口。
          if (widget.mode != ContactPickMode.pickForMessage)
            IconButton(
              tooltip: '扫码添加联系人',
              onPressed: _scanContactQr,
              icon: SvgPicture.asset(
                'assets/icons/scan-line.svg',
                width: AppLayout.scaled(context, 20),
                height: AppLayout.scaled(context, 20),
              ),
            ),
        ],
      ),
      // 未注册 = 合法状态,整页给统一注册引导(与广场/聊天/创作者同规),
      // 不显示搜索框和假的「空通讯录」。
      body: _unregistered
          ? IdentityRegisterGuide(
              description: '注册后即可使用通讯录。',
              onRegistered: () => unawaited(_load()),
            )
          : _buildContactList(visible),
    );
  }

  Widget _buildContactList(List<UserContact> visible) {
    return RefreshIndicator(
      onRefresh: _sync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          if (_loading) ...[
            LinearProgressIndicator(
              key: const ValueKey('contacts-local-load-progress'),
              minHeight: AppLayout.scaledValue(2),
            ),
            SizedBox(height: AppLayout.scaledValue(10)),
          ],
          _SyncBanner(state: _syncState, onRetry: _sync),
          SizedBox(height: AppLayout.scaledValue(10)),
          TextField(
            key: const ValueKey('contact-search'),
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '搜索昵称、备注或公民号',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: AppTheme.surfaceCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(14)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(12)),
          if (_loading && _contacts.isEmpty)
            const _ContactsLoadingNotice()
          else if (_contacts.isEmpty)
            const _EmptyContacts()
          else if (visible.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: AppLayout.scaledValue(56),
              ),
              child: const Center(child: Text('没有匹配的联系人')),
            )
          else
            for (final contact in visible) ...[
              _ContactCard(
                contact: contact,
                profile: _profileOf(contact),
                profileResolved: _resolvedProfileCidNumbers.contains(
                  contact.cidNumber,
                ),
                avatarPath: _profileMedia[contact.cidNumber]?.avatarPath,
                avatarUrl: _avatarUrl(_profileOf(contact)),
                avatarHeaders: _session == null
                    ? null
                    : <String, String>{
                        'authorization': 'Bearer ${_session!.sessionToken}',
                      },
                // 纯选私信模式只允许点选,不显示逐项操作菜单。
                showActions: widget.mode != ContactPickMode.pickForMessage,
                onTap: () => _open(contact),
                onTransfer: () => _transfer(contact),
                onMessage: () => _message(contact),
                onRename: () => _rename(contact),
                onDelete: () => _delete(contact),
              ),
              SizedBox(height: AppLayout.scaledValue(10)),
            ],
        ],
      ),
    );
  }

  String? _avatarUrl(CitizenProfile? profile) {
    final key = profile?.avatarObjectKey;
    return key == null
        ? null
        : _profileApi.mediaUrl(key, updatedAt: profile?.updatedAt);
  }

  String _contactDisplayName(UserContact contact) {
    final profile = _profileOf(contact);
    return ProfilePresentation.forIdentityKey(
      contact.cidNumber,
    ).resolveDisplayName(publicName: profile?.displayName);
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.profile,
    required this.profileResolved,
    required this.avatarPath,
    required this.avatarUrl,
    required this.avatarHeaders,
    required this.showActions,
    required this.onTap,
    required this.onTransfer,
    required this.onMessage,
    required this.onRename,
    required this.onDelete,
  });

  final UserContact contact;
  final CitizenProfile? profile;
  final bool profileResolved;
  final String? avatarPath;
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;

  /// 是否显示逐项操作菜单(转账/私信/改名/删除);纯选人模式为 false。
  final bool showActions;
  final VoidCallback onTap;
  final VoidCallback onTransfer;
  final VoidCallback onMessage;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final publicName = ProfilePresentation.forIdentityKey(
      contact.cidNumber,
    ).resolveDisplayName(publicName: profile?.displayName);
    final remark = contact.contactRemark;
    return Material(
      key: ValueKey('contact-card-${contact.cidNumber}'),
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(16)),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppLayout.scaled(context, 88)),
          child: Padding(
            padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
            child: Row(
              children: [
                ProfileAvatar(
                  seed: contact.cidNumber,
                  size: AppLayout.scaled(context, 52),
                  imagePath: avatarPath,
                  imageUrl: avatarUrl,
                  imageHeaders: avatarHeaders,
                  userImageSet: profileResolved
                      ? profile?.avatarObjectKey?.trim().isNotEmpty == true
                      : true,
                  identityLevel: profile?.identityLevel,
                  membershipLevel: profile?.membershipLevel,
                  membershipActive: profile?.membershipActive ?? false,
                  showBadge: profileResolved,
                  borderRadius: 14,
                ),
                SizedBox(width: AppLayout.scaled(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        publicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: AppLayout.scaled(context, 16),
                          fontWeight: FontWeight.w700,
                          height: AppLayout.compactLineHeight,
                        ),
                      ),
                      if (remark.isNotEmpty) ...[
                        SizedBox(height: AppLayout.scaled(context, 3)),
                        Text(
                          '备注：$remark',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppLayout.scaled(context, 12),
                            height: AppLayout.subtitleLineHeight,
                          ),
                        ),
                      ],
                      SizedBox(height: AppLayout.scaled(context, 3)),
                      Text(
                        '公民号：${contact.cidNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: AppLayout.scaled(context, 12),
                          height: AppLayout.subtitleLineHeight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showActions)
                  PopupMenuButton<_ContactMenuAction>(
                    tooltip: '联系人操作',
                    // 显式指定竖向三点，避免框架在 iOS 使用横向自适应图标。
                    icon: const Icon(
                      Icons.more_vert,
                      size: AppLayout.iconStandard,
                    ),
                    onSelected: (action) => switch (action) {
                      _ContactMenuAction.transfer => onTransfer(),
                      _ContactMenuAction.message => onMessage(),
                      _ContactMenuAction.rename => onRename(),
                      _ContactMenuAction.delete => onDelete(),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ContactMenuAction.transfer,
                        child: Text('转账'),
                      ),
                      PopupMenuItem(
                        value: _ContactMenuAction.message,
                        child: Text('私信'),
                      ),
                      PopupMenuItem(
                        value: _ContactMenuAction.rename,
                        child: Text('修改备注'),
                      ),
                      PopupMenuItem(
                        value: _ContactMenuAction.delete,
                        child: Text(
                          '删除联系人',
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ContactMenuAction { transfer, message, rename, delete }

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.state, required this.onRetry});

  final ContactSyncState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final retryable =
        state.phase == ContactSyncPhase.failed ||
        state.phase == ContactSyncPhase.offline;
    return InkWell(
      onTap: retryable ? () => unawaited(onRetry()) : null,
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 4),
          vertical: AppLayout.scaled(context, 5),
        ),
        child: Row(
          children: [
            Icon(
              state.phase == ContactSyncPhase.synced
                  ? Icons.cloud_done_outlined
                  : state.phase == ContactSyncPhase.syncing
                  ? Icons.sync_rounded
                  : Icons.cloud_outlined,
              size: AppLayout.scaled(context, 16),
              color: retryable ? AppTheme.warning : AppTheme.textTertiary,
            ),
            SizedBox(width: AppLayout.scaled(context, 6)),
            Text(
              state.label,
              style: TextStyle(
                color: retryable ? AppTheme.warning : AppTheme.textTertiary,
                fontSize: AppLayout.scaled(context, 12),
                height: AppLayout.subtitleLineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactsLoadingNotice extends StatelessWidget {
  const _ContactsLoadingNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppLayout.scaled(context, 64),
        horizontal: AppLayout.scaled(context, 28),
      ),
      child: Column(
        children: [
          Icon(
            Icons.perm_contact_calendar_outlined,
            size: AppLayout.scaled(context, 52),
            color: AppTheme.primary,
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),
          Text(
            '正在读取本地通讯录',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 17),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppLayout.scaled(context, 64),
        horizontal: AppLayout.scaled(context, 28),
      ),
      child: Column(
        children: [
          Icon(
            Icons.perm_contact_calendar_outlined,
            size: AppLayout.scaled(context, 52),
            color: AppTheme.primary,
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),
          Text(
            '通讯录还是空的',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 19),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 8)),
          const Text(
            '扫描其他用户的二维码添加联系人，密文同步后换设备也能恢复。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 通讯录 / 聊天页共用的「扫码加好友」收口。
///
/// 打开 contact 模式扫码页,扫到用户名片码即写入本人密文通讯录
/// (写库与「已加入/已更新通讯录」提示均在扫码页内完成)。调用方返回后自行刷新列表。
Future<void> scanAndAddContact(BuildContext context) async {
  // 通讯录浏览直接开放；扫码写入关系前才执行真实链身份校验，禁止未注册身份写库。
  // 未注册不再只弹文字提示,而是就地弹全 App 统一注册面板;占号成功后由用户
  // 重新点「扫码加好友」(不自动续跑)。钱包缺失/链读失败的提示在助手内统一。
  if (!await ensureCidRegisteredOrPrompt(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const QrScanPage(mode: QrScanMode.contact),
    ),
  );
}
