import 'dart:convert';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_media_store.dart';

import 'package:isar_community/isar.dart';

import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_media.dart';
import 'package:citizenapp/isar/social_isar.dart';

/// 广场草稿箱存储契约（便于测试注入）。
abstract class SquareComposeDraftRepository {
  Future<void> save(SquareComposeDraft draft);
  Future<List<SquareComposeDraft>> list(String cidNumber);
  Future<void> delete(String cidNumber, String draftId);

  /// 只有真实本地仓库存在待重试文件事实；测试或远端实现默认无需处理。
  Future<void> retryPendingFileCleanup({String? cidNumber}) async {}
}

class SquareComposeDraftStoreException implements Exception {
  const SquareComposeDraftStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 广场草稿的 SocialIsar 类型化仓库。
///
/// [list] 是严格纯读取：损坏行会 fail-closed 并原样保留，绝不在读取中修复、迁移、
/// 删除数据库行或媒体。未发布草稿不按数量淘汰；用户明确删除时才写入文件清理事实，
/// 再于事务外尝试删除媒体目录。
class SquareComposeDraftStore implements SquareComposeDraftRepository {
  SquareComposeDraftStore._();

  static final SquareComposeDraftStore instance = SquareComposeDraftStore._();

  static const String _draftDirectoryCleanup = 'draft_directory';

  static String _draftKey(String cidNumber, String draftId) =>
      '${cidNumber.length}:$cidNumber$draftId';

  static String _cleanupKey(String cidNumber, String draftId) =>
      'draft:${_draftKey(cidNumber, draftId)}';

