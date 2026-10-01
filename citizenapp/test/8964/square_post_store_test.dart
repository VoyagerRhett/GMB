import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_local_post_presenter.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/isar/social_isar.dart';
import 'package:citizenapp/8964/services/square_media_store.dart';

import '../support/isar_test_env.dart';

const _accountA =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _accountB =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _cidA = 'R5-K3P1C1-N9-D4';
const _cidB = 'R5-K3P1C1-N8-D5';

Uint8List _manifest({
  String cidNumber = _cidA,
  String postType = 'document',
  String text = '本人发布的正文',
}) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schema': SquarePostStore.manifestSchema,
        'cid_number': cidNumber,
        'post_type': postType,
        'text': text,
        'media_items': [
          {
            'media_kind': 'image',
            'file_name': 'photo.jpg',
            'content_type': 'image/jpeg',
            'byte_size': 1234,
            'sha256': 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          },
        ],
      }),
    ),
  );
}

SquareLocalPost _post({
  String postId = 'sqp_a',
  String cidNumber = _cidA,
  String accountId = _accountA,
  String postCategory = 'normal',
  String postType = 'document',
  Uint8List? manifestBytes,
  String? contentHash,
  String storageReceiptId = 'sr_a',
  int? chainBlock = 123,
  int createdAt = 1000,
  String postState = SquarePostStore.publishedState,
}) {
  final bytes =
      manifestBytes ?? _manifest(cidNumber: cidNumber, postType: postType);
  return SquareLocalPost(
    postId: postId,
    cidNumber: cidNumber,
    accountId: accountId,
    postCategory: postCategory,
    postType: postType,
    manifestBytes: bytes,
    contentHash: contentHash ?? sha256.convert(bytes).toString(),
    storageReceiptId: storageReceiptId,
    chainBlock: chainBlock,
    createdAt: createdAt,
    postState: postState,
  );
}

