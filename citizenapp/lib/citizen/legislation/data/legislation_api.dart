// LegislationApi 客户端(ADR-028 P3)——读链上法律 + 宪法不可修改条款 manifest。
//
// `list_laws` 走 runtime API(state_call);`law/law_version` 与
// `ConstitutionImmutableManifest` 走 finalized storage 精确 key 读取。全部经
// `legislation_codec` 镜像解码。

import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;

import 'package:citizenapp/citizen/legislation/data/law_models.dart';
import 'package:citizenapp/citizen/legislation/data/legislation_codec.dart';
import 'package:citizenapp/isar/wallet_isar.dart';

class LegislationApi {
  LegislationApi({required CitizenChain chain}) : _chain = chain;

  final CitizenChain _chain;

  // 会话内内存缓存(法律体量大、改动稀;同实例复用避免重拉,尤其宪法 219KB)。
  // 本机持久快照只写 WalletLegislationSnapshotEntity；链上 finalized 仍是真源。
  final Map<int, Law> _lawCache = {};
  final Map<String, LawVersion> _versionCache = {};
  final Map<String, LawVersionLabel> _versionLabelCache = {};
  ImmutableManifest? _manifestCache;

  /// 某层级+行政区范围下的全部 law_id(`list_laws(tier, scope_code)`)。
  Future<List<int>> listLaws(LawTier tier, int scopeCode) async {
    final finalized = await _chain.getFinalizedHead();
    final raw = await _chain.callRuntimeApi(
      finalized,
      'LegislationApi_list_laws',
      Uint8List.fromList([tier.index, ..._u32(scopeCode)]),
    );
    return decodeLawIds(raw);
  }

  /// 法律主记录(`law(law_id)`,不存在返回 null)。
  Future<Law?> law(int lawId, {bool forceRefresh = false}) async {
    final cached = _lawCache[lawId];
    if (!forceRefresh && cached != null) return cached;
    final raw = await _readStorage(
      _storageMapKey(
        'LegislationYuan',
        'Laws',
        Uint8List.fromList(_u64(lawId)),
      ),
    );
    if (raw == null) return null;
    final law = decodeLaw(raw);
    _lawCache[lawId] = law;
    await _writeRaw(_lawKey(lawId), raw);
    return law;
  }

  /// 法律某版本正文(`law_version(law_id, version)`,不存在返回 null)。
  Future<LawVersion?> lawVersion(
    int lawId,
    int version, {
    bool forceRefresh = false,
  }) async {
    final key = '$lawId:$version';
    final cached = _versionCache[key];
    if (!forceRefresh && cached != null) return cached;
    final raw = await _readStorage(
      _storageDoubleMapKey(
        'LegislationYuan',
        'LawVersions',
        Uint8List.fromList(_u64(lawId)),
        Uint8List.fromList(_u32(version)),
      ),
    );
    if (raw == null) return null;
    final v = decodeLawVersion(raw);
    _versionCache[key] = v;
    await _writeRaw(_versionKey(lawId, version), raw);
    return v;
  }

  /// 法律版本展示标签(`LawVersionLabels[(law_id, version)]`,不存在返回 null)。
  Future<LawVersionLabel?> lawVersionLabel(
    int lawId,
    int version, {
    bool forceRefresh = false,
  }) async {
    final key = '$lawId:$version';
    final cached = _versionLabelCache[key];
    if (!forceRefresh && cached != null) return cached;
    final raw = await _readStorage(
      _storageDoubleMapKey(
        'LegislationYuan',
        'LawVersionLabels',
        Uint8List.fromList(_u64(lawId)),
        Uint8List.fromList(_u32(version)),
      ),
    );
    if (raw == null) return null;
    final label = decodeLawVersionLabel(raw);
    _versionLabelCache[key] = label;
    await _writeRaw(_versionLabelKey(lawId, version), raw);
    return label;
  }

