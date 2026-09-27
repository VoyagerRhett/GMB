import 'dart:convert';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:citizenapp/isar/user_isar.dart';

import 'citizen_identity_chain_reader.dart';

/// 身份的持久展示快照；完整链数据只供卡片显示，不能用作当前操作的授权结果。
class IdentityBadgeSnapshot {
  const IdentityBadgeSnapshot({
    required this.cidNumber,
    required this.identityLevel,
    required this.updatedAtMillis,
    this.accountId,
    this.identity,
    this.verified = false,
  });

  final String cidNumber;
  final String identityLevel;
  final int updatedAtMillis;
  final String? accountId;
  final CitizenIdentityChainSnapshot? identity;

  /// 已完整读取过身份；true 且 identity 为 null 明确表示已验证未注册。
  final bool verified;
}

/// 身份页、我的及广场唯一展示存储；读取永远不联网。
class IdentityBadgeSnapshotStore {
  IdentityBadgeSnapshotStore({DateTime Function()? nowProvider})
    : _nowProvider = nowProvider ?? DateTime.now;

  static const _allowedLevels = {'visitor', 'voting', 'candidate'};
  static final revision = ValueNotifier<int>(0);
  final DateTime Function() _nowProvider;

  Future<IdentityBadgeSnapshot?> read(String cidNumber) async {
    final cid = cidNumber.trim();
    if (cid.isEmpty) return null;
    final row = await UserIsar.instance.read(
      (isar) async => isar.userIdentityBadgeSnapshotEntitys
          .filter()
          .cidNumberEqualTo(cid)
          .sortByUpdatedAtMillisDesc()
          .findFirst(),
    );
    return _decode(row);
  }

  Future<IdentityBadgeSnapshot?> readForAccountId(String accountId) async {
    final row = await UserIsar.instance.read(
      (isar) async => isar.userIdentityBadgeSnapshotEntitys
          .filter()
          .accountIdEqualTo(accountId)
          .sortByUpdatedAtMillisDesc()
          .findFirst(),
    );
    return _decode(row);
  }

  IdentityBadgeSnapshot? _decode(UserIdentityBadgeSnapshotEntity? row) {
    if (row == null ||
        !_allowedLevels.contains(row.identityLevel) ||
        row.updatedAtMillis < 0) {
      return null;
    }
    CitizenIdentityChainSnapshot? identity;
    final raw = row.identitySnapshotJson;
    try {
      if (raw != null) {
        final account = row.accountId;
        if (account == null || !RegExp(r'^0x[0-9a-f]{64}$').hasMatch(account)) {
          return null;
        }
        final value = jsonDecode(raw);
        if (value == null) {
          if (row.cidNumber.isNotEmpty) return null;
        } else {
          if (value is! Map<String, dynamic> || row.cidNumber.isEmpty) {
            return null;
          }
          final version = value['binding_revision'];
          if (version is! int || version <= 0) return null;
          Uint8List? bytes(String field) {
            final input = value[field];
            if (input == null) return null;
            if (input is! List ||
                input.any((v) => v is! int || v < 0 || v > 255)) {
              throw const FormatException('身份展示数据损坏');
            }
            return Uint8List.fromList(input.cast<int>());
          }

          final voting = bytes('voting_identity');
          final candidate = bytes('candidate_identity');
          if ((voting != null &&
                  !CitizenIdentityChainReader.votingIdentityLayoutIsValid(
                    voting,
                  )) ||
              (candidate != null &&
                  (voting == null ||
                      !CitizenIdentityChainReader.candidateIdentityLayoutIsValid(
                        candidate,
                      )))) {
            return null;
          }
          identity = CitizenIdentityChainSnapshot(
            cidNumber: row.cidNumber,
            accountId: Uint8List.fromList([
              for (var i = 2; i < account.length; i += 2)
                int.parse(account.substring(i, i + 2), radix: 16),
            ]),
            bindingRevision: version,
            votingIdentity: voting,
            candidateIdentity: candidate,
          );
        }
      }
      return IdentityBadgeSnapshot(
        cidNumber: row.cidNumber,
        identityLevel: row.identityLevel,
        updatedAtMillis: row.updatedAtMillis,
        accountId: row.accountId,
        identity: identity,
        verified: raw != null,
      );
    } on FormatException {
      // 缓存损坏只表示未知，读取不得清库、查链或冒充未注册。
      return null;
    }
  }

