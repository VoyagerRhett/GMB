import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';

@immutable
class CitizenProfileRevisionEvent {
  const CitizenProfileRevisionEvent({
    required this.cidNumber,
    required this.revision,
  });
  final String cidNumber;
  final int revision;
}

/// 公开资料唯一持久存储入口。读取只访问本地，缺失不触发下载或身份验真。
/// 既有集合名保留以保存用户数据；记录没有TTL，也不作容量淘汰。
class CitizenProfileCache {
  const CitizenProfileCache();
  static final ValueNotifier<CitizenProfileRevisionEvent?> revision =
      ValueNotifier<CitizenProfileRevisionEvent?>(null);
  static int _revision = 0;

  /// 请求与选图先于远端PUT落盘；同CID只允许一个未完成修改。
  Future<void> prepareUpdate(
    String cidNumber, {
    required Map<String, String> request,
    Uint8List? avatarBytes,
    Uint8List? bannerBytes,
  }) async {
    final cid = _cid(cidNumber);
    final epoch = CitizenProfileMediaCache._epoch(cid);
    const allowed = {
      'display_name',
      'bio',
      'avatar_object_key',
      'avatar_content_hash',
      'banner_object_key',
      'banner_content_hash',
    };
    if (request.isEmpty || request.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('资料修改字段不合法');
    }
    final row = UserProfileUpdateEntity()
      ..cidNumber = cid
      ..operationState = 'pending'
      ..requestJson = jsonEncode(request)
      ..avatarBytes = Uint8List.fromList(avatarBytes ?? [])
      ..bannerBytes = Uint8List.fromList(bannerBytes ?? []);
    for (final role in ['avatar', 'banner']) {
      final bytes = role == 'avatar' ? row.avatarBytes : row.bannerBytes;
      if (bytes.isEmpty) {
        if (request.containsKey('${role}_object_key') ||
            request.containsKey('${role}_content_hash')) {
          throw ArgumentError('修改图片必须持有完整字节');
        }
      } else {
        if (bytes.length > _limit(role) ||
            request['${role}_content_hash'] !=
                sha256.convert(bytes).toString() ||
            request['${role}_object_key']?.isNotEmpty != true) {
          throw ArgumentError('待保存图片声明不一致');
        }
        _contentType(bytes);
      }
    }
    row.contentHash = _updateHash(row);
    await UserIsar.instance.writeTxn((db) async {
      CitizenProfileMediaCache._check(cid, epoch);
      final old = await db.userProfileUpdateEntitys.getByCidNumber(cid);
      if (old != null) {
        if (old.contentHash != row.contentHash) throw StateError('请先恢复上次资料修改');
        return;
      }
      await db.userProfileUpdateEntitys.put(row);
    });
  }

