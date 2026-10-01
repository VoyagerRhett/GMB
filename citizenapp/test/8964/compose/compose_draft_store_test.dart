import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_media.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/isar/social_isar.dart';
import 'package:citizenapp/8964/services/square_media_store.dart';

import '../../support/isar_test_env.dart';

SquareComposeDraft _draft(
  String id,
  int updatedAt, {
  String cidNumber = 'CN001-CTZN-100000001-2026',
}) => SquareComposeDraft(
  draftId: id,
  cidNumber: cidNumber,
  postType: SquarePostType.document,
  text: '内容 $id',
  media: const <SquareLocalMediaDraft>[],
  updatedAtMillis: updatedAt,
);

void main() {
  useIsolatedIsar();
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = SquareComposeDraftStore.instance;
  late Directory documentsDirectory;

  setUpAll(() {
    documentsDirectory = Directory.systemTemp.createTempSync(
      'citizenapp_square_drafts_',
    );
    ComposeDraftMedia.debugDocumentsDirectoryProvider = () async =>
        documentsDirectory;
  });
  setUp(() async {
    await ComposeDraftMedia.resetForTest(
      documentsDirectoryProvider: () async => documentsDirectory,
    );
  });
  tearDown(() async {
    await ComposeDraftMedia.resetForTest(
      documentsDirectoryProvider: () async => documentsDirectory,
    );
  });
  tearDownAll(() async {
    ComposeDraftMedia.debugDocumentsDirectoryProvider = null;
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
  });

  test('多草稿按 updated_at 新→旧列出，仅本人可见', () async {
    await store.save(_draft('a', 1000));
    await store.save(_draft('b', 3000));
    await store.save(_draft('c', 2000));
    await store.save(_draft('x', 9999, cidNumber: 'CN001-CTZN-999999999-2026'));

    final drafts = await store.list('CN001-CTZN-100000001-2026');
    expect(drafts.map((d) => d.draftId).toList(), ['b', 'c', 'a']);
    expect(
      drafts.every((d) => d.cidNumber == 'CN001-CTZN-100000001-2026'),
      isTrue,
    );
  });

  test('草稿媒体实际字节入库，移除来源文件后仍能恢复，不持久保存路径', () async {
    const cid = 'CN001-CTZN-100000001-2026';
    final input = File('${documentsDirectory.path}/selected.webp');
    await input.writeAsBytes([1, 3, 5, 7]);
    await store.save(
      _draft('bytes', 1000).copyWith(
        media: [
          SquareLocalMediaDraft(
            mediaKind: SquareMediaKind.image,
            path: input.path,
            fileName: 'photo.webp',
            contentType: 'image/webp',
            byteSize: 4,
          ),
        ],
      ),
    );
    final saved = (await store.list(cid)).single;
    expect(saved.media.single.mediaId, isNotNull);
    expect(saved.media.single.path, isEmpty);
    expect(saved.toJsonString(), isNot(contains(documentsDirectory.path)));
    await input.delete();
    final restored = await store.restore(saved);
    expect(await File(restored.media.single.path).readAsBytes(), [1, 3, 5, 7]);
    expect(
      (await const SquareMediaStore().get(
        cidNumber: cid,
        mediaId: saved.media.single.mediaId!,
      ))!.complete,
      isTrue,
    );
  });

  test('保存第101条草稿不删除已有草稿', () async {
    for (var i = 0; i < 101; i++) {
      await store.save(_draft('keep-$i', i + 1));
    }
    final drafts = await store.list('CN001-CTZN-100000001-2026');
    expect(drafts, hasLength(101));
    expect(drafts.any((draft) => draft.draftId == 'keep-0'), isTrue);
  });

  test('媒体导入失败或引用其他CID的媒体不能覆盖原草稿', () async {
    const cid = 'CN001-CTZN-100000001-2026';
    await store.save(_draft('retain', 1000));
    final file = File('${documentsDirectory.path}/incomplete.webp');
    await file.writeAsBytes([1, 2]);
    final incoming = SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.image,
      path: file.path,
      fileName: 'incomplete.webp',
      contentType: 'image/webp',
      byteSize: 3,
    );
    await expectLater(
      store.save(_draft('retain', 2000).copyWith(media: [incoming])),
      throwsA(isA<SquareMediaStoreException>()),
    );
    final other = await const SquareMediaStore().saveFile(
      cidNumber: 'CN001-CTZN-999999999-2026',
      path: file.path,
      mediaKind: 'image',
      contentType: 'image/webp',
      byteSize: 2,
    );
    await expectLater(
      store.save(
        _draft('retain', 2000).copyWith(
          media: [
            SquareLocalMediaDraft(
              mediaKind: SquareMediaKind.image,
              path: '',
              mediaId: other.mediaId,
              fileName: 'other.webp',
              contentType: 'image/webp',
              byteSize: 2,
            ),
          ],
        ),
      ),
      throwsA(isA<SquareMediaStoreException>()),
    );
    expect((await store.list(cid)).single.updatedAtMillis, 1000);
  });

  test('旧草稿恢复先持久保存字节，删除旧目录后仍能再次恢复', () async {
    const cid = 'CN001-CTZN-100000001-2026';
    final root = Directory(
      '${documentsDirectory.path}/square_drafts/$cid/legacy-owned',
    );
    await root.create(recursive: true);
    final input = File('${root.path}/original.webp');
    await input.writeAsBytes([2, 4, 6, 8]);
    final legacy = _draft('legacy-owned', 1000).copyWith(
      media: [
        SquareLocalMediaDraft(
          mediaKind: SquareMediaKind.image,
          path: input.path,
          fileName: 'original.webp',
          contentType: 'image/webp',
          byteSize: 4,
        ),
      ],
    );
    final restored = await store.restore(legacy);
    expect(restored.media.single.mediaId, isNotNull);
    expect(await File(restored.media.single.path).readAsBytes(), [2, 4, 6, 8]);
    expect(await root.exists(), isFalse);
    await File(restored.media.single.path).delete();
    final saved = (await store.list(cid)).single;
    expect(saved.media.single.path, isEmpty);
    final reopened = await store.restore(saved);
    expect(await File(reopened.media.single.path).readAsBytes(), [2, 4, 6, 8]);
  });

  test('旧草稿路径越过当前CID和草稿目录时拒绝读取', () async {
    const cid = 'CN001-CTZN-100000001-2026';
    final root = Directory(
      '${documentsDirectory.path}/square_drafts/$cid/legacy',
    );
    await root.create(recursive: true);
    final outside = File('${documentsDirectory.path}/not-owned.webp');
    await outside.writeAsBytes([9]);
    final old = _draft('legacy', 1000).copyWith(
      media: [
        SquareLocalMediaDraft(
          mediaKind: SquareMediaKind.image,
          path: outside.path,
          fileName: 'not-owned.webp',
          contentType: 'image/webp',
          byteSize: 1,
        ),
      ],
    );
    await expectLater(store.restore(old), throwsStateError);
    expect(await outside.readAsBytes(), [9]);
    expect(await const SquareMediaStore().listByCid(cid), isEmpty);
  });

  test('同 draftId 再存为覆盖，不新增', () async {
    await store.save(_draft('s', 1000, cidNumber: 'CN001-CTZN-200000001-2026'));
    await store.save(_draft('s', 5000, cidNumber: 'CN001-CTZN-200000001-2026'));
    final drafts = await store.list('CN001-CTZN-200000001-2026');
    expect(drafts.length, 1);
    expect(drafts.single.updatedAtMillis, 5000);
  });

  test('损坏草稿读取 fail-closed，数据库行与媒体目录均原样保留', () async {
    const cidNumber = 'CN001-CTZN-300000001-2026';
    const draftId = 'broken';
    final entity = SquareComposeDraftEntity()
      ..draftKey = '${cidNumber.length}:$cidNumber$draftId'
      ..cidNumber = cidNumber
      ..draftId = draftId
      ..postType = 'document'
      ..text = '损坏行'
      ..mediaJson = '{bad-json'
      ..updatedAtMillis = 1000;
    await SocialIsar.instance.writeTxn((isar) async {
      await isar.squareComposeDraftEntitys.putByDraftKey(entity);
    });
    final mediaDir = Directory(
      '${documentsDirectory.path}/square_drafts/'
      '${Uri.encodeComponent(cidNumber)}/${Uri.encodeComponent(draftId)}',
    );
    mediaDir.createSync(recursive: true);
    File('${mediaDir.path}/sentinel.bin').writeAsBytesSync(<int>[1, 2, 3]);

    await expectLater(
      store.list(cidNumber),
      throwsA(isA<SquareComposeDraftStoreException>()),
    );

    final retained = await SocialIsar.instance.read(
      (isar) => isar.squareComposeDraftEntitys.getByDraftKey(entity.draftKey),
    );
    expect(retained, isNotNull);
    expect(File('${mediaDir.path}/sentinel.bin').existsSync(), isTrue);
  });

  test('明确删除先提交事实与清理计划，文件失败保留计划并可重试', () async {
    const cidNumber = 'CN001-CTZN-400000001-2026';
    const draftId = 'delete-retry';
    await store.save(_draft(draftId, 1000, cidNumber: cidNumber));

    final invalidRoot = File('${documentsDirectory.path}/square_drafts');
    invalidRoot.writeAsStringSync('阻断目录删除');
    await expectLater(
      store.delete(cidNumber, draftId),
      throwsA(isA<SquareComposeDraftStoreException>()),
    );

    expect(await store.list(cidNumber), isEmpty);
    final pending = await SocialIsar.instance.read(
      (isar) => isar.squareFileCleanupEntitys.where().findAll(),
    );
    expect(pending, hasLength(1));
    expect(pending.single.attemptCount, 1);

    invalidRoot.deleteSync();
    await store.retryPendingFileCleanup(cidNumber: cidNumber);
    final remaining = await SocialIsar.instance.read(
      (isar) => isar.squareFileCleanupEntitys.where().count(),
    );
    expect(remaining, 0);
  });

  test('非法路径段和属主符号链接均 fail-closed，不扩大删除范围', () async {
    final root = Directory('${documentsDirectory.path}/square_drafts')
      ..createSync(recursive: true);
    final rootMarker = File('${root.path}/root-marker.bin')
      ..writeAsBytesSync(<int>[1]);

    await expectLater(
      store.delete('CN001-CTZN-500000001-2026', '..'),
      throwsA(isA<SquareComposeDraftStoreException>()),
    );
    expect(rootMarker.existsSync(), isTrue);

    const cidNumber = 'CN001-CTZN-500000002-2026';
    final outside = Directory('${documentsDirectory.path}/outside')
      ..createSync();
    final outsideMarker = File('${outside.path}/must-survive.bin')
      ..writeAsBytesSync(<int>[2]);
    Link('${root.path}/${Uri.encodeComponent(cidNumber)}')
        .createSync(outside.path);

    await expectLater(
      ComposeDraftMedia.deleteDir(cidNumber, 'draft-a'),
      throwsA(isA<StateError>()),
    );
    expect(outsideMarker.existsSync(), isTrue);
  });
}