  /// 徽章生产者写入同一行；已有完整身份不能被局部徽章覆盖。
  Future<void> write({
    required String cidNumber,
    required String identityLevel,
  }) async {
    final cid = cidNumber.trim();
    if (cid.isEmpty || !_allowedLevels.contains(identityLevel)) {
      throw ArgumentError('公民号或身份档无效');
    }
    await UserIsar.instance.writeTxn((isar) async {
      final collection = isar.userIdentityBadgeSnapshotEntitys;
      final existing = await collection
          .filter()
          .cidNumberEqualTo(cid)
          .findFirst();
      if (existing?.identitySnapshotJson != null) return;
      final row = existing ?? UserIdentityBadgeSnapshotEntity();
      row
        ..cidNumber = cid
        ..identityLevel = identityLevel
        ..updatedAtMillis = _nowProvider().millisecondsSinceEpoch;
      await collection.put(row);
    });
    revision.value++;
  }

  /// 成功的完整验真是唯一完整快照写入者；无身份也保存账户事实，避免重进后误用旧CID。
  Future<void> writeVerified({
    required String accountId,
    required CitizenIdentityChainSnapshot? identity,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(accountId)) {
      throw ArgumentError('account_id 无效');
    }
    if (identity != null &&
        CitizenIdentityChainReader.hexEncode(identity.accountId) != accountId) {
      throw StateError('身份快照与账户不一致');
    }
    await UserIsar.instance.writeTxn((isar) async {
      if (!isCurrent()) throw StateError('身份上下文已变化');
      final rows = isar.userIdentityBadgeSnapshotEntitys;
      final row =
          await rows.filter().accountIdEqualTo(accountId).findFirst() ??
          UserIdentityBadgeSnapshotEntity();
      // 同一个CID的旧账户或旧徽章一并收敛；保留旧账户已失去绑定的事实，禁止双重归属。
      if (identity != null) {
        final previous = await rows
            .filter()
            .cidNumberEqualTo(identity.cidNumber)
            .findAll();
        for (final old in previous) {
          final known = _decode(old)?.identity;
          if (known != null &&
              (known.bindingRevision > identity.bindingRevision ||
                  (known.bindingRevision == identity.bindingRevision &&
                      old.accountId != accountId))) {
            throw StateError('身份绑定版本禁止回退或改写');
          }
          if (old.id == row.id) continue;
          if (old.accountId == null) {
            await rows.delete(old.id);
          } else {
            old
              ..cidNumber = ''
              ..identityLevel = 'visitor'
              ..identitySnapshotJson = 'null'
              ..updatedAtMillis = _nowProvider().millisecondsSinceEpoch;
            await rows.put(old);
          }
        }
      }
      row
        ..accountId = accountId
        ..cidNumber = identity?.cidNumber ?? ''
        ..identityLevel = identity?.votingIdentity == null
            ? 'visitor'
            : identity?.candidateIdentity == null
            ? 'voting'
            : 'candidate'
        ..identitySnapshotJson = jsonEncode(
          identity == null
              ? null
              : {
                  'binding_revision': identity.bindingRevision,
                  'voting_identity': identity.votingIdentity?.toList(),
                  'candidate_identity': identity.candidateIdentity?.toList(),
                },
        )
        ..updatedAtMillis = _nowProvider().millisecondsSinceEpoch;
      if (!isCurrent()) throw StateError('身份上下文已变化');
      await rows.put(row);
    });
    revision.value++;
  }

  Future<void> remove(String cidNumber) async {
    final cid = cidNumber.trim();
    if (cid.isEmpty) return;
    await UserIsar.instance.writeTxn((isar) async {
      await isar.userIdentityBadgeSnapshotEntitys
          .filter()
          .cidNumberEqualTo(cid)
          .deleteAll();
    });
    revision.value++;
  }
}
