import '../../support/fake_citizen_sdk.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/isar/user_isar.dart';

import '../../support/isar_test_env.dart';

const String _owner = '5GrwvaEF5zXb26Fz9rcQpDWS7u4m6DXb6T6TQvF9j5uQ8g6U';

Map<String, dynamic> _profileJson({
  String displayName = '轻节点',
  String? cidNumber = 'CN001-CTZN-000000001-2026',
  bool isFollowing = false,
  bool isFollowedBy = false,
  int following = 2,
  int followers = 128,
  int mutualFollowing = 8,
  int posts = 36,
  int campaigns = 6,
  int videos = 4,
  int articles = 12,
  String identityLevel = 'voting',
  String? membershipLevel = 'democracy',
  bool membershipActive = true,
}) {
  return <String, dynamic>{
    'account_id': _owner,
    'display_name': displayName,
    'bio': '链上公民',
    'avatar_object_key': 'profile/$_owner/avatar',
    'banner_object_key': null,
    'cid_number': cidNumber,
    'is_certified': cidNumber != null,
    'identity_level': identityLevel,
    'membership_level': membershipLevel,
    'membership_active': membershipActive,
    'counts': {
      'following': following,
      'followers': followers,
      'mutual_following': mutualFollowing,
      'posts': posts,
      'campaigns': campaigns,
      'videos': videos,
      'articles': articles,
    },
    'is_following': isFollowing,
    'is_followed_by': isFollowedBy,
    'updated_at': 123,
  };
}

SquareApiClient _client(MockClient mock) =>
    SquareApiClient(baseUrl: 'https://example.com', httpClient: mock);

