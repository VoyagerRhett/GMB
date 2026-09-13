import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/signer/signing.dart';
import 'package:citizenapp/security/device_subkey.dart' show hexToBytes;
import 'package:citizenapp/8964/services/square_request_signer.dart';

class SquareApiException implements Exception {
  const SquareApiException(this.message, {this.statusCode, this.errorCode});

  final String message;
  final int? statusCode;
  final String? errorCode;

  @override
  String toString() => message;
}

class SquareSession {
  const SquareSession({
    required this.sessionToken,
    required this.cidNumber,
    required this.bindingRevision,
    required this.accountId,
    required this.expiresAt,
    this.signRequest,
  });

  final String sessionToken;

  /// 本会话的身份主键 CID 号（Worker 登录响应下发；广场/聊天一切归属与寻址的主键）。
  final String cidNumber;

  /// 本会话签发时的 finalized 绑定版本；与 CID、账户共同锁定当前授权。
  final int bindingRevision;

  /// 本会话当前绑定的钱包账户 account_id（签名/链上交易用；换绑后由新账户重新登录）。
  final String accountId;
  final int expiresAt;
  final SquareDeviceSigner? signRequest;

  bool get isUsable => expiresAt > DateTime.now().millisecondsSinceEpoch;
}

class _FinalizedSessionBinding {
  const _FinalizedSessionBinding({
    required this.cidNumber,
    required this.bindingRevision,
    required this.accountId,
  });

  final String cidNumber;
  final int bindingRevision;
  final String accountId;

  bool matches(SquareSession session) =>
      session.cidNumber == cidNumber &&
      session.bindingRevision == bindingRevision &&
      session.accountId == accountId;
}

/// 会员订阅态（ADR-037：与身份彻底解耦）。只描述付费订阅本身，不含任何链上身份信息；
/// 身份展示由身份页（myid）单独负责。
class SquareMembershipState {
  const SquareMembershipState({
    required this.active,
    required this.paidUntil,
    this.membershipLevel,
    this.subscriptionStatus,
    this.subscriptionActive = false,
    this.lastChargedAt = 0,
    this.plans = const <SquareMembershipPlan>[],
    this.usageState,
  });

  final bool active;
  final int paidUntil;
  final String? membershipLevel;

  /// 订阅生命周期态（链上单源镜像）：`active`=自动续费授权有效 /
  /// `terminated`=到期扣款失败并终止 / `cancelled`=用户已签名取消。
  /// 按钮双态与横幅文案据此判定。
  final String? subscriptionStatus;

  /// 订阅是否已支付且未过期（worker `subscription_active`）。解耦后权益态即订阅态，
  /// [active] 与本字段等值；按钮双态与徽章勾均据此判定。
  final bool subscriptionActive;

  /// 最近一次真实扣款时间（毫秒）；与 [paidUntil] 组成会员卡当前已付周期展示。
  final int lastChargedAt;

  final List<SquareMembershipPlan> plans;
  final SquareMembershipUsageState? usageState;

  SquareMembershipPlan? planForLevel(String? level) {
    if (level == null) return null;
    for (final plan in plans) {
      if (plan.membershipLevel == level) return plan;
    }
    return null;
  }

  SquareMembershipPlan? get activePlan =>
      active ? planForLevel(membershipLevel) : null;

  /// 有可展示的订阅起止窗口（已支付且起止时间齐备）。
  bool get hasSubscriptionWindow =>
      subscriptionActive && lastChargedAt > 0 && paidUntil > 0;
}

class SquareMembershipPlan {
  const SquareMembershipPlan({
    required this.membershipLevel,
    required this.displayName,
    required this.chatFileMaxBytes,
    required this.chat,
    required this.document,
    required this.video,
    required this.article,
    required this.usage,
  });

  final String membershipLevel;
  final String displayName;

  /// 聊天文件大小上限（字节，会员权益之一，ADR-037）：自由 10MB / 民主 100MB / 薪火 5GB。
  final int chatFileMaxBytes;
  final SquareChatQuota chat;
  final SquareDocumentQuota document;
  final SquareVideoQuota video;
  final SquareArticleQuota article;
  final SquareMembershipUsageQuota usage;

  /// 提炼展示用短串（卡片与详情页共用，杜绝口径漂移）。
  String get chatFileSizeLabel => _fileSize(chatFileMaxBytes);
  String get chatVoiceDurationLabel => _duration(chat.voiceMessageMaxSeconds);
  String get chatVideoDurationLabel => _duration(chat.videoMessageMaxSeconds);
  String get documentImageQualityLabel => _quality(document.imageQuality);
  String get videoQualityLabel => _quality(video.videoQuality);
  String get videoDurationLabel => _duration(video.maxVideoSeconds);
  String get videoBytesLabel => _decimalFileSize(video.maxVideoBytes);
  String get articleImageQualityLabel => _quality(article.imageQuality);
  String get articleCoverQualityLabel => _quality(article.coverQuality);

  /// 周期额度以服务端定义的完整分钟数展示，不能折算整小时后丢失余下分钟。
  String get monthlyVideoDurationLabel =>
      '${_thousands(usage.monthlyVideoSeconds ~/ 60)} 分钟';
  String get storageSizeLabel => _decimalFileSize(usage.storageBytes);

  String get chatFileLabel => '聊天附件：单个 ≤ ${_fileSize(chatFileMaxBytes)}';

  String get documentLabel =>
      '公文：${document.textMaxChars} 字、${document.maxImages} 张${_quality(document.imageQuality)}图片';

  String get videoLabel =>
      '视频：${video.textMaxChars} 字配文、1 个${_duration(video.maxVideoSeconds)}${_quality(video.videoQuality)}视频';

  String get articleLabel =>
      '文章：${article.bodyMaxChars} 字、${article.maxImages} 张${_quality(article.imageQuality)}图片（含首图）、${article.maxVideos} 个视频、标题 ${article.titleMinChars}-${article.titleMaxChars} 字';

  static String _quality(String value) => value == 'hd' ? '高清' : '标清';

  static String _thousands(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  static String _duration(int seconds) {
    if (seconds >= 3600) return '${seconds ~/ 3600} 小时';
    if (seconds >= 60) return '${seconds ~/ 60} 分钟';
    return '$seconds 秒';
  }

  static String _fileSize(int bytes) {
    const mib = 1024 * 1024;
    if (bytes >= 1024 * mib) {
      // 非整 GB 保留一位小数，避免聊天文件额度被取整成失真的整数 GB。
      final gb = bytes / (1024 * mib);
      return gb == gb.roundToDouble()
          ? '${gb.round()}GB'
          : '${gb.toStringAsFixed(1)}GB';
    }
    return '${(bytes / mib).round()}MB';
  }

  /// 广场媒体与存储额度按服务端资源表的十进制字节展示，避免把 300MB 误显为 286MB。
  static String _decimalFileSize(int bytes) {
    const mb = 1000 * 1000;
    const gb = 1000 * mb;
    const tb = 1000 * gb;
    if (bytes >= tb && bytes % tb == 0) return '${bytes ~/ tb}TB';
    if (bytes >= gb && bytes % gb == 0) return '${bytes ~/ gb}GB';
    if (bytes >= mb && bytes % mb == 0) return '${bytes ~/ mb}MB';
    return '$bytes B';
  }
}

/// CitizenServe 下发的聊天权益。只有 [SquareMembershipState.activePlan] 存在时才可使用；
/// 无会员不会构造虚假的自由会员权益。
class SquareChatQuota {
  const SquareChatQuota({
    required this.textEnabled,
    required this.emojiEnabled,
    required this.stickerEnabled,
    required this.imageEnabled,
    required this.voiceMessageMaxSeconds,
    required this.videoMessageMaxSeconds,
    required this.voiceCallEnabled,
    required this.videoCallEnabled,
  });