  /// 与发布成功收尾共用的文件清理事实；调用方已处于 Social 写事务。
  static Future<void> planCleanupInTransaction(
    Isar db,
    String cid,
    String draftId,
  ) async {
    await db.squareFileCleanupEntitys.putByCleanupKey(
      _newCleanup(
        cidNumber: cid,
        draftId: draftId,
        createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> save(SquareComposeDraft draft) async {
    _validateIdentity(cidNumber: draft.cidNumber, draftId: draft.draftId);
    if (draft.updatedAtMillis <= 0) {
      throw const SquareComposeDraftStoreException('草稿时间不合法');
    }
    final normalizedMedia = <SquareLocalMediaDraft>[];
    final importingFiles = draft.media.any((item) => item.mediaId == null);
    for (final item in draft.media) {
      normalizedMedia.add(
        item.mediaId == null
            ? await ComposeDraftMedia.persist(
                draft.cidNumber,
                draft.draftId,
                item,
              )
            : item,
      );
    }
    final normalized = draft.copyWith(media: normalizedMedia);
    final prepared = _toEntity(normalized);
    final cleanupKeys = <String>[];
    await SocialIsar.instance.writeTxn((isar) async {
      final publishing = await isar.squarePublicationEntitys
          .getByCidNumberDraftId(draft.cidNumber, draft.draftId);
      if (publishing != null) {
        throw const SquareComposeDraftStoreException('该草稿正在恢复发布结果，不能覆盖内容');
      }
      for (final item in normalizedMedia) {
        final stored = await isar.squareMediaEntitys.getByCidNumberMediaId(
          draft.cidNumber,
          item.mediaId!,
        );
        if (stored == null ||
            stored.byteSize != item.byteSize ||
            stored.mediaKind != item.mediaKind.workerValue ||
            stored.contentType != item.contentType) {
          throw const SquareMediaStoreException('草稿媒体声明与数据库不一致');
        }
      }
      await SquareMediaStore.replaceReferencesInTransaction(
        isar,
        cidNumber: draft.cidNumber,
        contentKind: 'draft',
        contentId: draft.draftId,
        references: [
          for (var i = 0; i < normalizedMedia.length; i++)
            SquareMediaReference(
              cidNumber: draft.cidNumber,
              mediaId: normalizedMedia[i].mediaId!,
              contentKind: 'draft',
              contentId: draft.draftId,
              mediaIndex: i,
              mediaRole: 'main',
            ),
        ],
      );
      final existing = await isar.squareComposeDraftEntitys.getByDraftKey(
        prepared.draftKey,
      );
      if (existing != null) prepared.id = existing.id;
      await isar.squareComposeDraftEntitys.putByDraftKey(prepared);

      // 重新保存同一 draft_id 即声明它仍是有效草稿，撤销尚未执行的旧清理事实。
      final staleCleanup = await isar.squareFileCleanupEntitys.getByCleanupKey(
        _cleanupKey(draft.cidNumber, draft.draftId),
      );
      if (staleCleanup != null) {
        await isar.squareFileCleanupEntitys.delete(staleCleanup.id);
      }

      if (importingFiles) {
        final cleanup = _newCleanup(
          cidNumber: draft.cidNumber,
          draftId: draft.draftId,
          createdAtMillis: draft.updatedAtMillis,
        );
        await isar.squareFileCleanupEntitys.putByCleanupKey(cleanup);
        cleanupKeys.add(cleanup.cleanupKey);
      }
    });
    await _runCleanupKeys(cleanupKeys);
  }

  /// 用户明确恢复旧草稿时逐条核验文件并提交数据库，成功前绝不清除旧来源。
  /// 新草稿只从数据库生成临时处理文件；普通列表只查询描述。
  Future<SquareComposeDraft> restore(SquareComposeDraft draft) async {
    var source = draft;
    if (draft.media.any((item) => item.mediaId == null)) {
      await ComposeDraftMedia.validateLegacyPaths(
        draft.cidNumber,
        draft.draftId,
        draft.media
            .where((item) => item.mediaId == null)
            .map((item) => item.path),
      );
      await save(draft);
      final row = await SocialIsar.instance.read(
        (db) => db.squareComposeDraftEntitys.getByDraftKey(
          _draftKey(draft.cidNumber, draft.draftId),
        ),
      );
      if (row == null) throw const SquareComposeDraftStoreException('草稿已不存在');
      source = _fromEntity(row);
    }
    final media = <SquareLocalMediaDraft>[];
    for (final item in source.media) {
      media.add(
        await ComposeDraftMedia.persist(source.cidNumber, source.draftId, item),
      );
    }
    return source.copyWith(media: media);
  }

  @override
  Future<List<SquareComposeDraft>> list(String cidNumber) async {
    _validateIdentity(cidNumber: cidNumber);
    final entities = await SocialIsar.instance.read((isar) async {
      final rows = await isar.squareComposeDraftEntitys
          .filter()
          .cidNumberEqualTo(cidNumber)
          .findAll();
      return rows.map(_copyEntity).toList(growable: false);
    });

    final drafts = entities.map(_fromEntity).toList(growable: false);
    drafts.sort((left, right) {
      final byTime = right.updatedAtMillis.compareTo(left.updatedAtMillis);
      if (byTime != 0) return byTime;
      return right.draftId.compareTo(left.draftId);
    });
    return drafts;
  }

  @override
  Future<void> delete(String cidNumber, String draftId) async {
    _validateIdentity(cidNumber: cidNumber, draftId: draftId);
    final cleanupKey = _cleanupKey(cidNumber, draftId);
    final createdAtMillis = DateTime.now().millisecondsSinceEpoch;
    await SocialIsar.instance.writeTxn((isar) async {
      final publishing = await isar.squarePublicationEntitys
          .getByCidNumberDraftId(cidNumber, draftId);
      if (publishing != null) throw StateError('请先恢复该草稿的发布结果');
      await SquareMediaStore.removeContentInTransaction(
        isar,
        cidNumber: cidNumber,
        contentKind: 'draft',
        contentId: draftId,
      );
      final entity = await isar.squareComposeDraftEntitys.getByDraftKey(
        _draftKey(cidNumber, draftId),
      );
      if (entity != null) {
        await isar.squareComposeDraftEntitys.delete(entity.id);
      }
      await isar.squareFileCleanupEntitys.putByCleanupKey(
        _newCleanup(
          cidNumber: cidNumber,
          draftId: draftId,
          createdAtMillis: createdAtMillis,
        ),
      );
    });
    await _runCleanupKeys(<String>[cleanupKey]);
  }

  /// 重试此前由明确删除动作留下的文件清理事实。
  ///
  /// 本方法不会由 [list] 或普通启动隐式调用；调用方应在用户明确重试或同一删除流程中
  /// 调用。全部计划都会尝试，最后聚合报告失败项。
  @override
  Future<void> retryPendingFileCleanup({String? cidNumber}) async {
    if (cidNumber != null) _validateIdentity(cidNumber: cidNumber);
    final keys = await SocialIsar.instance.read((isar) async {
      final rows = cidNumber == null
          ? await isar.squareFileCleanupEntitys.where().findAll()
          : await isar.squareFileCleanupEntitys
                .filter()
                .cidNumberEqualTo(cidNumber)
                .findAll();
      return rows.map((row) => row.cleanupKey).toList(growable: false);
    });
    await _runCleanupKeys(keys);
  }

  Future<void> _runCleanupKeys(List<String> cleanupKeys) async {
    final failures = <String>[];
    for (final cleanupKey in cleanupKeys) {
      final plan = await SocialIsar.instance.read((isar) async {
        final row = await isar.squareFileCleanupEntitys.getByCleanupKey(
          cleanupKey,
        );
        return row == null ? null : _copyCleanup(row);
      });
      if (plan == null) continue;
      if (plan.cleanupKind != _draftDirectoryCleanup) {
        failures.add('$cleanupKey：未知清理类型 ${plan.cleanupKind}');
        continue;
      }

      try {
        await ComposeDraftMedia.deleteDir(plan.cidNumber, plan.draftId);
        await SocialIsar.instance.writeTxn((isar) async {
          final current = await isar.squareFileCleanupEntitys.getByCleanupKey(
            cleanupKey,
          );
          if (current != null && current.id == plan.id) {
            await isar.squareFileCleanupEntitys.delete(current.id);
          }
        });
      } catch (error) {
        failures.add('$cleanupKey：$error');
        await SocialIsar.instance.writeTxn((isar) async {
          final current = await isar.squareFileCleanupEntitys.getByCleanupKey(
            cleanupKey,
          );
          if (current == null || current.id != plan.id) return;
          current
            ..attemptCount += 1
            ..lastError = error.toString();
          await isar.squareFileCleanupEntitys.putByCleanupKey(current);
        });
      }
    }
    if (failures.isNotEmpty) {
      throw SquareComposeDraftStoreException(
        '草稿事实已更新，但媒体清理尚未全部完成：${failures.join('；')}',
      );
    }
  }

  static SquareComposeDraftEntity _toEntity(SquareComposeDraft draft) {
    _validateIdentity(cidNumber: draft.cidNumber, draftId: draft.draftId);
    if (draft.updatedAtMillis <= 0) {
      throw const SquareComposeDraftStoreException('草稿时间不合法');
    }
    final json = draft.toJson();
    return SquareComposeDraftEntity()
      ..draftKey = _draftKey(draft.cidNumber, draft.draftId)
      ..cidNumber = draft.cidNumber
      ..draftId = draft.draftId
      ..postType = draft.postType.workerValue
      ..title = draft.title
      ..text = draft.text
      ..mediaJson = jsonEncode(json['media'])
      ..contentSectionsJson = json['content_sections'] == null
          ? null
          : jsonEncode(json['content_sections'])
      ..updatedAtMillis = draft.updatedAtMillis;
  }

  static void _validateIdentity({required String cidNumber, String? draftId}) {
    final invalidCid =
        cidNumber.trim().isEmpty ||
        cidNumber.trim() != cidNumber ||
        utf8.encode(cidNumber).length > 32 ||
        cidNumber == '.' ||
        cidNumber == '..';
    final invalidDraft =
        draftId != null &&
        (draftId.trim().isEmpty ||
            draftId.trim() != draftId ||
            draftId == '.' ||
            draftId == '..');
    if (invalidCid || invalidDraft) {
      throw const SquareComposeDraftStoreException('草稿主键不合法');
    }
  }

  static SquareComposeDraft _fromEntity(SquareComposeDraftEntity entity) {
    try {
      final media = jsonDecode(entity.mediaJson);
      final sections = entity.contentSectionsJson == null
          ? null
          : jsonDecode(entity.contentSectionsJson!);
      if (media is! List || (sections != null && sections is! List)) {
        throw const FormatException('草稿嵌套字段不是目标结构');
      }
      return SquareComposeDraft.fromJson(<String, dynamic>{
        'draft_id': entity.draftId,
        'cid_number': entity.cidNumber,
        'post_type': entity.postType,
        if (entity.title != null) 'title': entity.title,
        'text': entity.text,
        'media': media,
        'content_sections': ?sections,
        'updated_at': entity.updatedAtMillis,
      });
    } on Object catch (error) {
      throw SquareComposeDraftStoreException(
        '草稿 ${entity.draftId} 数据损坏，已原样保留：$error',
      );
    }
  }

  static SquareComposeDraftEntity _copyEntity(
    SquareComposeDraftEntity source,
  ) => SquareComposeDraftEntity()
    ..id = source.id
    ..draftKey = source.draftKey
    ..cidNumber = source.cidNumber
    ..draftId = source.draftId
    ..postType = source.postType
    ..title = source.title
    ..text = source.text
    ..mediaJson = source.mediaJson
    ..contentSectionsJson = source.contentSectionsJson
    ..updatedAtMillis = source.updatedAtMillis;

  static SquareFileCleanupEntity _newCleanup({
    required String cidNumber,
    required String draftId,
    required int createdAtMillis,
  }) => SquareFileCleanupEntity()
    ..cleanupKey = _cleanupKey(cidNumber, draftId)
    ..cidNumber = cidNumber
    ..draftId = draftId
    ..cleanupKind = _draftDirectoryCleanup
    ..createdAtMillis = createdAtMillis
    ..attemptCount = 0;

  static SquareFileCleanupEntity _copyCleanup(SquareFileCleanupEntity source) =>
      SquareFileCleanupEntity()
        ..id = source.id
        ..cleanupKey = source.cleanupKey
        ..cidNumber = source.cidNumber
        ..draftId = source.draftId
        ..cleanupKind = source.cleanupKind
        ..createdAtMillis = source.createdAtMillis
        ..attemptCount = source.attemptCount
        ..lastError = source.lastError;
}