void main() {
  useIsolatedIsar();
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SquarePostStore();

  test('持久写入、单条及用户删除后按CID通知，失败写入不通知', () async {
    final notices = <String>[];
    void listener() => notices.add(SquarePostStore.revision.value!.cidNumber);
    SquarePostStore.revision.addListener(listener);
    try {
      await store.save(_post());
      await store.save(
        _post(postId: 'other', cidNumber: _cidB, accountId: _accountB),
      );
      await store.delete(cidNumber: _cidA, postId: 'sqp_a');
      await store.deleteAllByCid(_cidB);
      expect(notices, [_cidA, _cidB, _cidA, _cidB]);
      await expectLater(
        store.save(_post(contentHash: 'invalid')),
        throwsA(isA<SquarePostStoreException>()),
      );
      expect(notices.length, 4);
    } finally {
      SquarePostStore.revision.removeListener(listener);
    }
  });

  test('删除确认持久保存，晚到同步和重复保存不能复活正文', () async {
    final post = _post();
    await store.save(post);
    await store.recordDeletion(_cidA, post.postId, confirmed: true);
    await store.delete(cidNumber: _cidA, postId: post.postId);
    await (await SocialIsar.instance.db()).close();
    await store.save(post);
    await store.saveSyncedPage([post], {post.postId: []});
    expect(await store.listByCid(_cidA), isEmpty);
    expect(
      (await store.readDeletion(_cidA, post.postId))!.operationState,
      'confirmed',
    );
  });

  test('帖子删除原子解绑媒体，共享原件保留到最后引用删除', () async {
    const media = SquareMediaStore();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final hash = sha256.convert(bytes).toString();
    await media.saveStream(
      SquareStoredMedia(
        cidNumber: _cidA,
        mediaId: hash,
        mediaKind: 'image',
        contentType: 'image/png',
        byteSize: bytes.length,
        sha256: hash,
      ),
      Stream.value(bytes),
    );
    for (final id in ['first', 'second']) {
      await store.save(_post(postId: id));
      await SocialIsar.instance.writeTxn(
        (db) => SquareMediaStore.replaceReferencesInTransaction(
          db,
          cidNumber: _cidA,
          contentKind: 'post',
          contentId: id,
          references: [
            SquareMediaReference(
              cidNumber: _cidA,
              mediaId: hash,
              contentKind: 'post',
              contentId: id,
              mediaIndex: 0,
              mediaRole: 'main',
            ),
          ],
        ),
      );
    }
    await store.delete(cidNumber: _cidA, postId: 'first');
    expect(await media.get(cidNumber: _cidA, mediaId: hash), isNotNull);
    await store.delete(cidNumber: _cidA, postId: 'second');
    expect(await media.get(cidNumber: _cidA, mediaId: hash), isNull);
  });

  for (final damage in [false, true]) {
    test('发布收尾事务${damage ? '失败时保留草稿与恢复事实' : '保存正文与媒体后删除草稿'}', () async {
      const mediaStore = SquareMediaStore();
      final content = Uint8List.fromList([1, 2, 3, 4]);
      final thumb = Uint8List.fromList([5, 6]);
      Future<String> saveBytes(Uint8List bytes) async {
        final hash = sha256.convert(bytes).toString();
        await mediaStore.saveStream(
          SquareStoredMedia(
            cidNumber: _cidA,
            mediaId: hash,
            mediaKind: 'image',
            contentType: 'image/webp',
            byteSize: bytes.length,
            sha256: hash,
          ),
          Stream.value(bytes),
        );
        return hash;
      }

      final mainId = await saveBytes(content);
      final thumbId = await saveBytes(thumb);
      final manifest = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': SquarePostStore.manifestSchema,
            'cid_number': _cidA,
            'post_type': 'document',
            'text': '已发布正文',
            'media_items': [
              {
                'media_kind': 'image',
                'content_type': 'image/webp',
                'byte_size': content.length,
                'sha256': mainId,
                'file_name': 'synthetic.webp',
              },
            ],
          }),
        ),
      );
      await SocialIsar.instance.writeTxn((db) async {
        await db.squareComposeDraftEntitys.put(
          SquareComposeDraftEntity()
            ..draftKey =
                '${_cidA.length}:$_cidA'
                'draft-publish'
            ..cidNumber = _cidA
            ..draftId = 'draft-publish'
            ..postType = 'document'
            ..text = '未完成前保留'
            ..mediaJson = '[]'
            ..updatedAtMillis = 1000,
        );
      });
      final row = SquarePublicationEntity()
        ..cidNumber = _cidA
        ..draftId = 'draft-publish'
        ..accountId = _accountA
        ..postId = 'post-published'
        ..postType = 'document'
        ..contentHash = sha256.convert(manifest).toString()
        ..manifestBytes = manifest
        ..storageReceiptId = 'receipt'
        ..uploadId = 'upload'
        ..publicationState = 'prepared';
      await store.savePublication(
        row,
        references: [
          SquareMediaReference(
            cidNumber: _cidA,
            mediaId: mainId,
            contentKind: 'publication',
            contentId: row.postId,
            mediaIndex: 0,
            mediaRole: 'main',
          ),
          SquareMediaReference(
            cidNumber: _cidA,
            mediaId: thumbId,
            contentKind: 'publication',
            contentId: row.postId,
            mediaIndex: 0,
            mediaRole: 'thumbnail',
          ),
        ],
      );
      row.publicationState = 'submitting';
      await store.savePublication(row);
      row
        ..publicationState = 'finalized'
        ..transactionHash = 'synthetic-transaction'
        ..blockHash = 'synthetic-block';
      await store.savePublication(row);
      row
        ..publicationState = 'confirmed'
        ..postCategory = 'normal'
        ..createdAt = 1001
        ..chainBlock = 1;
      await store.savePublication(row);
      if (damage) {
        await SocialIsar.instance.writeTxn(
          (db) =>
              db.squareMediaEntitys.deleteByCidNumberMediaId(_cidA, thumbId),
        );
        await expectLater(
          store.save(
            SquarePostStore.confirmedPublication(row),
            draftId: row.draftId,
          ),
          throwsA(isA<SquarePostStoreException>()),
        );
        expect(await store.read(cidNumber: _cidA, postId: row.postId), isNull);
        expect(
          (await store.readPublication(_cidA, row.draftId))!.publicationState,
          'confirmed',
        );
      } else {
        await store.save(
          SquarePostStore.confirmedPublication(row),
          draftId: row.draftId,
        );
        await (await SocialIsar.instance.db()).close();
        expect(
          (await store.read(
            cidNumber: _cidA,
            postId: row.postId,
          ))!.manifestBytes,
          manifest,
        );
        expect(
          await mediaStore.readRange(
            cidNumber: _cidA,
            mediaId: mainId,
            offset: 0,
            length: 4,
          ),
          content,
        );
        expect(await store.readPublication(_cidA, row.draftId), isNull);
        expect(
          await mediaStore.referencesForContent(
            cidNumber: _cidA,
            contentKind: 'post',
            contentId: row.postId,
          ),
          hasLength(2),
        );
      }
      final draft = await SocialIsar.instance.read(
        (db) => db.squareComposeDraftEntitys.getByDraftKey(
          '${_cidA.length}:$_cidA'
          'draft-publish',
        ),
      );
      expect(draft, damage ? isNotNull : isNull);
    });
  }

  test('展示转换器只解析正文与媒体声明，不伪造本地媒体 URL', () {
    const presenter = SquareLocalPostPresenter();
    final presentation = presenter.present(_post(createdAt: 1700000000123));

    expect(presentation.post.text, '本人发布的正文');
    expect(presentation.post.isLocal, isTrue);
    expect(
      presentation.post.mediaItems.single.mediaKind,
      SquareMediaKind.image,
    );
    expect(presentation.post.mediaItems.single.cidNumber, _cidA);
    expect(presentation.post.mediaItems.single.url, isEmpty);
    expect(presentation.post.createdAt.millisecondsSinceEpoch, 1700000000123);
  });

  test('展示转换器拒绝缺少首图声明的本地文章', () {
    const presenter = SquareLocalPostPresenter();
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': SquarePostStore.manifestSchema,
          'cid_number': _cidA,
          'post_type': 'article',
          'title': '本地文章标题标题标题',
          'text': '本地文章正文内容满足最低要求',
          'media_items': <Object>[],
        }),
      ),
    );

    expect(
      () => presenter.present(
        _post(
          postType: 'article',
          manifestBytes: bytes,
          contentHash: sha256.convert(bytes).toString(),
        ),
      ),
      throwsA(
        isA<SquareLocalPostPresenterException>().having(
          (error) => error.message,
          'message',
          '本地文章首图声明缺失',
        ),
      ),
    );
  });

  test('原始 manifest 字节逐字节持久化，Worker 时间和链锚不被改写', () async {
    final bytes = _manifest(text: '含中文与 emoji 🧭');
    await store.save(
      _post(manifestBytes: bytes, createdAt: 1700000000123, chainBlock: 456),
    );

    final saved = await store.read(cidNumber: _cidA, postId: 'sqp_a');
    expect(saved, isNotNull);
    expect(saved!.manifestBytes, orderedEquals(bytes));
    expect(saved.contentHash, sha256.convert(bytes).toString());
    expect(saved.createdAt, 1700000000123);
    expect(saved.chainBlock, 456);
    expect(saved.postState, SquarePostStore.publishedState);
  });

  test('同一发布事实可幂等重放，post_id 不得被另一内容或 CID 覆盖', () async {
    final original = _post(createdAt: 1000);
    await store.save(original);
    await store.save(original);
    final conflictingBytes = _manifest(text: '试图覆盖不可变正文');
    expect(
      () => store.save(
        _post(
          manifestBytes: conflictingBytes,
          contentHash: sha256.convert(conflictingBytes).toString(),
          createdAt: 2000,
        ),
      ),
      throwsA(isA<SquarePostStoreException>()),
    );
    final otherCidBytes = _manifest(cidNumber: _cidB, text: '越权覆盖');
    expect(
      () => store.save(
        _post(
          cidNumber: _cidB,
          accountId: _accountB,
          manifestBytes: otherCidBytes,
        ),
      ),
      throwsA(isA<SquarePostStoreException>()),
    );
    await store.save(
      _post(
        postId: 'sqp_b',
        cidNumber: _cidB,
        accountId: _accountB,
        manifestBytes: _manifest(cidNumber: _cidB, text: '另一个 CID'),
        createdAt: 9999,
      ),
    );

    final own = await store.listByCid(_cidA);
    expect(own.map((post) => post.postId), ['sqp_a']);
    expect(own.single.manifestBytes, orderedEquals(original.manifestBytes));
    expect(await store.read(cidNumber: _cidB, postId: 'sqp_a'), isNull);
  });

  test('列表只用 Worker created_at 排序，同毫秒按 post_id 稳定排序', () async {
    await store.save(_post(postId: 'sqp_a', createdAt: 1000));
    await store.save(_post(postId: 'sqp_c', createdAt: 3000));
    await store.save(_post(postId: 'sqp_b', createdAt: 3000));

    final posts = await store.listByCid(_cidA);
    expect(posts.map((post) => post.postId), ['sqp_c', 'sqp_b', 'sqp_a']);
  });

  test('哈希、schema、CID 和 post_type 不一致均拒绝且不覆盖正确副本', () async {
    final original = _post();
    await store.save(original);

    final invalidCases = <SquareLocalPost>[
      _post(
        manifestBytes: _manifest(text: '被篡改'),
        contentHash: original.contentHash,
      ),
      _post(
        manifestBytes: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schema': 'legacy.square.post',
              'cid_number': _cidA,
              'post_type': 'document',
              'text': '旧 schema',
              'media_items': [],
            }),
          ),
        ),
      ),
      _post(manifestBytes: _manifest(cidNumber: _cidB)),
      _post(
        postType: 'article',
        manifestBytes: _manifest(postType: 'document'),
      ),
    ];

    for (final invalid in invalidCases) {
      expect(
        () => store.save(
          SquareLocalPost(
            postId: invalid.postId,
            cidNumber: invalid.cidNumber,
            accountId: invalid.accountId,
            postCategory: invalid.postCategory,
            postType: invalid.postType,
            manifestBytes: invalid.manifestBytes,
            contentHash: invalid.contentHash == original.contentHash
                ? invalid.contentHash
                : sha256.convert(invalid.manifestBytes).toString(),
            storageReceiptId: invalid.storageReceiptId,
            chainBlock: invalid.chainBlock,
            createdAt: invalid.createdAt,
            postState: invalid.postState,
          ),
        ),
        throwsA(isA<SquarePostStoreException>()),
      );
    }

    final saved = await store.read(cidNumber: _cidA, postId: 'sqp_a');
    expect(saved!.manifestBytes, orderedEquals(original.manifestBytes));
  });

  test('非 published、非法 UTF-8 JSON 和不完整 manifest 均不得入库', () async {
    expect(
      () => store.save(_post(postState: 'draft')),
      throwsA(isA<SquarePostStoreException>()),
    );
    expect(
      () => store.save(_post(manifestBytes: Uint8List.fromList([0xff, 0xfe]))),
      throwsA(isA<SquarePostStoreException>()),
    );
    final incomplete = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': SquarePostStore.manifestSchema,
          'cid_number': _cidA,
          'post_type': 'document',
          'text': '缺少 media_items',
        }),
      ),
    );
    expect(
      () => store.save(_post(manifestBytes: incomplete)),
      throwsA(isA<SquarePostStoreException>()),
    );
  });

  test('磁盘行被篡改后读取 fail-closed，不静默返回空白内容', () async {
    await store.save(_post());
    await SocialIsar.instance.writeTxn((isar) async {
      final entity = await isar.squareLocalPostEntitys.getByPostId('sqp_a');
      entity!.manifestBytes = utf8.encode('{"broken":true}');
      await isar.squareLocalPostEntitys.put(entity);
    });

    expect(
      () => store.read(cidNumber: _cidA, postId: 'sqp_a'),
      throwsA(isA<SquarePostStoreException>()),
    );
  });

  test('删除必须匹配 CID，注销清理只删除目标 CID', () async {
    await store.save(_post(postId: 'sqp_a'));
    await store.save(_post(postId: 'sqp_b', createdAt: 2000));
    final otherBytes = _manifest(cidNumber: _cidB, text: '另一个 CID');
    await store.save(
      _post(
        postId: 'sqp_other',
        cidNumber: _cidB,
        accountId: _accountB,
        manifestBytes: otherBytes,
        createdAt: 3000,
      ),
    );

    expect(await store.delete(cidNumber: _cidB, postId: 'sqp_a'), isFalse);
    expect(await store.delete(cidNumber: _cidA, postId: 'sqp_a'), isTrue);
    expect(await store.deleteAllByCid(_cidA), 1);
    expect(await store.listByCid(_cidA), isEmpty);
    expect((await store.listByCid(_cidB)).single.postId, 'sqp_other');
  });

  test('关闭重开 Isar 后副本仍存在且实体没有媒体文件或 URL 字段', () async {
    await store.save(_post());
    final first = await SocialIsar.instance.db();
    await first.close();

    final reopened = await SocialIsar.instance.db();
    final entity = await reopened.squareLocalPostEntitys.getByPostId('sqp_a');
    expect(entity, isNotNull);
    expect(entity!.manifestBytes, isNotEmpty);
    expect(
      SquareLocalPostEntitySchema.properties.keys,
      isNot(
        containsAll(<String>['mediaPath', 'mediaUrl', 'coverUrl', 'cachedAt']),
      ),
    );
  });
}