  final bool textEnabled;
  final bool emojiEnabled;
  final bool stickerEnabled;
  final bool imageEnabled;
  final int voiceMessageMaxSeconds;
  final int videoMessageMaxSeconds;
  final bool voiceCallEnabled;
  final bool videoCallEnabled;
}

/// 公文额度结构与 Worker `document` 对象逐字段对应。
class SquareDocumentQuota {
  const SquareDocumentQuota({
    required this.textMaxChars,
    required this.imageQuality,
    required this.maxImages,
  });

  final int textMaxChars;
  final String imageQuality;
  final int maxImages;
}

/// 视频额度结构与 Worker `video` 对象逐字段对应。
class SquareVideoQuota {
  const SquareVideoQuota({
    required this.textMaxChars,
    required this.videoQuality,
    required this.maxVideoSeconds,
    required this.maxVideoBytes,
  });

  final int textMaxChars;
  final String videoQuality;
  final int maxVideoSeconds;

  /// 单个发布视频体积上限（十进制字节）：自由 16MB / 民主 300MB / 薪火 3GB。
  final int maxVideoBytes;
}

/// 文章额度结构与 Worker `article` 对象逐字段对应。
class SquareArticleQuota {
  const SquareArticleQuota({
    required this.titleMinChars,
    required this.titleMaxChars,
    required this.bodyMaxChars,
    required this.coverQuality,
    required this.imageQuality,
    required this.maxImages,
    required this.maxVideos,
  });

  final int titleMinChars;
  final int titleMaxChars;
  final int bodyMaxChars;
  final String coverQuality;
  final String imageQuality;
  final int maxImages;
  final int maxVideos;
}

/// 会员用量额度结构与 Worker `usage` 对象逐字段对应。
class SquareMembershipUsageQuota {
  const SquareMembershipUsageQuota({
    required this.monthlyImages,
    required this.monthlyVideoSeconds,
    required this.activeUploads,
    required this.storageBytes,
  });

  final int monthlyImages;
  final int monthlyVideoSeconds;
  final int activeUploads;

  /// 当前档位允许占用的总存储空间（十进制字节），不随订阅周期重置。
  final int storageBytes;
}

/// 当前会员已用量与未过期上传预留的合计；手机端只用于发布前预检。
class SquareMembershipUsageState {
  const SquareMembershipUsageState({
    required this.periodStart,
    required this.periodEnd,
    required this.imageCount,
    required this.videoSeconds,
    required this.activeUploads,
  });

  final int periodStart;
  final int periodEnd;
  final int imageCount;
  final int videoSeconds;
  final int activeUploads;
}

class SquareUploadMediaRequest {
  const SquareUploadMediaRequest({
    required this.mediaKind,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.width,
    required this.height,
    required this.derivativeKind,
    required this.derivativeContentType,
    required this.derivativeByteSize,
    required this.derivativeSha256,
    this.durationSeconds,
  });

  final SquareMediaKind mediaKind;
  final String contentType;
  final int byteSize;
  final String sha256;
  final int width;
  final int height;
  final String derivativeKind;
  final String derivativeContentType;
  final int derivativeByteSize;
  final String derivativeSha256;
  final int? durationSeconds;

  Map<String, Object?> toJson() => {
    'media_kind': mediaKind.workerValue,
    'content_type': contentType,
    'byte_size': byteSize,
    'sha256': sha256,
    'width': width,
    'height': height,
    'derivative_kind': derivativeKind,
    'derivative_content_type': derivativeContentType,
    'derivative_byte_size': derivativeByteSize,
    'derivative_sha256': derivativeSha256,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };
}

class SquarePreparedMediaUpload {
  const SquarePreparedMediaUpload({
    required this.mediaKind,
    required this.contentType,
    required this.byteSize,
    required this.objectKey,
    required this.uploadMethod,
    required this.uploadUrl,
    required this.uploadHeaders,
    required this.derivativeKind,
    required this.derivativeByteSize,
    required this.derivativeObjectKey,
    required this.derivativeUploadUrl,
    required this.derivativeUploadHeaders,
  });

  final SquareMediaKind mediaKind;
  final String contentType;
  final int byteSize;
  final String objectKey;
  final String uploadMethod;
  final String uploadUrl;
  final Map<String, String> uploadHeaders;
  final String derivativeKind;
  final int derivativeByteSize;
  final String derivativeObjectKey;
  final String derivativeUploadUrl;
  final Map<String, String> derivativeUploadHeaders;
}

class SquarePreparedUpload {
  const SquarePreparedUpload({
    required this.uploadId,
    required this.postId,
    required this.storageReceiptId,
    required this.expiresAt,
    required this.estimatedBytes,
    required this.manifestObjectKey,
    required this.manifestUploadUrl,
    required this.mediaItems,
  });

  final String uploadId;
  final String postId;
  final String storageReceiptId;
  final int expiresAt;
  final int estimatedBytes;
  final String manifestObjectKey;
  final String manifestUploadUrl;
  final List<SquarePreparedMediaUpload> mediaItems;
}

class SquareCompletedUpload {
  const SquareCompletedUpload({
    required this.uploadId,
    required this.postId,
    required this.contentHash,
    required this.storageReceiptId,
    required this.storageState,
  });

  final String uploadId;
  final String postId;
  final String contentHash;
  final String storageReceiptId;
  final String storageState;
}

class SquareBrowseState {
  const SquareBrowseState({
    required this.browseDay,
    required this.browseCount,
    required this.browseLimit,
    required this.browseLeft,
  });

  final String browseDay;
  final int browseCount;
  final int? browseLimit;
  final int? browseLeft;
}

/// Cloudflare 只可见的单条通讯录密文信封。联系人 CID、账户、SS58 和私人备注只存在于
/// [ciphertext] 内；[bindingRevision] / [accountId] 只是公开密钥版本上下文，Worker
/// 不参与密钥派生或解密。
class SquareEncryptedContact {
  const SquareEncryptedContact({
    required this.bindingRevision,
    required this.accountId,
    required this.contactId,
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    required this.updatedAt,
  });

  final int bindingRevision;
  final String accountId;
  final String contactId;
  final String ciphertext;
  final String nonce;
  final String mac;
  final int updatedAt;

  factory SquareEncryptedContact.fromJson(Map<String, dynamic> json) {
    return SquareEncryptedContact(
      bindingRevision: SquareApiClient._asInt(json['binding_revision']),
      accountId: json['account_id']?.toString() ?? '',
      contactId: json['contact_id']?.toString() ?? '',
      ciphertext: json['ciphertext']?.toString() ?? '',
      nonce: json['nonce']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      updatedAt: SquareApiClient._asInt(json['updated_at']),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'binding_revision': bindingRevision,
    'account_id': accountId,
    'contact_id': contactId,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'mac': mac,
    'updated_at': updatedAt,
  };
}

abstract class SquareFeedSource {
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit,
    SquareSession? session,
  });
}

abstract class SquarePublicationConfirmer {
  Future<SquarePost> confirmPublishedPost({
    required SquareSession session,
    required String postId,
    required String blockHashHex,
    required String txHash,
  });

  /// 删除没有形成 finalized 发布事实的当前 CID 上传；服务端必须再次查链后决定。
  Future<void> abortUpload({
    required SquareSession session,
    required String uploadId,
  });
}

abstract class SquarePostDeletionService {
  Future<void> deletePost({
    required SquareSession session,
    required String postId,
  });
}

/// Cloudflare `users` finalized 投影为本次登录挑战确认的身份上下文。
class SquareLoginContext {
  const SquareLoginContext({
    required this.cidNumber,
    required this.bindingRevision,
    required this.accountId,
  });

  final String cidNumber;
  final int bindingRevision;
  final String accountId;
}

