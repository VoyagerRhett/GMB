import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:citizenapp/8964/services/square_media_store.dart';
import 'package:citizenapp/isar/isar_core_bootstrap.dart';
import 'package:citizenapp/isar/social_isar.dart';

import '../support/isar_test_env.dart';

const _cidA = 'R5-K3P1C1-N9-D4';
const _cidB = 'R5-K3P1C1-N8-D5';
const _store = SquareMediaStore();
const _chunkSize = SquareMediaStore.chunkSize;
final _storeError = isA<SquareMediaStoreException>();

// 全部使用合成字节与虚构 CID，不读取设备媒体或用户数据。
Uint8List _bytes(int size) => Uint8List.fromList(
  List<int>.generate(size, (index) => (index * 17 + 3) % 251),
);

SquareStoredMedia _media(
  Uint8List bytes, {
  String cid = _cidA,
  String id = 'media-a',
  String? digest,
}) => SquareStoredMedia(
  cidNumber: cid,
  mediaId: id,
  mediaKind: 'image',
  contentType: 'image/webp',
  byteSize: bytes.length,
  sha256: digest ?? sha256.convert(bytes).toString(),
);

SquareMediaReference _reference({
  String cid = _cidA,
  String mediaId = 'media-a',
  String contentKind = 'post',
  String contentId = 'post-a',
  int index = 0,
  String role = 'main',
}) => SquareMediaReference(
  cidNumber: cid,
  mediaId: mediaId,
  contentKind: contentKind,
  contentId: contentId,
  mediaIndex: index,
  mediaRole: role,
);

Future<void> _save(
  Uint8List bytes, {
  String cid = _cidA,
  String id = 'media-a',
}) async {
  await _store.begin(_media(bytes, cid: cid, id: id));
  for (var offset = 0; offset < bytes.length; offset += _chunkSize) {
    await _store.writeChunk(
      cidNumber: cid,
      mediaId: id,
      chunkIndex: offset ~/ _chunkSize,
      bytes: Uint8List.sublistView(
        bytes,
        offset,
        math.min(offset + _chunkSize, bytes.length),
      ),
    );
  }
  await _store.finish(cidNumber: cid, mediaId: id);
}

