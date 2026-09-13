import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/compose/article/article_compose_body.dart';
import 'package:citizenapp/8964/compose/compose_payload.dart';
import 'package:citizenapp/8964/compose/document/document_compose_body.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_media.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/compose/drafts/drafts_page.dart';
import 'package:citizenapp/8964/compose/video/video_compose_body.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_compose_signers.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_publish_service.dart';
import 'package:citizenapp/8964/services/square_upload_service.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场发布页公共外壳；[postType] 由广场圆弧入口决定，页面内不可切换。
class SquareComposePage extends StatefulWidget {
  const SquareComposePage({
    super.key,
    required this.postType,
    this.identityService,
    this.publishService,
    this.draftStore,
    this.profileCache,
    this.profileMediaCache,
    this.initialText,
    this.initialTitle,
    this.replacePostId,
  });

  final SquareIdentityService? identityService;
  final SquarePublishService? publishService;
  final SquareComposeDraftRepository? draftStore;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquarePostType postType;

  /// 编辑既有帖时预填正文/标题；媒体需重选（远端资源无法转回本地草稿）。
  final String? initialText;
  final String? initialTitle;
  final String? replacePostId;

  @override
  State<SquareComposePage> createState() => _SquareComposePageState();
}

class _SquareComposePageState extends State<SquareComposePage>
    with WidgetsBindingObserver {
  final _documentKey = GlobalKey<SquareDocumentComposeBodyState>();
  final _articleKey = GlobalKey<SquareArticleComposeBodyState>();
  final _videoKey = GlobalKey<SquareVideoComposeBodyState>();

  SquarePublishService? _publishService;
  late final SquareIdentityService _identityService;
  late final SquareComposeDraftRepository _draftStore;
  late final CitizenProfileCache _profileCache;
  late final CitizenProfileMediaCache _profileMediaCache;
  late Future<SquareIdentityState> _identityFuture;

  /// 本次编辑对应的草稿 id（开页即建；从草稿箱恢复时切到该草稿 id）。
  late String _draftId;
  SquareIdentityState? _identity;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future<void>.value();
  ComposeSnapshot? _latestSnapshot;
  bool _savePendingForIdentity = false;
  bool _draftSaved = false;
  String? _avatarPath;
  bool _avatarSet = false;
  int _documentImageCount = 0;
  SquareLocalMediaDraft? _selectedVideo;

  SquarePublishStage _stage = SquarePublishStage.idle;
  bool _publishing = false;
  bool _contentValid = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftStore = widget.draftStore ?? SquareComposeDraftStore.instance;
    _profileCache = widget.profileCache ?? const CitizenProfileCache();
    _profileMediaCache = widget.profileMediaCache ?? CitizenProfileMediaCache();
    _draftId = 'd${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injectedIdentity = widget.identityService;
    if (injectedIdentity != null) {
      _identityService = injectedIdentity;
    } else {
      final sdk = context.read<CitizenSdk>();
      _identityService = SquareIdentityService(
        wallet: sdk.wallet,
        currentUserContext: context.read<CurrentUserContext>(),
        chainService: SquareChainService(
          chain: sdk.chain,
          transactions: sdk.transactions,
        ),
      );
    }
    _publishService = widget.publishService;
    // 编辑页只读取默认账户的本地用户上下文，禁止为了展示或保存草稿启动轻节点。
    _identityFuture = _identityService.loadCurrent(readLiveChain: false)
      ..then((identity) {
        _identity = identity;
        unawaited(_loadAvatar(identity));
        if (mounted) _refreshEditorState();
        // 即使页面已被系统返回手势移除，也要用退出前缓存的快照完成待保存任务。
        if (_savePendingForIdentity) unawaited(_flushLatestSnapshot());
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEditorState());
    _dependenciesReady = true;
  }

  /// 发布页只读当前 CID 的公开资料与已验证媒体缓存，不额外联网，也不建立本机头像
  /// 第二真源。用户已设置但缓存暂缺时显示中性占位，不能回退内置随机头像。
  Future<void> _loadAvatar(SquareIdentityState identity) async {
    final cidNumber = identity.cidNumber?.trim() ?? '';
    if (cidNumber.isEmpty) return;
    try {
      final profile = await _profileCache.read(cidNumber);
      if (profile == null) return;
      final media = await _profileMediaCache.read(profile);
      if (mounted && _identity?.cidNumber == identity.cidNumber) {
        setState(() {
          _avatarPath = media.avatarPath;
          _avatarSet = profile.avatarObjectKey?.trim().isNotEmpty == true;
        });
      }
    } on Exception {
      // 头像缓存读取失败不阻塞发布编辑。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    // 路由被系统手势直接移除时，使用已缓存快照继续排队保存；不再读取已销毁子组件。
    unawaited(_flushLatestSnapshot());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autosaveTimer?.cancel();
      _refreshEditorState();
      unawaited(_flushLatestSnapshot());
    }
  }

  ComposeBodyCollector? get _activeBody => switch (widget.postType) {
    SquarePostType.document =>
      _documentKey.currentState as ComposeBodyCollector?,
    SquarePostType.article => _articleKey.currentState as ComposeBodyCollector?,
    SquarePostType.video => _videoKey.currentState as ComposeBodyCollector?,
  };

  Future<SquareLocalMediaDraft> _persistMedia(
    SquareLocalMediaDraft media,
  ) async {
    final cidNumber = _identity?.cidNumber;
    if (cidNumber == null || cidNumber.isEmpty) {
      throw StateError('保存草稿媒体前必须取得当前 CID');
    }
    return ComposeDraftMedia.persist(cidNumber, _draftId, media);
  }

  /// 内容变化同时更新发布按钮和最新快照，再防抖 800ms 持久化草稿。
  void _handleBodyChanged() {
    // 文本监听器触发时先同步缓存，保证同一帧立刻发生系统返回也能取得最后一个字符；
    // 发布按钮的 setState 延到下一帧，避免在子组件构建阶段重建父组件。
    _captureLatestSnapshot();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEditorState());
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 800),
      () => _flushLatestSnapshot(),
    );
  }

  void _refreshEditorState() {
    if (!mounted) return;
    final valid = _captureLatestSnapshot();
    if (valid == null) return;
    // 即使合法性未变化也重建顶部媒体入口，使首图缩略图等子编辑器状态即时同步。
    setState(() => _contentValid = valid);
  }

  /// 只同步读取子编辑器，不触发布局；用于输入事件与退出事件之间的零帧窗口。
  bool? _captureLatestSnapshot() {
    final collector = _activeBody;
    if (collector == null) return null;
    _latestSnapshot = collector.snapshot();
    final valid = collector.isContentValid;
    return valid;
  }

  /// 快照当前内容存草稿；空内容不存（已存过则删除）。
  Future<void> _saveDraft() async {
    _refreshEditorState();
    await _flushLatestSnapshot();
  }

  /// 保存调用严格串行，确保较慢的旧快照永远不能在新快照之后覆盖草稿。
  Future<void> _flushLatestSnapshot() async {
    final cidNumber = _identity?.cidNumber;
    final snapshot = _latestSnapshot;
    if (cidNumber == null || cidNumber.isEmpty) {
      _savePendingForIdentity = snapshot != null && !snapshot.isEmpty;
      return;
    }
    if (snapshot == null) return;
    _savePendingForIdentity = false;
    final draftId = _draftId;
    _saveChain = _saveChain
        .catchError((_) {
          // 上一次失败不能阻断后续新快照；显式退出仍会等待当前这次写入。
        })
        .then((_) => _writeSnapshot(cidNumber, draftId, snapshot));
    await _saveChain;
  }

  Future<void> _writeSnapshot(
    String cidNumber,
    String draftId,
    ComposeSnapshot snapshot,
  ) async {
    if (snapshot.isEmpty) {
      if (_draftSaved) {
        await _draftStore.delete(cidNumber, draftId);
        _draftSaved = false;
      }
      return;
    }
    await _draftStore.save(
      SquareComposeDraft(
        draftId: draftId,
        cidNumber: cidNumber,
        postType: widget.postType,
        title: snapshot.title,
        text: snapshot.text,
        media: snapshot.media,
        contentSections: snapshot.contentSections,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _draftSaved = true;
  }

  /// 退出/取消前把待保存的草稿立即落盘。
  Future<void> _flushAndPop() async {
    _autosaveTimer?.cancel();
    await _saveDraft();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _deleteCurrentDraft() async {
    final cidNumber = _identity?.cidNumber;
    if (cidNumber == null || !_draftSaved) return;
    await _draftStore.delete(cidNumber, _draftId);
    _draftSaved = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_flushLatestSnapshot());
      },
      child: Scaffold(
        body: SafeArea(
          child: FutureBuilder<SquareIdentityState>(
            future: _identityFuture,
            builder: (context, snapshot) {
              final identity =
                  snapshot.data ?? const SquareIdentityState(accountId: '');
              return Column(
                children: [
                  _TopBar(
                    title: '发${widget.postType.label}',
                    publishing: _publishing,
                    canCancel:
                        !_publishing ||
                        _stage == SquarePublishStage.processingMedia,
                    stageLabel: _stage.label,
                    onCancel:
                        _publishing &&
                            _stage == SquarePublishStage.processingMedia
                        ? _cancelMediaProcessing
                        : _flushAndPop,
                    onDrafts: _openDrafts,
                    onPublish:
                        identity.hasWallet &&
                            identity.signMode != null &&
                            identity.cidNumber?.isNotEmpty == true &&
                            _contentValid &&
                            !_publishing
                        ? () => _publish(identity)
                        : null,
                  ),
                  _IdentityBar(
                    identity: identity,
                    avatarPath: _avatarPath,
                    avatarSet: _avatarSet,
                    mediaAction: _buildMediaAction(),
                  ),
                  Expanded(child: _buildBody()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody() => switch (widget.postType) {
    SquarePostType.document => SquareDocumentComposeBody(
      key: _documentKey,
      initialText: widget.initialText,
      onChanged: _handleBodyChanged,
      persistMedia: _persistMedia,
      onMediaCountChanged: (count) {
        if (mounted && count != _documentImageCount) {
          setState(() => _documentImageCount = count);
        }
      },
    ),
    SquarePostType.article => SquareArticleComposeBody(
      key: _articleKey,
      initialTitle: widget.initialTitle,
      initialText: widget.initialText,
      onChanged: _handleBodyChanged,
      persistMedia: _persistMedia,
    ),
    SquarePostType.video => SquareVideoComposeBody(
      key: _videoKey,
      initialText: widget.initialText,
      onChanged: _handleBodyChanged,
      persistMedia: _persistMedia,
      onVideoChanged: (video) {
        if (mounted && video != _selectedVideo) {
          setState(() => _selectedVideo = video);
        }
      },
    ),
  };

  /// 原类型胶囊位置只承载当前编辑器的媒体入口，不重复显示内容类型。
  Widget? _buildMediaAction() => switch (widget.postType) {
    SquarePostType.document => ComposeMediaAddButton(
      key: const ValueKey('document-add-images'),
      icon: Icons.add_photo_alternate_outlined,
      tooltip: _documentImageCount >= documentMaxImages
          ? '最多选择 $documentMaxImages 张图片'
          : '添加图片',
      onPressed: _documentImageCount >= documentMaxImages
          ? null
          : () => _documentKey.currentState?.pickImages(),
    ),
    SquarePostType.video =>
      _selectedVideo == null
          ? ComposeMediaAddButton(
              key: const ValueKey('video-picker'),
              icon: Icons.video_library_outlined,
              tooltip: '选择视频',
              onPressed: () => _videoKey.currentState?.pickVideo(),
            )
          : ComposeVideoThumbnailButton(
              key: const ValueKey('video-picker-thumbnail'),
              path: _selectedVideo!.path,
              onPressed: () => _videoKey.currentState?.pickVideo(),
            ),
    SquarePostType.article => ComposeMediaAddButton(
      key: const ValueKey('article-add-section'),
      icon: Icons.post_add_outlined,
      iconSize: 25,
      tooltip: '添加图文框',
      onPressed: () => _articleKey.currentState?.addTextSection(),
    ),
  };

  Future<void> _openDrafts() async {
    final cidNumber = _identity?.cidNumber;
    if (cidNumber == null || cidNumber.isEmpty) return;
    // 先把当前内容落盘，避免进草稿箱丢失。
    _autosaveTimer?.cancel();
    await _saveDraft();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<SquareComposeDraft>(
      MaterialPageRoute<SquareComposeDraft>(
        builder: (_) => DraftsPage(
          cidNumber: cidNumber,
          postType: widget.postType,
          store: _draftStore,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.postType != widget.postType) {
      _showError('草稿类型与当前发布页面不一致');
      return;
    }
    setState(() {
      _draftId = selected.draftId;
      _draftSaved = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (widget.postType) {
        case SquarePostType.document:
          _documentKey.currentState?.restore(selected);
        case SquarePostType.article:
          _articleKey.currentState?.restore(selected);
        case SquarePostType.video:
          _videoKey.currentState?.restore(selected);
      }
    });
  }

  SquarePublishService _requirePublishService() {
    final existing = _publishService;
    if (existing != null) return existing;
    final sdk = context.read<CitizenSdk>();
    final created = SquarePublishService(
      chain: sdk.chain,
      transactions: sdk.transactions,
      uploadService: SquareUploadService(
        subscriptionService: SubscriptionService(
          wallet: sdk.wallet,
          chain: sdk.chain,
          transactions: sdk.transactions,
          identityResolver: context.read<FinalizedIdentityResolver>(),
          sessionProvider: context.read<SquareSessionProvider>(),
        ),
      ),
    );
    _publishService = created;
    return created;
  }

  Future<void> _publish(SquareIdentityState identity) async {
    if (_publishing) return;
    final collector = _activeBody;
    if (collector == null) return;
    final payload = collector.collect();
    if (!payload.isValid) {
      _showError(payload.error!);
      return;
    }
    setState(() {
      _publishing = true;
      _stage = SquarePublishStage.signingIn;
    });
    final signers = SquareComposeSigners(context: context, identity: identity);
    try {
      final result = await _requirePublishService().publish(
        identity: identity,
        postType: widget.postType,
        text: payload.text,
        title: payload.title,
        contentSections: payload.contentSections,
        mediaDrafts: payload.mediaDrafts,
        signLoginPayload: signers.signLogin,
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
        replacePostId: widget.replacePostId,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      // 发布成功：删除该草稿（含媒体目录）。
      _autosaveTimer?.cancel();
      await _deleteCurrentDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.completionWarning ?? '已发布'),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      Navigator.of(context).pop(result.post);
    } catch (e) {
      // 失败保留草稿（已由自动保存落盘）；用户可再次点发布重试。
      if (mounted) _showError('发布失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
          _stage = SquarePublishStage.idle;
        });
      }
    }
  }

  Future<void> _cancelMediaProcessing() async {
    await _requirePublishService().cancelMediaProcessing();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.publishing,
    required this.canCancel,
    required this.stageLabel,
    required this.onCancel,
    required this.onDrafts,
    required this.onPublish,
  });

  final String title;
  final bool publishing;
  final bool canCancel;
  final String stageLabel;
  final VoidCallback onCancel;
  final VoidCallback onDrafts;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 标题以整屏宽度的几何中心定位，不受左右操作区宽度影响。
          Transform.translate(
            offset: Offset(0, -AppLayout.scaled(context, 4)),
            child: Center(
              child: Text(
                title,
                key: const ValueKey('compose-centered-title'),
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 18),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: AppLayout.scaled(context, 8)),
              child: TextButton(
                onPressed: canCancel ? onCancel : null,
                child: Text(publishing ? '停止' : '取消'),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: AppLayout.scaled(context, 12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: publishing ? null : onDrafts,
                    child: const Text('草稿'),
                  ),
                  SizedBox(width: AppLayout.scaled(context, 2)),
                  Tooltip(
                    message: publishing ? stageLabel : '发布',
                    child: FilledButton(
                      key: const ValueKey('compose-publish-button'),
                      onPressed: onPublish,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(56, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(publishing ? '发布中' : '发布'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityBar extends StatelessWidget {
  const _IdentityBar({
    required this.identity,
    required this.avatarPath,
    required this.avatarSet,
    required this.mediaAction,
  });

  final SquareIdentityState identity;
  final String? avatarPath;
  final bool avatarSet;
  final Widget? mediaAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('compose-fixed-identity-bar'),
      height: AppLayout.scaled(context, 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            ProfileAvatar(
              key: const ValueKey('compose-user-avatar'),
              imagePath: avatarPath,
              userImageSet: avatarSet,
              size: 34,
              seed: identity.cidNumber ?? identity.accountId,
              borderRadius: 17,
              showBadge: false,
            ),
            if (mediaAction != null) ...[const Spacer(), mediaAction!],
          ],
        ),
      ),
    );
  }
}