  static String _updateHash(UserProfileUpdateEntity row) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            row.cidNumber,
            row.requestJson,
            sha256.convert(row.avatarBytes).toString(),
            sha256.convert(row.bannerBytes).toString(),
          ]),
        ),
      )
      .toString();

  Future<UserProfileUpdateEntity?> readUpdate(String cidNumber) async {
    final cid = _cid(cidNumber);
    final row = await UserIsar.instance.read(
      (db) => db.userProfileUpdateEntitys.getByCidNumber(cid),
    );
    if (row != null &&
        (row.cidNumber != cid ||
            row.contentHash != _updateHash(row) ||
            !{'pending', 'confirmed'}.contains(row.operationState) ||
            (row.operationState == 'confirmed' && row.responseJson == null))) {
      throw StateError('资料恢复记录损坏');
    }
    return row;
  }

  bool updateMatches(UserProfileUpdateEntity row, CitizenProfile profile) {
    if (row.cidNumber != profile.cidNumber) return false;
    final request = jsonDecode(row.requestJson) as Map<String, dynamic>;
    final actual = profile.toJson();
    return request.entries
        .where((e) => !e.key.endsWith('_content_hash'))
        .every((e) => actual[e.key] == e.value);
  }

  Future<void> confirmUpdate(CitizenProfile profile) async {
    final row = await readUpdate(profile.cidNumber ?? '');
    if (row == null || !updateMatches(row, profile)) {
      throw StateError('远端资料未确认本次修改');
    }
    final response = jsonEncode(profile.toJson());
    await UserIsar.instance.writeTxn((db) async {
      final current = await db.userProfileUpdateEntitys.getByCidNumber(
        row.cidNumber,
      );
      if (current == null || current.contentHash != row.contentHash) {
        throw StateError('资料修改上下文已变化');
      }
      current
        ..operationState = 'confirmed'
        ..responseJson = response;
      await db.userProfileUpdateEntitys.put(current);
    });
  }

  /// 已确认修改只在本地收尾，资料、图片与恢复行删除同事务提交。
  Future<CitizenProfile> finishUpdate(String cidNumber) async {
    final row = await readUpdate(cidNumber);
    if (row == null || row.operationState != 'confirmed') {
      throw StateError('资料修改尚未确认');
    }
    final profile = CitizenProfile.fromJson(
      jsonDecode(row.responseJson!) as Map<String, dynamic>,
    );
    if (!updateMatches(row, profile)) throw StateError('资料确认响应与请求不一致');
    final media = <UserProfileMediaEntity>[
      if (row.avatarBytes.isNotEmpty)
        CitizenProfileMediaCache._prepare(
          profile,
          'avatar',
          Uint8List.fromList(row.avatarBytes),
        ),
      if (row.bannerBytes.isNotEmpty)
        CitizenProfileMediaCache._prepare(
          profile,
          'banner',
          Uint8List.fromList(row.bannerBytes),
        ),
    ];
    await _commit(profile, media, completeUpdate: row);
    return profile;
  }

  static void _notify(String cid) {
    revision.value = CitizenProfileRevisionEvent(
      cidNumber: cid,
      revision: ++_revision,
    );
  }

  Future<CitizenProfile?> read(String cidNumber) async {
    if (cidNumber.trim().isEmpty) return null;
    final cid = _cid(cidNumber);
    final raw = await UserIsar.instance.read(
      (db) async =>
          (await db.userPublicProfileCacheEntitys.getByCidNumber(cid))
              ?.profileJson,
    );
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final profile = CitizenProfile.fromJson(decoded);
      // 主键与内容必须一致，不能把其它用户的资料读到当前页面。
      if (profile.cidNumber != cid || profile.updatedAt < 0) return null;
      return profile;
    } on FormatException {
      // 损坏记录保留，不将读取失败推断为注销，也不自动联网修复。
      return null;
    }
  }

  Future<void> write(CitizenProfile profile) async {
    if (profile.cidNumber == null || profile.cidNumber!.isEmpty) return;
    final cid = _cid(profile.cidNumber!);
    final epoch = CitizenProfileMediaCache._epoch(cid);
    await _commit(
      profile,
      const [],
      assertCurrent: () => CitizenProfileMediaCache._check(cid, epoch),
    );
  }

  /// 资料编辑唯一提交入口；所有字节校验完成后才进入原子事务。
  Future<void> writeWithMedia(
    CitizenProfile profile, {
    Uint8List? avatarBytes,
    Uint8List? bannerBytes,
  }) async {
    final cid = _cid(profile.cidNumber ?? '');
    final epoch = CitizenProfileMediaCache._epoch(cid);
    final rows = <UserProfileMediaEntity>[
      if (avatarBytes != null)
        CitizenProfileMediaCache._prepare(profile, 'avatar', avatarBytes),
      if (bannerBytes != null)
        CitizenProfileMediaCache._prepare(profile, 'banner', bannerBytes),
    ];
    await _commit(
      profile,
      rows,
      assertCurrent: () => CitizenProfileMediaCache._check(cid, epoch),
    );
  }

  /// 媒体在事务外校验；完整资料及本次所选图片只提交一次，再通知展示端。
  static Future<void> _commit(
    CitizenProfile profile,
    List<UserProfileMediaEntity> media, {
    void Function()? assertCurrent,
    UserProfileUpdateEntity? completeUpdate,
  }) async {
    final cid = _cid(profile.cidNumber ?? '');
    if (profile.updatedAt < 0) throw ArgumentError('资料版本无效');
    final payload = jsonEncode(profile.toJson());
    final changed = await UserIsar.instance.writeTxn((db) async {
      assertCurrent?.call();
      if (completeUpdate != null) {
        final row = await db.userProfileUpdateEntitys.getByCidNumber(cid);
        if (row == null ||
            row.contentHash != completeUpdate.contentHash ||
            row.operationState != 'confirmed' ||
            row.responseJson != payload) {
          throw StateError('资料恢复事实已变化');
        }
      }
      final current = await db.userPublicProfileCacheEntitys.getByCidNumber(
        cid,
      );
      if (current != null) {
        final old = CitizenProfile.fromJson(
          jsonDecode(current.profileJson) as Map<String, dynamic>,
        );
        if (old.cidNumber != cid) throw StateError('本地资料归属损坏');
        if (old.updatedAt > profile.updatedAt) {
          throw StateError('旧资料不能覆盖较新的本地版本');
        }
      }
      var changed = current?.profileJson != payload;
      for (final row in media) {
        if (row.cidNumber != cid ||
            row.updatedAt != profile.updatedAt ||
            row.objectKey != _objectKey(profile, row.mediaRole)) {
          throw StateError('资料媒体与当前资料归属不一致');
        }
        changed = await CitizenProfileMediaCache._put(db, row) || changed;
      }
      if (current?.profileJson != payload) {
        await db.userPublicProfileCacheEntitys.putByCidNumber(
          UserPublicProfileCacheEntity()
            ..cidNumber = cid
            ..profileJson = payload,
        );
      }
      assertCurrent?.call();
      if (completeUpdate != null) {
        await db.userProfileUpdateEntitys.delete(completeUpdate.id);
      }
      return changed;
    });
    if (changed) _notify(cid);
  }

  /// 显式删除只处理指定CID，同时删除所属图片；迟到下载不得复活已删除资料。
  Future<void> clear(String cidNumber) async {
    if (cidNumber.trim().isEmpty) return;
    final cid = _cid(cidNumber);
    CitizenProfileMediaCache._invalidate(cid);
    final changed = await UserIsar.instance.writeTxn((db) async {
      final removed = await db.userPublicProfileCacheEntitys.deleteByCidNumber(
        cid,
      );
      await db.userProfileUpdateEntitys.deleteByCidNumber(cid);
      final images = await db.userProfileMediaEntitys
          .filter()
          .cidNumberEqualTo(cid)
          .deleteAll();
      return removed || images != 0;
    });
    if (changed) _notify(cid);
  }
}