Future<void> _changeChunk(
  Future<void> Function(Isar, SquareMediaChunkEntity) change,
) {
  return SocialIsar.instance.writeTxn((db) async {
    final chunk = await db.squareMediaChunkEntitys
        .getByCidNumberMediaIdChunkIndex(_cidA, 'media-a', 0);
    await change(db, chunk!);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();

  test('媒体关联组合进业务事务时，后续失败回滚引用替换和字节回收', () async {
    await _save(_bytes(3));
    await _save(_bytes(4), id: 'media-b');
    await _store.attach(_reference(contentKind: 'draft'));
    await expectLater(SocialIsar.instance.writeTxn((db) async {
      await SquareMediaStore.replaceReferencesInTransaction(db,
          cidNumber: _cidA, contentKind: 'draft', contentId: 'post-a',
          references: [_reference(mediaId: 'media-b', contentKind: 'draft')]);
      throw StateError('模拟同一事务后续业务保存失败');
    }), throwsStateError);
    final refs = await _store.referencesForContent(cidNumber: _cidA,
        contentKind: 'draft', contentId: 'post-a');
    expect(refs.single.mediaId, 'media-a');
    expect(await _store.readRange(cidNumber: _cidA, mediaId: 'media-a', offset: 0, length: 3), _bytes(3));
  });

  test('媒体流按固定块入库，输入分片不必与数据库块对齐', () async {
    final bytes = _bytes(_chunkSize + 11);
    await _store.saveStream(
      _media(bytes),
      Stream.fromIterable([
        bytes.sublist(0, 3),
        bytes.sublist(3, 900),
        bytes.sublist(900),
      ]),
    );
    expect(
      await _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: _chunkSize - 2,
        length: 13,
      ),
      bytes.sublist(_chunkSize - 2),
    );
  });

  test('短流或超长流不能标记完成，已有媒体字节保持不变', () async {
    for (final size in [4, 6]) {
      final descriptor = _media(_bytes(5), id: 'size-$size');
      await expectLater(
        _store.saveStream(descriptor, Stream.value(_bytes(size))),
        throwsA(_storeError),
      );
      expect(
        (await _store.get(
          cidNumber: _cidA,
          mediaId: descriptor.mediaId,
        ))!.complete,
        isFalse,
      );
    }
    await _save(_bytes(5));
    await expectLater(
      _store.saveStream(_media(_bytes(5)), Stream.value(Uint8List(5))),
      throwsA(_storeError),
    );
    expect(
      await _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 5,
      ),
      _bytes(5),
    );
  });

  test('旧Social库增加媒体集合后保留原草稿事实', () async {
    final old = await Isar.open(
      [
        SquareLocalPostEntitySchema,
        SquareComposeDraftEntitySchema,
        SquarePostSyncCheckpointEntitySchema,
        SquareFileCleanupEntitySchema,
      ],
      name: 'citizenapp_social',
      directory: await IsarCoreBootstrap.resolveDirectory(),
    );
    await old.writeTxn(() async {
      await old.squareComposeDraftEntitys.put(
        SquareComposeDraftEntity()
          ..draftKey = '$_cidA|draft-old'
          ..cidNumber = _cidA
          ..draftId = 'draft-old'
          ..postType = 'document'
          ..text = '未发布草稿必须保留'
          ..mediaJson = '[]'
          ..updatedAtMillis = 123,
      );
    });
    await old.close();
    await _save(_bytes(5));
    final draft = await SocialIsar.instance.read(
      (db) => db.squareComposeDraftEntitys.getByDraftKey('$_cidA|draft-old'),
    );
    expect(draft!.text, '未发布草稿必须保留');
    expect(draft.cidNumber, _cidA);
    expect(draft.updatedAtMillis, 123);
  });

  test('描述、实际字节和关联分别持久化；跨块、尾块及EOF读取准确', () async {
    final bytes = _bytes(_chunkSize + 37);
    await _save(bytes);
    final reference = _reference();
    await _store.attach(reference);

    // 关闭但不删除数据库，再以新的入口实例读取，排除仅存在于内存的实现。
    await (await SocialIsar.instance.db()).close();
    const reopened = SquareMediaStore();
    final media = await reopened.get(cidNumber: _cidA, mediaId: 'media-a');
    expect(media!.complete, isTrue);
    expect(media.byteSize, bytes.length);
    expect(media.sha256, sha256.convert(bytes).toString());
    expect(
      await reopened.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: _chunkSize,
      ),
      bytes.sublist(0, _chunkSize),
    );
    expect(
      await reopened.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: _chunkSize - 5,
        length: 42,
      ),
      bytes.sublist(_chunkSize - 5),
    );
    expect(
      await reopened.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: bytes.length,
        length: 0,
      ),
      isEmpty,
    );
    expect(
      (await reopened.referencesForContent(
        cidNumber: _cidA,
        contentKind: 'post',
        contentId: 'post-a',
      )).single.mediaId,
      reference.mediaId,
    );
    expect((await reopened.listByCid(_cidA)).single.mediaId, 'media-a');
  });

  test('整块整数长度不要求空尾块，单字节媒体同样校验', () async {
    for (final size in [1, _chunkSize, _chunkSize * 2]) {
      await _save(_bytes(size), id: 'size-$size');
      expect(
        (await _store.get(cidNumber: _cidA, mediaId: 'size-$size'))!.complete,
        isTrue,
      );
    }
  });

  test('写入中断后不可读不可关联，重开数据库后能显式续写', () async {
    final bytes = _bytes(_chunkSize + 7);
    await _store.begin(_media(bytes));
    await _store.writeChunk(
      cidNumber: _cidA,
      mediaId: 'media-a',
      chunkIndex: 0,
      bytes: Uint8List.sublistView(bytes, 0, _chunkSize),
    );
    await (await SocialIsar.instance.db()).close();
    await expectLater(
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    await expectLater(
      _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 1,
      ),
      throwsA(_storeError),
    );
    await expectLater(_store.attach(_reference()), throwsA(_storeError));
    expect((await _store.listByCid(_cidA)).single.complete, isFalse);
    await _save(bytes);
    expect(
      (await _store.get(cidNumber: _cidA, mediaId: 'media-a'))!.complete,
      isTrue,
    );
  });

  test('重复块、描述和完成幂等，不允许覆盖不同内容', () async {
    final bytes = _bytes(23);
    await _save(bytes);
    await _save(bytes);
    await expectLater(_store.begin(_media(_bytes(24))), throwsA(_storeError));
    await expectLater(
      _store.writeChunk(
        cidNumber: _cidA,
        mediaId: 'media-a',
        chunkIndex: 0,
        bytes: Uint8List(23),
      ),
      throwsA(_storeError),
    );
    expect(
      await _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 23,
      ),
      bytes,
    );
  });

  test('乱序分块最终按序校验，排队前复制调用方缓冲区', () async {
    final bytes = _bytes(_chunkSize + 2);
    await _store.begin(_media(bytes));
    final input = Uint8List.fromList(bytes.sublist(_chunkSize));
    final writing = _store.writeChunk(
      cidNumber: _cidA,
      mediaId: 'media-a',
      chunkIndex: 1,
      bytes: input,
    );
    input.fillRange(0, input.length, 0);
    await writing;
    await _store.writeChunk(
      cidNumber: _cidA,
      mediaId: 'media-a',
      chunkIndex: 0,
      bytes: Uint8List.sublistView(bytes, 0, _chunkSize),
    );
    await _store.finish(cidNumber: _cidA, mediaId: 'media-a');
    expect(
      await _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: _chunkSize,
        length: 2,
      ),
      bytes.sublist(_chunkSize),
    );
  });

  test('完整长度但整体哈希错误仍不可标记完成，失败后队列可继续', () async {
    final bytes = _bytes(19);
    await _store.begin(_media(bytes, digest: sha256.convert([0]).toString()));
    await _store.writeChunk(
      cidNumber: _cidA,
      mediaId: 'media-a',
      chunkIndex: 0,
      bytes: bytes,
    );
    await expectLater(
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    expect(
      (await _store.get(cidNumber: _cidA, mediaId: 'media-a'))!.complete,
      isFalse,
    );
    expect(
      await _store.deleteUnused(cidNumber: _cidA, mediaId: 'media-a'),
      isTrue,
    );
    await _save(bytes);
  });

  test('缺失、额外、损坏分块均拒绝完成', () async {
    final bytes = _bytes(11);
    await _store.begin(_media(bytes));
    await expectLater(
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    await _store.writeChunk(
      cidNumber: _cidA,
      mediaId: 'media-a',
      chunkIndex: 0,
      bytes: bytes,
    );
    await _changeChunk((db, chunk) async {
      chunk.chunkBytes = [0, ...chunk.chunkBytes.skip(1)];
      await db.squareMediaChunkEntitys.put(chunk);
    });
    await expectLater(
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    await _changeChunk((db, chunk) async {
      chunk.chunkBytes = bytes;
      await db.squareMediaChunkEntitys.put(chunk);
      await db.squareMediaChunkEntitys.put(
        SquareMediaChunkEntity()
          ..cidNumber = _cidA
          ..mediaId = 'media-a'
          ..chunkIndex = 1
          ..chunkBytes = [1]
          ..chunkSha256 = sha256.convert([1]).toString(),
      );
    });
    await expectLater(
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    expect(
      (await _store.get(cidNumber: _cidA, mediaId: 'media-a'))!.complete,
      isFalse,
    );
  });

  test('完成后磁盘分块损坏或缺失，范围读取明确失败', () async {
    await _save(_bytes(13));
    await _changeChunk((db, chunk) async {
      chunk.chunkBytes = List<int>.filled(13, 0);
      await db.squareMediaChunkEntitys.put(chunk);
    });
    await expectLater(
      _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 1,
      ),
      throwsA(_storeError),
    );
    await _changeChunk((db, chunk) async {
      await db.squareMediaChunkEntitys.delete(chunk.id);
    });
    await expectLater(
      _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 1,
      ),
      throwsA(_storeError),
    );
  });

  test('分块序号、零块、超长块及不准确尾块全部拒绝', () async {
    await _store.begin(_media(_bytes(_chunkSize + 7)));
    for (final input in [
      (-1, _bytes(1)),
      (2, _bytes(1)),
      (0, Uint8List(0)),
      (0, _bytes(_chunkSize + 1)),
      (0, _bytes(7)),
      (1, _bytes(6)),
      (1, _bytes(8)),
    ]) {
      await expectLater(
        _store.writeChunk(
          cidNumber: _cidA,
          mediaId: 'media-a',
          chunkIndex: input.$1,
          bytes: input.$2,
        ),
        throwsA(_storeError),
      );
    }
  });

  test('范围不能负数、越界或一次加载超过1MiB', () async {
    await _save(_bytes(9));
    for (final range in [
      (-1, 1),
      (0, -1),
      (8, 2),
      (10, 0),
      (0, _chunkSize + 1),
    ]) {
      await expectLater(
        _store.readRange(
          cidNumber: _cidA,
          mediaId: 'media-a',
          offset: range.$1,
          length: range.$2,
        ),
        throwsA(_storeError),
      );
    }
  });

  test('同名媒体按CID完全隔离，跨用户不能读写、关联或删除', () async {
    final bytesA = _bytes(9);
    final bytesB = _bytes(10);
    await _save(bytesA);
    expect(await _store.get(cidNumber: _cidB, mediaId: 'media-a'), isNull);
    expect(await _store.listByCid(_cidB), isEmpty);
    await expectLater(
      _store.readRange(
        cidNumber: _cidB,
        mediaId: 'media-a',
        offset: 0,
        length: 1,
      ),
      throwsA(_storeError),
    );
    await expectLater(
      _store.writeChunk(
        cidNumber: _cidB,
        mediaId: 'media-a',
        chunkIndex: 0,
        bytes: bytesA,
      ),
      throwsA(_storeError),
    );
    await expectLater(
      _store.attach(_reference(cid: _cidB)),
      throwsA(_storeError),
    );
    expect(
      await _store.deleteUnused(cidNumber: _cidB, mediaId: 'media-a'),
      isFalse,
    );
    expect(await _store.detach(_reference(cid: _cidB)), isFalse);
    await _save(bytesB, cid: _cidB);
    await _store.attach(_reference());
    await _store.attach(_reference(cid: _cidB));
    expect(await _store.detach(_reference(cid: _cidB)), isTrue);
    expect(
      await _store.deleteUnused(cidNumber: _cidB, mediaId: 'media-a'),
      isTrue,
    );
    expect(
      await _store.readRange(
        cidNumber: _cidA,
        mediaId: 'media-a',
        offset: 0,
        length: 9,
      ),
      bytesA,
    );
    expect(
      await _store.referencesForContent(
        cidNumber: _cidA,
        contentKind: 'post',
        contentId: 'post-a',
      ),
      hasLength(1),
    );
  });

  test('关联分类型、顺序和用途；移除一个引用不删除共享媒体', () async {
    await _save(_bytes(17));
    final refs = [
      _reference(contentKind: 'draft'),
      _reference(index: 2),
      _reference(index: 1, role: 'cover'),
      _reference(index: 1),
    ];
    for (final reference in refs) {
      await _store.attach(reference);
      await _store.attach(reference);
    }
    final post = await _store.referencesForContent(
      cidNumber: _cidA,
      contentKind: 'post',
      contentId: 'post-a',
    );
    expect(post.map((r) => r.mediaIndex), [1, 1, 2]);
    expect(post.take(2).map((r) => r.mediaRole), ['cover', 'main']);
    expect(await _store.detach(refs.first), isTrue);
    expect(await _store.detach(refs.first), isFalse);
    await expectLater(
      _store.deleteUnused(cidNumber: _cidA, mediaId: 'media-a'),
      throwsA(_storeError),
    );
    for (final reference in refs.skip(1)) {
      await _store.detach(reference);
    }
    expect(
      await _store.deleteUnused(cidNumber: _cidA, mediaId: 'media-a'),
      isTrue,
    );
    expect(await _store.get(cidNumber: _cidA, mediaId: 'media-a'), isNull);
    expect(
      await SocialIsar.instance.read(
        (db) => db.squareMediaChunkEntitys.count(),
      ),
      0,
    );
  });

  test('槽位冲突和迟到的解绑不能覆盖或移除新内容', () async {
    await _save(_bytes(17));
    await _save(_bytes(18), id: 'media-b');
    await _store.attach(_reference());
    await expectLater(
      _store.attach(_reference(mediaId: 'media-b')),
      throwsA(_storeError),
    );
    await _store.detach(_reference());
    await _store.attach(_reference(mediaId: 'media-b'));
    expect(await _store.detach(_reference()), isFalse);
    expect(
      (await _store.referencesForContent(
        cidNumber: _cidA,
        contentKind: 'post',
        contentId: 'post-a',
      )).single.mediaId,
      'media-b',
    );
  });

  test('多个入口并发重试不会重复建行，绑定先于删除时删除必须失败', () async {
    final bytes = _bytes(23);
    const other = SquareMediaStore();
    await Future.wait([
      _store.begin(_media(bytes)),
      other.begin(_media(bytes)),
    ]);
    await Future.wait([
      _store.writeChunk(
        cidNumber: _cidA,
        mediaId: 'media-a',
        chunkIndex: 0,
        bytes: bytes,
      ),
      other.writeChunk(
        cidNumber: _cidA,
        mediaId: 'media-a',
        chunkIndex: 0,
        bytes: bytes,
      ),
    ]);
    await Future.wait([
      _store.finish(cidNumber: _cidA, mediaId: 'media-a'),
      other.finish(cidNumber: _cidA, mediaId: 'media-a'),
    ]);
    final binding = _store.attach(_reference());
    final deleting = other.deleteUnused(cidNumber: _cidA, mediaId: 'media-a');
    await expectLater(deleting, throwsA(_storeError));
    await binding;
    expect(await _store.listByCid(_cidA), hasLength(1));
    expect(
      await SocialIsar.instance.read(
        (db) => db.squareMediaChunkEntitys.count(),
      ),
      1,
    );
  });

  test('非法CID、空媒体及未知关联值拒绝，不能伪造完成标记', () async {
    await expectLater(_store.begin(_media(Uint8List(0))), throwsA(_storeError));
    await expectLater(
      _store.begin(_media(_bytes(1), digest: 'bad')),
      throwsA(_storeError),
    );
    for (final cid in ['', ' $_cidA', List.filled(33, 'a').join()]) {
      await expectLater(
        _store.begin(_media(_bytes(1), cid: cid)),
        throwsA(_storeError),
      );
      await expectLater(_store.listByCid(cid), throwsA(_storeError));
    }
    final media = _media(_bytes(1));
    await expectLater(
      _store.begin(
        SquareStoredMedia(
          cidNumber: media.cidNumber,
          mediaId: media.mediaId,
          mediaKind: media.mediaKind,
          contentType: media.contentType,
          byteSize: media.byteSize,
          sha256: media.sha256,
          complete: true,
        ),
      ),
      throwsA(_storeError),
    );
    for (final reference in [
      _reference(index: -1),
      _reference(role: 'unknown'),
      _reference(contentKind: 'unknown'),
      _reference(contentId: ''),
    ]) {
      await expectLater(_store.attach(reference), throwsA(_storeError));
    }
  });
}
