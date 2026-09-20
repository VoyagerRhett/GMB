// 立法法律 SCALE 镜像解码(ADR-027 / ADR-028 P3)——单一源,浏览页与(将来 P4)
// 条款编辑器共用,绝不另写第二套(链端布局一改两处必裂)。
//
// 链端 `LegislationApi` 故意返回 SCALE 字节(`Option<Vec<u8>>` / `Vec<u64>`),
// 客户端镜像解码。布局逐字段对齐 legislation-yuan(多字节 LE;`Option`=1 tag 字节;
// `Compact` 变长;`BoundedVec/Vec`=Compact(len)+items;`[u8;N]`=N 裸字节;
// String=`BoundedVec<u8>`=Compact(len)+utf8)。

import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenapp/citizen/legislation/data/law_models.dart';

/// 游标式 SCALE 读取器(内部)。
class _Scale {
  _Scale(this.data);
  final Uint8List data;
  int _i = 0;

  bool get isDone => _i == data.length;

  void requireDone() {
    if (!isDone) throw const FormatException('SCALE 数据存在尾随字节');
  }

  int u8() => data[_i++];

  int u32() {
    final v = data[_i] |
        (data[_i + 1] << 8) |
        (data[_i + 2] << 16) |
        (data[_i + 3] << 24);
    _i += 4;
    return v;
  }

  int u64() {
    var v = 0;
    for (var k = 0; k < 8; k++) {
      v |= data[_i + k] << (8 * k);
    }
    _i += 8;
    return v;
  }

  /// SCALE `Compact<u32>`(长度/小整数用)。
  int compact() {
    final b0 = data[_i];
    final mode = b0 & 0x03;
    if (mode == 0) {
      _i += 1;
      return b0 >> 2;
    }
    if (mode == 1) {
      final v = (data[_i] | (data[_i + 1] << 8)) >> 2;
      _i += 2;
      return v;
    }
    if (mode == 2) {
      final v = (data[_i] |
              (data[_i + 1] << 8) |
              (data[_i + 2] << 16) |
              (data[_i + 3] << 24)) >>
          2;
      _i += 4;
      return v;
    }
    // mode 3:big-integer,low6+4 = 字节数(长度极少命中此分支)。
    final n = (b0 >> 2) + 4;
    _i += 1;
    var v = 0;
    for (var k = 0; k < n; k++) {
      v |= data[_i + k] << (8 * k);
    }
    _i += n;
    return v;
  }

  Uint8List bytes(int n) {
    final b = data.sublist(_i, _i + n);
    _i += n;
    return b;
  }

  /// Compact(len)+len 字节 → UTF-8 字符串。
  String boundedString() => utf8.decode(bytes(compact()));

  /// 链端统一 CidNumber：`BoundedVec<u8, 32>`。
  String cidNumber() {
    final length = compact();
    if (length <= 0 || length > 32) {
      throw const FormatException('机构 CID 长度必须为 1..32 字节');
    }
    return utf8.decode(bytes(length));
  }

  /// N 裸字节 → 小写 hex(不含 0x)。
  String hex(int n) =>
      bytes(n).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// `Option<T>`:1 tag 字节(0=None / 1=Some)。
  T? option<T>(T Function() some) {
    final tag = u8();
    if (tag == 0) return null;
    if (tag == 1) return some();
    throw FormatException('Option tag 非法: $tag');
  }

  /// `Vec<T>`/`BoundedVec<T>`:Compact(len)+items。
  List<T> vec<T>(T Function() item) {
    final n = compact();
    return [for (var k = 0; k < n; k++) item()];
  }
}

/// 解 `Option<Vec<u8>>`(API 边界外层)→ 内层 SCALE 字节(None 返回 null)。
Uint8List? decodeOptionBytes(Uint8List raw) {
  final s = _Scale(raw);
  final tag = s.u8();
  if (tag == 0) {
    s.requireDone();
    return null;
  }
  if (tag != 1) throw FormatException('Option tag 非法: $tag');
  final value = s.bytes(s.compact());
  s.requireDone();
  return value;
}

