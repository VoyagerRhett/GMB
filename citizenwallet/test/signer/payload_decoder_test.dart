import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenwallet/signer/institution_code.dart';
import 'package:citizenwallet/signer/payload_decoder.dart';
import 'package:citizenwallet/signer/role_permission_codec.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';

void main() {
  const registryActorCid = 'ZS001-FRG07-249474503-2026';
  const nrcActorCid = 'LN001-NRC0G-944805165-2026';
  String hexOf(List<int> payload) =>
      '0x${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  String hexLower(List<int> payload) =>
      payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> compactU32(int value) {
    if (value < 64) return [value << 2];
    if (value < 16384) {
      final v = (value << 2) | 1;
      return [v & 0xff, (v >> 8) & 0xff];
    }
    final v = (value << 2) | 2;
    return [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  }

  /// SCALE `Vec<u8>` = compact(**字节**长度) ++ utf8。
  ///
  /// 长度前缀必须走 [compactU32]:此处曾内联 `bytes.length << 2`,只覆盖 1 字节档,
  /// 文本超过 63 字节即编出错误前缀,基于它构造的用例会建立在非法输入上。
  List<int> compactVec(String text) {
    final bytes = utf8.encode(text);
    return [...compactU32(bytes.length), ...bytes];
  }

  List<int> adminPerson(
    List<int> adminAccount,
    String familyName,
    String givenName, {
    String citizenCidNumber = '',
  }) => [
    ...adminAccount,
    ...compactVec(citizenCidNumber),
    ...compactVec(familyName),
    ...compactVec(givenName),
  ];

  List<int> u128LeForTest(BigInt value) {
    final out = List<int>.filled(16, 0);
    var tmp = value;
    for (var i = 0; i < 16; i++) {
      out[i] = (tmp & BigInt.from(0xFF)).toInt();
      tmp = tmp >> 8;
    }
    return out;
  }

  List<int> u16Le(int value) => [value & 0xff, (value >> 8) & 0xff];

  List<int> u32Le(int value) => [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];

  List<int> u64Le(int value) {
    final out = List<int>.filled(8, 0);
    var tmp = value;
    for (var i = 0; i < 8; i++) {
      out[i] = tmp & 0xff;
      tmp >>= 8;
    }
    return out;
  }

  Map<String, dynamic> readRolePermissionFixture() {
    final candidates = [
      File('test/signer/fixtures/role_permission.json'),
    ];
    final file = candidates.firstWhere((candidate) => candidate.existsSync());
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Uint8List roleFixtureBytes(Map<String, dynamic> fixture, String name) {
    final cases = fixture['cases']! as List<dynamic>;
    final entry = cases.cast<Map<String, dynamic>>().singleWhere(
      (item) => item['name'] == name,
    );
    final hex = entry['encoded_hex']! as String;
    return Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);
  }

  test('岗位权限与 VotePlan 严格解码统一 SCALE fixture', () {
    final fixture = readRolePermissionFixture();
    final role = RolePermissionCodec.decodeRoleSubject(
      roleFixtureBytes(fixture, 'role_subject_nrc_committee'),
    )!;
    expect(role.cidNumber, nrcActorCid);
    expect(role.roleCode, 'COMMITTEE_MEMBER');

    final action = RolePermissionCodec.decodeBusinessActionId(
      roleFixtureBytes(fixture, 'business_action_resolution_issuance'),
    )!;
    expect(action.moduleTag, 'res-iss');
    expect(action.actionCode, 0);

    final permission = RolePermissionCodec.decodeRoleBusinessPermission(
      roleFixtureBytes(fixture, 'permission_resolution_issuance_propose'),
    )!;
    expect(permission.operation, RolePermissionOperation.propose);

    final personal = RolePermissionCodec.decodeAuthorizationSubject(
      roleFixtureBytes(fixture, 'authorization_personal_multisig'),
    )!;
    expect(personal.isInstitution, isFalse);
    expect(personal.personalAccountHex, '07' * 32);

    final plan = RolePermissionCodec.decodeVotePlan(
      roleFixtureBytes(fixture, 'vote_plan_resolution_issuance_joint'),
    )!;
    expect(plan.proposalOwner, 'res-iss');
    expect(plan.voterSubjects, hasLength(3));
    expect(plan.voterSubjects.last.roleSubject!.roleCode, 'DIRECTOR');
    expect(plan.votingEngine, VotingEngineKind.joint);
    expect(plan.businessObjectHash, 'ab' * 32);

    final withTrailingByte = Uint8List.fromList([
      ...roleFixtureBytes(fixture, 'vote_plan_resolution_issuance_joint'),
      0,
    ]);
    expect(RolePermissionCodec.decodeVotePlan(withTrailingByte), isNull);
  });

  // SigningPayload 扩展尾,布局与节点端 build_signing_payload / citizenapp
  // polkadart 编码一致:era(0x00 immortal) + Compact<nonce> + Compact<tip>
  // + mode(0x00) + spec(4) + tx(4) + genesis(32) + birth=genesis(32) + None。
  // 真实 QR payload_hex = call_data + 本尾部;链上分支夹具必须带尾构造,
  // 裸 call_data 会被 decoder 的尾部校验拒绝(Reject → 红色)。
  final tailGenesis = List<int>.generate(32, (i) => 0x49 ^ i);
  List<int> signingTail({int nonce = 1, int tip = 0}) => [
    0x00,
    ...compactU32(nonce),
    ...compactU32(tip),
    0x00,
    1, 0, 0, 0, // spec_version u32 LE
    1, 0, 0, 0, // tx_version u32 LE
    ...tailGenesis,
    ...tailGenesis,
    0x00,
  ];

  Uint8List withSigningTail(List<int> callData, {int nonce = 1, int tip = 0}) =>
      Uint8List.fromList([...callData, ...signingTail(nonce: nonce, tip: tip)]);

  List<int> citizenIdentityPayloadForTest(List<int> walletBytes) => [
    ...compactVec('CTZN-430100-0001'),
    ...walletBytes,
    ...u32Le(20260630),
    ...u32Le(20360630),
    0,
    ...compactVec('43'),
    ...compactVec('0100'),
    ...compactVec('001'),
  ];

  /// 身份写入防重放两标量：expected_identity_version(8) + expires_at(8)。
  /// 链端 extrinsic 里紧跟 payload，授权载荷里位于末尾，两处顺序一致。
  List<int> identityAuthorizationTailForTest({
    int identityVersion = 3,
    int expiresAt = 1800000000,
  }) => [...u64Le(identityVersion), ...u64Le(expiresAt)];

  /// 公民实际签名覆盖的完整授权字节：
  /// genesis_hash(32) ++ payload ++ version(8) ++ expires_at(8)。
  List<int> citizenIdentityAuthorizationForTest(
    List<int> payloadBytes, {
    int identityVersion = 3,
    int expiresAt = 1800000000,
  }) => [
    ...List<int>.filled(32, 0x11), // genesis_hash
    ...payloadBytes,
    ...identityAuthorizationTailForTest(
      identityVersion: identityVersion,
      expiresAt: expiresAt,
    ),
  ];

  List<int> candidateIdentityPayloadForTest(List<int> walletBytes) => [
    ...citizenIdentityPayloadForTest(walletBytes),
    ...compactVec('43'),
    ...compactVec('0100'),
    ...compactVec('002'),
    ...compactVec('测'),
    ...compactVec('试公民'),
    1, // CitizenSex::Female
    // CandidateIdentityPayload 的末字段为 u32 LE YYYYMMDD。
    ...u32Le(20260630),
  ];

  List<int> bytesFromHex(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    return List<int>.generate(
      clean.length ~/ 2,
      (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
      growable: false,
    );
  }

  String ss58FromBytes(List<int> bytes) => Keyring().encodeAddress(bytes, 2027);

  group('PayloadDecoder', () {
    // 发布授权必须按链端定义完整消费所有 SCALE 字段；同时覆盖 action 绑定与尾字节拒绝，
    // 防止钱包把其它动作或带有未解释附加数据的载荷展示成可签名发布请求。
    test('生产发布授权严格绑定产品端并拒绝错误标识与尾字节', () {
      const expiresAt = 1900000000;
      // 中文注释：发布授权中的 platform 是产品端身份；已登记产品端组合
      // 必须逐一进入同一解码路径，任何旧标识或交叉组合都在冷钱包拒绝。
      List<int> publishPayload(
        String product,
        String platform, {
        String? previous,
      }) {
        const versionTag = '1.2.3';
        return <int>[
          ...compactVec(product),
          ...compactVec(platform),
          ...compactVec(versionTag),
          ...List<int>.filled(20, 0x11),
          ...List<int>.filled(32, 0x22),
          ...compactVec(
            previous ??
                (product == 'citizenchatserver' ? '' : 'deployment-previous'),
          ),
          ...u64Le(expiresAt),
          ...List<int>.filled(32, 0x33),
        ];
      }

      const validProductPlatforms = <String, List<String>>{
        'citizenapp': ['ios', 'android'],
        'citizenwallet': ['ios', 'android'],
        'citizenserve': ['cloudflare'],
        'citizenchatserver': ['cloudflare'],
        'citizenweb': ['web'],
        'tuyulove': ['ios', 'android'],
        'tuyuserve': ['cloudflare'],
        'tuyuweb': ['web'],
        'tuyubooking': ['macos', 'linux', 'windows'],
      };
      const productNamesZh = <String, String>{
        'citizenapp': '公民',
        'citizenwallet': '公民钱包',
        'citizenserve': '公民服务端',
        'citizenchatserver': '公民聊天服务',
        'citizenweb': '公民官网',
        'tuyulove': '途遇',
        'tuyuserve': '途遇服务端',
        'tuyuweb': '途遇官网',
        'tuyubooking': '途遇商家端',
      };
      const platformNames = <String, String>{
        'ios': 'iOS',
        'android': 'Android',
        'cloudflare': 'Cloudflare',
        'web': 'Web',
        'macos': 'macOS',
        'linux': 'Linux',
        'windows': 'Windows',
      };
      for (final productEntry in validProductPlatforms.entries) {
        for (final platform in productEntry.value) {
          final payload = publishPayload(productEntry.key, platform);
          final decoded = PayloadDecoder.decode(
            hexOf(payload),
            expectedAction: 'publish',
          );
          expect(decoded?.action, 'publish');
          expect(decoded?.fields['product_id'], productEntry.key);
          expect(decoded?.fields['platform'], platform);
          expect(decoded?.fields['source_sha'], '0x${'11' * 20}');
          expect(decoded?.fields['artifact_sha256'], '0x${'22' * 32}');
          expect(decoded?.fields['expires_at'], '$expiresAt');
          expect(
            decoded?.summary,
            '授权发布 ${productNamesZh[productEntry.key]} '
            '1.2.3 到 ${platformNames[platform]}'
            '${productEntry.key == 'citizenchatserver' ? '；不授权回滚或删除资源' : ''}',
          );
        }
      }

      const invalidProductPlatforms = <(String, String)>[
        ('citizenchatserver', 'ios'),
        ('citizenchatserver', 'web'),
        ('citizenweb', 'cloudflare'),
        ('citizenserve', 'web'),
        ('tuyulove', 'web'),
        ('tuyuserve', 'web'),
        ('tuyuweb', 'cloudflare'),
        ('tuyubooking', 'android'),
        ('tuyuservice', 'cloudflare'),
        ('tuyu-mobile', 'ios'),
        ('tuyu-service', 'cloudflare'),
        ('tuyu-merchant', 'macos'),
      ];
      for (final invalid in invalidProductPlatforms) {
        expect(
          PayloadDecoder.decode(
            hexOf(publishPayload(invalid.$1, invalid.$2)),
            expectedAction: 'publish',
          ),
          isNull,
        );
      }

      final payload = publishPayload('citizenweb', 'web');
      expect(
        PayloadDecoder.decode(
          hexOf(
            publishPayload(
              'citizenchatserver',
              'cloudflare',
              previous: 'forged-previous',
            ),
          ),
          expectedAction: 'publish',
        ),
        isNull,
      );
      expect(
        PayloadDecoder.decode(
          hexOf(publishPayload('citizenweb', 'web', previous: '')),
          expectedAction: 'publish',
        ),
        isNull,
      );
      expect(PayloadDecoder.decode(hexOf(payload)), isNull);
      expect(
        PayloadDecoder.decode(
          hexOf([...payload, 0]),
          expectedAction: 'publish',
        ),
        isNull,
      );
    });

    test('账户用途钥请求只在 action 14 下严格解码并拒绝重复用途', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      const expiresAt = 1900000000;
      final payload = <int>[
        ...List<int>.filled(32, 0x11),
        ...compactVec(cid),
        ...u64Le(3),
        ...List<int>.filled(32, 0x22),
        ...List<int>.filled(32, 0x33),
        ...compactU32(2),
        1,
        0,
        6,
        1,
        ...u64Le(expiresAt),
        ...List<int>.filled(16, 0x44),
      ];

      final decoded = PayloadDecoder.decode(
        hexOf(payload),
        expectedAction: 'account_data_key_provision',
      );
      expect(decoded?.action, 'account_data_key_provision');
      expect(decoded?.fields['cid_number'], cid);
      expect(decoded?.fields['binding_revision'], '3');
      expect(decoded?.fields['account_id'], '0x${'22' * 32}');
      expect(decoded?.fields['key_purposes'], '1:0,6:1');
      expect(PayloadDecoder.decode(hexOf(payload)), isNull);

      final duplicate = List<int>.from(payload);
      final purposeOffset =
          32 + compactVec(cid).length + 8 + 32 + 32 + compactU32(2).length;
      duplicate[purposeOffset + 2] = 1;
      duplicate[purposeOffset + 3] = 0;
      expect(
        PayloadDecoder.decode(
          hexOf(duplicate),
          expectedAction: 'account_data_key_provision',
        ),
        isNull,
      );
    });

    test('默认账户切换只在明确动作下严格解码完整账户顺序', () {
      final payload = <int>[
        ...List<int>.filled(32, 0x11),
        ...List<int>.filled(32, 0xaa),
        ...compactU32(3),
        ...List<int>.filled(32, 0xbb),
        ...List<int>.filled(32, 0xaa),
        ...List<int>.filled(32, 0xcc),
        ...u64Le(1900000000),
        ...List<int>.filled(16, 0xdd),
      ];

      final decoded = PayloadDecoder.decode(
        hexOf(payload),
        expectedAction: 'switch_default_account',
      );

      expect(decoded?.action, 'switch_default_account');
      expect(decoded?.fields['genesis_hash'], '0x${'11' * 32}');
      expect(decoded?.fields['current_default_account_id'], '0x${'aa' * 32}');
      expect(decoded?.fields['new_default_account_id'], '0x${'bb' * 32}');
      expect(decoded?.fields['account_count'], '3');
      expect(decoded?.fields['expires_at'], '1900000000');
      expect(
        PayloadDecoder.decode(hexOf(payload)),
        isNull,
        reason: '无 QR 动作上下文时禁止按结构猜测本机授权',
      );

      final duplicate = List<int>.from(payload)
        ..setRange(64 + 1 + 64, 64 + 1 + 96, List<int>.filled(32, 0xaa));
      expect(
        PayloadDecoder.decode(
          hexOf(duplicate),
          expectedAction: 'switch_default_account',
        ),
        isNull,
      );
    });

    test('设备子钥绑定只在 action 13 下严格解码 CID、账户和 P-256 公钥', () {
      const cid = 'CN220-CTZN2-198805200-2026';
      const accountId =
          '0x1111111111111111111111111111111111111111111111111111111111111111';
      final devicePublicKey = '04${'ab' * 64}';
      final payload = <int>[
        ...compactVec(cid),
        ...u64Le(3),
        ...compactVec(accountId),
        ...compactVec(devicePublicKey),
        ...u64Le(1700000000123),
      ];

      final decoded = PayloadDecoder.decode(
        hexOf(payload),
        expectedAction: 'square_device_bind',
      );
      expect(decoded?.action, 'square_device_bind');
      expect(decoded?.fields['cid_number'], cid);
      expect(decoded?.fields['binding_revision'], '3');
      expect(decoded?.fields['account_id'], accountId);
      expect(decoded?.fields['device_public_key'], devicePublicKey);
      expect(decoded?.fields['issued_at'], '1700000000123');
      expect(PayloadDecoder.decode(hexOf(payload)), isNull);

      final malformed = List<int>.from(payload);
      final keyOffset =
          compactVec(cid).length + 8 + compactVec(accountId).length;
      malformed[keyOffset + 3] = '5'.codeUnitAt(0);
      expect(
        PayloadDecoder.decode(
          hexOf(malformed),
          expectedAction: 'square_device_bind',
        ),
        isNull,
      );
    });

    test('decodes transfer_with_remark (pallet=4 call=0)', () {
      final dest = Keyring.sr25519.fromSeed(Uint8List(32));
      dest.ss58Format = 2027;
      final destBytes = dest.bytes().toList();
      const remark = '中华联邦创世';

      final payload = Uint8List.fromList([
        0x04,
        0x00,
        ...destBytes,
        ...u128LeForTest(BigInt.from(23400)),
        ...compactVec(remark),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'transfer');
      expect(decoded.fields['amount_yuan'], '234.00 元');
      expect(
        decoded.fields['recipient_account_id'],
        '0x${hexLower(destBytes)}',
      );
      expect(decoded.fields['remark'], remark);
    });

    // Phase 3(2026-04-22)「投票引擎统一入口整改」:
    // 所有业务 pallet 的 vote_X 已物理删除，机构岗位选民/个人多签管理员统一走
    // InternalVote::cast(20.0)。

    test('decodes internal_vote (pallet=20 call=0) approve=true', () {
      // [0x14, 0x00, u64_le proposal_id=42, Personal=0, bool approve=true]
      final payload = Uint8List.fromList([
        0x14, 0x00,
        42, 0, 0, 0, 0, 0, 0, 0,
        0, // InternalVoteTicketClaim::Personal
        1, // approve = true
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'internal_vote');
      expect(decoded.fields['proposal_id'], '42');
      expect(decoded.fields['approve'], 'true');
      expect(decoded.summary, contains('赞成'));
    });

    test('decodes internal_vote (pallet=20 call=0) approve=false', () {
      final payload = Uint8List.fromList([
        0x14,
        0x00,
        7,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0, // approve = false
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded!.action, 'internal_vote');
      expect(decoded.fields['approve'], 'false');
      expect(decoded.summary, contains('反对'));
    });

    test('decodes joint_vote (pallet=21 call=0)', () {
      // JointVote.cast_admin = pallet 21 / call 0，投票席位由机构 CID + 岗位码标识。
      final payload = Uint8List.fromList([
        0x15,
        0x00,
        7,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...compactVec(nrcActorCid),
        ...compactVec('COMMITTEE_MEMBER'),
        0,
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'joint_vote');
      expect(decoded.fields['proposal_id'], '7');
      expect(decoded.fields['cid_number'], nrcActorCid);
      expect(decoded.fields['voter_role_code'], 'COMMITTEE_MEMBER');
      expect(decoded.fields['approve'], 'false');
      expect(decoded.summary, contains('反对'));
    });

    test('decodes cast_referendum (pallet=21 call=1)', () {
      // JointVote.cast_referendum = pallet 21 / call 1,链端按账户读取公民身份。
      final payload = Uint8List.fromList([
        0x15, 0x01,
        99, 0, 0, 0, 0, 0, 0, 0, // proposal_id = 99 u64_le
        1, // approve = true
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_referendum');
      expect(decoded.fields['proposal_id'], '99');
      expect(decoded.fields['approve'], 'true');
    });

    test('JointVote 保留 call 2 空洞并拒绝旧载荷', () {
      final payload = Uint8List.fromList([
        0x15, 0x02,
        ...compactVec(nrcActorCid),
        2, // PopulationScope::City
        ...compactVec('GZ'),
        ...compactVec('001'),
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNull);
    });

    test('decodes ElectionVote 公民普选完整候选主体 (22.2)', () {
      final candidateWallet = List<int>.generate(32, (index) => index + 1);
      final payload = Uint8List.fromList([
        0x16,
        0x02,
        ...u64Le(101),
        ...compactVec('GD-CTZN1-8F3A2B'),
        ...candidateWallet,
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_popular_vote');
      expect(decoded.fields['proposal_id'], '101');
      expect(decoded.fields['cid_number'], 'GD-CTZN1-8F3A2B');
      expect(decoded.fields['account_id'], '0x${hexLower(candidateWallet)}');
    });

    test('decodes ElectionVote 机构岗位互选完整候选主体 (22.3)', () {
      final candidateWallet = List<int>.filled(32, 0x35);
      final payload = Uint8List.fromList([
        0x16,
        0x03,
        ...u64Le(102),
        ...compactVec('COMMITTEE_MEMBER'),
        ...compactVec('GD-CTZN1-8F3A2B'),
        ...candidateWallet,
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_mutual_vote');
      expect(decoded.fields['proposal_id'], '102');
      expect(decoded.fields['voter_role_code'], 'COMMITTEE_MEMBER');
      expect(decoded.fields['cid_number'], 'GD-CTZN1-8F3A2B');
      expect(decoded.fields['account_id'], '0x${hexLower(candidateWallet)}');
    });

    test('ElectionVote 拒绝旧裸钱包候选、CID 截断和尾随字段', () {
      final wallet = List<int>.filled(32, 0x22);
      final oldWalletOnly = Uint8List.fromList([
        0x16,
        0x02,
        ...u64Le(103),
        ...wallet,
      ]);
      final trailing = Uint8List.fromList([
        0x16,
        0x02,
        ...u64Le(103),
        ...compactVec('GD-CTZN1-8F3A2B'),
        ...wallet,
        0,
      ]);

      expect(
        PayloadDecoder.decode(hexOf(withSigningTail(oldWalletOnly))),
        isNull,
      );
      expect(PayloadDecoder.decode(hexOf(withSigningTail(trailing))), isNull);
    });

    group('OnchainIssuance(23) strict SCALE decode', () {
      final executionAccount = List<int>.generate(32, (i) => i + 1);
      final fromAccount = List<int>.filled(32, 0x31);
      final toAccount = List<int>.filled(32, 0x42);
      final reasonHash = List<int>.generate(32, (i) => 0xa0 + i);

      List<int> assetHeader(int callIndex, int assetId) => [
        0x17,
        callIndex,
        ...compactVec(registryActorCid),
        ...compactVec('ASSET_OPERATOR'),
        ...u32Le(assetId),
      ];

      test('QR action codes are the unique pallet 23 call codes', () {
        expect(QrActions.proposeAssetIssue, 0x1700);
        expect(QrActions.proposeAssetMint, 0x1701);
        expect(QrActions.proposeAssetBurn, 0x1702);
        expect(QrActions.proposeAssetClose, 0x1703);
        expect(QrActions.proposeAssetTransfer, 0x1704);
        expect(QrActions.proposeMonitorFreeze, 0x170a);
        expect(QrActions.proposeMonitorUnfreeze, 0x170b);
        expect(QrActions.proposeMonitorConfiscate, 0x170c);
        expect(QrActions.proposeMonitorForceTransfer, 0x170d);
        expect(QrActions.proposeMonitorForceClose, 0x170e);
      });

      test('call 0 decodes actor CID and execution account in exact order', () {
        final callData = <int>[
          0x17,
          0x00,
          ...compactVec(registryActorCid),
          ...compactVec('ASSET_OPERATOR'),
          ...executionAccount,
          0, // AssetClass::Plain
          ...compactVec('公民测试资产'),
          ...compactVec('CTA'),
          ...compactVec('严格 SCALE 布局测试'),
          8,
          ...u128LeForTest(BigInt.from(123456789)),
        ];
        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));

        expect(decoded, isNotNull);
        expect(decoded!.action, 'propose_asset_issue');
        expect(decoded.fields['actor_cid_number'], registryActorCid);
        expect(decoded.fields['actor_role_code'], 'ASSET_OPERATOR');
        expect(
          decoded.fields['execution_account_id'],
          '0x${hexLower(executionAccount)}',
        );
        expect(decoded.fields['asset_class'], 'Plain');
        expect(decoded.fields['asset_name'], '公民测试资产');
        expect(decoded.fields['asset_symbol'], 'CTA');
        expect(decoded.fields['asset_description'], '严格 SCALE 布局测试');
        expect(decoded.fields['decimals'], '8');
        expect(decoded.fields['initial_supply_raw'], '123456789');
        expect(
          QrActions.fromDecodedAction(decoded.action),
          QrActions.proposeAssetIssue,
        );
      });

      test('calls 1..4 decode every business field', () {
        final cases =
            <
              ({
                List<int> callData,
                String action,
                int qrAction,
                Map<String, String> expected,
              })
            >[
              (
                callData: [
                  ...assetHeader(1, 7),
                  ...toAccount,
                  ...u128LeForTest(BigInt.from(101)),
                ],
                action: 'propose_asset_mint',
                qrAction: QrActions.proposeAssetMint,
                expected: {
                  'asset_id': '7',
                  'recipient_account_id': '0x${hexLower(toAccount)}',
                  'amount_raw': '101',
                },
              ),
              (
                callData: [
                  ...assetHeader(2, 8),
                  ...fromAccount,
                  ...u128LeForTest(BigInt.from(202)),
                ],
                action: 'propose_asset_burn',
                qrAction: QrActions.proposeAssetBurn,
                expected: {
                  'asset_id': '8',
                  'sender_account_id': '0x${hexLower(fromAccount)}',
                  'amount_raw': '202',
                },
              ),
              (
                callData: [...assetHeader(3, 9)],
                action: 'propose_asset_close',
                qrAction: QrActions.proposeAssetClose,
                expected: {'asset_id': '9'},
              ),
              (
                callData: [
                  ...assetHeader(4, 10),
                  ...fromAccount,
                  ...toAccount,
                  ...u128LeForTest(BigInt.from(303)),
                ],
                action: 'propose_asset_transfer',
                qrAction: QrActions.proposeAssetTransfer,
                expected: {
                  'asset_id': '10',
                  'sender_account_id': '0x${hexLower(fromAccount)}',
                  'recipient_account_id': '0x${hexLower(toAccount)}',
                  'amount_raw': '303',
                },
              ),
            ];

        for (final item in cases) {
          final decoded = PayloadDecoder.decode(
            hexOf(withSigningTail(item.callData)),
          );
          expect(decoded, isNotNull, reason: item.action);
          expect(decoded!.action, item.action);
          expect(decoded.fields['actor_cid_number'], registryActorCid);
          expect(decoded.fields['actor_role_code'], 'ASSET_OPERATOR');
          for (final field in item.expected.entries) {
            expect(decoded.fields[field.key], field.value, reason: item.action);
          }
          expect(QrActions.fromDecodedAction(item.action), item.qrAction);
        }
      });

      test('calls 10..14 decode every monitor field', () {
        final cases =
            <
              ({
                List<int> callData,
                String action,
                int qrAction,
                Map<String, String> expected,
              })
            >[
              (
                callData: [...assetHeader(10, 11), ...toAccount, ...reasonHash],
                action: 'propose_monitor_freeze',
                qrAction: QrActions.proposeMonitorFreeze,
                expected: {
                  'asset_id': '11',
                  'account_id': '0x${hexLower(toAccount)}',
                },
              ),
              (
                callData: [...assetHeader(11, 12), ...toAccount, ...reasonHash],
                action: 'propose_monitor_unfreeze',
                qrAction: QrActions.proposeMonitorUnfreeze,
                expected: {
                  'asset_id': '12',
                  'account_id': '0x${hexLower(toAccount)}',
                },
              ),
              (
                callData: [
                  ...assetHeader(12, 13),
                  ...toAccount,
                  ...u128LeForTest(BigInt.from(404)),
                  ...reasonHash,
                ],
                action: 'propose_monitor_confiscate',
                qrAction: QrActions.proposeMonitorConfiscate,
                expected: {
                  'asset_id': '13',
                  'account_id': '0x${hexLower(toAccount)}',
                  'amount_raw': '404',
                },
              ),
              (
                callData: [
                  ...assetHeader(13, 14),
                  ...fromAccount,
                  ...toAccount,
                  ...u128LeForTest(BigInt.from(505)),
                  ...reasonHash,
                ],
                action: 'propose_monitor_force_transfer',
                qrAction: QrActions.proposeMonitorForceTransfer,
                expected: {
                  'asset_id': '14',
                  'sender_account_id': '0x${hexLower(fromAccount)}',
                  'recipient_account_id': '0x${hexLower(toAccount)}',
                  'amount_raw': '505',
                },
              ),
              (
                callData: [...assetHeader(14, 15), ...reasonHash],
                action: 'propose_monitor_force_close',
                qrAction: QrActions.proposeMonitorForceClose,
                expected: {'asset_id': '15'},
              ),
            ];

        for (final item in cases) {
          final decoded = PayloadDecoder.decode(
            hexOf(withSigningTail(item.callData)),
          );
          expect(decoded, isNotNull, reason: item.action);
          expect(decoded!.action, item.action);
          expect(decoded.fields['actor_cid_number'], registryActorCid);
          expect(decoded.fields['actor_role_code'], 'ASSET_OPERATOR');
          expect(decoded.fields['reason_hash'], '0x${hexLower(reasonHash)}');
          for (final field in item.expected.entries) {
            expect(decoded.fields[field.key], field.value, reason: item.action);
          }
          expect(QrActions.fromDecodedAction(item.action), item.qrAction);
        }
      });

      test(
        'rejects truncated, trailing, invalid enum and AccountId-only layouts',
        () {
          final validIssue = <int>[
            0x17,
            0,
            ...compactVec(registryActorCid),
            ...compactVec('ASSET_OPERATOR'),
            ...executionAccount,
            0,
            ...compactVec('资产'),
            ...compactVec('ASSET'),
            ...compactVec('说明'),
            8,
            ...u128LeForTest(BigInt.one),
          ];
          final truncated = validIssue.sublist(0, validIssue.length - 1);
          final trailing = [...validIssue, 0xff];
          final invalidClass = [...validIssue]
            ..[2 +
                    compactVec(registryActorCid).length +
                    compactVec('ASSET_OPERATOR').length +
                    32] =
                2;
          final accountIdOnly = <int>[
            0x17,
            0,
            ...executionAccount,
            0,
            ...compactVec('资产'),
            ...compactVec('ASSET'),
            ...compactVec('说明'),
            8,
            ...u128LeForTest(BigInt.one),
          ];

          for (final rejected in [
            truncated,
            trailing,
            invalidClass,
            accountIdOnly,
          ]) {
            expect(
              PayloadDecoder.decode(hexOf(withSigningTail(rejected))),
              isNull,
            );
          }
        },
      );
    });

    test('decodes raw citizen identity payload', () {
      final wallet = List<int>.generate(32, (i) => i + 1);
      final payload = citizenIdentityAuthorizationForTest(
        citizenIdentityPayloadForTest(wallet),
      );
      final decoded = PayloadDecoder.decode(hexOf(payload));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'citizen_identity');
      expect(decoded.fields['cid_number'], 'CTZN-430100-0001');
      expect(decoded.fields['account_id'], '0x${hexLower(wallet)}');
      expect(decoded.reviewFields['residence'], '43 / 0100 / 001');
    });

    test('decodes raw candidate citizen identity payload', () {
      final wallet = List<int>.generate(32, (i) => i + 1);
      final payload = citizenIdentityAuthorizationForTest(
        candidateIdentityPayloadForTest(wallet),
      );
      final decoded = PayloadDecoder.decode(hexOf(payload));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'citizen_candidate_identity');
      expect(decoded.fields['cid_number'], 'CTZN-430100-0001');
      expect(decoded.fields['account_id'], '0x${hexLower(wallet)}');
      expect(decoded.reviewFields['identity_level'], '参选身份');
      expect(decoded.reviewFields['birth_place'], '43 / 0100 / 002');
      expect(decoded.reviewFields['family_name'], '测');
      expect(decoded.reviewFields['given_name'], '试公民');
      expect(decoded.reviewFields['citizen_sex'], '女');
      expect(decoded.fields['birth_date'], '20260630');
      expect(decoded.reviewFields['birth_date'], '2026-06-30');
    });

    test('decodes register_voting_identity raw call data', () {
      final wallet = List<int>.generate(32, (i) => i + 1);
      final payload = citizenIdentityPayloadForTest(wallet);
      final callData = [
        0x0a,
        0x00,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...payload,
        ...identityAuthorizationTailForTest(),
        ...compactU32(64),
        ...List<int>.filled(64, 0xaa),
      ];

      final decoded = PayloadDecoder.decode(hexOf(callData));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'register_voting_identity');
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(decoded.fields['account_id'], '0x${hexLower(wallet)}');
      expect(decoded.summary, contains('CTZN-430100-0001'));
    });

    test('decodes register_voting_identity with signing tail', () {
      final wallet = List<int>.generate(32, (i) => i + 1);
      final payload = citizenIdentityPayloadForTest(wallet);
      final callData = [
        0x0a,
        0x00,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...payload,
        ...identityAuthorizationTailForTest(),
        ...compactU32(64),
        ...List<int>.filled(64, 0xaa),
      ];

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'register_voting_identity');
      expect(decoded.reviewFields['actor_cid_number'], registryActorCid);
    });

    test('decodes upgrade_to_candidate_identity raw call data', () {
      final wallet = List<int>.generate(32, (i) => i + 1);
      final payload = candidateIdentityPayloadForTest(wallet);
      final callData = [
        0x0a,
        0x01,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...payload,
        ...identityAuthorizationTailForTest(),
        ...compactU32(64),
        ...List<int>.filled(64, 0xaa),
      ];

      final decoded = PayloadDecoder.decode(hexOf(callData));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'upgrade_to_candidate_identity');
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(decoded.fields['account_id'], '0x${hexLower(wallet)}');
      expect(decoded.reviewFields['identity_level'], '参选身份');
      expect(decoded.reviewFields['family_name'], '测');
      expect(decoded.reviewFields['given_name'], '试公民');
      expect(decoded.fields['birth_date'], '20260630');
      expect(decoded.reviewFields['birth_date'], '2026-06-30');
    });

    test(
      'decodes update identity calls and revoke_identity with actor CID',
      () {
        final wallet = List<int>.generate(32, (i) => i + 1);
        final votingCall = [
          0x0a,
          0x02,
          ...compactVec(registryActorCid),
          ...compactVec('REGISTRAR'),
          ...citizenIdentityPayloadForTest(wallet),
          ...identityAuthorizationTailForTest(),
          ...compactU32(64),
          ...List<int>.filled(64, 0xaa),
        ];
        final candidateCall = [
          0x0a,
          0x03,
          ...compactVec(registryActorCid),
          ...compactVec('REGISTRAR'),
          ...candidateIdentityPayloadForTest(wallet),
          ...identityAuthorizationTailForTest(),
          ...compactU32(64),
          ...List<int>.filled(64, 0xbb),
        ];
        final revokeCall = [
          0x0a,
          0x04,
          ...compactVec(registryActorCid),
          ...compactVec('REGISTRAR'),
          ...compactVec('CTZN-430100-0001'),
        ];
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(votingCall)))?.action,
          'update_voting_identity',
        );
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(candidateCall)))?.action,
          'update_candidate_identity',
        );
        final revoke = PayloadDecoder.decode(
          hexOf(withSigningTail(revokeCall)),
        );
        expect(revoke?.action, 'revoke_identity');
        expect(revoke?.fields['actor_cid_number'], registryActorCid);
      },
    );

    test('严格解码首次绑定/换绑授权模板并原位填入账户', () {
      const cid = 'CTZN-430100-0001';
      final occupyTemplate = Uint8List.fromList([
        ...List<int>.filled(32, 0x44),
        ...compactVec(cid),
        ...List<int>.filled(32, 0),
        ...u64Le(0),
        ...u64Le(1800000000),
      ]);
      final occupy = PayloadDecoder.readCidOccupyAuthorizationTemplate(
        occupyTemplate,
      );
      expect(occupy?.cidNumber, cid);
      expect(occupy?.expectedBindingRevision, 0);
      expect(occupy?.expiresAt, 1800000000);
      final selectedAccount = Uint8List.fromList(List<int>.filled(32, 0xaa));
      final materialized = occupy?.materialize(selectedAccount);
      expect(materialized, isNotNull);
      expect(
        materialized!.sublist(
          32 + compactVec(cid).length,
          32 + compactVec(cid).length + 32,
        ),
        selectedAccount,
      );

      final rebindTemplate = Uint8List.fromList([
        ...List<int>.filled(32, 0x44),
        ...compactVec(cid),
        ...List<int>.filled(32, 0x55),
        ...List<int>.filled(32, 0),
        ...u64Le(7),
        ...u64Le(1800000000),
      ]);
      final rebind = PayloadDecoder.readCidRebindAuthorizationTemplate(
        rebindTemplate,
      );
      expect(rebind?.currentAccountId, '0x${'55' * 32}');
      expect(rebind?.expectedBindingRevision, 7);
      expect(rebind?.materialize(selectedAccount), isNotNull);
      expect(
        rebind?.materialize(Uint8List.fromList(List<int>.filled(32, 0x55))),
        isNull,
      );

      // 非零账户槽、尾字节和错误 revision 都必须 fail-closed。
      final nonZeroSlot = Uint8List.fromList(occupyTemplate)
        ..[32 + compactVec(cid).length] = 1;
      expect(
        PayloadDecoder.readCidOccupyAuthorizationTemplate(nonZeroSlot),
        isNull,
      );
      expect(
        PayloadDecoder.readCidOccupyAuthorizationTemplate(
          Uint8List.fromList([...occupyTemplate, 0xff]),
        ),
        isNull,
      );
      final zeroRevisionRebind = Uint8List.fromList(rebindTemplate);
      final revisionOffset = 32 + compactVec(cid).length + 32 + 32;
      zeroRevisionRebind.setRange(
        revisionOffset,
        revisionOffset + 8,
        List<int>.filled(8, 0),
      );
      expect(
        PayloadDecoder.readCidRebindAuthorizationTemplate(zeroRevisionRebind),
        isNull,
      );

      // CID 最大 32 字节，只允许单字节 Compact(mode 0)；等值的 mode 1
      // 非规范编码也必须拒绝，避免同一授权语义出现多种可签字节。
      final nonCanonicalCompact = Uint8List.fromList([
        ...occupyTemplate.sublist(0, 32),
        (cid.length << 2) | 1,
        0,
        ...occupyTemplate.sublist(33),
      ]);
      expect(
        PayloadDecoder.readCidOccupyAuthorizationTemplate(nonCanonicalCompact),
        isNull,
      );
      final nonCanonicalRebindCompact = Uint8List.fromList([
        ...rebindTemplate.sublist(0, 32),
        (cid.length << 2) | 1,
        0,
        ...rebindTemplate.sublist(33),
      ]);
      expect(
        PayloadDecoder.readCidRebindAuthorizationTemplate(
          nonCanonicalRebindCompact,
        ),
        isNull,
      );
    });

    test('decodes occupy_cid raw call data (pallet=10 call=6, 占即绑)', () {
      // 占即绑,逐字节对齐 onchina encode_occupy_cid_call:
      // [10][6] actor_cid actor_role cid account_id[32] expires_at:u64 occupy_signature:Vec(64B)。
      final accountId = List<int>.filled(32, 0xbb);
      final signature = List<int>.filled(64, 0xcc);
      final callData = [
        0x0a,
        0x06,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('CTZN-430100-0001'),
        ...accountId,
        ...u64Le(1800000000),
        ...compactU32(64),
        ...signature,
      ];

      final decoded = PayloadDecoder.decode(hexOf(callData));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'occupy_cid');
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(decoded.fields['cid_number'], 'CTZN-430100-0001');
      expect(decoded.fields['account_id'], '0x${hexLower(accountId)}');
      expect(decoded.fields['expected_binding_revision'], '0');
      expect(decoded.fields['expires_at'], '1800000000');
      expect(decoded.reviewFields['account_id'], '0x${hexLower(accountId)}');
      expect(decoded.summary, contains('CTZN-430100-0001'));
    });

    test('decodes occupy_cid with signing tail (pallet=10 call=6)', () {
      final accountId = List<int>.filled(32, 0xbb);
      final signature = List<int>.filled(64, 0xcc);
      final callData = [
        0x0a,
        0x06,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('CTZN-430100-0001'),
        ...accountId,
        ...u64Le(1800000000),
        ...compactU32(64),
        ...signature,
      ];

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'occupy_cid');
      expect(decoded.reviewFields['actor_cid_number'], registryActorCid);
      expect(decoded.reviewFields['cid_number'], 'CTZN-430100-0001');
    });

    test('decodes revoke_cid raw call data (pallet=10 call=8)', () {
      // 注册局吊销,逐字节对齐 onchina encode_revoke_cid_call:
      // [10][8] actor_cid_number + cid_number。
      final callData = [
        0x0a,
        0x08,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('CTZN-430100-0001'),
      ];

      final decoded = PayloadDecoder.decode(hexOf(callData));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'revoke_cid');
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(decoded.fields['cid_number'], 'CTZN-430100-0001');
      expect(decoded.summary, contains('CTZN-430100-0001'));
    });

    test('decodes revoke_cid with signing tail (pallet=10 call=8)', () {
      final callData = [
        0x0a,
        0x08,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('CTZN-430100-0001'),
      ];

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'revoke_cid');
      expect(decoded.reviewFields['cid_number'], 'CTZN-430100-0001');
    });

    test(
      'decodes admin_rebind_cid_account_id (call 7) and rejects self_occupy call 5',
      () {
        // 链上 call 7 = admin_rebind_cid_account_id；已删除的旧批量绑定调用不得恢复。
        // 布局:actor_cid actor_role cid new_account_id[32] revision:u64 expires:u64 signature:Vec。
        final accountId = List<int>.filled(32, 0x11);
        final signature = List<int>.filled(64, 0xdd);
        final rebindCall = [
          0x0a,
          0x07,
          ...compactVec(registryActorCid),
          ...compactVec('REGISTRAR'),
          ...compactVec('CTZN-430100-0001'),
          ...accountId,
          ...u64Le(7),
          ...u64Le(1800000000),
          ...compactU32(64),
          ...signature,
        ];
        final decoded = PayloadDecoder.decode(
          hexOf(withSigningTail(rebindCall)),
        );
        expect(decoded?.action, 'admin_rebind_cid_account_id');
        expect(decoded?.fields['actor_cid_number'], registryActorCid);
        expect(decoded?.fields['cid_number'], 'CTZN-430100-0001');
        expect(decoded?.fields['new_account_id'], '0x${hexLower(accountId)}');
        expect(decoded?.fields['expected_binding_revision'], '7');
        expect(decoded?.fields['expires_at'], '1800000000');

        // CitizenIdentity call 5 = self_occupy_cid(自助路径),不在注册局冷签 decoder 覆盖内,须拒。
        final snapshotCall = [
          0x0a,
          0x05,
          1, // Province
          ...compactVec('GZ'),
        ];
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(snapshotCall))),
          isNull,
        );
      },
    );

    test('cast_referendum 夹带旧凭证字段时拒绝解码', () {
      // 当前投票只携带 proposal_id + approve，旧凭证尾必须拒绝。
      final payload = Uint8List.fromList([
        0x15, 0x01,
        99, 0, 0, 0, 0, 0, 0, 0,
        ...List.filled(32, 0),
        0,
        0,
        1, // 只到 approve,长度 = 45。
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNull, reason: '投票不得夹带旧凭证字段');
    });

    test('decodes finalize_proposal (pallet=9 call=3)', () {
      final payload = Uint8List.fromList([0x09, 0x03, 15, 0, 0, 0, 0, 0, 0, 0]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded!.action, 'finalize_proposal');
      expect(decoded.fields['proposal_id'], '15');
    });

    test('returns null for unknown pallet', () {
      expect(PayloadDecoder.decode('0xff01'), isNull);
    });

    test('returns null for too-short input', () {
      expect(PayloadDecoder.decode('0x02'), isNull);
    });

    test('decodes onchina_admin_action with SS58 review fields', () {
      final actor = '0x${List.filled(32, '11').join()}';
      final target = '0x${List.filled(32, '22').join()}';
      const actorCidNumber = 'GD001-FRG0M-000000001-2026';
      final payload = jsonEncode({
        'domain': 'onchina_admin_governance',
        'qr_proto': 'QR_V1',
        'action_id': 'admin-action-test',
        'action_type': 'PASSKEY_REGISTER',
        'actor_cid_number': actorCidNumber,
        'actor_public_key': actor,
        'actor_province_name': '广东省',
        'target': target,
        'request_hash': '0x${List.filled(32, '33').join()}',
        'before_hash': 'none',
        'after_hash': '0x${List.filled(32, '44').join()}',
        'expires_at': 1779984120,
      });

      final decoded = PayloadDecoder.decode(hexOf(utf8.encode(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'onchina_admin_action');
      expect(decoded.fields['action_type'], '更新 Passkey');
      expect(decoded.reviewFields['actor_cid_number'], actorCidNumber);
      expect(decoded.reviewFields['actor_province_name'], '广东省');
      expect(decoded.reviewFields['actor_public_key'], actor);
      expect(decoded.reviewFields['target'], target);
      expect(decoded.reviewFields.containsKey('payload_hash'), isFalse);
    });

    test('decodes onchina admin action labels', () {
      final actor = '0x${List.filled(32, '11').join()}';
      final target = '0x${List.filled(32, '22').join()}';
      const actorCidNumber = 'GD001-FRG0M-000000001-2026';
      final cases = {
        'CREATE_ADMIN': '新增管理员',
        'UPDATE_ADMIN': '编辑管理员',
        'DELETE_ADMIN': '删除管理员',
      };

      for (final entry in cases.entries) {
        final payload = jsonEncode({
          'domain': 'onchina_admin_governance',
          'qr_proto': 'QR_V1',
          'action_id': 'admin-action-${entry.key}',
          'action_type': entry.key,
          'actor_cid_number': actorCidNumber,
          'actor_public_key': actor,
          'actor_province_name': '广东省',
          'target': target,
          'request_hash': '0x${List.filled(32, '33').join()}',
          'before_hash': 'none',
          'after_hash': '0x${List.filled(32, '44').join()}',
          'expires_at': 1779984120,
        });

        final decoded = PayloadDecoder.decode(hexOf(utf8.encode(payload)));

        expect(decoded, isNotNull);
        expect(decoded!.fields['action_type'], entry.value);
      }
    });

    test('rejects legacy onchina admin action without actor CID', () {
      final payload = jsonEncode({
        'domain': 'onchina_admin_governance',
        'qr_proto': 'QR_V1',
        'action_type': 'CREATE_ADMIN',
        'actor_public_key': '0x${List.filled(32, '11').join()}',
        'actor_province_name': '广东省',
        'target': '0x${List.filled(32, '22').join()}',
        'before_hash': 'none',
        'after_hash': '0x${List.filled(32, '44').join()}',
      });

      expect(PayloadDecoder.decode(hexOf(utf8.encode(payload))), isNull);
    });

    test(
      'decodes clearing bank binding and switching with institution CID',
      () {
        const currentBankCid = 'AH001-SCB0N-202605010-2026';
        const newBankCid = 'GD001-SCB0N-202605011-2026';
        final bind = PayloadDecoder.decode(
          hexOf(withSigningTail([19, 30, ...compactVec(currentBankCid)])),
        );
        final switching = PayloadDecoder.decode(
          hexOf(withSigningTail([19, 33, ...compactVec(newBankCid)])),
        );

        expect(bind?.action, 'bind_clearing_bank');
        expect(bind?.fields, {'bank_cid_number': currentBankCid});
        expect(switching?.action, 'switch_clearing_bank');
        expect(switching?.fields, {'new_bank_cid_number': newBankCid});
      },
    );

    test(
      'decodes clearing bank deposit and withdrawal without bank account',
      () {
        final deposit = PayloadDecoder.decode(
          hexOf(withSigningTail([19, 31, ...compactU32(12345)])),
        );
        final withdrawal = PayloadDecoder.decode(
          hexOf(withSigningTail([19, 32, ...compactU32(500)])),
        );

        expect(deposit?.action, 'deposit_clearing_bank');
        expect(deposit?.fields, {'amount_yuan': '123.45 元'});
        expect(withdrawal?.action, 'withdraw_clearing_bank');
        expect(withdrawal?.fields, {'amount_yuan': '5.00 元'});
      },
    );

    test('decodes clearing bank register node call', () {
      const cidNumber = 'AH001-SZG1Z-883241719-2026';
      const peerId = '12D3KooWABCDEFG1234567890abcdefghijk';
      const domain = 'l2.example.com';
      final payload = Uint8List.fromList([
        19,
        50,
        ...compactVec(cidNumber),
        ...compactVec('CLEARING_OPERATOR'),
        ...compactVec(peerId),
        ...compactVec(domain),
        ...u16Le(9944),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'register_clearing_bank');
      expect(decoded.fields['actor_cid_number'], cidNumber);
      expect(decoded.fields['peer_id'], peerId);
      expect(decoded.fields['rpc_domain'], domain);
      expect(decoded.fields['rpc_port'], '9944');
    });

    test('decodes clearing bank endpoint update call', () {
      const cidNumber = 'AH001-SZG1Z-883241719-2026';
      const domain = 'new-l2.example.com';
      final payload = Uint8List.fromList([
        19,
        51,
        ...compactVec(cidNumber),
        ...compactVec('CLEARING_OPERATOR'),
        ...compactVec(domain),
        ...u16Le(443),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'update_clearing_bank_endpoint');
      expect(decoded.fields['actor_cid_number'], cidNumber);
      expect(decoded.fields['new_domain'], domain);
      expect(decoded.fields['new_port'], '443');
    });

    test('decodes clearing bank unregister call', () {
      const cidNumber = 'AH001-SZG1Z-883241719-2026';
      final payload = Uint8List.fromList([
        19,
        52,
        ...compactVec(cidNumber),
        ...compactVec('CLEARING_OPERATOR'),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'unregister_clearing_bank');
      expect(decoded.fields['actor_cid_number'], cidNumber);
    });

    test(
      'decodes clearing bank fee proposal with CID and institution account',
      () {
        final institutionAccount = List<int>.filled(32, 0x55);
        final payload = [
          19,
          40,
          ...compactVec(nrcActorCid),
          ...compactVec('CLEARING_OPERATOR'),
          ...institutionAccount,
          ...u32Le(35),
        ];
        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
        expect(decoded?.action, 'propose_l2_fee_rate');
        expect(decoded?.fields['actor_cid_number'], nrcActorCid);
        expect(
          decoded?.fields['institution_account_id'],
          '0x${hexLower(institutionAccount)}',
        );
        expect(decoded?.fields['new_rate_bp'], '35');
      },
    );

    test('decodes AddressRegistry calls with actor CID', () {
      final catalogHash = List<int>.filled(32, 0x77);
      final catalog = [
        33,
        0,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('2026.07'),
        ...catalogHash,
      ];
      final address = [
        33,
        3,
        ...compactVec(registryActorCid),
        ...compactVec('REGISTRAR'),
        ...compactVec('GD'),
        ...compactVec('001'),
        ...compactVec('001001'),
        ...compactVec('ROAD'),
        ...compactVec('88'),
        ...compactVec('一号楼'),
      ];
      final catalogDecoded = PayloadDecoder.decode(
        hexOf(withSigningTail(catalog)),
      );
      expect(catalogDecoded?.action, 'set_address_catalog_version');
      expect(catalogDecoded?.fields['actor_cid_number'], registryActorCid);
      final addressDecoded = PayloadDecoder.decode(
        hexOf(withSigningTail(address)),
      );
      expect(addressDecoded?.action, 'set_address');
      expect(addressDecoded?.fields['address_local_no'], '88');
      expect(addressDecoded?.fields['address_detail'], '一号楼');
    });

    test('decodes clearing bank decrypt challenge', () {
      const cidNumber = 'AH001-SZG1Z-883241719-2026';
      final idBytes = List<int>.filled(32, 0);
      final rawId = ascii.encode(cidNumber);
      for (var i = 0; i < rawId.length; i++) {
        idBytes[i] = rawId[i];
      }
      final payload = Uint8List.fromList([
        // ADR-026 Phase 2 二进制前缀 GMB || 0x19。
        0x47, 0x4D, 0x42, 0x19,
        ...idBytes,
        ...List<int>.filled(32, 0xAA),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...List<int>.filled(16, 0xBB),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(payload));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'decrypt_admin');
      expect(decoded.fields['cid_number'], cidNumber);
      expect(decoded.summary, contains('解密清算行管理员'));
    });

    test('rejects legacy 48-byte clearing bank decrypt challenge', () {
      const cidNumber = 'AH001-SZG1Z-883241719-2026';
      final idBytes = List<int>.filled(48, 0);
      final rawId = ascii.encode(cidNumber);
      for (var i = 0; i < rawId.length; i++) {
        idBytes[i] = rawId[i];
      }
      final payload = Uint8List.fromList([
        0x47,
        0x4D,
        0x42,
        0x19,
        ...idBytes,
        ...List<int>.filled(32, 0xAA),
        ...List<int>.filled(8, 0),
        ...List<int>.filled(16, 0xBB),
      ]);

      expect(
        PayloadDecoder.decode(hexOf(payload)),
        isNull,
        reason: '目标态只接受协议单源定义的 32B 机构 CID 槽位',
      );
    });

    test('decodes propose_sweep_to_main CID + institution account', () {
      final institutionAccount = List<int>.filled(32, 0x66);
      const amount = 10000;
      final amountBytes = List<int>.filled(16, 0);
      amountBytes[0] = amount & 0xff;
      amountBytes[1] = (amount >> 8) & 0xff;

      final payload = Uint8List.fromList([
        0x11,
        0x02,
        ...compactVec(nrcActorCid),
        ...compactVec('COMMITTEE_MEMBER'),
        ...institutionAccount,
        ...amountBytes,
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_sweep_to_main');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(
        decoded.fields['institution_account_id'],
        '0x${hexLower(institutionAccount)}',
      );
      expect(
        decoded.fields['operation_fee_payer_description'],
        '$nrcActorCid 的链上费用账户',
      );
      expect(
        decoded.fields['execution_fee_payer_description'],
        '$nrcActorCid 的链上费用账户',
      );
      expect(decoded.fields['amount_yuan'], '100.00 元');
    });

    test('rejects legacy 48-byte sweep account payload', () {
      final legacySubject = List<int>.filled(48, 0);
      final amountBytes = List<int>.filled(16, 0);
      amountBytes[0] = 0x10;

      final payload = Uint8List.fromList([
        0x11,
        0x02,
        ...legacySubject,
        ...amountBytes,
      ]);

      expect(
        PayloadDecoder.decode(hexOf(withSigningTail(payload))),
        isNull,
        reason: '目标态只接受机构多签 AccountId32,不兼容旧 48B 主体',
      );
    });

    test('decodes propose_transfer for institution CID + account', () {
      final institutionAccount = List<int>.filled(32, 0x66);
      final beneficiary = List<int>.filled(32, 0x44);
      final payload = Uint8List.fromList([
        0x11,
        0x00,
        0x01, // Option::Some(actor_cid_number)
        ...compactVec(nrcActorCid),
        0x01, // Option::Some(proposer_role_code)
        ...compactVec('COMMITTEE_MEMBER'),
        ...institutionAccount,
        ...beneficiary,
        ...u128LeForTest(BigInt.from(12345)),
        0x10,
        ...utf8.encode('test'),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_transfer');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(decoded.fields['proposer_role_code'], 'COMMITTEE_MEMBER');
      expect(
        decoded.fields['institution_account_id'],
        '0x${hexLower(institutionAccount)}',
      );
      expect(
        decoded.fields['operation_fee_payer_description'],
        '$nrcActorCid 的链上费用账户',
      );
      expect(
        decoded.fields['execution_fee_payer_description'],
        '$nrcActorCid 的链上费用账户',
      );
      expect(decoded.fields['amount_yuan'], '123.45 元');
      expect(decoded.fields['remark'], 'test');
    });

    test('rejects legacy 48-byte transfer account payload', () {
      // 旧布局 [org:u8][subject:48B]，目标态 Option<CID> + AccountId32 不兼容。
      final payload = Uint8List.fromList([
        0x11,
        0x00,
        0x02,
        ...List<int>.filled(48, 0x22),
        ...List<int>.filled(32, 0x44),
        ...u128LeForTest(BigInt.one),
        0x00,
      ]);

      expect(
        PayloadDecoder.decode(hexOf(withSigningTail(payload))),
        isNull,
        reason: '目标态只接受机构多签 AccountId32,不兼容旧 48B 主体',
      );
    });

    test('Compact encoding mode 1 (two-byte)', () {
      final dest = Keyring.sr25519.fromSeed(Uint8List(32));
      dest.ss58Format = 2027;
      final destBytes = dest.bytes().toList();
      final remark = List.filled(64, 'a').join();
      final remarkBytes = utf8.encode(remark);

      final payload = Uint8List.fromList([
        0x04,
        0x00,
        ...destBytes,
        ...u128LeForTest(BigInt.from(234)),
        ...compactU32(remarkBytes.length), // Compact(64) two-byte mode
        ...remarkBytes,
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNotNull);
      expect(decoded!.fields['amount_yuan'], '2.34 元');
      expect(decoded.fields['remark'], remark);
    });
    // Phase 3(2026-04-22)新增:8 个 execute / cleanup / cancel 类 call。
    // 链端签名统一 `fn <name>(origin, proposal_id: u64)`,
    // 冷钱包走通用 _decodeProposalIdOnly 解码器。
    //
    // 所有分支的 fields 按 Registry 统一为
    //   { proposal_id: <decimal string> }
    // 保证节点 Tauri UI / citizenapp 发出的手动兜底 QR 在冷钱包走 🟢 绿色。
    Uint8List buildProposalIdPayload(int palletIdx, int callIdx, int id) {
      return Uint8List.fromList([
        palletIdx,
        callIdx,
        id & 0xff,
        (id >> 8) & 0xff,
        (id >> 16) & 0xff,
        (id >> 24) & 0xff,
        (id >> 32) & 0xff,
        (id >> 40) & 0xff,
        (id >> 48) & 0xff,
        (id >> 56) & 0xff,
      ]);
    }

    String encodeHex(Uint8List bytes) =>
        '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

    test('decodes retry_passed_proposal (pallet=9 call=4)', () {
      // Phase 4(2026-05-02): 业务 pallet 的 execute_xxx wrapper 全部物理删除,
      // 手动重试统一收口至 VotingEngine::retry_passed_proposal(9.4)。
      final payload = buildProposalIdPayload(0x09, 0x04, 100);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'retry_passed_proposal');
      expect(decoded.fields['proposal_id'], '100');
      expect(decoded.summary, contains('#100'));
    });

    test(
      'decodes cancel_passed_proposal with empty reason (pallet=9 call=5)',
      () {
        // SCALE: [0x09][0x05][proposal_id u64_le][Compact<u32> 0]
        final builder = BytesBuilder()
          ..add([0x09, 0x05])
          ..add(
            Uint8List.fromList(
              buildProposalIdPayload(0x09, 0x05, 401).sublist(2, 10),
            ),
          )
          ..add([0x00]); // Compact<u32> 0 (空 reason)
        final payload = builder.toBytes();
        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
        expect(decoded, isNotNull);
        expect(decoded!.action, 'cancel_passed_proposal');
        expect(decoded.fields['proposal_id'], '401');
        expect(decoded.fields['reason'], '');
      },
    );

    test(
      'decodes cancel_passed_proposal with utf8 reason (pallet=9 call=5)',
      () {
        final reason = utf8.encode('密钥不可执行');
        // Compact<u32> for reason length (small => single byte mode, len << 2)
        final compactLen = reason.length << 2;
        final builder = BytesBuilder()
          ..add([0x09, 0x05])
          ..add(
            Uint8List.fromList(
              buildProposalIdPayload(0x09, 0x05, 402).sublist(2, 10),
            ),
          )
          ..add([compactLen])
          ..add(reason);
        final payload = builder.toBytes();
        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
        expect(decoded, isNotNull);
        expect(decoded!.action, 'cancel_passed_proposal');
        expect(decoded.fields['proposal_id'], '402');
        expect(decoded.fields['reason'], '密钥不可执行');
      },
    );

    test('decodes both GRANDPA key change paths', () {
      final newPublicKey = List<int>.generate(32, (index) => index + 1);
      final common = <int>[
        ...compactVec(nrcActorCid),
        ...compactVec('COMMITTEE_MEMBER'),
        ...newPublicKey,
        ...u64Le(7),
        ...u32Le(1234),
      ];
      final emergency = PayloadDecoder.decode(
        hexOf(
          withSigningTail([
            0x0f,
            0x00,
            ...common,
            ...List<int>.filled(64, 0x11),
          ]),
        ),
      );
      expect(emergency, isNotNull);
      expect(emergency!.action, 'propose_emergency_grandpa_key_recovery');
      expect(emergency.fields['actor_role_code'], 'COMMITTEE_MEMBER');
      expect(emergency.fields['proof_nonce'], '7');
      expect(emergency.fields['proof_expires_at'], '1234');

      final routine = PayloadDecoder.decode(
        hexOf(
          withSigningTail([
            0x0f,
            0x01,
            ...common,
            ...List<int>.filled(64, 0x22),
            ...List<int>.filled(64, 0x33),
          ]),
        ),
      );
      expect(routine, isNotNull);
      expect(routine!.action, 'schedule_grandpa_key_rotation');
      expect(routine.fields['new_public_key'], hexOf(newPublicKey));
    });

    test('rejects deleted business wrappers (pallet=17/13/12/15)', () {
      // Phase 4 物理删除的 call_index 不应再被解码识别。
      final cases = <List<int>>[
        [0x11, 0x03], // MultisigTransfer(17) execute_transfer
        [0x11, 0x04], // execute_safety_fund_transfer
        [0x11, 0x05], // execute_sweep_to_main
        [0x0d, 0x01], // ResolutionDestroy(13) execute_destroy
        [0x0c, 0x01], // RuntimeUpgrade(12) call_index=1 留洞;冷钱包不解码协议升级
        [0x0f, 0x02], // cancel_failed_replace_grandpa_key
      ];
      for (final c in cases) {
        final payload = buildProposalIdPayload(c[0], c[1], 999);
        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
        expect(
          decoded,
          isNull,
          reason: 'pallet=${c[0]} call=${c[1]} 应已废弃,decoder 拒绝',
        );
      }
    });

    test('decodes personal propose_admin_set_change only', () {
      final account = List<int>.generate(32, (i) => 0x80 + i);
      for (final item in [
        (29, 0, 'PMUL', 2, 2, 'propose_personal_admin_set_change'),
      ]) {
        final adminAccounts = List<List<int>>.generate(
          item.$4,
          (i) => List<int>.filled(32, 0x11 + i),
        );
        final payload = Uint8List.fromList([
          item.$1,
          item.$2,
          ...InstitutionCode.codeBytes(item.$3),
          ...account,
          item.$4 << 2, // Compact(admins.length)
          for (var i = 0; i < adminAccounts.length; i++)
            ...adminPerson(
              adminAccounts[i],
              i == 0 ? '张' : '管理',
              i == 0 ? '三' : '员',
            ),
          ...u32Le(item.$5),
        ]);

        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

        expect(decoded, isNotNull);
        expect(decoded!.action, item.$6);
        expect(
          decoded.fields['institution_code'],
          InstitutionCode.codeLabel(item.$3),
        );
        expect(decoded.fields['account_id'], '0x${hexLower(account)}');
        expect(jsonDecode(decoded.fields['admins']!) as List<dynamic>, [
          {
            'account_id': '0x${hexLower(adminAccounts[0])}',
            'cid_number': '',
            'family_name': '张',
            'given_name': '三',
          },
          {
            'account_id': '0x${hexLower(adminAccounts[1])}',
            'cid_number': '',
            'family_name': '管理',
            'given_name': '员',
          },
        ]);
        expect(decoded.reviewFields['admins'], contains('张三('));
        expect(decoded.reviewFields['admins'], contains('管理员('));
        expect(decoded.reviewFields['new_threshold'], '${item.$5}/${item.$4}');
        expect(decoded.summary, contains('管理员集合变更'));
      }

      final admin1 = List<int>.filled(32, 0x11);
      final admin2 = List<int>.filled(32, 0x22);
      final personalPayload = Uint8List.fromList([
        0x07,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        0x08,
        ...admin1,
        ...admin2,
        ...u32Le(2),
      ]);
      expect(
        PayloadDecoder.decode(hexOf(withSigningTail(personalPayload))),
        isNull,
      );
    });

    test('rejects propose_admin_set_change without new_threshold', () {
      final account = List<int>.generate(32, (i) => 0x80 + i);
      final payload = Uint8List.fromList([
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        0x08,
        ...adminPerson(List<int>.filled(32, 0x11), '张', '三'),
        ...adminPerson(List<int>.filled(32, 0x22), '李', '四'),
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change with trailing bytes', () {
      final account = List<int>.generate(32, (i) => 0x80 + i);
      final payload = Uint8List.fromList([
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        0x08,
        ...adminPerson(List<int>.filled(32, 0x11), '张', '三'),
        ...adminPerson(List<int>.filled(32, 0x22), '李', '四'),
        ...u32Le(2),
        0xff,
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change below majority threshold', () {
      final account = List<int>.generate(32, (i) => 0x80 + i);
      final payload = Uint8List.fromList([
        0x1d, 0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        0x0c, // Compact(3)
        ...adminPerson(List<int>.filled(32, 0x11), '张', '三'),
        ...adminPerson(List<int>.filled(32, 0x22), '李', '四'),
        ...adminPerson(List<int>.filled(32, 0x33), '王', '五'),
        ...u32Le(1),
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change legacy pure-account layout', () {
      final account = List<int>.filled(32, 0x80);
      final payload = <int>[
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        ...compactU32(2),
        ...List<int>.filled(32, 0x11),
        ...List<int>.filled(32, 0x22),
        ...u32Le(2),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change legacy combined-name layout', () {
      final account = List<int>.filled(32, 0x80);
      final payload = <int>[
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        ...compactU32(2),
        ...compactVec('张三'),
        ...List<int>.filled(32, 0x11),
        ...compactVec('李四'),
        ...List<int>.filled(32, 0x22),
        ...u32Le(2),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change duplicate account_id', () {
      final account = List<int>.filled(32, 0x80);
      final duplicate = List<int>.filled(32, 0x11);
      final payload = <int>[
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        ...compactU32(2),
        ...adminPerson(duplicate, '张', '三'),
        ...adminPerson(duplicate, '李', '四'),
        ...u32Le(2),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects propose_admin_set_change malformed UTF-8 name', () {
      final account = List<int>.filled(32, 0x80);
      final payload = <int>[
        0x1d,
        0x00,
        ...InstitutionCode.codeBytes('PMUL'),
        ...account,
        ...compactU32(2),
        ...List<int>.filled(32, 0x11),
        ...compactVec(''),
        ...compactU32(1),
        0xff,
        ...compactVec('三'),
        ...adminPerson(List<int>.filled(32, 0x22), '李', '四'),
        ...u32Le(2),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('rejects deleted institution admin change call', () {
      final account = List<int>.generate(32, (i) => 0x40 + i);
      final payload = Uint8List.fromList([
        0x0c, 0x00,
        ...InstitutionCode.codeBytes('NRC'), // 国家储委会固定治理档 19/13
        ...account,
        0x4c, // Compact(19)
        for (var i = 0; i < 19; i++) ...List<int>.filled(32, i + 1),
        ...u32Le(12),
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('decodes CID-level admin activation payload', () {
      const cidNumber = 'GD001-CGOVM-000000001-2026';
      final cidBytes = utf8.encode(cidNumber);
      final cidSlot = <int>[
        ...cidBytes,
        ...List<int>.filled(32 - cidBytes.length, 0),
      ];
      final signerPublicKey = List<int>.filled(32, 0xaa);
      final payload = Uint8List.fromList([
        // ADR-026 Phase 2 二进制前缀 GMB || 0x18。
        0x47, 0x4D, 0x42, 0x18,
        ...cidSlot,
        ...InstitutionCode.codeBytes('CGOV'),
        0x00, // kind = PublicInstitution
        ...signerPublicKey,
        1, 0, 0, 0, 0, 0, 0, 0, // timestamp u64 LE
        ...List<int>.filled(16, 0),
      ]);

      final decoded = PayloadDecoder.decode(encodeHex(payload));

      expect(decoded, isNotNull);
      expect(decoded!.action, 'activate_admin_account');
      expect(decoded.fields['cid_number'], cidNumber);
      expect(decoded.fields['institution_code'], 'CGOV');
      expect(
        decoded.fields['signer_public_key'],
        '0x${hexLower(signerPublicKey)}',
      );
      expect(decoded.fields.containsKey('account_id'), isFalse);
      expect(decoded.reviewFields['cid_number'], cidNumber);
      expect(
        decoded.reviewFields['signer_public_key'],
        '0x${hexLower(signerPublicKey)}',
      );
    });

    test('rejects legacy account-shaped admin activation payload', () {
      final account = List<int>.generate(32, (i) => 0x20 + i);
      final payload = Uint8List.fromList([
        0x47,
        0x4D,
        0x42,
        0x18,
        ...account,
        ...InstitutionCode.codeBytes('CGOV'),
        0x00,
        ...List<int>.filled(32, 0xaa),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...List<int>.filled(16, 0),
      ]);

      expect(PayloadDecoder.decode(encodeHex(payload)), isNull);
    });

    test('rejects admin activation when CID and institution code mismatch', () {
      const cidNumber = 'LN001-NRC0G-944805165-2026';
      final cidBytes = utf8.encode(cidNumber);
      final payload = Uint8List.fromList([
        0x47,
        0x4D,
        0x42,
        0x18,
        ...cidBytes,
        ...List<int>.filled(32 - cidBytes.length, 0),
        ...InstitutionCode.codeBytes('CGOV'),
        0x00,
        ...List<int>.filled(32, 0xaa),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...List<int>.filled(16, 0),
      ]);

      expect(PayloadDecoder.decode(encodeHex(payload)), isNull);
    });

    test('admin activation accepts both explicit unincorporated routes', () {
      const cidNumber = 'GD001-SFGT1-000000001-2026';
      final cidBytes = utf8.encode(cidNumber);
      for (final kind in const [0, 1]) {
        final payload = Uint8List.fromList([
          0x47,
          0x4D,
          0x42,
          0x18,
          ...cidBytes,
          ...List<int>.filled(32 - cidBytes.length, 0),
          ...InstitutionCode.codeBytes('SFGT'),
          kind,
          ...List<int>.filled(32, 0xaa),
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          ...List<int>.filled(16, 0),
        ]);

        expect(PayloadDecoder.decode(encodeHex(payload)), isNotNull);
      }
    });

    test(
      'rejects personal multisig admin activation as institution payload',
      () {
        const cidNumber = 'GD001-PMUL1-000000001-2026';
        final cidBytes = utf8.encode(cidNumber);
        final payload = Uint8List.fromList([
          0x47,
          0x4D,
          0x42,
          0x18,
          ...cidBytes,
          ...List<int>.filled(32 - cidBytes.length, 0),
          ...InstitutionCode.codeBytes('PMUL'),
          0x02,
          ...List<int>.filled(32, 0xaa),
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          ...List<int>.filled(16, 0),
        ]);

        expect(PayloadDecoder.decode(encodeHex(payload)), isNull);
      },
    );

    test('rejects institution-account admin set change calls', () {
      final account = List<int>.generate(32, (i) => 0x30 + i);
      final admin1 = List<int>.filled(32, 0x44);
      final admin2 = List<int>.filled(32, 0x55);

      for (final item in const [(0x1b, 'CGOV'), (0x1c, 'SFLP')]) {
        final payload = Uint8List.fromList([
          item.$1,
          0x00,
          ...InstitutionCode.codeBytes(item.$2),
          ...account,
          0x08,
          ...admin1,
          ...admin2,
          ...u32Le(2),
        ]);

        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

        expect(decoded, isNull);
      }
    });

    test('rejects legacy 48-byte admin account payload', () {
      // 旧布局 [org:u8][subject:48B]。新布局 [institution_code:4B][account:32B],
      // 48B 主体下偏移全部错位 → 签名尾校验失败 → null。
      final legacySubject = List<int>.filled(48, 0x66);
      final admin1 = List<int>.filled(32, 0x11);
      final admin2 = List<int>.filled(32, 0x22);

      final payload = Uint8List.fromList([
        0x0c,
        0x00,
        0x04,
        ...legacySubject,
        0x08,
        ...admin1,
        ...admin2,
        ...u32Le(2),
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('PublicManage 保留 call 4 空洞并拒绝旧载荷', () {
      final payload = buildProposalIdPayload(0x1e, 0x04, 500);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNull);
    });

    test('decodes public institution close action', () {
      // 机构关闭提案只携带机构 CID、岗位码、机构账户和受益账户。
      final institutionAccount = List<int>.filled(32, 0x11);
      final beneficiary = List<int>.filled(32, 0x22);
      final payload = <int>[
        0x1e, 0x01, // PublicManage.propose_close_public_institution
        ...compactVec(registryActorCid),
        ...compactVec('RLEGAL'),
        ...institutionAccount,
        ...beneficiary,
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_close_public_institution');
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(
        decoded.fields['institution_account_id'],
        '0x${hexLower(institutionAccount)}',
      );
      expect(
        decoded.fields['beneficiary_account_id'],
        '0x${hexLower(beneficiary)}',
      );
    });

    test('rejects unknown out-of-range pallet index', () {
      // 新号表 pallet 连续 0..34(SquarePost=34);0x23=35 不存在 → decoder 拒签。
      // (旧“淘汰机构生命周期 pallet 17”已随连续化消失,17 现为 MultisigTransfer。)
      final payload = Uint8List.fromList([
        0x23,
        0x01,
        ...List<int>.filled(32, 0x11),
        ...List<int>.filled(32, 0x22),
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNull);
    });

    test('decodes SquarePost platform price proposal with Chinese fields', () {
      const actorCid = 'GD001-SFGQ0-000000001-2026';
      final payload = <int>[
        34,
        5,
        ...compactVec(actorCid),
        ...compactVec('GENESIS_PRODUCT_MANAGER'),
        1,
        ...u128LeForTest(BigInt.from(123456)),
      ];
      final decoded = PayloadDecoder.decode(hexOf(payload));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_set_platform_price');
      expect(decoded.fields['actor_cid_number'], actorCid);
      expect(decoded.fields['membership_level'], '民主会员');
      expect(decoded.fields['new_price_fen'], contains('123456 分'));
    });

    test('strictly decodes all Hot/Cold SquarePost wallet calls', () {
      const creatorCid = 'CN220-CTZN2-198805200-2026';
      final calls = <({List<int> callData, String action})>[
        (
          callData: [
            34,
            0,
            ...compactVec('post-1'),
            1,
            ...List<int>.filled(32, 0x22),
            ...compactVec('receipt-1'),
          ],
          action: 'publish_post',
        ),
        (
          callData: [34, 1, 0, 0, 2, ...u128LeForTest(BigInt.from(599900))],
          action: 'subscribe',
        ),
        (callData: [34, 2, 1, ...compactVec(creatorCid)], action: 'cancel'),
        (
          callData: [
            34,
            3,
            ...compactU32(1),
            ...compactVec('t1'),
            ...compactVec('核心支持者'),
            ...compactU32(2),
            0,
            ...u128LeForTest(BigInt.from(990)),
            2,
            ...u128LeForTest(BigInt.from(9990)),
          ],
          action: 'set_creator_plans',
        ),
        (
          callData: [
            34,
            4,
            1,
            ...compactVec(creatorCid),
            1,
            ...compactVec('t1'),
            1,
            ...u128LeForTest(BigInt.from(2990)),
          ],
          action: 'change_subscription_plan',
        ),
        (
          callData: [34, 6, ...compactVec('t1'), ...compactVec('铁杆粉丝')],
          action: 'update_creator_tier_name',
        ),
      ];

      for (final item in calls) {
        final decoded = PayloadDecoder.decode(
          hexOf(withSigningTail(item.callData)),
        );
        expect(decoded?.action, item.action, reason: item.action);
      }
    });

    test(
      'rejects malformed SquarePost wallet calls instead of changing route',
      () {
        const creatorCid = 'CN220-CTZN2-198805200-2026';
        final issuerPlanMismatch = [
          34,
          1,
          0, // Platform issuer
          1, // Creator plan
          ...compactVec('t1'),
          0,
          ...u128LeForTest(BigInt.one),
        ];
        final duplicatePeriod = [
          34,
          3,
          ...compactU32(1),
          ...compactVec('t1'),
          ...compactVec('支持者'),
          ...compactU32(2),
          0,
          ...u128LeForTest(BigInt.one),
          0,
          ...u128LeForTest(BigInt.from(2)),
        ];
        final emptyReceipt = [
          34,
          0,
          ...compactVec('post-1'),
          0,
          ...List<int>.filled(32, 0x11),
          ...compactU32(0),
        ];
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(issuerPlanMismatch))),
          isNull,
        );
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(duplicatePeriod))),
          isNull,
        );
        expect(
          PayloadDecoder.decode(hexOf(withSigningTail(emptyReceipt))),
          isNull,
        );
        expect(
          PayloadDecoder.decode(hexOf([34, 2, 1, ...compactVec(creatorCid)])),
          isNull,
          reason: '钱包账户冷签必须携带完整 SigningPayload 尾',
        );
      },
    );

    test('rejects invalid SquarePost platform price proposal payloads', () {
      const actorCid = 'GD001-SFGQ0-000000001-2026';
      List<int> call(int level, BigInt price) => <int>[
        34,
        5,
        ...compactVec(actorCid),
        ...compactVec('GENESIS_PRODUCT_MANAGER'),
        level,
        ...u128LeForTest(price),
      ];
      expect(PayloadDecoder.decode(hexOf(call(3, BigInt.one))), isNull);
      expect(PayloadDecoder.decode(hexOf(call(0, BigInt.zero))), isNull);
      expect(
        PayloadDecoder.decode(hexOf([...call(2, BigInt.one), 0xff])),
        isNull,
      );
      expect(
        PayloadDecoder.decode(hexOf(call(2, BigInt.one)..removeLast())),
        isNull,
      );
    });

    test('decodes personal close action as propose_close_personal', () {
      final payload = Uint8List.fromList([
        0x07, 0x01, // PersonalManage.propose_close
        ...List<int>.filled(32, 0x33),
        ...List<int>.filled(32, 0x44),
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_close_personal');
      expect(decoded.fields.keys.toList(), [
        'account_id',
        'beneficiary_account_id',
      ]);
    });
    // 协议升级 propose_runtime_upgrade / developer_direct_upgrade 的 SCALE decoder 已删
    // (call_data 含 600KB+ WASM,塞不进 QR;server 在 QR 里只放 32 字节 blake2
    // 哈希,decoder 路径不可达)。改走 OfflineSignService 的"哈希直签例外"。
    // 相关回归测试见 citizenwallet/test/signer/offline_sign_service_*_test.dart。
    test('已关闭的机构直接创建 call 5 必须拒绝解码', () {
      for (final pallet in [0x1e, 0x1f]) {
        final payload = Uint8List.fromList([
          pallet,
          0x05,
          ...compactVec('AH001-SCB0N-202605010-2026'),
        ]);
        expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
      }
    });

    List<int> buildPublicInstitutionAdminsForGovernance() {
      return <int>[
        ...compactU32(2),
        ...adminPerson(
          List<int>.filled(32, 0x31),
          '张',
          '三',
          citizenCidNumber: 'CN220-CTZN2-198805200-2026',
        ),
        ...adminPerson(List<int>.filled(32, 0x32), '', ''),
      ];
    }

    List<int> buildPrivateInstitutionAdminsForGovernance() {
      return <int>[
        ...compactU32(2),
        ...adminPerson(
          List<int>.filled(32, 0x31),
          '张',
          '三',
          citizenCidNumber: 'CN220-CTZN2-198805200-2026',
        ),
        ...adminPerson(List<int>.filled(32, 0x32), '李', '四'),
      ];
    }

    List<int> appendGovernanceCallTail(List<int> payload, String actorCid) {
      return <int>[
        ...payload,
        ...compactVec(actorCid),
        ...compactVec('RCHAIR'),
      ];
    }

    test('decodes propose_public_institution_governance 替换管理员集合', () {
      const cidNumber = 'GZ001-SFAS1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1e,
          0x08,
          ...compactVec(cidNumber),
          0x00, // InstitutionGovernanceAction::ReplaceAdmins
          ...buildPublicInstitutionAdminsForGovernance(),
        ], cidNumber),
      );

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_public_institution_governance');
      expect(decoded.fields['cid_number'], cidNumber);
      expect(decoded.fields['governance_action'], '替换管理员集合');
      expect(decoded.fields['governance_detail'], contains('2 名管理员'));
      expect(decoded.fields['actor_cid_number'], cidNumber);
      expect(decoded.fields['fee_payer_description'], '$cidNumber 的链上费用账户');
      expect(decoded.reviewFields['governance_detail'], contains('资料待完善'));
    });

    test('decodes propose_public_institution_governance 解除法定代表人', () {
      const cidNumber = 'GZ001-SFAS1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1e,
          0x08,
          ...compactVec(cidNumber),
          0x01, // InstitutionGovernanceAction::MutateRolesAndAssignments
          ...compactU32(0), // role_changes
          ...compactU32(0), // assignment_changes
          0x01, // Option<InstitutionLegalRepresentativeChange>::Some
          0x01, // InstitutionLegalRepresentativeChange::Clear
        ], cidNumber),
      );

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_public_institution_governance');
      expect(decoded.fields['governance_action'], '岗位/任职治理');
      expect(decoded.fields['governance_detail'], contains('含法定代表人解除'));
    });

    test('decodes 新协议岗位创建及其权限和初始任职', () {
      const cidNumber = 'GZ001-SFAS1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1e,
          0x08,
          ...compactVec(cidNumber),
          0x01, // InstitutionGovernanceAction::MutateRolesAndAssignments
          ...compactU32(1), // role_mutations
          0x00, // InstitutionRoleMutation::Create
          ...compactVec('财务负责人'),
          0x01, // term_required
          ...compactU32(2), // permissions
          ...compactVec('pub-mgmt'),
          ...u32Le(3),
          0x00, // Propose
          ...compactVec('pub-mgmt'),
          ...u32Le(3),
          0x01, // Vote
          ...compactU32(1), // initial assignments
          ...List<int>.filled(32, 0x31),
          ...u32Le(100),
          ...u32Le(200),
          0x05, // InstitutionGovernance
          ...compactVec('proposal-42'),
          0x00, // Active
          ...compactU32(0), // assignment_changes
          0x00, // legal_representative_change=None
        ], cidNumber),
      );

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_public_institution_governance');
      expect(decoded.fields['governance_detail'], contains('1 个岗位生命周期操作'));
    });

    test('旧 InstitutionRoleChange 布局必须拒绝解码', () {
      const cidNumber = 'GZ001-SFAS1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1e,
          0x08,
          ...compactVec(cidNumber),
          0x01,
          ...compactU32(1),
          ...compactVec('OLD_ROLE'),
          ...compactVec('旧岗位'),
          0x00,
          0x00,
          ...compactU32(0),
          0x00,
        ], cidNumber),
      );

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });

    test('decodes register_private_institution_admins 注册局直接登记管理员', () {
      const cidNumber = 'GD001-COMP1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1f,
          0x09,
          ...compactVec(cidNumber),
          ...buildPrivateInstitutionAdminsForGovernance(),
        ], registryActorCid),
      );

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'register_private_institution_admins');
      expect(decoded.fields['cid_number'], cidNumber);
      expect(decoded.fields['admins_len'], '2');
      expect(
        decoded.reviewFields['admins'],
        contains(
          '张三 / CN220-CTZN2-198805200-2026'
          '(${ss58FromBytes(List<int>.filled(32, 0x31))})',
        ),
      );
      expect(decoded.fields['actor_cid_number'], registryActorCid);
      expect(
        decoded.fields['fee_payer_description'],
        '$registryActorCid 的链上费用账户',
      );
    });

    test('decodes register_public_institution_admins 公民资料允许暂空', () {
      const cidNumber = 'GZ001-SFAS1-123456789-2026';
      final payload = Uint8List.fromList(
        appendGovernanceCallTail(<int>[
          0x1e,
          0x09,
          ...compactVec(cidNumber),
          ...compactU32(1),
          ...adminPerson(List<int>.filled(32, 0x41), '', ''),
        ], registryActorCid),
      );

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'register_public_institution_admins');
      expect(decoded.fields['admins_len'], '1');
      expect(decoded.fields['admins'], contains('"cid_number":""'));
      expect(decoded.reviewFields['admins'], contains('资料待完善'));
    });

    test(
      'decodes current propose_create_personal with regular_threshold field',
      () {
        final name = utf8.encode('家庭基金');
        final admins = [
          adminPerson(List<int>.filled(32, 0x11), '张', '三'),
          adminPerson(List<int>.filled(32, 0x22), '李', '四'),
          adminPerson(List<int>.filled(32, 0x33), '管理', '员'),
        ];
        final payload = Uint8List.fromList([
          0x07,
          0x00,
          (name.length << 2) & 0xff,
          ...name,
          (admins.length << 2) & 0xff,
          ...admins.expand((admin) => admin),
          ...u32Le(3),
          ...u128LeForTest(BigInt.from(12345)),
        ]);

        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

        expect(decoded, isNotNull);
        expect(decoded!.action, 'propose_create_personal');
        expect(decoded.fields['account_name'], '家庭基金');
        expect(decoded.reviewFields['admins'], contains('张三('));
        expect(decoded.reviewFields['admins'], contains('管理员('));
        expect(decoded.fields['admins_len'], '3');
        expect(decoded.fields['regular_threshold'], '3/3');
        expect(decoded.fields['create_threshold'], '3/3');
        expect(decoded.fields['amount_yuan'], '123.45 元');
        expect(decoded.fields.containsKey('threshold'), isFalse);
      },
    );

    test('rejects propose_create_personal without regular_threshold', () {
      final name = utf8.encode('家庭基金');
      final admins = [
        adminPerson(List<int>.filled(32, 0x11), '张', '三'),
        adminPerson(List<int>.filled(32, 0x22), '李', '四'),
        adminPerson(List<int>.filled(32, 0x33), '王', '五'),
      ];
      final payload = Uint8List.fromList([
        0x07,
        0x00,
        (name.length << 2) & 0xff,
        ...name,
        (admins.length << 2) & 0xff,
        ...admins.expand((admin) => admin),
        ...u128LeForTest(BigInt.from(12345)),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNull);
    });

    test(
      'rejects propose_create_personal regular_threshold below majority',
      () {
        final name = utf8.encode('家庭基金');
        final admins = [
          adminPerson(List<int>.filled(32, 0x11), '张', '三'),
          adminPerson(List<int>.filled(32, 0x22), '李', '四'),
          adminPerson(List<int>.filled(32, 0x33), '王', '五'),
          adminPerson(List<int>.filled(32, 0x44), '赵', '六'),
        ];
        final payload = Uint8List.fromList([
          0x07,
          0x00,
          (name.length << 2) & 0xff,
          ...name,
          (admins.length << 2) & 0xff,
          ...admins.expand((admin) => admin),
          ...u32Le(2),
          ...u128LeForTest(BigInt.from(12345)),
        ]);

        final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

        expect(decoded, isNull);
      },
    );

    test('rejects propose_create_personal with admins_len and threshold', () {
      final name = utf8.encode('家庭基金');
      final admins = [List<int>.filled(32, 0x11), List<int>.filled(32, 0x22)];
      final payload = Uint8List.fromList([
        0x07,
        0x00,
        (name.length << 2) & 0xff,
        ...name,
        2,
        0,
        0,
        0,
        (admins.length << 2) & 0xff,
        ...admins.expand((admin) => admin),
        2,
        0,
        0,
        0,
        ...u128LeForTest(BigInt.from(111)),
      ]);

      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));

      expect(decoded, isNull);
    });
    // 跨端 call data 字节一致性金标：
    // 当前金标固化公民账户投票交易与发行提案交易，统一真源在
    // test/signer/fixtures/（冻结自 runtime fixture），钱包与链协议
    // 三处必须产出同一序列。
    // 任何一端编码漂移 → 这里直接断言失败。
    Map<String, dynamic> readFixture() {
      final candidates = [
        File('test/signer/fixtures/call_data.json'),
      ];
      final file = candidates.firstWhere(
        (candidate) => candidate.existsSync(),
        orElse: () => candidates.first,
      );
      final raw = file.readAsStringSync();
      return jsonDecode(raw) as Map<String, dynamic>;
    }

    test('call data 金标 cast_referendum：decoder 解出账户投票字段', () {
      final fixture = readFixture();
      final caseEntry = (fixture['cases'] as List).firstWhere(
        (e) => e['name'] == 'cast_referendum',
      );
      final hex = caseEntry['expected_call_data_hex'] as String;
      expect(caseEntry['pallet_index'], 21);
      expect(caseEntry['call_index'], 1);
      expect(hex.toLowerCase().startsWith('0x1501'), isTrue);
      // fixture 固化的是纯 call_data,真实 QR 还带签名扩展尾。
      final decoded = PayloadDecoder.decode(
        hexOf(withSigningTail(bytesFromHex(hex))),
      );
      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_referendum');
      expect(decoded.fields['proposal_id'], '99');
      expect(decoded.fields['approve'], 'true');
    });

    // 历史协议升级 decoder 用例已删除：同上，SCALE decoder 不得处理已移除的调用。
    // 整体下线,fixture 走 OfflineSignService.verifyPayload 的哈希直签例外。

    test('decodes propose_issuance (pallet=8 call=0) 当前字段', () {
      final reason = utf8.encode('紧急救灾');
      final totalFen = BigInt.from(50000000); // 500_000.00 GMB
      final totalLe = List<int>.filled(16, 0);
      var tmp = totalFen;
      for (var i = 0; i < 16; i++) {
        totalLe[i] = (tmp & BigInt.from(0xFF)).toInt();
        tmp = tmp >> 8;
      }
      // allocations: 2 项, 每项 32B + 16B = 48B
      final alloc1 = [
        ...List<int>.filled(32, 0xA1),
        ...List<int>.filled(16, 0x00),
      ];
      final alloc2 = [
        ...List<int>.filled(32, 0xA2),
        ...List<int>.filled(16, 0x00),
      ];
      final payload = Uint8List.fromList([
        0x08, 0x00, // pallet=8 call=0
        ...compactVec(nrcActorCid),
        ...compactVec('COMMITTEE_MEMBER'),
        (reason.length << 2) & 0xff,
        ...reason,
        ...totalLe,
        // allocations Vec count=2
        (2 << 2) & 0xff,
        ...alloc1,
        ...alloc2,
      ]);
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(payload)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_issuance');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(decoded.fields['proposer_role_code'], 'COMMITTEE_MEMBER');
      expect(decoded.fields['reason'], '紧急救灾');
      expect(decoded.fields['allocation_count'], '2');
      expect(decoded.fields.containsKey('eligible_total'), isFalse);
    });

    test('rejects propose_issuance without proposer_role_code', () {
      final reason = utf8.encode('旧载荷');
      final payload = Uint8List.fromList([
        0x08,
        0x00,
        ...compactVec(nrcActorCid),
        (reason.length << 2) & 0xff,
        ...reason,
        ...List<int>.filled(16, 0),
        0x00,
      ]);

      expect(PayloadDecoder.decode(hexOf(withSigningTail(payload))), isNull);
    });
    // 签名扩展尾校验(2026-06-10):真实 QR payload_hex = call_data + 扩展尾。
    // 历史 bug:84080b6a 把多个分支改成"严格到尾"却没算扩展尾,
    // 国家储委会转账提案等 9 类提案扫码必红。本组用例锁死两端约定:
    // 带合法尾 → 解码成功;裸 call_data / 篡改尾 → null(红色拒签)。
    List<int> buildNrcTransferCallData() => [
      0x11, 0x00,
      0x01, // institution Some
      ...compactVec(nrcActorCid),
      0x01, // proposer_role_code Some
      ...compactVec('COMMITTEE_MEMBER'),
      ...List<int>.filled(32, 0x66), // funding_account_id
      ...List<int>.filled(32, 0x44), // beneficiary
      ...u128LeForTest(BigInt.from(12345)),
      0x00, // remark 空 Vec
    ];

    test('decodes 国家储委会 propose_transfer 带真实签名扩展尾', () {
      final decoded = PayloadDecoder.decode(
        hexOf(withSigningTail(buildNrcTransferCallData())),
      );
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_transfer');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(
        decoded.fields['institution_account_id'],
        '0x${hexLower(List<int>.filled(32, 0x66))}',
      );
      expect(decoded.fields['amount_yuan'], '123.45 元');
      expect(decoded.fields['remark'], '');
    });

    test('propose_transfer 大 nonce(两字节 Compact)尾部同样接受', () {
      final decoded = PayloadDecoder.decode(
        hexOf(withSigningTail(buildNrcTransferCallData(), nonce: 1000)),
      );
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_transfer');
    });

    test('rejects 裸 call_data(无签名扩展尾)', () {
      expect(
        PayloadDecoder.decode(hexOf(buildNrcTransferCallData())),
        isNull,
        reason: '真实 SigningPayload 必带扩展尾,裸 call_data 拒签',
      );
    });

    test('rejects 非零 tip 的签名扩展尾', () {
      final payload = withSigningTail(buildNrcTransferCallData(), tip: 1);
      expect(
        PayloadDecoder.decode(hexOf(payload)),
        isNull,
        reason: 'tip 不属于五类交易费，冷钱包必须在签名前拒绝非零 tip',
      );
    });

    test('rejects 篡改的签名扩展尾', () {
      final callData = buildNrcTransferCallData();
      final good = withSigningTail(callData);

      // era ≠ immortal(0x00)
      final badEra = Uint8List.fromList(good);
      badEra[callData.length] = 0x15;
      expect(PayloadDecoder.decode(hexOf(badEra)), isNull);

      // immortal 下 birth hash 必等于 genesis hash
      final badBirth = Uint8List.fromList(good);
      badBirth[badBirth.length - 2] ^= 0xff;
      expect(PayloadDecoder.decode(hexOf(badBirth)), isNull);

      // call_data 与尾部之间夹带多余字节
      expect(
        PayloadDecoder.decode(hexOf([...callData, 0xee, ...signingTail()])),
        isNull,
      );

      // 尾部末尾多挂字节
      expect(PayloadDecoder.decode(hexOf([...good, 0x00])), isNull);
    });
  });

  // 立法院 LegislationYuan(25) + 立法投票 LegislationVote(26),布局逐字段对齐
  // citizenchain runtime + citizenapp legislation_codec。夹具必须带签名扩展尾。
  group('立法 pallet 解码(LegislationYuan 25 / LegislationVote 26)', () {
    const firstHouseCid = 'ZS001-NLG0H-100000001-2026';
    const secondHouseCid = 'ZS001-NLG0H-100000002-2026';
    const executiveCid = 'ZS001-PRS0G-100000003-2026';
    const legislatureCid = 'ZS001-PLG0H-100000004-2026';
    const proposerRoleCode = 'REPRESENTATIVE';

    // 一章一节一条无款的最小章节树。
    List<int> minimalChapters() => [
      ...compactU32(1), // 1 章
      ...u32Le(1), // Chapter.number
      ...compactVec('总则'), // Chapter.title
      0x00, // Chapter.title_en None
      ...compactU32(1), // 1 节
      ...u32Le(1), // Section.number
      ...compactVec('第一节'), // Section.title
      0x00, // Section.title_en None
      ...compactU32(1), // 1 条
      ...u32Le(1), // Article.number
      ...compactVec('第一条'), // Article.title
      0x00, // Article.title_en None
      ...compactVec('正文内容'), // Article.body
      0x00, // Article.body_en None
      ...compactU32(0), // 0 款
    ];

    test('decodes propose_enact_law (25.0)', () {
      final callData = [
        25, 0,
        1, // tier = National(1)
        ...u32Le(110000), // scope_code
        ...compactU32(2), // houses 2 项
        ...compactVec(firstHouseCid),
        ...compactVec(secondHouseCid),
        ...compactVec(nrcActorCid),
        ...compactVec(proposerRoleCode),
        ...compactVec(executiveCid),
        0x00, // legislature None
        2, // vote_type = Major(2)
        ...compactVec('教育法'), // title
        0x00, // title_en None
        ...minimalChapters(),
        ...u64Le(5000), // effective_at: unix 毫秒
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_enact_law');
      expect(decoded.fields['title'], '教育法');
      expect(decoded.fields['tier'], '国家级');
      expect(decoded.fields['vote_type'], '重要案');
      expect(decoded.fields['chapter_count'], '1');
      expect(decoded.fields['article_count'], '1');
      expect(decoded.fields['effective_at'], '5000');
      expect(decoded.fields['houses'], '$firstHouseCid、$secondHouseCid');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(decoded.fields['proposer_role_code'], proposerRoleCode);
      expect(decoded.fields['executive_cid_number'], executiveCid);
    });

    test('rejects propose_enact_law with tier=Constitution(0)', () {
      final callData = [
        25, 0,
        0, // tier = Constitution(0) → 立法入口禁止新立宪法
        ...u32Le(0),
        ...compactU32(1),
        ...compactVec(firstHouseCid),
        ...compactVec(nrcActorCid),
        ...compactVec(proposerRoleCode),
        ...compactVec(executiveCid),
        0x00,
        0,
        ...compactVec('宪法'),
        0x00,
        ...minimalChapters(),
        ...u64Le(1),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(callData))), isNull);
    });

    test('rejects propose_enact_law with out-of-range vote_type', () {
      final callData = [
        25, 0,
        1,
        ...u32Le(0),
        ...compactU32(1),
        ...compactVec(firstHouseCid),
        ...compactVec(nrcActorCid),
        ...compactVec(proposerRoleCode),
        ...compactVec(executiveCid),
        0x00,
        9, // 非法 vote_type
        ...compactVec('法'),
        0x00,
        ...minimalChapters(),
        ...u64Le(1),
      ];
      expect(PayloadDecoder.decode(hexOf(withSigningTail(callData))), isNull);
    });

    test('decodes propose_amend_law (25.1)', () {
      final callData = [
        25, 1,
        ...u64Le(42), // law_id
        ...compactVec(nrcActorCid),
        ...compactVec(proposerRoleCode),
        ...compactVec(executiveCid),
        0x01, ...compactVec(legislatureCid), // legislature Some
        4, // vote_type = Special(4)
        ...compactVec('修订版'),
        0x00,
        ...minimalChapters(),
        ...u64Le(7777),
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_amend_law');
      expect(decoded.fields['law_id'], '42');
      expect(decoded.fields['title'], '修订版');
      expect(decoded.fields['vote_type'], '特别案（强制公投）');
      expect(decoded.fields['effective_at'], '7777');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(decoded.fields['proposer_role_code'], proposerRoleCode);
      expect(decoded.fields['executive_cid_number'], executiveCid);
      expect(decoded.fields['legislature_cid_number'], legislatureCid);
    });

    test('decodes propose_repeal_law (25.2)', () {
      final callData = [
        25, 2,
        ...u64Le(7), // law_id
        ...compactVec(nrcActorCid),
        ...compactVec(proposerRoleCode),
        ...compactVec(executiveCid),
        0x00, // legislature None
        0, // vote_type = Regular(0)
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'propose_repeal_law');
      expect(decoded.fields['law_id'], '7');
      expect(decoded.fields['vote_type'], '常规案');
      expect(decoded.fields['actor_cid_number'], nrcActorCid);
      expect(decoded.fields['proposer_role_code'], proposerRoleCode);
      expect(decoded.fields['executive_cid_number'], executiveCid);
    });

    test('LegislationVote 保留 call 0 空洞并拒绝旧载荷', () {
      final callData = [
        26, 0,
        3, // PopulationScope::Town
        ...compactVec('GZ'),
        ...compactVec('001'),
        ...compactVec('001001'),
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNull);
    });

    test('decodes cast_representative_vote (26.1)', () {
      final callData = [26, 1, ...u64Le(99), ...compactVec('SENATOR'), 0x01];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_representative_vote');
      expect(decoded.fields['proposal_id'], '99');
      expect(decoded.fields['voter_role_code'], 'SENATOR');
      expect(decoded.fields['approve'], 'true');
    });

    test('decodes cast_referendum_vote (26.2)', () {
      final callData = [
        26, 2,
        ...u64Le(55), // proposal_id
        0x00, // approve = false
      ];
      final decoded = PayloadDecoder.decode(hexOf(withSigningTail(callData)));
      expect(decoded, isNotNull);
      expect(decoded!.action, 'cast_referendum_vote');
      expect(decoded.fields['proposal_id'], '55');
      expect(decoded.fields['approve'], 'false');
    });

    test(
      'decodes executive_sign (26.3) / override_sign (26.4) / guard_vote (26.5)',
      () {
        final exec = PayloadDecoder.decode(
          hexOf(withSigningTail([26, 3, ...u64Le(1), 0x01])),
        );
        expect(exec?.action, 'executive_sign');
        final override = PayloadDecoder.decode(
          hexOf(withSigningTail([26, 4, ...u64Le(2), 0x00])),
        );
        expect(override?.action, 'override_sign');
        final guard = PayloadDecoder.decode(
          hexOf(withSigningTail([26, 5, ...u64Le(3), 0x01])),
        );
        expect(guard?.action, 'guard_vote');
      },
    );

    test('rejects 裸 call_data 无签名尾(立法投票)', () {
      expect(PayloadDecoder.decode(hexOf([26, 1, ...u64Le(1), 0x01])), isNull);
    });
  });

  // ADR-026 Phase 2 二进制前缀域金标:冷钱包 decode() 必须能解析 node/citizenapp
  // 用相同 4B 前缀(GMB||0x18 / GMB||0x19)构造的 payload。fixture 是 Rust 切片
  // 导出的副本(canonical 真源 primitives/tests/fixtures),四方逐字节锁步。
  group('二进制前缀域金标(node/citizenapp 构造 ↔ 冷钱包 decode 锁步)', () {
    final file = File('test/signer/fixtures/binary_prefix_domain_vectors.json');
    if (!file.existsSync()) {
      test('二进制前缀域金标 fixture 尚未生成', () {
        markTestSkipped('缺少 fixture —— 由 Rust 切片导出');
      }, skip: '缺少 fixture');
      return;
    }
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final vectors = (root['vectors'] as List).cast<Map<String, dynamic>>();
    final byName = {for (final v in vectors) v['name'] as String: v};

    test(
      'ACTIVATE_ADMIN fixture payload → decode 解出 activate_admin_account',
      () {
        final v = byName['ACTIVATE_ADMIN']!;
        final inputs = v['sample_inputs'] as Map<String, dynamic>;
        final decoded = PayloadDecoder.decode('0x${v['payload_hex']}');
        expect(decoded, isNotNull);
        expect(decoded!.action, 'activate_admin_account');
        // institution_code = "NRC"(fixture sample),kind=0 与 NRC 固定治理码匹配。
        expect(decoded.fields['institution_code'], isNotEmpty);
        expect(decoded.fields['cid_number'], inputs['cid_number']);
        expect(decoded.fields.containsKey('account_id'), isFalse);
      },
    );

    test('DECRYPT fixture payload → decode 解出 decrypt_admin + cid_number', () {
      final v = byName['DECRYPT']!;
      final inputs = v['sample_inputs'] as Map<String, dynamic>;
      final decoded = PayloadDecoder.decode('0x${v['payload_hex']}');
      expect(decoded, isNotNull);
      expect(decoded!.action, 'decrypt_admin');
      expect(decoded.fields['cid_number'], inputs['cid_number']);
    });
  });
}
