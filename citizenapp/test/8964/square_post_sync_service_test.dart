import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:citizenapp/8964/services/square_media_store.dart';
import 'package:citizenapp/isar/social_isar.dart';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/8964/services/square_post_sync_service.dart';

import '../support/isar_test_env.dart';

const _cid = 'R5-K3P1C1-N9-D4';
const _account =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _session = SquareSession(
  sessionToken: 'sqs_sync',
  cidNumber: _cid,
  bindingRevision: 1,
  accountId: _account,
  expiresAt: 1900000000000,
);

SquareLocalPost _post(
  String postId,
  int createdAt, {
  String cid = _cid,
  List<Map<String, Object>> media = const [],
}) {
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schema': SquarePostStore.manifestSchema,
        'cid_number': cid,
        'post_type': 'document',
        'text': '正文 $postId',
        'media_items': media,
      }),
    ),
  );
  return SquareLocalPost(
    postId: postId,
    cidNumber: cid,
    accountId: _account,
    postCategory: 'normal',
    postType: 'document',
    manifestBytes: bytes,
    contentHash: sha256.convert(bytes).toString(),
    storageReceiptId: 'sqr_$postId',
    chainBlock: createdAt,
    createdAt: createdAt,
    postState: SquarePostStore.publishedState,
  );
}

class _MediaApi extends SquareApiClient {
  _MediaApi(this.post, this.main, this.preview);
  final SquareLocalPost post;
  final Uint8List main;
  final Uint8List preview;
  bool corrupt = false;
  int downloads = 0;
  @override
  Future<List<Map<String, dynamic>>> fetchPostMedia({
    required SquareSession session,
    required SquareLocalPost post,
  }) async {
    final manifest = jsonDecode(utf8.decode(post.manifestBytes)) as Map;
    return (manifest['media_items'] as List)
        .map(
          (item) => <String, dynamic>{
            ...Map<String, dynamic>.from(item as Map),
            'asset_state': 'ready',
            'url': 'https://example.com/main',
            'derivative_kind': item['media_kind'] == 'video'
                ? 'cover'
                : 'thumbnail',
            'thumbnail_url': 'https://example.com/preview',
          },
        )
        .toList();
  }

  @override
  Future<http.StreamedResponse> openPostMedia(String url) async {
    downloads++;
    final bytes = url.endsWith('/main')
        ? (corrupt ? Uint8List.fromList(List.filled(main.length, 9)) : main)
        : preview;
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      headers: {'content-type': 'image/png'},
    );
  }
}