@immutable
class CitizenProfileMediaSnapshot {
  const CitizenProfileMediaSnapshot({this.avatarPath, this.bannerPath});

  /// 当前展示的可再生临时文件，持久字节及归属只在UserIsar。
  final String? avatarPath;
  final String? bannerPath;
}

/// UserIsar资料图片唯一读写入口，按CID、用途、版本分条保存完整字节。
/// 网络、哈希和文件操作均在数据库事务外，普通read绝不联网。
class CitizenProfileMediaCache {
  CitizenProfileMediaCache({
    Future<Directory> Function()? supportDirectoryProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
    http.Client? client,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ??
           supportDirectoryProvider ??
           getTemporaryDirectory,
       _client = client;

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  final http.Client? _client;
  static int _generation = 0;
  static final Map<String, int> _cidGenerations = {};
  static void _invalidate(String cid) =>
      _cidGenerations[cid] = (_cidGenerations[cid] ?? 0) + 1;
  static String _epoch(String cid) =>
      '$_generation-${_cidGenerations[cid] ?? 0}';
  static void _check(String cid, String epoch) {
    if (_epoch(cid) != epoch) throw StateError('用户资料已清除，拒绝迟到结果');
  }

  Future<void> clearCid(String cidNumber) async {
    final cid = _cid(cidNumber);
    _invalidate(cid);
    await UserIsar.instance.writeTxn((db) async {
      await db.userProfileMediaEntitys
          .filter()
          .cidNumberEqualTo(cid)
          .deleteAll();
    });
    await _deleteExactTree(p.join((await _legacyRoot()).path, _cidHash(cid)));
    await _deleteExactTree(p.join((await _workRoot()).path, _cidHash(cid)));
    CitizenProfileCache._notify(cid);
  }

  /// AppLock先关闭并擦除UserIsar，再清除旧文件与临时域；这里不重新打开数据库。
  /// 代次检查阻止此前下载或文件写入在擦除后复活用户图片。
  Future<void> closeAndDeleteAll() async {
    _generation++;
    await _deleteExactTree((await _legacyRoot()).path);
    await _deleteExactTree((await _workRoot()).path);
  }

  Future<CitizenProfileMediaSnapshot> read(CitizenProfile profile) async {
    if (profile.cidNumber == null || profile.cidNumber!.isEmpty) {
      return const CitizenProfileMediaSnapshot();
    }
    final cid = _cid(profile.cidNumber ?? '');
    final epoch = _epoch(cid);
    final avatar = await _readBest(profile, 'avatar', epoch);
    final banner = await _readBest(profile, 'banner', epoch);
    _check(cid, epoch);
    return CitizenProfileMediaSnapshot(avatarPath: avatar, bannerPath: banner);
  }

  /// 编辑成功已有原始字节，资料和图片同事务提交，不下载已持有的图片。
  Future<CitizenProfileMediaSnapshot> rememberSelected({
    required CitizenProfile profile,
    Uint8List? avatarBytes,
    Uint8List? bannerBytes,
  }) async {
    await const CitizenProfileCache().writeWithMedia(
      profile,
      avatarBytes: avatarBytes,
      bannerBytes: bannerBytes,
    );
    return read(profile);
  }

  /// 只由显式远端操作调用；下载有长度上限，失败保留已有数据库图片。
  Future<CitizenProfileMediaSnapshot> refresh({
    required CitizenProfile profile,
    required String? avatarUrl,
    required String? bannerUrl,
    required Map<String, String>? headers,
  }) async {
    final cid = _cid(profile.cidNumber ?? '');
    final epoch = _epoch(cid);
    for (final entry in {'avatar': avatarUrl, 'banner': bannerUrl}.entries) {
      final role = entry.key;
      final url = entry.value;
      if (_objectKey(profile, role) == null || url == null || url.isEmpty) {
        continue;
      }
      if (await _exact(profile, role) != null) continue;
      if (await _importLegacy(profile, role, epoch) != null) continue;
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ArgumentError('资料图片地址必须使用HTTPS');
      }
      final client = _client ?? http.Client();
      try {
        final request = http.Request('GET', uri)..followRedirects = false;
        if (headers != null) request.headers.addAll(headers);
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          continue;
        }
        final limit = _limit(role);
        if ((response.contentLength ?? 0) > limit) {
          await response.stream.listen(null).cancel();
          continue;
        }
        final output = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (output.length + chunk.length > limit) {
            throw const FormatException('资料图片超出大小限制');
          }
          output.add(chunk);
        }
        final row = _prepare(profile, role, output.takeBytes());
        final changed = await UserIsar.instance.writeTxn((db) async {
          _check(cid, epoch);
          return _put(db, row);
        });
        if (changed) CitizenProfileCache._notify(cid);
      } on Exception {
        // 下载失败不修改旧字节，不能由网络错误推断云端已删除。
      } finally {
        if (_client == null) client.close();
      }
    }
    _check(cid, epoch);
    return read(profile);
  }

  static UserProfileMediaEntity _prepare(
    CitizenProfile profile,
    String role,
    Uint8List input,
  ) {
    final cid = _cid(profile.cidNumber ?? '');
    final key = _objectKey(profile, role);
    if (key == null || profile.updatedAt < 0) {
      throw ArgumentError('资料图片缺少归属或版本');
    }
    // 复制后计算摘要，防止调用方修改缓冲区导致入库字节与哈希不一致。
    final bytes = Uint8List.fromList(input);
    if (bytes.isEmpty || bytes.length > _limit(role)) {
      throw const FormatException('资料图片大小无效');
    }
    return UserProfileMediaEntity()
      ..cidNumber = cid
      ..mediaRole = role
      ..mediaId = _mediaId(profile, role)
      ..objectKey = key
      ..updatedAt = profile.updatedAt
      ..contentType = _contentType(bytes)
      ..byteSize = bytes.length
      ..sha256 = sha256.convert(bytes).toString()
      ..mediaBytes = bytes;
  }

  /// 已处于User写事务；调用方先在事务外校验字节，同版本只接受完全相同的内容。
  static Future<bool> _put(Isar db, UserProfileMediaEntity row) async {
    final previous = await db.userProfileMediaEntitys
        .getByCidNumberMediaRoleMediaId(
          row.cidNumber,
          row.mediaRole,
          row.mediaId,
        );
    if (previous != null) {
      if (previous.sha256 != row.sha256 ||
          previous.byteSize != row.byteSize ||
          previous.contentType != row.contentType ||
          previous.objectKey != row.objectKey ||
          previous.updatedAt != row.updatedAt ||
          !listEquals(previous.mediaBytes, row.mediaBytes)) {
        throw StateError('同一资料图片版本的内容冲突，保留原记录');
      }
      return false;
    }
    row.id = Isar.autoIncrement;
    await db.userProfileMediaEntitys.put(row);
    return true;
  }

  Future<UserProfileMediaEntity?> _exact(
    CitizenProfile profile,
    String role,
  ) async {
    final cid = _cid(profile.cidNumber ?? '');
    final row = await UserIsar.instance.read(
      (db) => db.userProfileMediaEntitys.getByCidNumberMediaRoleMediaId(
        cid,
        role,
        _mediaId(profile, role),
      ),
    );
    if (row != null) _validate(row, cid, role);
    return row;
  }

  static void _validate(UserProfileMediaEntity row, String cid, String role) {
    if (row.cidNumber != cid ||
        row.mediaRole != role ||
        row.updatedAt < 0 ||
        row.mediaId != _version(cid, role, row.objectKey, row.updatedAt) ||
        row.byteSize <= 0 ||
        row.byteSize > _limit(role) ||
        row.mediaBytes.length != row.byteSize ||
        sha256.convert(row.mediaBytes).toString() != row.sha256 ||
        _contentType(row.mediaBytes) != row.contentType) {
      throw StateError('本地资料图片归属或完整性校验失败');
    }
  }

  Future<String?> _readBest(
    CitizenProfile profile,
    String role,
    String epoch,
  ) async {
    final cid = _cid(profile.cidNumber ?? '');
    if (_objectKey(profile, role) == null) return null;
    var row = await _exact(profile, role);
    row ??= await _importLegacy(profile, role, epoch);
    // 刷新失败可显示同CID已有图片，但不把它登记为新版本下载成功。
    row ??= await UserIsar.instance.read(
      (db) => db.userProfileMediaEntitys
          .filter()
          .cidNumberEqualTo(cid)
          .mediaRoleEqualTo(role)
          .updatedAtLessThan(profile.updatedAt, include: true)
          .sortByUpdatedAtDesc()
          .findFirst(),
    );
    if (row == null) return null;
    _validate(row, cid, role);
    _check(cid, epoch);
    final root = await _workRoot(create: true);
    final owner = await _directory(
      p.join(root.path, _cidHash(cid)),
      create: true,
    );
    final dir = await _directory(p.join(owner.path, epoch), create: true);
    final target = File(p.join(dir.path, '${row.mediaRole}_${row.mediaId}'));
    Directory? staging;
    try {
      _check(cid, epoch);
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw StateError('资料临时文件不是普通文件');
      }
      if (type == FileSystemEntityType.notFound ||
          await target.length() != row.byteSize ||
          sha256.convert(await target.readAsBytes()).toString() != row.sha256) {
        // 同一图片可被多个页面同时读取，用独立临时文件原子替换，避免显示半份字节。
        staging = await dir.createTemp('writing-');
        final temporary = File(p.join(staging.path, 'image'));
        await temporary.writeAsBytes(row.mediaBytes, flush: true);
        _check(cid, epoch);
        await temporary.rename(target.path);
      }
      _check(cid, epoch);
      return target.path;
    } catch (_) {
      if (_epoch(cid) != epoch && await target.exists()) await target.delete();
      rethrow;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// 只导入当前CID/用途/准确版本的旧文件，不按文件时间猜测未知版本归属。
  /// 成功提交并回读校验后才删除来源；失败保留，普通读取不连接远端。
  Future<UserProfileMediaEntity?> _importLegacy(
    CitizenProfile profile,
    String role,
    String epoch,
  ) async {
    final cid = _cid(profile.cidNumber ?? '');
    final root = await _legacyRoot();
    final owner = await _directory(
      p.join(root.path, _cidHash(cid)),
      create: false,
    );
    final source = File(
      p.join(owner.path, '${role}_${_mediaId(profile, role)}'),
    );
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) throw StateError('旧资料图片不是普通文件');
    if (await source.length() > _limit(role)) {
      throw const FormatException('旧资料图片超出大小限制');
    }
    final row = _prepare(profile, role, await source.readAsBytes());
    await UserIsar.instance.writeTxn((db) async {
      _check(cid, epoch);
      await _put(db, row);
    });
    final saved = await _exact(profile, role);
    if (saved == null || saved.sha256 != row.sha256) {
      throw StateError('旧资料图片入库回读失败');
    }
    _check(cid, epoch);
    await source.delete();
    return saved;
  }

  Future<Directory> _legacyRoot() async {
    final parent = await _supportDirectoryProvider();
    final user = await _directory(p.join(parent.path, 'user'), create: false);
    return _directory(p.join(user.path, 'profile_media'), create: false);
  }

  Future<Directory> _workRoot({bool create = false}) async {
    final parent = await _temporaryDirectoryProvider();
    return _directory(
      p.join(parent.path, 'profile_media_work'),
      create: create,
    );
  }

  static Future<Directory> _directory(
    String path, {
    required bool create,
  }) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('资料媒体目录类型异常');
    }
    final dir = Directory(path);
    if (create && type == FileSystemEntityType.notFound) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _deleteExactTree(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }
}

