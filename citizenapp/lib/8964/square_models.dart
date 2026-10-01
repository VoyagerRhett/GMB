import 'package:citizenapp/8964/profile/models/profile_presentation.dart';

/// 广场前端模型。
///
/// 广场正文和媒体最终统一进入 R2；链上只记录发布索引、内容哈希和存储回执。
enum SquareFeedKind {
  recommended('推荐', 'recommended'),
  following('关注', 'following'),
  campaign('竞选', 'campaign'),
  // 内容型分类：服务端仍取推荐流（workerValue=recommended），前端按明确发布类型过滤。
  article('文章', 'recommended'),
  videos('视频', 'recommended');

  const SquareFeedKind(this.label, this.workerValue);

  final String label;
  final String workerValue;
}

enum SquarePostCategory {
  normal('普通', 'normal'),
  campaign('竞选', 'campaign');

  const SquarePostCategory(this.label, this.workerValue);

  final String label;
  final String workerValue;
}

/// 用户在广场发布入口选择的唯一内容类型。
///
/// [SquarePostCategory] 是 runtime 按发布者身份派生的普通/竞选分类，二者正交；
/// 客户端只能选择本枚举，不能选择或伪造发布分类。
enum SquarePostType {
  document('公文', 'document'),
  article('文章', 'article'),
  video('视频', 'video');

  const SquarePostType(this.label, this.workerValue);

  final String label;
  final String workerValue;
}

enum SquareMediaKind {
  image('图片', 'image'),
  video('视频', 'video');

  const SquareMediaKind(this.label, this.workerValue);

  final String label;
  final String workerValue;
}

enum SquarePublishStage {
  idle('待发布'),
  checkingBalance('校验余额'),
  signingIn('钱包登录'),
  processingMedia('处理媒体'),
  preparingStorage('准备存储'),
  submittingChain('扣费入块'),
  waitingInBlock('等待入块'),
  uploadingMedia('上传媒体'),
  completingStorage('确认存储'),
  confirmingPost('发布可见'),
  completed('已发布');

  const SquarePublishStage(this.label);

  final String label;
}

class SquareAuthor {
  const SquareAuthor({
    required this.accountId,
    this.cidNumber,
    this.displayName,
    this.avatarObjectKey,
    this.identityLevel,
    this.membershipLevel,
    this.membershipActive = false,
  });

  final String accountId;
  final String? cidNumber;
  final String? displayName;

  /// 作者头像对象键（profile.json 的 avatar_object_key）；缺失或读取失败时由
  /// ProfileAvatar 优先按永久 CID 稳定选择本地默认照片；纯访客才按账户兜底。
  final String? avatarObjectKey;

  /// 作者链上身份档：visitor/voting/candidate/null；无有效会员时用于徽章颜色。
  final String? identityLevel;

  /// 作者已购买会员档：freedom/democracy/spark/null；会员有效时用于徽章颜色。
  final String? membershipLevel;

  /// 作者会员是否有效。
  final bool membershipActive;

  bool get isCertified {
    final level = identityLevel;
    if (level != null) return level != 'visitor';
    return cidNumber != null && cidNumber!.isNotEmpty;
  }

  String get title {
    // 默认昵称稳定种子按身份主键 cid_number（与资料页/头像一致）；cid 缺失回落账户。
    return ProfilePresentation.forIdentityKey(cidNumber ?? accountId)
        .resolveDisplayName(publicName: displayName);
  }
}

class SquareMediaItem {
  const SquareMediaItem({
    required this.mediaKind,
    required this.url,
    this.coverUrl,
    this.byteSize,
    this.assetState,
    this.width,
    this.height,
    this.cidNumber,
    this.postId,
    this.mediaIndex,
  });

  final SquareMediaKind mediaKind;
  final String url;
  final String? coverUrl;
  final int? byteSize;
  final String? assetState;

  /// 本地展示以内容槽位寻址数据库；不把数据库标识拼成远端URL。
  final String? cidNumber;
  final String? postId;
  final int? mediaIndex;
  bool get isLocal => cidNumber != null && postId != null && mediaIndex != null;

  /// 媒体原始像素宽/高（Worker LimitTicket 上传时落库并随 feed 回传）。
  /// 广场卡片据此判横竖屏；缺失时按横屏兜底。
  final int? width;
  final int? height;

  /// 竖屏 = 高严格大于宽；宽高缺失或非正数时按横屏处理。
  bool get isPortrait {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    return h > w;
  }
}

class SquareLocalMediaDraft {
  const SquareLocalMediaDraft({
    required this.mediaKind,
    required this.path,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    this.durationSeconds,
    this.width,
    this.height,
    this.photoManagerAssetId,
    this.mediaId,
  });

  final SquareMediaKind mediaKind;
  final String path;