  /// 宪法不可修改条款 manifest(展示「不可修改条款」徽章用)。
  Future<ImmutableManifest?> immutableManifest(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _manifestCache != null) return _manifestCache;
    final key = _storageValueKey(
      'LegislationYuan',
      'ConstitutionImmutableManifest',
    );
    final raw = await _readStorage(key);
    if (raw == null) return null;
    await _writeRaw(_manifestKey, raw);
    return _manifestCache = decodeImmutableManifest(raw);
  }

  /// 读取本机法律主记录快照；只作首屏展示,不得替代链上 finalized 真源。
  Future<Law?> localLaw(int lawId) async {
    final raw = await _readRaw(_lawKey(lawId));
    if (raw == null) return null;
    try {
      final law = decodeLaw(raw);
      _lawCache[lawId] = law;
      return law;
    } on Object {
      return null;
    }
  }

  /// 读取本机法律版本正文快照；后台会用链上内容哈希核对是否更新。
  Future<LawVersion?> localLawVersion(int lawId, int version) async {
    final raw = await _readRaw(_versionKey(lawId, version));
    if (raw == null) return null;
    try {
      final v = decodeLawVersion(raw);
      _versionCache['$lawId:$version'] = v;
      return v;
    } on Object {
      return null;
    }
  }

  /// 读取本机版本标签快照；只作显示兜底,链上 finalized storage 仍是真源。
  Future<LawVersionLabel?> localLawVersionLabel(int lawId, int version) async {
    final raw = await _readRaw(_versionLabelKey(lawId, version));
    if (raw == null) return null;
    try {
      final label = decodeLawVersionLabel(raw);
      _versionLabelCache['$lawId:$version'] = label;
      return label;
    } on Object {
      return null;
    }
  }

  /// 读取本机不可修改条款清单快照。
  Future<ImmutableManifest?> localImmutableManifest() async {
    final raw = await _readRaw(_manifestKey);
    if (raw == null) return null;
    try {
      return _manifestCache = decodeImmutableManifest(raw);
    } on Object {
      return null;
    }
  }

  Uint8List _storageValueKey(String pallet, String item) {
    final p = Hasher.twoxx128.hashString(pallet);
    final s = Hasher.twoxx128.hashString(item);
    return Uint8List.fromList([...p, ...s]);
  }

  Future<Uint8List?> _readStorage(Uint8List key) async {
    final finalized = await _chain.getFinalizedHead();
    return _chain.getStorage(finalized, key);
  }

  Uint8List _storageMapKey(String pallet, String item, Uint8List keyData) {
    final p = Hasher.twoxx128.hashString(pallet);
    final s = Hasher.twoxx128.hashString(item);
    final k = _blake2128Concat(keyData);
    return Uint8List.fromList([...p, ...s, ...k]);
  }

  Uint8List _storageDoubleMapKey(
    String pallet,
    String item,
    Uint8List key1,
    Uint8List key2,
  ) {
    final p = Hasher.twoxx128.hashString(pallet);
    final s = Hasher.twoxx128.hashString(item);
    final k1 = _blake2128Concat(key1);
    final k2 = _blake2128Concat(key2);
    return Uint8List.fromList([...p, ...s, ...k1, ...k2]);
  }

  Uint8List _blake2128Concat(Uint8List data) {
    final hash = Hasher.blake2b128.hash(data);
    return Uint8List.fromList([...hash, ...data]);
  }

  String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _decodeHex(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    return Uint8List.fromList([
      for (var i = 0; i + 1 < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ]);
  }

  String _lawKey(int lawId) => 'legislation:law:$lawId';

  String _versionKey(int lawId, int version) =>
      'legislation:law_version:$lawId:$version';

  String _versionLabelKey(int lawId, int version) =>
      'legislation:law_version_label:$lawId:$version';

  static const String _manifestKey = 'legislation:constitution_manifest';

  Future<Uint8List?> _readRaw(String key) async {
    try {
      return await WalletIsar.instance.read((isar) async {
        final row =
            await isar.walletLegislationSnapshotEntitys.getByStateKey(key);
        final value = row?.rawHex;
        if (value == null || value.isEmpty) return null;
        return _decodeHex(value);
      });
    } on Object {
      return null;
    }
  }

  Future<void> _writeRaw(String key, Uint8List raw) async {
    try {
      await WalletIsar.instance.writeTxn((isar) async {
        final rawHex = _hex(raw);
        final existing =
            await isar.walletLegislationSnapshotEntitys.getByStateKey(key);
        if (existing?.rawHex == rawHex) return;
        final row =
            existing ?? (WalletLegislationSnapshotEntity()..stateKey = key);
        row
          ..rawHex = rawHex
          ..updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
        await isar.walletLegislationSnapshotEntitys.putByStateKey(row);
      });
    } on Object {
      // 本机快照写入失败不影响链上读取；下次进入最多回到首屏等待。
    }
  }

  List<int> _u32(int v) =>
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

  List<int> _u64(int v) => List.generate(8, (k) => (v >> (8 * k)) & 0xff);
}