void main() {
  useIsolatedIsar();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通加载拒绝联网，用户刷新跨实例复用同CID任务', () async {
    final gate = Completer<SquareLocalPostPage>();
    var calls = 0;
    Future<SquareLocalPostPage> load({
      required SquareSession session,
      String? cursor,
      required int limit,
    }) {
      calls++;
      return gate.future;
    }

    final a = SquarePostSyncService(pageLoader: load),
        b = SquarePostSyncService(pageLoader: load);
    expect(() => a.sync(_session, userInitiated: false), throwsStateError);
    expect(calls, 0);
    final first = a.sync(_session, userInitiated: true);
    final second = b.sync(_session, userInitiated: true);
    expect(identical(first, second), isTrue);
    gate.complete(const SquareLocalPostPage(items: [], nextCursor: null));
    await first;
    expect(calls, 1);
  });

  for (final kind in ['image', 'video']) {
    test('$kind实际字节入库并跨重启保留，哈希错误不得提交正文或推进检查点', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final preview = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==',
      );
      final hash = sha256.convert(bytes).toString();
      final post = _post(
        'media-post',
        2000,
        media: [
          {
            'media_kind': kind,
            'file_name': kind == 'image' ? 'photo.png' : 'video.mp4',
            'byte_size': bytes.length,
            'sha256': hash,
            'content_type': kind == 'image' ? 'image/png' : 'video/mp4',
          },
        ],
      );
      final api = _MediaApi(post, bytes, preview)..corrupt = true;
      final sync = SquarePostSyncService(
        api: api,
        pageLoader: ({required session, cursor, required limit}) async =>
            SquareLocalPostPage(items: [post], nextCursor: null),
      );
      await expectLater(
        sync.sync(_session, userInitiated: true),
        throwsA(isA<Exception>()),
      );
      const store = SquarePostStore();
      expect(await store.listByCid(_cid), isEmpty);
      expect(await store.readSyncCheckpoint(_cid), isNull);
      api.corrupt = false;
      await sync.sync(_session, userInitiated: true);
      await (await SocialIsar.instance.db()).close();
      const media = SquareMediaStore();
      expect(
        await media.readRange(
          cidNumber: _cid,
          mediaId: hash,
          offset: 0,
          length: bytes.length,
        ),
        bytes,
      );
      expect(
        (await media.referencesForContent(
          cidNumber: _cid,
          contentKind: 'post',
          contentId: post.postId,
        )).length,
        2,
      );
      final downloads = api.downloads;
      await sync.sync(_session, userInitiated: true);
      expect(api.downloads, downloads);
    });
  }

  test('首次回灌完整分页，后续只扫描到旧检查点且保留本地历史', () async {
    final firstCursors = <String?>[];
    final firstSync = SquarePostSyncService(
      pageLoader: ({required session, cursor, required limit}) async {
        expect(session.cidNumber, _cid);
        expect(limit, 5);
        firstCursors.add(cursor);
        if (cursor == null) {
          return SquareLocalPostPage(
            items: [_post('sqp_3', 3000), _post('sqp_2', 2000)],
            nextCursor: 'cursor_2',
          );
        }
        expect(cursor, 'cursor_2');
        return SquareLocalPostPage(
          items: [_post('sqp_1', 1000)],
          nextCursor: null,
        );
      },
    );

    await firstSync.sync(_session, userInitiated: true);
    expect(firstCursors, [null, 'cursor_2']);
    expect(
      (await const SquarePostStore().listByCid(_cid))
          .map((post) => post.postId),
      ['sqp_3', 'sqp_2', 'sqp_1'],
    );
    final firstCheckpoint = await const SquarePostStore().readSyncCheckpoint(
      _cid,
    );
    expect(firstCheckpoint?.newestPostId, 'sqp_3');
    expect(firstCheckpoint?.newestCreatedAt, 3000);

    var secondPageCalls = 0;
    final incrementalSync = SquarePostSyncService(
      pageLoader: ({required session, cursor, required limit}) async {
        secondPageCalls += 1;
        expect(cursor, isNull);
        return SquareLocalPostPage(
          items: [_post('sqp_4', 4000), _post('sqp_3', 3000)],
          nextCursor: 'must_not_be_requested',
        );
      },
    );
    await incrementalSync.sync(_session, userInitiated: true);

    expect(secondPageCalls, 1);
    expect(
      (await const SquarePostStore().listByCid(_cid))
          .map((post) => post.postId),
      ['sqp_4', 'sqp_3', 'sqp_2', 'sqp_1'],
    );
    final nextCheckpoint = await const SquarePostStore().readSyncCheckpoint(
      _cid,
    );
    expect(nextCheckpoint?.newestPostId, 'sqp_4');
    expect(nextCheckpoint?.newestCreatedAt, 4000);
  });

  test('一页任一条归属错误时整页不落盘且不推进检查点', () async {
    final service = SquarePostSyncService(
      pageLoader: ({required session, cursor, required limit}) async =>
          SquareLocalPostPage(
            items: [
              _post('sqp_good', 2000),
              _post('sqp_wrong_owner', 1000, cid: 'R5-K3P1C1-N8-D5'),
            ],
            nextCursor: null,
          ),
    );

    await expectLater(
      service.sync(_session, userInitiated: true),
      throwsA(isA<SquarePostStoreException>()),
    );
    expect(await const SquarePostStore().listByCid(_cid), isEmpty);
    expect(await const SquarePostStore().readSyncCheckpoint(_cid), isNull);
  });

  test('远端为空只更新空检查点，不删除会员到期前已落盘的本地副本', () async {
    const store = SquarePostStore();
    await store.save(_post('sqp_local', 1000));
    final service = SquarePostSyncService(
      pageLoader: ({required session, cursor, required limit}) async =>
          const SquareLocalPostPage(items: [], nextCursor: null),
    );

    await service.sync(_session, userInitiated: true);

    expect((await store.listByCid(_cid)).single.postId, 'sqp_local');
    final checkpoint = await store.readSyncCheckpoint(_cid);
    expect(checkpoint?.newestPostId, isNull);
    expect(checkpoint?.newestCreatedAt, 0);
  });

  test('注销清理同时删除本人副本和同步检查点', () async {
    const store = SquarePostStore();
    await store.save(_post('sqp_local', 1000));
    await store.writeSyncCheckpoint(
      cidNumber: _cid,
      checkpoint: const SquarePostSyncCheckpoint(
        newestPostId: 'sqp_local',
        newestCreatedAt: 1000,
      ),
    );

    expect(await store.deleteAllByCid(_cid), 1);
    expect(await store.listByCid(_cid), isEmpty);
    expect(await store.readSyncCheckpoint(_cid), isNull);
  });

  test('同一 CID 并发启动复用同一个回灌任务', () async {
    final pageCompleter = Completer<SquareLocalPostPage>();
    var calls = 0;
    final service = SquarePostSyncService(
      pageLoader: ({required session, cursor, required limit}) {
        calls += 1;
        return pageCompleter.future;
      },
    );

    final first = service.sync(_session, userInitiated: true);
    final second = service.sync(_session, userInitiated: true);
    expect(identical(first, second), isTrue);
    pageCompleter.complete(
      const SquareLocalPostPage(items: [], nextCursor: null),
    );
    await Future.wait([first, second]);

    expect(calls, 1);
  });
}
