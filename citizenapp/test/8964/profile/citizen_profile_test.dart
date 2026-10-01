import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';

import '../../support/fake_citizen_sdk.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/isar/user_isar.dart';

import '../../support/isar_test_env.dart';

// 固定1×1 PNG测试素材，不来自用户图片。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==',
);

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
  test('公开资料显式刷新跨实例合并，普通读取不发请求', () async {
    final gate = Completer<http.Response>();
    var requests = 0;
    final client = _client(
      MockClient((_) {
        requests++;
        return gate.future;
      }),
    );
    final firstApi = CitizenProfileApi(client: client),
        secondApi = CitizenProfileApi(client: client);
    const cid = 'CN001-CTZN-000000001-2026';
    expect(
      () => firstApi.refreshProfile(
        cid,
        session: _session(),
        userInitiated: false,
      ),
      throwsStateError,
    );
    expect(await const CitizenProfileCache().read(cid), isNull);
    expect(requests, 0);
    final first = firstApi.refreshProfile(
      cid,
      session: _session(),
      userInitiated: true,
    );
    final second = secondApi.refreshProfile(
      cid,
      session: _session(),
      userInitiated: true,
    );
    expect(identical(first, second), isTrue);
    final json = _profileJson()..['avatar_object_key'] = null;
    gate.complete(_ok({'profile': json}));
    await first;
    expect(requests, 1);
    expect((await const CitizenProfileCache().read(cid))!.displayName, '轻节点');
  });
  test('资料修改原件跨重启保留，已确认恢复原子保存资料和图片并清除操作行', () async {
    const cache = CitizenProfileCache();
    final profile = CitizenProfile.fromJson(_profileJson(displayName: '新名'));
    final cid = profile.cidNumber!;
    final request = {
      'display_name': '新名',
      'avatar_object_key': profile.avatarObjectKey!,
      'avatar_content_hash': sha256.convert(_png).toString(),
    };
    await cache.prepareUpdate(cid, request: request, avatarBytes: _png);
    await (await UserIsar.instance.db()).close();
    final pending = await cache.readUpdate(cid);
    expect(pending!.avatarBytes, _png);
    expect(pending.operationState, 'pending');
    await expectLater(
      cache.prepareUpdate(cid, request: {'display_name': '另一修改'}),
      throwsStateError,
    );
    expect(cache.updateMatches(pending, profile), isTrue);
    await cache.confirmUpdate(profile);
    await (await UserIsar.instance.db()).close();
    await cache.finishUpdate(cid);
    expect((await cache.read(cid))!.displayName, '新名');
    expect(await cache.readUpdate(cid), isNull);
    final rows = await UserIsar.instance.read(
      (db) => db.userProfileMediaEntitys.where().findAll(),
    );
    expect(rows.single.mediaBytes, _png);
  });

  test('清除指定CID同时清除待修改原件，不波及其他CID', () async {
    const cache = CitizenProfileCache();
    const a = 'CN001-CTZN-000000001-2026', b = 'CN002-CTZN-000000002-2026';
    await cache.prepareUpdate(a, request: {'display_name': 'A'});
    await cache.prepareUpdate(b, request: {'display_name': 'B'});
    await cache.clear(a);
    expect(await cache.readUpdate(a), isNull);
    expect(await cache.readUpdate(b), isNotNull);
  });
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

    test('较旧资料不能覆盖新版本，数据库主键与正文CID不一致拒绝展示', () async {
      const cache = CitizenProfileCache();
      final profile = CitizenProfile.fromJson(_profileJson());
      await cache.write(profile.copyWith(updatedAt: 200));
      await expectLater(cache.write(profile), throwsStateError);
      expect((await cache.read(cid))!.updatedAt, 200);
      await UserIsar.instance.writeTxn((db) async {
        await db.userPublicProfileCacheEntitys.putByCidNumber(
          UserPublicProfileCacheEntity()
            ..cidNumber = cid
            ..profileJson = jsonEncode(
              _profileJson(cidNumber: 'CN001-CTZN-000000002-2026'),
            ),
        );
      });
      expect(await cache.read(cid), isNull);
      expect(
        await UserIsar.instance.read(
          (db) => db.userPublicProfileCacheEntitys.count(),
        ),
        1,
      );
    });

    test(
      'old cache without complete relation and content counts is rejected',
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
        final retained = await UserIsar.instance.read(
          (isar) async =>
              isar.userPublicProfileCacheEntitys.getByCidNumber(cid),
        );
        expect(retained, isNotNull, reason: '损坏缓存读取不得隐式删除事实');
      },
    );
  });

  group('CitizenProfileMediaCache', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('citizen-profile-media-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('重开数据库并删除临时文件后两种图片仍可恢复，普通读取不联网', () async {
      var requests = 0;
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
        client: MockClient((_) async {
          requests++;
          throw StateError('普通读取不能联网');
        }),
      );
      final profile = CitizenProfile.fromJson(_profileJson())
          .copyWith(bannerObjectKey: 'profile/banner');
      final saved = await cache.rememberSelected(
        profile: profile,
        avatarBytes: _png,
        bannerBytes: _png,
      );
      expect(
        (await const CitizenProfileCache().read(profile.cidNumber!))
            ?.bannerObjectKey,
        'profile/banner',
      );
      final rows = await UserIsar.instance.read(
        (db) => db.userProfileMediaEntitys.where().findAll(),
      );
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.mediaRole).toSet(), {'avatar', 'banner'});
      for (final row in rows) {
        expect(row.mediaBytes, _png);
      }
      await File(saved.avatarPath!).delete();
      await File(saved.bannerPath!).delete();
      await (await UserIsar.instance.db()).close();
      final restored = await cache.read(profile);
      expect(await File(restored.avatarPath!).readAsBytes(), _png);
      expect(await File(restored.bannerPath!).readAsBytes(), _png);
      expect(requests, 0);
    });

    test('同版本媒体冲突整笔回滚，资料和已有图片不被半更新', () async {
      const profiles = CitizenProfileCache();
      final profile = CitizenProfile.fromJson(_profileJson())
          .copyWith(bannerObjectKey: 'profile/banner');
      await profiles.writeWithMedia(
        profile,
        avatarBytes: _png,
        bannerBytes: _png,
      );
      await expectLater(
        profiles.writeWithMedia(
          profile.copyWith(displayName: '不得提交'),
          avatarBytes: _png,
          bannerBytes: Uint8List.fromList([..._png, 0]),
        ),
        throwsStateError,
      );
      expect(
        (await profiles.read(profile.cidNumber!))!.displayName,
        profile.displayName,
      );
      final rows = await UserIsar.instance.read(
        (db) => db.userProfileMediaEntitys.where().findAll(),
      );
      for (final row in rows) {
        expect(row.mediaBytes, _png);
      }
    });

    test('图片损坏拒绝读取且保留记录，不自动下载或清空', () async {
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final profile = CitizenProfile.fromJson(_profileJson());
      await cache.rememberSelected(profile: profile, avatarBytes: _png);
      await UserIsar.instance.writeTxn((db) async {
        final row = (await db.userProfileMediaEntitys.where().findAll()).single;
        row.mediaBytes = [...row.mediaBytes]..[0] = 0;
        await db.userProfileMediaEntitys.put(row);
      });
      await expectLater(cache.read(profile), throwsStateError);
      expect(
        await UserIsar.instance.read(
          (db) => db.userProfileMediaEntitys.count(),
        ),
        1,
      );
    });

    test('图片大小边界和格式错误不改变已有资料', () async {
      const profiles = CitizenProfileCache();
      final profile = CitizenProfile.fromJson(_profileJson());
      await profiles.write(profile);
      for (final input in [
        Uint8List(0),
        Uint8List(512 * 1024 + 1),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          profiles.writeWithMedia(
            profile.copyWith(displayName: '不得提交'),
            avatarBytes: input,
          ),
          throwsFormatException,
        );
      }
      expect(
        (await profiles.read(profile.cidNumber!))!.displayName,
        profile.displayName,
      );
      final atLimit = Uint8List(512 * 1024)..setRange(0, _png.length, _png);
      await profiles.writeWithMedia(profile, avatarBytes: atLimit);
      expect(
        await UserIsar.instance.read(
          (db) => db.userProfileMediaEntitys.count(),
        ),
        1,
      );
    });

    test('准确旧版本文件先入库回读再删除，未知版本文件保留', () async {
      final profile = CitizenProfile.fromJson(_profileJson());
      final cid = profile.cidNumber!;
      final hash = sha256.convert(utf8.encode(cid)).toString();
      final revision = sha256
          .convert(
            utf8.encode(
              '$cid\u0000avatar\u0000${profile.avatarObjectKey}\u0000${profile.updatedAt}',
            ),
          )
          .toString();
      final dir = Directory('${root.path}/user/profile_media/$hash');
      await dir.create(recursive: true);
      final old = File('${dir.path}/avatar_$revision');
      final unknown = File('${dir.path}/avatar_unknown');
      await old.writeAsBytes(_png);
      await unknown.writeAsBytes(_png);
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final result = await cache.read(profile);
      expect(await old.exists(), isFalse);
      expect(await unknown.exists(), isTrue);
      expect(await File(result.avatarPath!).readAsBytes(), _png);
      await File(result.avatarPath!).delete();
      expect((await cache.read(profile)).avatarPath, isNotNull);
    });

    test('旧文件为符号链接或损坏时保留来源且不入库', () async {
      final profile = CitizenProfile.fromJson(_profileJson());
      final cid = profile.cidNumber!;
      final hash = sha256.convert(utf8.encode(cid)).toString();
      final revision = sha256
          .convert(
            utf8.encode(
              '$cid\u0000avatar\u0000${profile.avatarObjectKey}\u0000${profile.updatedAt}',
            ),
          )
          .toString();
      final dir = Directory('${root.path}/user/profile_media/$hash');
      await dir.create(recursive: true);
      final outside = File('${root.path}/outside');
      await outside.writeAsBytes(_png);
      final link = Link('${dir.path}/avatar_$revision');
      await link.create(outside.path);
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      await expectLater(cache.read(profile), throwsStateError);
      expect(await link.exists(), isTrue);
      await link.delete();
      final broken = File(link.path);
      await broken.writeAsBytes([1, 2, 3]);
      await expectLater(cache.read(profile), throwsFormatException);
      expect(await broken.readAsBytes(), [1, 2, 3]);
      expect(
        await UserIsar.instance.read(
          (db) => db.userProfileMediaEntitys.count(),
        ),
        0,
      );
    });

    test('清除CID后迟到下载不得写回', () async {
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
        client: MockClient((_) {
          entered.complete();
          return response.future;
        }),
      );
      final profile = CitizenProfile.fromJson(_profileJson());
      final pending = cache.refresh(
        profile: profile,
        avatarUrl: 'https://example.com/avatar',
        bannerUrl: null,
        headers: null,
      );
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      await cache.clearCid(profile.cidNumber!);
      response.complete(http.Response.bytes(_png, 200));
      await rejected;
      expect(
        await UserIsar.instance.read(
          (db) => db.userProfileMediaEntitys.count(),
        ),
        0,
      );
    });

    test('显式下载入库后后续刷新复用本地，拒绝非HTTPS地址', () async {
      var requests = 0;
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(_png, 200);
        }),
      );
      final profile = CitizenProfile.fromJson(_profileJson());
      await expectLater(
        cache.refresh(
          profile: profile,
          avatarUrl: 'file:///image',
          bannerUrl: null,
          headers: null,
        ),
        throwsArgumentError,
      );
      for (var i = 0; i < 2; i++) {
        final result = await cache.refresh(
          profile: profile,
          avatarUrl: 'https://example.com/avatar',
          bannerUrl: null,
          headers: null,
        );
        expect(await File(result.avatarPath!).readAsBytes(), _png);
      }
      expect(requests, 1);
    });

    test('用户设置图片后首帧读取本机副本，未设置才返回空让页面使用内置图', () async {
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final profile = CitizenProfile.fromJson(_profileJson());
      final remembered = await cache.rememberSelected(
        profile: profile,
        avatarBytes: Uint8List.fromList(_png),
      );

      expect(remembered.avatarPath, isNotNull);
      expect(await File(remembered.avatarPath!).readAsBytes(), _png);

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
        avatarBytes: Uint8List.fromList(_png),
      );
      final changed = profile.copyWith(updatedAt: profile.updatedAt + 1);

      final refreshed = await cache.refresh(
        profile: changed,
        avatarUrl: 'https://example.com/avatar',
        bannerUrl: null,
        headers: const <String, String>{'authorization': 'Bearer token'},
      );

      expect(refreshed.avatarPath, previous.avatarPath);
      expect(await File(refreshed.avatarPath!).readAsBytes(), _png);
    });

    test('按 CID 清理不影响其它用户，全量安全擦除删除整个资料媒体域', () async {
      final cache = CitizenProfileMediaCache(
        supportDirectoryProvider: () async => root,
      );
      final first = CitizenProfile.fromJson({
        ..._profileJson(),
        'cid_number': 'CN001-CTZN-000000001-2026',
      });
      final second = CitizenProfile.fromJson({
        ..._profileJson(),
        'cid_number': 'CN001-CTZN-000000002-2026',
      });
      final firstMedia = await cache.rememberSelected(
        profile: first,
        avatarBytes: Uint8List.fromList(_png),
      );
      final secondMedia = await cache.rememberSelected(
        profile: second,
        avatarBytes: Uint8List.fromList(_png),
      );

      await cache.clearCid(first.cidNumber!);
      expect(await File(firstMedia.avatarPath!).exists(), isFalse);
      expect(await File(secondMedia.avatarPath!).exists(), isTrue);

      await UserIsar.instance.closeAndDeleteFromDisk();
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

    test('fetchAuthorPosts parses post_type and title for articles', () async {
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
                  },
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
    });

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

    test('fetchFollows sends the mutual_following query without local intersection', () async {
      Uri? seen;
      final client = _client(
        MockClient((request) async {
          seen = request.url;
          return _ok({'ok': true, 'entries': [], 'next_cursor': null});
        }),
      );

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