/// 广场/Chat 登录签名器：CID 由 Worker 的 finalized 用户投影随挑战下发，调用方
/// 不得在登录前读取链。签名器只用该 CID 选择本机 P-256 设备子钥，并对客户端钉死
/// op_tag 后得到的 32 字节摘要签名。
typedef SquareLoginSigner =
    Future<String> Function(SquareLoginContext context, Uint8List loginMessage);

typedef SquareMissingDeviceHandler =
    Future<void> Function(SquareLoginContext context);

/// 账户敏感动作（注销/退订）签名器：对 `signing_message(OP_SIGN_SQUARE_ACTION)`
/// 的 32 字节摘要用 sr25519 **主钥**签名，返回 `0x` hex 签名（动钱动权，弹生物识别）。
typedef SquareActionSigner = Future<String> Function(Uint8List actionMessage);

class SquareApiConfig {
  const SquareApiConfig._();

  static const baseUrlDefineName = 'SQUARE_API_URL';

  /// 线上 Worker 唯一默认地址：聊天瞬时转发与广场共用同一个 Cloudflare Worker。
  /// 默认即连生产 Cloudflare，绝不回落本机；开发者要连本机 wrangler dev 时，
  /// 显式传 --dart-define=SQUARE_API_URL=http://127.0.0.1:8787。
  static const prodBaseUrl = 'https://www.crcfrcn.com/api';

  static const _configuredBaseUrl = String.fromEnvironment(baseUrlDefineName);

  static String get defaultBaseUrl {
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return normalizeBaseUrl(_configuredBaseUrl);
    }
    return prodBaseUrl;
  }

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (trimmed.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw UnsupportedError('$baseUrlDefineName 必须是完整的 Worker API URL');
    }
    final isLocalHttp =
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1');
    if (uri.scheme != 'https' && !isLocalHttp) {
      throw UnsupportedError(
        '$baseUrlDefineName 只允许 HTTPS，或本地调试 http://127.0.0.1',
      );
    }
    return trimmed;
  }
}