/// 解 `list_laws` 返回的 `Vec<u64>`。
List<int> decodeLawIds(Uint8List raw) {
  final s = _Scale(raw);
  final ids = s.vec(s.u64);
  s.requireDone();
  return ids;
}

/// 解 `Law`(内层字节,调用方先 [decodeOptionBytes] 拆 Option)。
Law decodeLaw(Uint8List raw) {
  final s = _Scale(raw);
  final lawId = s.u64();
  final tier = LawTier.fromIndex(s.u8());
  final scopeCode = s.u32();
  final houses = s.vec(s.cidNumber);
  final effectiveVersion = s.option(s.u32);
  final latestVersion = s.u32();
  final pendingVersion = s.option(s.u32);
  final status = LawStatus.fromIndex(s.u8());
  s.requireDone();
  return Law(
    lawId: lawId,
    tier: tier,
    scopeCode: scopeCode,
    houses: houses,
    effectiveVersion: effectiveVersion,
    latestVersion: latestVersion,
    pendingVersion: pendingVersion,
    status: status,
  );
}

/// 解 `LawVersion`(内层字节)。
LawVersion decodeLawVersion(Uint8List raw) {
  final s = _Scale(raw);
  final lawId = s.u64();
  final version = s.u32();
  final title = s.boundedString();
  final titleEn = s.option(s.boundedString);
  final chapters = s.vec(() => _chapter(s));
  final contentHash = s.hex(32);
  final voteType = s.u8();
  final proposalId = s.u64();
  final publishedAt = s.u64();
  final effectiveAt = s.u64();
  s.requireDone();
  return LawVersion(
    lawId: lawId,
    version: version,
    title: title,
    titleEn: titleEn,
    chapters: chapters,
    contentHash: contentHash,
    voteType: voteType,
    proposalId: proposalId,
    publishedAt: publishedAt,
    effectiveAt: effectiveAt,
  );
}

/// 解 `LawVersionLabel`(内层字节)。
LawVersionLabel decodeLawVersionLabel(Uint8List raw) {
  final s = _Scale(raw);
  final title = s.boundedString();
  final titleEn = s.option(s.boundedString);
  s.requireDone();
  return LawVersionLabel(title: title, titleEn: titleEn);
}

/// 解 `ConstitutionImmutableManifest`(StorageValue 原始字节)。
ImmutableManifest decodeImmutableManifest(Uint8List raw) {
  final s = _Scale(raw);
  final numbers = s.vec(s.u32);
  final hashes = s.vec(() => s.hex(32));
  s.requireDone();
  return ImmutableManifest(articleNumbers: numbers, articleHashes: hashes);
}

LawChapter _chapter(_Scale s) {
  final number = s.u32();
  final title = s.boundedString();
  final titleEn = s.option(s.boundedString);
  final sections = s.vec(() => _section(s));
  return LawChapter(
      number: number, title: title, titleEn: titleEn, sections: sections);
}

LawSection _section(_Scale s) {
  final number = s.u32();
  final title = s.boundedString();
  final titleEn = s.option(s.boundedString);
  final articles = s.vec(() => _article(s));
  return LawSection(
      number: number, title: title, titleEn: titleEn, articles: articles);
}

LawArticle _article(_Scale s) {
  final number = s.u32();
  final title = s.boundedString();
  final titleEn = s.option(s.boundedString);
  final body = s.boundedString();
  final bodyEn = s.option(s.boundedString);
  final clauses = s.vec(() => _clause(s));
  return LawArticle(
    number: number,
    title: title,
    titleEn: titleEn,
    body: body,
    bodyEn: bodyEn,
    clauses: clauses,
  );
}

LawClause _clause(_Scale s) {
  final number = s.u32();
  final text = s.boundedString();
  final textEn = s.option(s.boundedString);
  return LawClause(number: number, text: text, textEn: textEn);
}
