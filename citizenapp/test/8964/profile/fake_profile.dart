import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';

const String kOwner =
    '0xd43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d';

SquareSession fakeSession() => SquareSession(
      sessionToken: 'tok',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId: kOwner,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      signRequest: (_) async => 'test-device-signature',
    );

class FakeSessionProvider implements SquareSessionProvider {
  FakeSessionProvider(this.session);

  final SquareSession? session;

  @override
  Future<SquareSession?> ensureSession() async => session;

  @override
  Future<SquareSession?> refreshSession() async => session;

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async =>
      session == null
          ? const SquareSessionResolution(SquareSessionStatus.noWallet)
          : SquareSessionResolution(SquareSessionStatus.ready, session: session);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SquarePost samplePost({
  String id = 'p1',
  SquarePostCategory category = SquarePostCategory.normal,
  SquarePostType postType = SquarePostType.document,
  String? title,
  String text = '内容',
  String displayName = '轻节点',
  List<SquareMediaItem> media = const [],
}) {
  return SquarePost(
    postId: id,
    author: SquareAuthor(
      accountId: kOwner,
      cidNumber: 'CN001-CTZN-000000001-2026',
      displayName: displayName,
    ),
    postCategory: category,
    postType: postType,
    title: title,
    text: text,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    mediaItems: media,
  );
}

CitizenProfile sampleProfile({
  bool certified = true,
  bool following = false,
  bool followedBy = false,
  bool notifying = false,
  int mutualFollowing = 8,
  int campaigns = 6,
  int videos = 4,
  int articles = 12,
  String displayName = '轻节点',
  String bio = '链上公民',
  String accountId = kOwner,
  String? avatarKey,
  String? bannerKey,
  String? identityLevel,
  String? membershipLevel,
  bool? membershipActive,
}) {
  return CitizenProfile(
    accountId: accountId,
    displayName: displayName,
    bio: bio,
    avatarObjectKey: avatarKey,
    bannerObjectKey: bannerKey,
    cidNumber: certified ? 'CN001-CTZN-000000001-2026' : null,
    isCertified: certified,
    // 认证真源=链上身份档位；默认认证=投票公民，未认证=访客。
    identityLevel: identityLevel ?? (certified ? 'voting' : 'visitor'),
    // 会员默认未购买；传合法 membershipLevel 才显示对应档位色与对勾。
    membershipLevel: membershipLevel,
    membershipActive: membershipActive ?? (membershipLevel != null),
    following: 2,
    followers: 128,
    mutualFollowing: mutualFollowing,
    posts: 36,
    campaigns: campaigns,
    videos: videos,
    articles: articles,
    isFollowing: following,
    isFollowedBy: followedBy,
    isNotifying: notifying,
    updatedAt: 1,
  );
}

class FakeProfileApi extends CitizenProfileApi {
  FakeProfileApi(
    this.result, {
    this.authorPosts = const [],
    this.localPosts = const [],
    this.follows = const [],
    this.throwOnFollow = false,
    this.throwOnProfile = false,
    this.throwOnAuthorPosts = false,
    this.unauthorizedAuthorPosts = 0,
  }) : super();

  final CitizenProfile result;
  final List<SquarePost> authorPosts;
  final List<SquareLocalPost> localPosts;
  final List<SquareFollowEntry> follows;
  final bool throwOnFollow;
  final bool throwOnProfile;
  final bool throwOnAuthorPosts;
  final int unauthorizedAuthorPosts;
  int calls = 0;
  int followCalls = 0;
  int unfollowCalls = 0;
  int notifyCalls = 0;
  int localPostCalls = 0;
  int authorPostCalls = 0;
  final List<SquareSession?> authorPostSessions = [];
  final List<SquarePostType?> authorPostTypes = [];
  bool? lastNotifyEnabled;
  String? lastFollowsType;
  Map<String, String?>? lastUpdate;

  @override
  Future<CitizenProfile> fetchProfile(
    String cidNumber, {
    SquareSession? session,
  }) async {
    calls++;
    if (throwOnProfile) {
      throw const SquareApiException('profile failed');
    }
    return result;
  }

  @override
  Future<({List<SquarePost> posts, int? nextCursor})> fetchAuthorPosts(
    String cidNumber, {
    SquarePostCategory? category,
    SquarePostType? postType,
    int limit = 20,
    int? cursor,
    SquareSession? session,
  }) async {
    authorPostCalls++;
    authorPostSessions.add(session);
    authorPostTypes.add(postType);
    if (authorPostCalls <= unauthorizedAuthorPosts) {
      throw const SquareApiException(
        'session expired',
        statusCode: 401,
        errorCode: 'expired_session',
      );
    }
    if (throwOnAuthorPosts) {
      throw const SquareApiException('author posts failed');
    }
    final filtered = authorPosts
        .where((post) => category == null || post.postCategory == category)
        .where(
          (post) => postType == null || post.postType == postType,
        )
        .toList();
    return (posts: filtered, nextCursor: null);
  }

  @override
  Future<List<SquareLocalPost>> fetchLocalPublishedPosts(
    String cidNumber,
  ) async {
    localPostCalls++;
    return localPosts
        .where((post) => post.cidNumber == cidNumber)
        .toList(growable: false);
  }

  @override
  Future<void> followUser({
    required SquareSession session,
    required String followedCidNumber,
  }) async {
    followCalls++;
    if (throwOnFollow) {
      throw const SquareApiException('follow failed');
    }
  }

  @override
  Future<void> unfollowUser({
    required SquareSession session,
    required String followedCidNumber,
  }) async {
    unfollowCalls++;
    if (throwOnFollow) {
      throw const SquareApiException('unfollow failed');
    }
  }

  @override
  Future<void> setNotify({
    required SquareSession session,
    required String followedCidNumber,
    required bool enabled,
  }) async {
    notifyCalls++;
    lastNotifyEnabled = enabled;
    if (throwOnFollow) {
      throw const SquareApiException('notify failed');
    }
  }

  @override
  Future<({List<SquareFollowEntry> entries, int? nextCursor})> fetchFollows(
    String cidNumber, {
    required String type,
    int limit = 20,
    int? cursor,
    SquareSession? session,
  }) async {
    lastFollowsType = type;
    return (entries: follows, nextCursor: null);
  }

  @override
  Future<CitizenProfile> updateProfile({
    required SquareSession session,
    String? displayName,
    String? bio,
    String? avatarObjectKey,
    String? avatarContentHash,
    String? bannerObjectKey,
    String? bannerContentHash,
  }) async {
    lastUpdate = {'display_name': displayName, 'bio': bio};
    return result.copyWith(displayName: displayName, bio: bio);
  }
}

class FakeProfileCache extends CitizenProfileCache {
  FakeProfileCache([this.seed]) : super();

  CitizenProfile? seed;
  bool wrote = false;

  @override
  Future<CitizenProfile?> read(String cidNumber) async => seed;

  @override
  Future<void> write(CitizenProfile profile) async {
    seed = profile;
    wrote = true;
  }

  @override
  Future<void> clear(String cidNumber) async {
    seed = null;
  }
}