String _cid(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      utf8.encode(value).length > 32) {
    throw ArgumentError('资料CID无效');
  }
  return value;
}

String _cidHash(String cid) => sha256.convert(utf8.encode(cid)).toString();
int _limit(String role) => switch (role) {
  'avatar' => 512 * 1024,
  'banner' => 1536 * 1024,
  _ => throw ArgumentError('资料媒体用途无效'),
};
String? _objectKey(CitizenProfile profile, String role) {
  _limit(role);
  final key = role == 'avatar'
      ? profile.avatarObjectKey
      : profile.bannerObjectKey;
  return key == null || key.trim().isEmpty ? null : key.trim();
}

String _version(String cid, String role, String key, int updatedAt) => sha256
    .convert(utf8.encode('$cid\u0000$role\u0000$key\u0000$updatedAt'))
    .toString();
String _mediaId(CitizenProfile profile, String role) => _version(
  _cid(profile.cidNumber ?? ''),
  role,
  _objectKey(profile, role) ?? '',
  profile.updatedAt,
);

/// 只接受现有选图链路输出的PNG/JPEG/WebP，类型不取自URL扩展名或响应声明。
String _contentType(List<int> bytes) {
  if (bytes.length >= 8 &&
      listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  throw const FormatException('资料图片格式不支持');
}