  /// 持久化媒体的数据库标识；path 只允许作为本次处理/预览的可再生文件。
  final String? mediaId;
  final String fileName;
  final String contentType;
  final int byteSize;
  final int? durationSeconds;
  final int? width;
  final int? height;

  /// 设备相册 Photo Manager 的 `AssetEntity.id`；只用于本机重新选择时恢复勾选。
  final String? photoManagerAssetId;

  SquareLocalMediaDraft copyWith({String? photoManagerAssetId}) =>
      SquareLocalMediaDraft(
        mediaKind: mediaKind,
        path: path,
        mediaId: mediaId,
        fileName: fileName,
        contentType: contentType,
        byteSize: byteSize,
        durationSeconds: durationSeconds,
        width: width,
        height: height,
        photoManagerAssetId: photoManagerAssetId ?? this.photoManagerAssetId,
      );

  String get fileExt {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// 阅读侧文章段落：富文本在前，后面最多附属一个图集或视频。
final class ArticleContentSection {
  ArticleContentSection({
    required List<Map<String, Object?>> textDelta,
    List<int>? galleryMediaIndices,
    this.videoMediaIndex,
  }) : textDelta = List<Map<String, Object?>>.unmodifiable(textDelta),
       galleryMediaIndices = galleryMediaIndices == null
           ? null
           : List<int>.unmodifiable(galleryMediaIndices);

  final List<Map<String, Object?>> textDelta;
  final List<int>? galleryMediaIndices;
  final int? videoMediaIndex;
}

/// 只解析唯一 `content_sections`，旧平铺块不兼容。
List<ArticleContentSection> parseArticleContentSections(Object? raw) {
  if (raw is! List) return const <ArticleContentSection>[];
  final out = <ArticleContentSection>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final rawDelta = item['text_delta'];
    if (rawDelta is! List || rawDelta.isEmpty) continue;
    final delta = <Map<String, Object?>>[];
    for (final operation in rawDelta) {
      if (operation is! Map || operation['insert'] is! String) {
        delta.clear();
        break;
      }
      delta.add(operation.map((key, value) => MapEntry(key.toString(), value)));
    }
    if (delta.isEmpty) continue;
    List<int>? galleryIndices;
    int? videoIndex;
    final rawIndices = item['gallery_media_indices'];
    if (rawIndices != null) {
      if (rawIndices is! List || rawIndices.isEmpty || rawIndices.length > 9) {
        continue;
      }
      final indices = <int>[];
      for (final rawIndex in rawIndices) {
        final index = rawIndex is int
            ? rawIndex
            : int.tryParse(rawIndex?.toString() ?? '');
        if (index == null || index <= 0) {
          indices.clear();
          break;
        }
        indices.add(index);
      }
      if (indices.isEmpty) continue;
      galleryIndices = indices;
    }
    final rawIndex = item['video_media_index'];
    if (rawIndex != null) {
      if (galleryIndices != null) continue;
      final index = rawIndex is int
          ? rawIndex
          : int.tryParse(rawIndex?.toString() ?? '');
      if (index == null || index <= 0) continue;
      videoIndex = index;
    }
    out.add(
      ArticleContentSection(
        textDelta: delta,
        galleryMediaIndices: galleryIndices,
        videoMediaIndex: videoIndex,
      ),
    );
  }
  return out;
}

class SquarePost {
  const SquarePost({
    required this.postId,
    required this.author,
    required this.postCategory,
    required this.postType,
    required this.text,
    required this.createdAt,
    this.title,
    this.contentSections = const <ArticleContentSection>[],
    this.mediaItems = const <SquareMediaItem>[],
    this.contentHash,
    this.storageReceiptId,
    this.chainBlock,
    this.campaignInstitutionCid,
    this.campaignPosition,
    this.isLocal = false,
  });

  final String postId;

  /// 仅表示展示来源，不能用于写操作身份授权。
  final bool isLocal;
  final SquareAuthor author;
  final SquarePostCategory postCategory;

  /// 用户选择的发布类型；普通/竞选分类由 runtime 独立派生。
  final SquarePostType postType;

  /// 文章标题；公文和视频为空。
  final String? title;

  /// 文章正文段落（富文本 + 可选媒体）；公文和视频为空。
  final List<ArticleContentSection> contentSections;

  final String text;
  final DateTime createdAt;
  final List<SquareMediaItem> mediaItems;
  final String? contentHash;
  final String? storageReceiptId;
  final int? chainBlock;

  // 竞选目标（待公民身份上链完成后由 Worker 回填与校验）：竞选哪个机构的哪个岗位。
  // 公民 CID 复用 author.cidNumber。

  /// 竞选目标机构 CID（预留，暂不入 UI）。
  final String? campaignInstitutionCid;

  /// 竞选目标岗位；竞选卡头部有值时展示（如"市长候选人"），Worker 暂未回传则为空只显时间。
  final String? campaignPosition;
}