/// http.Response(String) 默认按 Latin1 编码，中文会抛异常；显式声明 utf-8。
http.Response _ok(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

// `_headers` 对带 session 的请求强制要求设备请求签名器（发布会员体系后新增硬校验）；
// 测试用固定假签名占位，MockClient 不校验签名头。
SquareSession _session() => SquareSession(
      sessionToken: 'tok',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId: _owner,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      signRequest: (_) async => 'test-device-signature',
    );

void main() {
  TestCitizenSdkHarness();
  useIsolatedIsar();
  group('CitizenProfile model', () {
    test('maps counts, certification and follow state from json', () {
      final profile = CitizenProfile.fromJson(
        _profileJson(isFollowing: true, isFollowedBy: true),
      );

      expect(profile.accountId, _owner);
      expect(profile.isCertified, isTrue);
      expect(profile.cidNumber, 'CN001-CTZN-000000001-2026');
      expect(profile.isFollowing, isTrue);
      expect(profile.isFollowedBy, isTrue);
      expect(profile.following, 2);
      expect(profile.followers, 128);
      expect(profile.mutualFollowing, 8);
      expect(profile.posts, 36);
      expect(profile.campaigns, 6);
      expect(profile.videos, 4);
      expect(profile.articles, 12);
    });

    test('resolvedDisplayName uses public truth then stable local name', () {
      final named = CitizenProfile.fromJson(_profileJson(displayName: '张三'));
      expect(named.resolvedDisplayName, '张三');

      final unnamed = CitizenProfile.fromJson(_profileJson(displayName: ''));
      final fallback = ProfilePresentation.forIdentityKey(
        'CN001-CTZN-000000001-2026',
      ).fallbackName;
      expect(unnamed.resolvedDisplayName, fallback);
      expect(fallback, isNot(contains(_owner.substring(0, 6))));
    });

    test('local defaults are stable and reject account-derived nicknames', () {
      const cidNumber = 'CN001-CTZN-000000001-2026';
      final first = ProfilePresentation.forIdentityKey(cidNumber);
      final second = ProfilePresentation.forIdentityKey(cidNumber);
      final short =
          '${cidNumber.substring(0, 6)}...${cidNumber.substring(cidNumber.length - 6)}';
      const accountId =
          '0x2222222222222222222222222222222222222222222222222222222222222222';

      expect(second.fallbackName, first.fallbackName);
      expect(second.avatarAsset, first.avatarAsset);
      expect(second.bannerAsset, first.bannerAsset);
      expect(first.avatarAsset, isNot(first.bannerAsset));
      expect(
        first.resolveDisplayName(publicName: accountId),
        first.fallbackName,
      );
      expect(first.resolveDisplayName(publicName: _owner), first.fallbackName);
      expect(
        first.resolveDisplayName(publicName: cidNumber),
        first.fallbackName,
      );
      expect(first.resolveDisplayName(publicName: short), first.fallbackName);
      expect(ProfilePresentation.assets, hasLength(11));
    });

    test('SquareAuthor never falls back to its wallet account', () {
      const author = SquareAuthor(
        accountId: _owner,
        cidNumber: 'CN001-CTZN-000000001-2026',
        displayName: '',
      );
      expect(
        author.title,
        ProfilePresentation.forIdentityKey(author.cidNumber!).fallbackName,
      );
      expect(author.title, isNot(_owner));
    });

    test('survives a json round-trip', () {
      final original = CitizenProfile.fromJson(_profileJson());
      final restored = CitizenProfile.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.displayName, original.displayName);
      expect(restored.followers, original.followers);
      expect(restored.mutualFollowing, original.mutualFollowing);
      expect(restored.campaigns, original.campaigns);
      expect(restored.videos, original.videos);
      expect(restored.articles, original.articles);
      expect(restored.avatarObjectKey, original.avatarObjectKey);
    });

  });

  group('CitizenProfileCache', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    // 缓存主键 = 身份主键 cid_number（_profileJson 的 cid_number）。
    const cid = 'CN001-CTZN-000000001-2026';

    test('round-trips a profile through local storage', () async {
      const cache = CitizenProfileCache();
      final profile = CitizenProfile.fromJson(_profileJson());

      expect(await cache.read(cid), isNull);
      await cache.write(profile);
      final loaded = await cache.read(cid);

      expect(loaded, isNotNull);
      expect(loaded!.displayName, '轻节点');
      expect(loaded.followers, 128);
      expect(CitizenProfileCache.revision.value?.cidNumber, cid);
    });

    test('clear removes the cached profile', () async {
      const cache = CitizenProfileCache();
      await cache.write(CitizenProfile.fromJson(_profileJson()));
      final before = CitizenProfileCache.revision.value!.revision;
      await cache.clear(cid);
      expect(await cache.read(cid), isNull);
      expect(CitizenProfileCache.revision.value?.cidNumber, cid);
      expect(CitizenProfileCache.revision.value!.revision, greaterThan(before));
    });

    test('old cache without complete relation and content counts is rejected',
        () async {
      await UserIsar.instance.writeTxn((isar) async {
        await isar.userPublicProfileCacheEntitys.putByCidNumber(
          UserPublicProfileCacheEntity()
            ..cidNumber = cid
            ..profileJson = jsonEncode({
              ..._profileJson(),
              'counts': {'following': 2, 'followers': 128, 'posts': 48},
            }),
        );
      });
      expect(await const CitizenProfileCache().read(cid), isNull);
      final retained = await UserIsar.instance.read((isar) async =>
          isar.userPublicProfileCacheEntitys.getByCidNumber(cid));
      expect(retained, isNotNull, reason: '损坏缓存读取不得隐式删除事实');
    });
  });

  group('CitizenProfileMediaCache', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('citizen-profile-media-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('用户设置图片后首帧读取本机副本，未设置才返回空让页面使用内置图', () async {
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final profile = CitizenProfile.fromJson(_profileJson());
      final remembered = await cache.rememberSelected(
        profile: profile,
        avatarBytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      );

      expect(remembered.avatarPath, isNotNull);
      expect(
        await File(remembered.avatarPath!).readAsBytes(),
        const <int>[1, 2, 3, 4],
      );

      final unset = profile.copyWith(
        avatarObjectKey: null,
        updatedAt: profile.updatedAt + 1,
      );
      expect((await cache.read(unset)).avatarPath, isNull);
    });

    test('新图片下载失败时保留上一张用户图片且不回退内置随机图', () async {
      final profile = CitizenProfile.fromJson(_profileJson());
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
        client: MockClient((_) async => http.Response('failed', 503)),
      );
      final previous = await cache.rememberSelected(
        profile: profile,
        avatarBytes: Uint8List.fromList(const <int>[9, 8, 7]),
      );
      final changed = profile.copyWith(updatedAt: profile.updatedAt + 1);

      final refreshed = await cache.refresh(
        profile: changed,
        avatarUrl: 'https://example.com/avatar',
        bannerUrl: null,
        headers: const <String, String>{'authorization': 'Bearer token'},
      );

      expect(refreshed.avatarPath, previous.avatarPath);
      expect(
        await File(refreshed.avatarPath!).readAsBytes(),
        const <int>[9, 8, 7],
      );
    });

    test('按 CID 清理不影响其它用户，全量安全擦除删除整个资料媒体域', () async {
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final first = CitizenProfile.fromJson(
        {..._profileJson(), 'cid_number': 'CN001-CTZN-000000001-2026'},
      );
      final second = CitizenProfile.fromJson(
        {..._profileJson(), 'cid_number': 'CN001-CTZN-000000002-2026'},
      );
      final firstMedia = await cache.rememberSelected(
        profile: first,
        avatarBytes: Uint8List.fromList(const <int>[1]),
      );
      final secondMedia = await cache.rememberSelected(
        profile: second,
        avatarBytes: Uint8List.fromList(const <int>[2]),
      );

      await cache.clearCid(first.cidNumber!);
      expect(await File(firstMedia.avatarPath!).exists(), isFalse);
      expect(await File(secondMedia.avatarPath!).exists(), isTrue);

      await cache.closeAndDeleteAll();
      expect(await File(secondMedia.avatarPath!).exists(), isFalse);
    });
  });

  group('SquareApiClient profile endpoints', () {
    test(
      'fetchUserProfile parses the profile and forwards the session',
      () async {
        String? authHeader;
        final client = _client(
          MockClient((request) async {
            authHeader = request.headers['authorization'];
            expect(request.url.path, '/square/users/$_owner');
            return _ok({
              'ok': true,
              'profile': _profileJson(isFollowing: true),
            });
          }),
        );

        final profile = await client.fetchUserProfile(
          cidNumber: _owner,
          session: _session(),
        );

        expect(authHeader, 'Bearer tok');
        expect(profile.isFollowing, isTrue);
        expect(profile.followers, 128);
        expect(profile.mutualFollowing, 8);
        expect(profile.campaigns, 6);
        expect(profile.videos, 4);
        expect(profile.articles, 12);
      },
    );

    test(
      'fetchAuthorPosts filters by category and returns the cursor',
      () async {
        Uri? seen;
        final client = _client(
          MockClient((request) async {
            seen = request.url;
            return _ok({
              'ok': true,
              'posts': [
                {
                  'post_id': 'c1',
                  'account_id': _owner,
                  'post_category': 'campaign',
                  'post_type': 'document',
                  'excerpt': '竞选宣言',
                  'created_at': 300,
                },
              ],
              'next_cursor': 300,
            });
          }),
        );

        final page = await client.fetchAuthorPosts(
          cidNumber: _owner,
          category: SquarePostCategory.campaign,
          limit: 2,
        );

        expect(seen!.path, '/square/users/$_owner/posts');
        expect(seen!.queryParameters['category'], 'campaign');
        expect(seen!.queryParameters['limit'], '2');
        expect(page.posts.single.postId, 'c1');
        expect(page.posts.single.postCategory, SquarePostCategory.campaign);
        expect(page.nextCursor, 300);
      },
    );

    test(
      'fetchAuthorPosts parses post_type and title for articles',
      () async {
        final client = _client(
          MockClient((request) async {
            return _ok({
              'ok': true,
              'posts': [
                {
                  'post_id': 'a1',
                  'account_id': _owner,
                  'post_category': 'normal',
                  'post_type': 'article',
                  'title': '我的文章',
                  'excerpt': '正文摘要',
                  'created_at': 100,
                  'media_items': [
                    {
                      'media_kind': 'image',
                      'url': 'https://media.test/cover.jpg',
                    }
                  ],
                },
              ],
              'next_cursor': null,
            });
          }),
        );

        final page = await client.fetchAuthorPosts(cidNumber: _owner);
        final post = page.posts.single;

        expect(post.postType, SquarePostType.article);
        expect(post.title, '我的文章');
      },
    );

    test('fetchAuthorPosts sends post_type query', () async {
      Uri? seen;
      final client = _client(
        MockClient((request) async {
          seen = request.url;
          return _ok({'ok': true, 'posts': [], 'next_cursor': null});
        }),
      );

      await client.fetchAuthorPosts(
        cidNumber: _owner,
        postType: SquarePostType.article,
      );

      expect(seen!.queryParameters['post_type'], 'article');
    });

    test(
        'fetchFollows sends the mutual_following query without local intersection',
        () async {
      Uri? seen;
      final client = _client(MockClient((request) async {
        seen = request.url;
        return _ok({'ok': true, 'entries': [], 'next_cursor': null});
      }));

      await client.fetchFollows(
        cidNumber: 'CN001-CTZN-000000001-2026',
        type: 'mutual_following',
        session: _session(),
      );

      expect(seen!.queryParameters['type'], 'mutual_following');
    });

    test('mediaUrl builds an encoded wallet media url', () {
      final client = _client(MockClient((_) async => http.Response('', 200)));
      expect(
        client.mediaUrl('profile/acct/avatar'),
        'https://example.com/square/media/profile/acct/avatar',
      );
    });

    test('updateProfile PUTs only the provided fields', () async {
      String? method;
      Map<String, dynamic>? body;
      final client = _client(
        MockClient((request) async {
          method = request.method;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _ok({'ok': true, 'profile': _profileJson(displayName: '新名字')});
        }),
      );

      final updated = await client.updateProfile(
        session: _session(),
        displayName: '新名字',
      );

      expect(method, 'PUT');
      expect(body, {'display_name': '新名字'});
      expect(updated.displayName, '新名字');
    });
  });
}