class SquareApiClient
    implements
        SquareFeedSource,
        SquarePublicationConfirmer,
        SquarePostDeletionService {
  SquareApiClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = SquareApiConfig.normalizeBaseUrl(
        baseUrl ?? SquareApiConfig.defaultBaseUrl,
      ),
      _http = httpClient ?? http.Client() {
    _liveClients.add(WeakReference<SquareApiClient>(this));
  }

  static const int _r2UploadAttempts = 3;

  static final List<WeakReference<SquareApiClient>> _liveClients =
      <WeakReference<SquareApiClient>>[];
  static _FinalizedSessionBinding? _finalizedSessionBinding;

  /// finalized 绑定切换后立即清除所有现存 API 客户端中的非当前 Session。
  ///
  /// WeakReference 不延长页面级客户端生命周期；仍在进行的此前账户握手即使稍后返回，
  /// 也会在落入缓存前再次核对本绑定并失败关闭。
  static void activateFinalizedBinding({
    required String cidNumber,
    required int bindingRevision,
    required String accountId,
  }) {
    final binding = _FinalizedSessionBinding(
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
    );
    _finalizedSessionBinding = binding;
    for (var index = _liveClients.length - 1; index >= 0; index--) {
      final client = _liveClients[index].target;
      if (client == null) {
        _liveClients.removeAt(index);
        continue;
      }
      client._sessions.removeWhere((_, session) => !binding.matches(session));
      client._inflightSessions.clear();
    }
  }

  static String get defaultBaseUrl => SquareApiConfig.defaultBaseUrl;

  final String baseUrl;
  final http.Client _http;
  SquareBrowseState? lastBrowseState;
  final Map<String, SquareSession> _sessions = {};
  // 进行中的握手：同账户并发调用共享同一 Future，杜绝冷启动握手风暴。
  final Map<String, Future<SquareSession>> _inflightSessions = {};

  /// Worker API 根地址。Chat 无内容唤醒与建连信令复用同一个 Worker 登录态。
  Uri get baseUri => Uri.parse(baseUrl);

  Future<SquareSession> ensureSession({
    required String accountId,
    required SquareLoginSigner signLoginPayload,
    SquareMissingDeviceHandler? onDeviceNotRegistered,
  }) async {
    final cached = _sessions[accountId];
    final finalizedBinding = _finalizedSessionBinding;
    if (cached != null &&
        cached.isUsable &&
        (finalizedBinding == null || finalizedBinding.matches(cached))) {
      return cached;
    }
    if (cached != null) _sessions.remove(accountId);

    // in-flight 去重：同账户并发调用共享一次握手（challenge+session=2 请求），
    // 避免广场/聊天等多入口冷启动各跑一套、迅速打满 `auth:{ip}` 限流桶（429）。
    final pending = _inflightSessions[accountId];
    if (pending != null) return pending;

    final future = _establishSessionWithRetry(
      accountId,
      signLoginPayload,
      onDeviceNotRegistered,
    );
    _inflightSessions[accountId] = future;
    try {
      return await future;
    } finally {
      _inflightSessions.remove(accountId);
    }
  }

  Future<SquareSession> _establishSessionWithRetry(
    String accountId,
    SquareLoginSigner signLoginPayload,
    SquareMissingDeviceHandler? onDeviceNotRegistered,
  ) async {
    SquareLoginContext? attemptedContext;
    try {
      return await _establishSession(accountId, (context, message) {
        attemptedContext = context;
        return signLoginPayload(context, message);
      });
    } on SquareApiException catch (e) {
      // 可自愈的两类 401,都交给前台真实业务初始化一次**本机**子钥并重试:
      // - device_not_registered:库里没有该身份的任何设备行;
      // - invalid_signature:库里有行但都不是本机钥(换新手机/重装/钱包重建后
      //   walletIndex 换新,硬件 P-256 子钥随之换新)。只认前者会死锁:行存在
      //   → 挑战能发;钥不配 → 完成必败;而登记永远不被触发。
      // 安全性由注册端点兜底:按链上 finalized 绑定 + 钱包主钥 sr25519 签名 +
      // Turnstile 重新自证,每设备一行(device_id = P-256 公钥哈希),多设备
      // 并存不覆盖别机;无种子者伪造不出绑定签名。其余错误原样上抛。
      const recoverable = {'device_not_registered', 'invalid_signature'};
      if (!recoverable.contains(e.errorCode) ||
          onDeviceNotRegistered == null ||
          attemptedContext == null) {
        rethrow;
      }
      await onDeviceNotRegistered(attemptedContext!);
      return _establishSession(accountId, signLoginPayload);
    }
  }

  Future<SquareSession> _establishSession(
    String accountId,
    SquareLoginSigner signLoginPayload,
  ) async {
    final challenge = await _postJson('/square/auth/challenge', {
      'account_id': accountId,
    });
    final signingPayloadHex = challenge['signing_payload_hex'];
    final challengeId = challenge['challenge_id'];
    final challengeCidNumber = challenge['cid_number'];
    final challengeBindingRevision = challenge['binding_revision'];
    final challengeAccountId = challenge['account_id'];
    if (signingPayloadHex is! String ||
        challengeId is! String ||
        challengeCidNumber is! String ||
        challengeCidNumber.isEmpty ||
        challengeBindingRevision is! int ||
        challengeBindingRevision <= 0 ||
        challengeAccountId != accountId) {
      throw const SquareApiException('广场登录挑战响应不完整');
    }
    final loginContext = SquareLoginContext(
      cidNumber: challengeCidNumber,
      bindingRevision: challengeBindingRevision,
      accountId: accountId,
    );

    // 客户端钉死 op_tag（登录 = OP_SIGN_SQUARE_LOGIN），只对 worker 下发的 SCALE
    // payload 重算 signing_message 摘要后签名，杜绝服务端诱导跨域签名。
    final loginMessage = signingMessage(
      opTag: kOpSignSquareLogin,
      scalePayload: hexToBytes(signingPayloadHex),
    );
    final signature = await signLoginPayload(loginContext, loginMessage);
    final session = await _postJson('/square/auth/session', {
      'challenge_id': challengeId,
      'account_id': accountId,
      'signature': signature,
    });
    final token = session['session_token'];
    final expiresAt = session['expires_at'];
    // 身份主键由 Worker 按链上绑定解析后随登录响应下发；缺失即会话不完整（未绑定 CID
    // 的账户在 Worker 侧已被拒绝建会话）。
    final cidNumber = session['cid_number'];
    final bindingRevision = session['binding_revision'];
    if (token is! String ||
        expiresAt is! int ||
        cidNumber is! String ||
        cidNumber.isEmpty ||
        bindingRevision is! int ||
        bindingRevision <= 0 ||
        cidNumber != challengeCidNumber ||
        bindingRevision != challengeBindingRevision) {
      throw const SquareApiException('广场登录态响应不完整');
    }

    final next = SquareSession(
      sessionToken: token,
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
      expiresAt: expiresAt,
      signRequest: (message) => signLoginPayload(loginContext, message),
    );
    final finalizedBinding = _finalizedSessionBinding;
    if (finalizedBinding != null && !finalizedBinding.matches(next)) {
      throw const SquareApiException('CID 当前绑定已切换，请重新登录');
    }
    _sessions[accountId] = next;
    return next;
  }

  /// 清除某账户的本地会话缓存（注销后调用，配合 Worker 端会话失效实现零残留）。
  void clearSession(String accountId) {
    _sessions.remove(accountId);
  }

  Future<void> deleteAccount({
    required String accountId,
    required SquareActionSigner signAction,
  }) {
    return _consumeAccountAction(
      accountId: accountId,
      challengePath: '/square/account/delete/challenge',
      confirmPath: '/square/account/delete',
      signAction: signAction,
    );
  }

  /// 账户敏感动作签名往返：取挑战 → 客户端**钉死** op_tag 重算摘要并签 → 提交确认。
  /// 绝不采信服务端下发的 op_tag（固定 [kOpSignSquareAction]），防被诱导跨域签名。
  Future<void> _consumeAccountAction({
    required String accountId,
    required String challengePath,
    required String confirmPath,
    required SquareActionSigner signAction,
  }) async {
    // 注销是登录态下的敏感动作:Worker 已对 account/delete 走默认拒(需有效会话),
    // 挑战与确认都必须携带当前账户的广场会话 Bearer。用户在个人页触发注销时会话
    // 已建立并缓存;未登录则明确报错,不再匿名发起(从源头杜绝对任意账户的挑战枚举)。
    final session = _sessions[accountId];
    if (session == null || !session.isUsable) {
      throw const SquareApiException('请先登录广场再注销账户');
    }
    final challenge = await _postJson(challengePath, {
      'account_id': accountId,
    }, session: session);
    final signingPayloadHex = challenge['signing_payload_hex'];
    final challengeId = challenge['challenge_id'];
    if (signingPayloadHex is! String || challengeId is! String) {
      throw const SquareApiException('动作挑战响应不完整');
    }
    final message = signingMessage(
      opTag: kOpSignSquareAction,
      scalePayload: hexToBytes(signingPayloadHex),
    );
    final signature = await signAction(message);
    await _postJson(confirmPath, {
      'account_id': accountId,
      'challenge_id': challengeId,
      'signature': signature,
    }, session: session);
  }

  /// 注册 P-256 设备子钥：绑定证明由 sr25519 主钥对
  /// [buildDeviceBindingSigningMessage]（op_tag 摘要）签名，后端验签后落库。
  /// 此后登录挑战改由子钥静默签名。
  Future<void> registerDeviceSubkey({
    required String accountId,
    required String p256PublicKeyHex,
    required int issuedAt,
    required String bindingSignatureHex,
    String? turnstileToken,
  }) async {
    await _postJson('/square/auth/device/register', {
      'account_id': accountId,
      'p256_public_key': p256PublicKeyHex,
      'issued_at': issuedAt,
      'binding_signature': bindingSignatureHex,
      if (turnstileToken != null) 'turnstile_token': turnstileToken,
    });
  }

  /// 读取 CitizenServe 的平台会员快照。该方法只解析响应，不修改页面或聊天全局状态；
  /// 会话级去重、本地缓存和刷新广播统一由 SubscriptionService 负责。
  Future<SquareMembershipState> fetchMembership(SquareSession session) async {
    const membershipPath = '/square/membership';
    final data = await _getJson(membershipPath, session: session);
    return _parseMembershipState(data);
  }

  SquareMembershipState _parseMembershipState(Map<String, dynamic> data) {
    final membership = data['membership'];
    final active = data['active'] == true;
    final subscriptionActive = data['subscription_active'] == true;
    final plans = _parseMembershipPlans(data['plans']);
    final usageState = _parseMembershipUsageState(data['usage_state']);
    // 会员与身份解耦（ADR-037）：响应只含订阅与套餐，无身份/冻结字段。
    if (membership is! Map<String, dynamic>) {
      return SquareMembershipState(
        active: false,
        paidUntil: 0,
        plans: plans,
        usageState: usageState,
      );
    }
    final membershipLevel = membership['membership_level']?.toString();
    return SquareMembershipState(
      active: active,
      paidUntil: _asInt(membership['paid_until']),
      membershipLevel: membershipLevel,
      subscriptionStatus: membership['subscription_status']?.toString(),
      subscriptionActive: subscriptionActive,
      lastChargedAt: _asInt(membership['last_charged_at']),
      plans: plans,
      usageState: usageState,
    );
  }

  /// 平台会员变更 finalized 后按 tx_hash + block_hash 同步；动作、档位、CID 与账户均由
  /// Worker 从指定链上交易和当前 Session 验证，客户端不重复声明。
  Future<SquareMembershipState> confirmPlatformSubscription({
    required SquareSession session,
    required String txHash,
    required String blockHashHex,
  }) async {
    final data = await _postJson(
      '/square/membership/confirm',
      {'tx_hash': txHash, 'block_hash': blockHashHex},
      session: session,
      finalizedMirror: true,
    );
    return _parseMembershipState(data);
  }

  /// 分页拉取当前 session 所属永久 CID 的通讯录密文。
  Future<({List<SquareEncryptedContact> items, String? nextCursor})>
  fetchEncryptedContacts({
    required SquareSession session,
    String? cursor,
    int limit = 100,
  }) async {
    final query = <String>['limit=$limit'];
    if (cursor != null && cursor.isNotEmpty) {
      query.add('cursor=${Uri.encodeQueryComponent(cursor)}');
    }
    final data = await _getJson(
      '/square/contacts?${query.join('&')}',
      session: session,
    );
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const SquareApiException('通讯录响应缺少密文列表');
    }
    final next = data['next_cursor']?.toString().trim();
    return (
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(SquareEncryptedContact.fromJson)
          .toList(growable: false),
      nextCursor: next == null || next.isEmpty ? null : next,
    );
  }

  /// 幂等写入一条通讯录密文；属主 CID 只能由 Worker 从 session 派生。
  Future<void> putEncryptedContact({
    required SquareSession session,
    required SquareEncryptedContact contact,
  }) async {
    await _putJson(
      '/square/contacts/${Uri.encodeComponent(contact.contactId)}',
      <String, Object?>{
        'binding_revision': contact.bindingRevision,
        'account_id': contact.accountId,
        'ciphertext': contact.ciphertext,
        'nonce': contact.nonce,
        'mac': contact.mac,
        'updated_at': contact.updatedAt,
      },
      session: session,
    );
  }

  /// 删除当前 session 所属永久 CID 的一条通讯录密文。
  Future<void> deleteEncryptedContact({
    required SquareSession session,
    required String contactId,
    int? bindingRevision,
    String? accountId,
  }) async {
    final revision = bindingRevision ?? session.bindingRevision;
    final bindingAccountId = accountId ?? session.accountId;
    await _deleteJson(
      '/square/contacts/${Uri.encodeComponent(contactId)}'
      '?binding_revision=$revision&account_id=${Uri.encodeQueryComponent(bindingAccountId)}',
      session: session,
    );
  }

  Future<SquarePreparedUpload> prepareUpload({
    required SquareSession session,
    required SquarePostType postType,
    required int titleLength,
    required int textLength,
    required String manifestHash,
    required int manifestByteSize,
    required List<SquareUploadMediaRequest> mediaItems,
  }) async {
    final data = await _postJson('/square/uploads/prepare', {
      'post_type': postType.workerValue,
      'title_length': titleLength,
      'text_length': textLength,
      'manifest_hash': manifestHash,
      'manifest_byte_size': manifestByteSize,
      'media_items': mediaItems.map((item) => item.toJson()).toList(),
    }, session: session);
    final rawMediaItems = data['media_items'];
    if (rawMediaItems is! List) {
      throw const SquareApiException('上传准备响应缺少媒体对象列表');
    }
    return SquarePreparedUpload(
      uploadId: _requireString(data, 'upload_id'),
      postId: _requireString(data, 'post_id'),
      storageReceiptId: _requireString(data, 'storage_receipt_id'),
      expiresAt: _asInt(data['expires_at']),
      estimatedBytes: _asInt(data['estimated_bytes']),
      manifestObjectKey: _requireString(data, 'manifest_object_key'),
      manifestUploadUrl: _requireString(data, 'manifest_upload_url'),
      mediaItems: rawMediaItems
          .map((item) => _parsePreparedMedia(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<void> uploadObject({
    required String uploadUrl,
    required String contentType,
    required Uint8List body,
    required SquareSession session,
  }) async {
    await uploadBytesTo(uploadUrl, body, contentType, session: session);
  }

  Future<void> uploadMediaAsset({
    required SquarePreparedMediaUpload upload,
    required String filePath,
  }) async {
    if (upload.uploadMethod != 'r2_put') {
      throw const SquareApiException('媒体上传方式不受支持');
    }
    await _retryR2Upload<void>(
      () => _uploadFileToR2(
        uploadUrl: upload.uploadUrl,
        filePath: filePath,
        contentLength: upload.byteSize,
        headers: upload.uploadHeaders,
      ),
    );
  }

  Future<void> uploadMediaDerivative({
    required SquarePreparedMediaUpload upload,
    required String filePath,
  }) => _retryR2Upload<void>(
    () => _uploadFileToR2(
      uploadUrl: upload.derivativeUploadUrl,
      filePath: filePath,
      contentLength: upload.derivativeByteSize,
      headers: upload.derivativeUploadHeaders,
    ),
  );

  Future<SquareCompletedUpload> completeUpload({
    required SquareSession session,
    required String uploadId,
    required String manifestHash,
    required String contentHash,
  }) async {
    final data = await _postJson('/square/uploads/complete', {
      'upload_id': uploadId,
      'manifest_hash': manifestHash,
      'content_hash': contentHash,
    }, session: session);
    return SquareCompletedUpload(
      uploadId: _requireString(data, 'upload_id'),
      postId: _requireString(data, 'post_id'),
      contentHash: _requireString(data, 'content_hash'),
      storageReceiptId: _requireString(data, 'storage_receipt_id'),
      storageState: _requireString(data, 'storage_state'),
    );
  }

  @override
  Future<SquarePost> confirmPublishedPost({
    required SquareSession session,
    required String postId,
    required String blockHashHex,
    required String txHash,
  }) async {
    final data = await _postJson('/square/posts/confirm', {
      'post_id': postId,
      'block_hash': blockHashHex,
      'tx_hash': txHash,
    }, session: session);
    final post = data['post'];
    if (post is! Map<String, dynamic>) {
      throw const SquareApiException('广场确认发布响应缺少内容数据');
    }
    return _parsePost(post);
  }

  @override
  Future<void> abortUpload({
    required SquareSession session,
    required String uploadId,
  }) async {
    await _deleteJson(
      '/square/uploads/${Uri.encodeComponent(uploadId)}',
      session: session,
    );
  }

  /// 拉取本人已发布内容的规范 manifest 原始字节。
  ///
  /// 请求沿用 [_getJson] 的 Bearer + P-256 设备证明；响应逐字段严格解析，任何一项
  /// 缺失、类型漂移或 CID 越界都会拒绝整页，不把部分结果交给本地仓库。
  Future<SquareLocalPostPage> fetchSelfPublishedPostCopies({
    required SquareSession session,
    String? cursor,
    int limit = 5,
  }) async {
    if (limit < 1 || limit > 5) {
      throw const SquareApiException('本人副本回灌 limit 必须为 1..5');
    }
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null) {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) {
        throw const SquareApiException('本人副本回灌 cursor 不合法');
      }
      params['cursor'] = cursor;
    }
    final query = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    final data = await _getJson('/square/posts/self?$query', session: session);
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.length > limit) {
      throw const SquareApiException('本人副本回灌 items 不合法');
    }
    final items = <SquareLocalPost>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, dynamic>) {
        throw const SquareApiException('本人副本回灌条目不合法');
      }
      final cidNumber = _requireExactString(rawItem, 'cid_number');
      if (cidNumber != session.cidNumber) {
        throw const SquareApiException('本人副本回灌 CID 与当前会话不一致');
      }
      final postCategory = _requireExactString(rawItem, 'post_category');
      if (postCategory != 'normal' && postCategory != 'campaign') {
        throw const SquareApiException('本人副本回灌 post_category 不合法');
      }
      final postType = _requireExactString(rawItem, 'post_type');
      if (postType != 'document' &&
          postType != 'article' &&
          postType != 'video') {
        throw const SquareApiException('本人副本回灌 post_type 不合法');
      }
      final contentHash = _requireExactString(rawItem, 'content_hash');
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash)) {
        throw const SquareApiException('本人副本回灌 content_hash 不合法');
      }
      final postState = _requireExactString(rawItem, 'post_state');
      if (postState != SquarePostStore.publishedState) {
        throw const SquareApiException('本人副本回灌只允许 published');
      }
      final chainBlockValue = rawItem['chain_block'];
      if (chainBlockValue != null &&
          (chainBlockValue is! int || chainBlockValue < 0)) {
        throw const SquareApiException('本人副本回灌 chain_block 不合法');
      }
      final createdAt = rawItem['created_at'];
      if (createdAt is! int || createdAt <= 0) {
        throw const SquareApiException('本人副本回灌 created_at 不合法');
      }
      items.add(
        SquareLocalPost(
          postId: _requireExactString(rawItem, 'post_id'),
          cidNumber: cidNumber,
          accountId: _requireExactString(rawItem, 'account_id'),
          postCategory: postCategory,
          postType: postType,
          manifestBytes: _decodeManifestBase64(
            _requireExactString(rawItem, 'manifest_bytes_base64'),
          ),
          contentHash: contentHash,
          storageReceiptId: _requireExactString(rawItem, 'storage_receipt_id'),
          chainBlock: chainBlockValue as int?,
          createdAt: createdAt,
          postState: postState,
        ),
      );
    }

    final rawNextCursor = data['next_cursor'];
    if (rawNextCursor != null &&
        (rawNextCursor is! String ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(rawNextCursor))) {
      throw const SquareApiException('本人副本回灌 next_cursor 不合法');
    }
    return SquareLocalPostPage(
      items: List<SquareLocalPost>.unmodifiable(items),
      nextCursor: rawNextCursor as String?,
    );
  }

  @override
  Future<void> deletePost({
    required SquareSession session,
    required String postId,
  }) async {
    await _deleteJson(
      '/square/posts/${Uri.encodeComponent(postId)}',
      session: session,
    );
  }

  /// 详情接口在确认 D1 可见状态后读取并校验 R2 manifest；Feed 只携带摘要。
  Future<SquarePost> fetchPostDetail({
    required SquareSession session,
    required SquarePost summary,
  }) async {
    final data = await _getJson(
      '/square/posts/${Uri.encodeComponent(summary.postId)}',
      session: session,
    );
    final post = data['post'];
    if (post is! Map<String, dynamic>) {
      throw const SquareApiException('内容详情响应缺少内容数据');
    }
    return _parsePost(post, isDetail: true, fallbackAuthor: summary.author);
  }

  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) async {
    final data = await _getJson(
      '/square/feed/${feedKind.workerValue}?limit=$limit',
      session: session,
    );
    final posts = data['posts'];
    if (posts is! List) {
      throw const SquareApiException('广场 feed 响应缺少内容列表');
    }
    lastBrowseState = _parseBrowseState(data);
    return posts
        .whereType<Map<String, dynamic>>()
        .map(_parsePost)
        .toList(growable: false);
  }

  /// 把私有头像、背景的 R2 object_key 拼成 Worker 会话门禁 URL。
  /// 广场帖子媒体由 Worker 直接返回公开 CDN 绝对地址，不经过本方法。
  String mediaUrl(String objectKey, {int? updatedAt}) {
    final encoded = objectKey.split('/').map(Uri.encodeComponent).join('/');
    final revision = updatedAt == null || updatedAt <= 0
        ? ''
        : '?updated_at=${Uri.encodeQueryComponent('$updatedAt')}';
    return '$baseUrl/square/media/$encoded$revision';
  }

  /// 拉取某身份（cid_number）的用户主页资料；钱包 Session 决定双向关注状态。
  /// 响应 profile 含 `account_id`（该身份当前绑定钱包账户，展示用，可能空串）+ `cid_number`。
  Future<CitizenProfile> fetchUserProfile({
    required String cidNumber,
    SquareSession? session,
  }) async {
    final data = await _getJson(
      '/square/users/${Uri.encodeComponent(cidNumber)}',
      session: session,
    );
    final profile = data['profile'];
    if (profile is! Map<String, dynamic>) {
      throw const SquareApiException('用户主页响应缺少资料数据');
    }
    return CitizenProfile.fromJson(profile);
  }

  /// 按作者身份主键 cid_number 分页拉帖。[category]/[postType]
  /// 为空表示不过滤；[cursor] 为上一页 nextCursor。
  Future<({List<SquarePost> posts, int? nextCursor})> fetchAuthorPosts({
    required String cidNumber,
    SquarePostCategory? category,
    SquarePostType? postType,
    int limit = 20,
    int? cursor,
    SquareSession? session,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (category != null) {
      params['category'] = category.workerValue;
    }
    if (postType != null) {
      params['post_type'] = postType.workerValue;
    }
    if (cursor != null) {
      params['cursor'] = '$cursor';
    }
    final query = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    final data = await _getJson(
      '/square/users/${Uri.encodeComponent(cidNumber)}/posts?$query',
      session: session,
    );
    final posts = data['posts'];
    if (posts is! List) {
      throw const SquareApiException('用户主页响应缺少内容列表');
    }
    lastBrowseState = _parseBrowseState(data);
    return (
      posts: posts
          .whereType<Map<String, dynamic>>()
          .map(_parsePost)
          .toList(growable: false),
      nextCursor: _nullableInt(data['next_cursor']),
    );
  }

  /// 申请头像/背景上传授权：返回 object_key、内容哈希与短期上传 URL。
  Future<({String objectKey, String contentHash, String uploadUrl})>
  prepareProfileAsset({
    required SquareSession session,
    required String kind,
    required String contentType,
    required int byteSize,
    required String sha256Hex,
  }) async {
    final data = await _postJson('/square/profile/assets/prepare', {
      'kind': kind,
      'content_type': contentType,
      'byte_size': byteSize,
      'sha256': sha256Hex,
    }, session: session);
    return (
      objectKey: _requireString(data, 'object_key'),
      contentHash: _requireString(data, 'content_hash'),
      uploadUrl: _requireString(data, 'upload_url'),
    );
  }

  /// 用户小文件只允许 PUT 到同域 Worker，并对原始字节生成设备请求签名。
  Future<void> uploadBytesTo(
    String uploadUrl,
    List<int> bytes,
    String contentType, {
    SquareSession? session,
  }) async {
    final uri = Uri.parse(uploadUrl);
    if (session == null || uri.origin != baseUri.origin) {
      throw const SquareApiException('资源上传地址必须是当前 Worker 且携带钱包会话');
    }
    final signer = session.signRequest;
    if (signer == null) {
      throw const SquareApiException('设备请求签名器缺失，请重新登录');
    }
    final body = Uint8List.fromList(bytes);
    final headers = <String, String>{
      'content-type': contentType,
      'authorization': 'Bearer ${session.sessionToken}',
      ...await squareRequestHeadersForBytes(
        method: 'PUT',
        uri: uri,
        body: body,
        sessionToken: session.sessionToken,
        sign: signer,
      ),
    };
    final response = await _http
        .put(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SquareApiException(
        '资源上传失败：${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 更新本人公开资料（仅传要改的字段；accountId 由 Worker 从 session 派生）。
  Future<CitizenProfile> updateProfile({
    required SquareSession session,
    String? displayName,
    String? bio,
    String? avatarObjectKey,
    String? avatarContentHash,
    String? bannerObjectKey,
    String? bannerContentHash,
  }) async {
    final body = <String, Object?>{
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (avatarObjectKey != null) 'avatar_object_key': avatarObjectKey,
      if (avatarContentHash != null) 'avatar_content_hash': avatarContentHash,
      if (bannerObjectKey != null) 'banner_object_key': bannerObjectKey,
      if (bannerContentHash != null) 'banner_content_hash': bannerContentHash,
    };
    final data = await _putJson('/square/profile', body, session: session);
    final profile = data['profile'];
    if (profile is! Map<String, dynamic>) {
      throw const SquareApiException('更新资料响应缺少资料数据');
    }
    return CitizenProfile.fromJson(profile);
  }

  /// 关注一个身份（写接口带 session；关注者 cid 由 Worker 从 session 派生，
  /// 请求体只带目标身份主键 followed_cid_number）。
  Future<void> followUser({
    required SquareSession session,
    required String followedCidNumber,
  }) async {
    await _postJson('/square/follows', {
      'followed_cid_number': followedCidNumber,
    }, session: session);
  }

  /// 取消关注一个身份（路径末段 = 目标身份主键 cid_number）。
  Future<void> unfollowUser({
    required SquareSession session,
    required String followedCidNumber,
  }) async {
    await _deleteJson(
      '/square/follows/${Uri.encodeComponent(followedCidNumber)}',
      session: session,
    );
  }

  /// 开/关对某关注的发帖通知（通知归属挂在关注关系上；须已关注，未关注 Worker 回 409）。
  /// 路径前段 = 目标身份主键 cid_number。
  Future<void> setNotify({
    required SquareSession session,
    required String followedCidNumber,
    required bool enabled,
  }) async {
    await _putJson(
      '/square/follows/${Uri.encodeComponent(followedCidNumber)}/notify',
      {'enabled': enabled},
      session: session,
    );
  }

  /// 拉取发帖通知双游标红点计数：广场底部 tab 与关注子 tab 各一。
  Future<({int squareUnread, int followingUnread})> fetchNotifyUnread({
    required SquareSession session,
  }) async {
    final data = await _getJson('/square/notify/unread', session: session);
    return (
      squareUnread: (data['square_unread'] as num?)?.toInt() ?? 0,
      followingUnread: (data['following_unread'] as num?)?.toInt() ?? 0,
    );
  }

  /// 推进某作用域的已读游标（`square` 进广场清、`following` 进关注子 tab 清），红点归零。
  Future<void> markNotifyRead({
    required SquareSession session,
    required String scope,
  }) async {
    await _postJson('/square/notify/read', {'scope': scope}, session: session);
  }

  /// 拉取关注、关注者或互关列表（路由末段 = 目标身份主键 cid_number；列表项为
  /// 身份主键 cid_number）。
  Future<({List<SquareFollowEntry> entries, int? nextCursor})> fetchFollows({
    required String cidNumber,
    required String type,
    int limit = 20,
    int? cursor,
    SquareSession? session,
  }) async {
    final params = <String, String>{'type': type, 'limit': '$limit'};
    if (cursor != null) {
      params['cursor'] = '$cursor';
    }
    final query = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    final data = await _getJson(
      '/square/users/${Uri.encodeComponent(cidNumber)}/follows?$query',
      session: session,
    );
    final rawEntries = data['entries'];
    if (rawEntries is! List) {
      throw const SquareApiException('关注列表响应缺少 entries 列表');
    }
    return (
      entries: rawEntries
          .whereType<Map<String, dynamic>>()
          .map(SquareFollowEntry.fromJson)
          .toList(growable: false),
      nextCursor: _nullableInt(data['next_cursor']),
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    SquareSession? session,
  }) async {
    final uri = _uri(path);
    final response = await _http
        .get(uri, headers: await _headers('GET', uri, '', session))
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    SquareSession? session,
    bool finalizedMirror = false,
  }) async {
    final encoded = jsonEncode(body);
    final uri = _uri(path);
    final response = await _http
        .post(
          uri,
          headers: finalizedMirror
              ? _finalizedMirrorHeaders(session)
              : await _headers('POST', uri, encoded, session),
          body: encoded,
        )
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }

  /// 业务交易已经账户签名并 finalized；回执只用会话鉴权，不能再生成设备签名。
  Map<String, String> _finalizedMirrorHeaders(SquareSession? session) {
    if (session == null) {
      throw const SquareApiException('会员镜像回执缺少登录态');
    }
    return {
      'content-type': 'application/json; charset=utf-8',
      'authorization': 'Bearer ${session.sessionToken}',
    };
  }

  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, Object?> body, {
    SquareSession? session,
  }) async {
    final encoded = jsonEncode(body);
    final uri = _uri(path);
    final response = await _http
        .put(
          uri,
          headers: await _headers('PUT', uri, encoded, session),
          body: encoded,
        )
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path, {
    SquareSession? session,
  }) async {
    final uri = _uri(path);
    final response = await _http
        .delete(uri, headers: await _headers('DELETE', uri, '', session))
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> _headers(
    String method,
    Uri uri,
    String body,
    SquareSession? session,
  ) async {
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
    };
    if (session == null) return headers;
    headers['authorization'] = 'Bearer ${session.sessionToken}';
    final signer = session.signRequest;
    if (signer == null) {
      throw const SquareApiException('设备请求签名器缺失，请重新登录');
    }
    headers.addAll(
      await squareRequestHeaders(
        method: method,
        uri: uri,
        body: body,
        sessionToken: session.sessionToken,
        sign: signer,
      ),
    );
    return headers;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw SquareApiException(
        '广场服务响应不是 JSON：${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw SquareApiException(
        '广场服务响应结构不合法：${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SquareApiException(
        decoded['message']?.toString() ?? '广场服务请求失败',
        statusCode: response.statusCode,
        errorCode: decoded['error_code']?.toString(),
      );
    }
    return decoded;
  }

  SquarePreparedMediaUpload _parsePreparedMedia(Map<String, dynamic> item) {
    final mediaKind = switch (_requireString(item, 'media_kind')) {
      'video' => SquareMediaKind.video,
      _ => SquareMediaKind.image,
    };
    return SquarePreparedMediaUpload(
      mediaKind: mediaKind,
      contentType: _requireString(item, 'content_type'),
      byteSize: _asInt(item['byte_size']),
      objectKey: _requireString(item, 'object_key'),
      uploadMethod: _requireString(item, 'upload_method'),
      uploadUrl: _requireString(item, 'upload_url'),
      uploadHeaders: _stringMap(item['upload_headers']),
      derivativeKind: _requireString(item, 'derivative_kind'),
      derivativeByteSize: _asInt(item['derivative_byte_size']),
      derivativeObjectKey: _requireString(item, 'derivative_object_key'),
      derivativeUploadUrl: _requireString(item, 'derivative_upload_url'),
      derivativeUploadHeaders: _stringMap(item['derivative_upload_headers']),
    );
  }

  List<SquareMembershipPlan> _parseMembershipPlans(Object? value) {
    if (value is! List) {
      return const <SquareMembershipPlan>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(_parseMembershipPlan)
        .toList(growable: false);
  }

  SquareMembershipPlan _parseMembershipPlan(Map<String, dynamic> data) {
    final chatQuota = data['chat'] is Map<String, dynamic>
        ? data['chat'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final documentQuota = data['document'] is Map<String, dynamic>
        ? data['document'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final videoQuota = data['video'] is Map<String, dynamic>
        ? data['video'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final articleQuota = data['article'] is Map<String, dynamic>
        ? data['article'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final usageQuota = data['usage'] is Map<String, dynamic>
        ? data['usage'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return SquareMembershipPlan(
      membershipLevel: _requireString(data, 'membership_level'),
      displayName: _requireString(data, 'display_name'),
      chatFileMaxBytes: _asInt(data['chat_file_max_bytes']),
      chat: SquareChatQuota(
        textEnabled: chatQuota['text_enabled'] == true,
        emojiEnabled: chatQuota['emoji_enabled'] == true,
        stickerEnabled: chatQuota['sticker_enabled'] == true,
        imageEnabled: chatQuota['image_enabled'] == true,
        voiceMessageMaxSeconds: _asInt(chatQuota['voice_message_max_seconds']),
        videoMessageMaxSeconds: _asInt(chatQuota['video_message_max_seconds']),
        voiceCallEnabled: chatQuota['voice_call_enabled'] == true,
        videoCallEnabled: chatQuota['video_call_enabled'] == true,
      ),
      document: SquareDocumentQuota(
        textMaxChars: _asInt(documentQuota['text_max_chars']),
        imageQuality: documentQuota['image_quality']?.toString() ?? 'sd',
        maxImages: _asInt(documentQuota['max_images']),
      ),
      video: SquareVideoQuota(
        textMaxChars: _asInt(videoQuota['text_max_chars']),
        videoQuality: videoQuota['video_quality']?.toString() ?? 'sd',
        maxVideoSeconds: _asInt(videoQuota['max_video_seconds']),
        maxVideoBytes: _asInt(videoQuota['max_video_bytes']),
      ),
      article: SquareArticleQuota(
        titleMinChars: _asInt(articleQuota['title_min_chars']),
        titleMaxChars: _asInt(articleQuota['title_max_chars']),
        bodyMaxChars: _asInt(articleQuota['body_max_chars']),
        coverQuality: articleQuota['cover_quality']?.toString() ?? 'hd',
        imageQuality: articleQuota['image_quality']?.toString() ?? 'sd',
        maxImages: _asInt(articleQuota['max_images']),
        maxVideos: _asInt(articleQuota['max_videos']),
      ),
      usage: SquareMembershipUsageQuota(
        monthlyImages: _asInt(usageQuota['monthly_images']),
        monthlyVideoSeconds: _asInt(usageQuota['monthly_video_seconds']),
        activeUploads: _asInt(usageQuota['active_uploads']),
        storageBytes: _asInt(usageQuota['storage_bytes']),
      ),
    );
  }

  SquareMembershipUsageState? _parseMembershipUsageState(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return SquareMembershipUsageState(
      periodStart: _asInt(value['period_start']),
      periodEnd: _asInt(value['period_end']),
      imageCount: _asInt(value['image_count']),
      videoSeconds: _asInt(value['video_seconds']),
      activeUploads: _asInt(value['active_uploads']),
    );
  }

  SquarePost _parsePost(
    Map<String, dynamic> data, {
    bool isDetail = false,
    SquareAuthor? fallbackAuthor,
  }) {
    final postType = _parsePostType(data['post_type']);
    final rawMediaItems = data['media_items'];
    final mediaItems = rawMediaItems is List
        ? rawMediaItems
              .whereType<Map<String, dynamic>>()
              .map(_parseMediaItem)
              .toList(growable: false)
        : const <SquareMediaItem>[];
    // 文章首图是发布协议的必填项。Worker 已在 prepare/complete 两次校验，客户端
    // 仍需对 Feed/详情响应失败关闭，禁止把损坏数据伪装成“无首图文章”正常展示。
    if (postType == SquarePostType.article &&
        (mediaItems.isEmpty ||
            mediaItems.first.mediaKind != SquareMediaKind.image ||
            mediaItems.first.url.isEmpty)) {
      throw const SquareApiException('文章首图缺失');
    }
    return SquarePost(
      postId: _requireString(data, 'post_id'),
      author: SquareAuthor(
        accountId: _requireString(data, 'account_id'),
        cidNumber: data['cid_number']?.toString(),
        // 昵称与头像来自作者 profile.json（Worker feed 按去重作者回填）；缺失时
        // Flutter 优先按作者永久 CID 稳定选择本地默认昵称和照片；纯访客才按账户兜底。
        displayName:
            (data['display_name']?.toString().trim().isNotEmpty ?? false)
            ? data['display_name'].toString().trim()
            : fallbackAuthor?.displayName,
        avatarObjectKey:
            (data['avatar_object_key']?.toString().isNotEmpty ?? false)
            ? data['avatar_object_key'].toString()
            : fallbackAuthor?.avatarObjectKey,
        // 作者徽章信号（Worker feed 已按去重作者读链身份+会员回填）。
        identityLevel:
            data['identity_level']?.toString() ?? fallbackAuthor?.identityLevel,
        membershipLevel:
            data['membership_level']?.toString() ??
            fallbackAuthor?.membershipLevel,
        membershipActive: data.containsKey('membership_active')
            ? data['membership_active'] == true
            : fallbackAuthor?.membershipActive ?? false,
      ),
      postCategory: _parseCategory(data['post_category']),
      postType: postType,
      title: (data['title']?.toString().trim().isNotEmpty ?? false)
          ? data['title'].toString().trim()
          : null,
      contentSections: isDetail
          ? parseArticleContentSections(data['content_sections'])
          : const <ArticleContentSection>[],
      text: (isDetail ? data['text'] : data['excerpt'])?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(data['created_at']),
      ),
      mediaItems: mediaItems,
      contentHash: data['content_hash']?.toString(),
      storageReceiptId: data['storage_receipt_id']?.toString(),
      chainBlock: _nullableInt(data['chain_block']),
      // 竞选目标（预留）：Worker 暂未返回，待公民身份上链落地后填充。
      campaignInstitutionCid: data['campaign_institution_cid']?.toString(),
      campaignPosition: data['campaign_position']?.toString(),
    );
  }

  SquareMediaItem _parseMediaItem(Map<String, dynamic> data) {
    final url = data['url']?.toString() ?? data['object_key']?.toString() ?? '';
    final coverUrl = data['thumbnail_url']?.toString() ?? '';
    return SquareMediaItem(
      mediaKind: data['media_kind'] == 'video'
          ? SquareMediaKind.video
          : SquareMediaKind.image,
      url: _resolveMediaUrl(url),
      coverUrl: coverUrl.isEmpty ? null : _resolveMediaUrl(coverUrl),
      byteSize: _nullableInt(data['byte_size']),
      assetState: data['asset_state']?.toString(),
      // 横竖屏判定所需原始尺寸；Worker feed 已随 media_items 回传。
      width: _nullableInt(data['width']),
      height: _nullableInt(data['height']),
    );
  }

  static SquarePostType _parsePostType(Object? value) {
    for (final postType in SquarePostType.values) {
      if (value == postType.workerValue) return postType;
    }
    throw const SquareApiException('post_type 不合法');
  }

  Future<void> _uploadFileToR2({
    required String uploadUrl,
    required String filePath,
    required int contentLength,
    required Map<String, String> headers,
  }) async {
    final file = File(filePath);
    if (contentLength <= 0 || await file.length() != contentLength) {
      throw const SquareApiException('媒体实际大小与上传授权不一致');
    }
    final uri = Uri.parse(uploadUrl);
    final request = http.StreamedRequest('PUT', uri)
      ..headers.addAll(headers)
      ..contentLength = contentLength;
    // 先让 Client 订阅请求流，再泵入文件；反向等待会因无人消费 StreamedRequest 而死锁。
    final responseFuture = _http
        .send(request)
        .timeout(const Duration(hours: 4));
    await request.sink.addStream(file.openRead());
    await request.sink.close();
    final response = await responseFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.stream.bytesToString();
      throw SquareApiException(
        'R2 上传失败：${response.statusCode} $text',
        statusCode: response.statusCode,
      );
    }
    await response.stream.drain<void>();
  }

  Future<T> _retryR2Upload<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _r2UploadAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt == _r2UploadAttempts || !_isRetryableR2Error(error)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw SquareApiException('R2 上传失败：$lastError');
  }

  bool _isRetryableR2Error(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }
    if (error is SquareApiException) {
      final status = error.statusCode;
      return status == 408 ||
          status == 429 ||
          (status != null && status >= 500);
    }
    return false;
  }

  String _resolveMediaUrl(String value) {
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return value;
    }
    return mediaUrl(value);
  }

  SquarePostCategory _parseCategory(Object? value) {
    return value == 'campaign'
        ? SquarePostCategory.campaign
        : SquarePostCategory.normal;
  }

  static String _requireString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) return value;
    throw SquareApiException('广场服务响应缺少 $key');
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) throw const SquareApiException('上传请求头不合法');
    return value.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  static String _requireExactString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty && value.trim() == value) {
      return value;
    }
    throw SquareApiException('广场服务响应字段 $key 不合法');
  }

  static Uint8List _decodeManifestBase64(String value) {
    if (value.isEmpty ||
        !RegExp(
          r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
        ).hasMatch(value)) {
      throw const SquareApiException('manifest_bytes_base64 不合法');
    }
    try {
      final bytes = base64Decode(value);
      if (bytes.isEmpty ||
          bytes.length > 256 * 1024 ||
          base64Encode(bytes) != value) {
        throw const SquareApiException('manifest_bytes_base64 不合法');
      }
      return Uint8List.fromList(bytes);
    } on SquareApiException {
      rethrow;
    } on Object {
      throw const SquareApiException('manifest_bytes_base64 不合法');
    }
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    return _asInt(value);
  }

  static SquareBrowseState? _parseBrowseState(Map<String, dynamic> data) {
    final day = data['browse_day'];
    if (day is! String || day.isEmpty) return null;
    return SquareBrowseState(
      browseDay: day,
      browseCount: _asInt(data['browse_count']),
      browseLimit: _nullableInt(data['browse_limit']),
      browseLeft: _nullableInt(data['browse_left']),
    );
  }

  void close() => _http.close();
}
