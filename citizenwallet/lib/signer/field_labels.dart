// 扫码确认页 reviewFields 字段名中文翻译单源。
//
// decoder(payload_decoder.dart)的 `reviewFields` 保留英文机器 key 用于
// 跨端验真,到 UI 层统一经本文件翻译。payload_decoder 新增 reviewFields key
// 时必须先登记 `citizenchain/crates/qr-protocol/registry/fields.yaml`,
// 再同步本表并补测试。未登记字段必须红色拒绝,不得 fallback 展示英文 key。
import 'dart:typed_data';

import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenwallet/chain/chain_constants.dart';
import 'package:citizenwallet/qr/generated/qr_action_registry.g.dart';

/// fields value 转换。
///
/// - `approve` 布尔 → 赞成/反对。
/// - 账户字段(ADR-040 命名约定:`account_id` 或 `*_account_id`)的 32 字节
///   公钥 hex 一律转成 SS58 地址展示 —— 人看的地方统一 SS58,hex 公钥只给系统用。
///   公钥字段(`*_public_key`)、哈希字段(`*_hash`)按明确标注保持 0x hex 不转。
String fieldValueText(String key, String value) {
  if (key == 'approve') return value == 'true' ? '赞成' : '反对';
  if (_isAccountIdKey(key)) {
    final ss58 = _accountHexToSs58OrNull(value);
    if (ss58 != null) return ss58;
  }
  return value;
}

/// ADR-040:单账户 `account_id`,多账户 `<角色>_account_id`。
bool _isAccountIdKey(String key) =>
    key == 'account_id' || key.endsWith('_account_id');

/// 规范 32 字节账户 hex(`0x` + 64 位小写)→ SS58;不匹配返回 null 按原值展示。
String? _accountHexToSs58OrNull(String value) {
  final match = RegExp(r'^0x([0-9a-f]{64})$').firstMatch(value);
  if (match == null) return null;
  final hex = match.group(1)!;
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return Keyring().encodeAddress(bytes, ChainConstants.ss58Prefix);
}

bool hasFieldLabel(String key) => fieldLabelTextOrNull(key) != null;

/// reviewFields key → 中文字段名；未登记返回 null,调用方必须红色拒绝。
///
/// 标签唯一真源 = qr-protocol 生成表(fields.yaml)。不得在此加英文兜底,
/// 否则未登记字段会以英文 key 泄漏到确认页(如历史上 `amount_yuan` 被
/// `amount_` 前缀规则误拆成「yuan金额」)。
String? fieldLabelTextOrNull(String key) {
  return GeneratedQrActionRegistry.fieldLabelForKey(key);
}

/// reviewFields key → 中文字段名。
///
/// 仅保留给既有测试和非签名确认辅助场景；真正签名放行必须使用
/// [fieldLabelTextOrNull] / [hasFieldLabel]。未登记字段直接抛错,不能生成展示兜底。
String fieldLabelText(String key) {
  final label = fieldLabelTextOrNull(key);
  if (label == null) {
    throw StateError('签名字段缺少中文名称');
  }
  return label;
}
