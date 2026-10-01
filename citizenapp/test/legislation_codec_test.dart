// 立法 SCALE 解码金标向量 —— 手工编码字节(独立于解码器正向推理),验证 codec
// 与链端布局逐字段对齐。structural 字节手写,字符串内容用 utf8.encode(长度 compact 手算)。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/citizen/legislation/data/law_models.dart';
import 'package:citizenapp/citizen/legislation/data/legislation_codec.dart';
import 'package:citizenapp/votingengine/legislation-vote/legislation_vote_query_service.dart';

/// 单字节 compact(仅 len<64;金标向量足够)。
int _c(int n) => n << 2;

/// 字符串 → [compact(len), ...utf8]。
List<int> _s(String s) {
  final b = utf8.encode(s);
  return [_c(b.length), ...b];
}

List<int> _u32(int v) =>
    [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
List<int> _u64(int v) => [...List.generate(8, (k) => (v >> (8 * k)) & 0xff)];
List<int> _someU32(int v) => [0x01, ..._u32(v)];

void main() {
  test('decodeLawIds: Vec<u64> [0, 5]', () {
    final raw = Uint8List.fromList([_c(2), ..._u64(0), ..._u64(5)]);
    expect(decodeLawIds(raw), [0, 5]);
  });

  test('decodeOptionBytes: Some / None', () {
    expect(decodeOptionBytes(Uint8List.fromList([0x01, _c(2), 0xAA, 0xBB])),
        [0xAA, 0xBB]);
    expect(decodeOptionBytes(Uint8List.fromList([0x00])), isNull);
  });

  test('decodeLaw: 宪法主记录', () {
    const houseCid = 'LN001-NLG0G-123456789-2026';
    final raw = Uint8List.fromList([
      ..._u64(0), // law_id
      0x00, // tier=Constitution
      ..._u32(0), // scope_code=0
      _c(1), // houses len=1
      ..._s(houseCid), // houses 只保存机构 CID
      ..._someU32(1), // effective_version
      ..._u32(1), // latest_version
      0x00, // pending_version=None
      0x01, // status=Effective
    ]);
    final law = decodeLaw(raw);
    expect(law.lawId, 0);
    expect(law.tier, LawTier.constitution);
    expect(law.scopeCode, 0);
    expect(law.houses.length, 1);
    expect(law.houses.first, houseCid);
    expect(law.effectiveVersion, 1);
    expect(law.latestVersion, 1);
    expect(law.pendingVersion, isNull);
    expect(law.status, LawStatus.effective);
  });

  test('decodeImmutableManifest: 不可修改条款', () {
    final raw = Uint8List.fromList([
      _c(2), ..._u32(1), ..._u32(3), // numbers [1,3]
      _c(2), ...List.filled(32, 0x11), ...List.filled(32, 0x22), // hashes
    ]);
    final m = decodeImmutableManifest(raw);
    expect(m.articleNumbers, [1, 3]);
    expect(m.articleHashes, ['11' * 32, '22' * 32]);
    expect(m.isImmutable(1), isTrue);
    expect(m.isImmutable(2), isFalse);
  });

  test('decodeLawVersion: 章>节>条>款 嵌套树 + 时间戳/状态', () {
    final raw = Uint8List.fromList([
      ..._u64(0), // law_id
      ..._u32(1), // version
      ..._s('法'), // title
      0x00, // title_en None
      _c(1), // chapters len=1
      ..._u32(1), ..._s('章'), 0x00, // chapter number/title/title_en
      _c(1), // sections len=1
      ..._u32(1), ..._s('节'), 0x00, // section
      _c(1), // articles len=1
      ..._u32(1), ..._s('条'), 0x00, // article number/title/title_en
      ..._s('正文'), 0x00, // body / body_en None
      _c(1), // clauses len=1
      ..._u32(1), ..._s('款'), 0x00, // clause number/text/text_en
      ...List.filled(32, 0), // content_hash
      0x04, // vote_type=Special
      ..._u64(0), // proposal_id
      ..._u64(10), // published_at
      ..._u64(20), // effective_at
    ]);
    final v = decodeLawVersion(raw);
    expect(v.lawId, 0);
    expect(v.version, 1);
    expect(v.title, '法');
    expect(v.titleEn, isNull);
    expect(v.voteTypeEnum, VoteType.special);
    expect(v.publishedAt, 10);
    expect(v.effectiveAt, 20);
    expect(v.chapters.length, 1);
    final ch = v.chapters.first;
    expect(ch.title, '章');
    expect(ch.sections.first.title, '节');
    final art = ch.sections.first.articles.first;
    expect(art.number, 1);
    expect(art.title, '条');
    expect(art.body, '正文');
    expect(art.clauses.first.text, '款');
  });

  test('decodeLawVersionLabel: 创世版本标签', () {
    final raw = Uint8List.fromList([
      ..._s('创世版'),
      0x01, ..._s('Genesis Edition'), // title_en=Some
    ]);
    final label = decodeLawVersionLabel(raw);
    expect(label.title, '创世版');
    expect(label.titleEn, 'Genesis Edition');
  });

  test('RepresentativeMetas 路线解码完整机构岗位主体', () {
    const firstCid = 'LN001-NLG0G-123456789-2026';
    const secondCid = 'LN001-NSE0G-987654321-2026';
    final raw = Uint8List.fromList([
      0x01, // Sequential
      _c(2),
      ..._s(firstCid),
      ..._s('HOUSE_MEMBER'),
      ..._s(secondCid),
      ..._s('SENATOR'),
      ..._u32(1), // current_body
      0x02, // Special rule
      0x01, // Legislation procedure
    ]);
    final meta = LegislationVoteQueryService.debugDecodeRepresentativeMeta(raw);
    expect(meta, isNotNull);
    expect(meta!.sequential, isTrue);
    expect(meta.bodies.map((body) => body.cidNumber), [firstCid, secondCid]);
    expect(
        meta.bodies.map((body) => body.roleCode), ['HOUSE_MEMBER', 'SENATOR']);
    expect(meta.currentBody, 1);
    expect(meta.rule, 2);
    expect(meta.procedure, 1);
  });

  test('LegislationMetas 行政与立法院主体只解码机构 CID', () {
    const executiveCid = 'LN001-NED0G-123456789-2026';
    const legislatureCid = 'LN001-NLG0G-987654321-2026';
    final raw = Uint8List.fromList([
      ..._s(executiveCid),
      0x01,
      ..._s(legislatureCid),
      0x01,
    ]);
    final meta = LegislationVoteQueryService.debugDecodeLegislationMeta(raw);
    expect(meta, isNotNull);
    expect(meta!.executiveCidNumber, executiveCid);
    expect(meta.legislatureCidNumber, legislatureCid);
    expect(meta.needsGuard, isTrue);
  });

  test('立法 CID 路由拒绝旧 code+AccountId 布局和尾随字节', () {
    final oldRoute = Uint8List.fromList([
      0x00,
      0x4e,
      0x4c,
      0x47,
      0x00,
      ...List.filled(32, 0xab),
      ..._u32(0),
      0x00,
      0x00,
    ]);
    expect(
      LegislationVoteQueryService.debugDecodeRepresentativeMeta(oldRoute),
      isNull,
    );

    const houseCid = 'LN001-NLG0G-123456789-2026';
    final lawWithTrailingByte = Uint8List.fromList([
      ..._u64(0),
      0x00,
      ..._u32(0),
      _c(1),
      ..._s(houseCid),
      ..._someU32(1),
      ..._u32(1),
      0x00,
      0x01,
      0xff,
    ]);
    expect(() => decodeLaw(lawWithTrailingByte), throwsFormatException);
  });
}
