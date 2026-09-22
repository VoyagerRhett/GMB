import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenapp/citizen/shared/account_derivation.dart';

/// 广场账户动作签名 payload（两色内容核对用）。
///
/// 布局须与 Worker `account/action_challenge.buildActionScalePayload` 逐字节一致：
///   scaleString(action) ‖ scaleString(accountId) ‖ scaleString(challengeId)
///   [‖ scaleString(context/level)] ‖ u64_le(expiresAt)
/// 其中 context 仅在 action == 'subscribe_membership' 时存在（= 会员等级）。
class SquareActionPayload {
  const SquareActionPayload({
    required this.action,
    required this.accountId,
    required this.challengeId,
    required this.expiresAt,
    this.context,
  });

  final String action;
  final String accountId;
  final String challengeId;
  final int expiresAt;

  /// 动作专属绑定字段（subscribe_membership = 会员等级）。
  final String? context;

  /// registry 镜像中文动作名。未命中返回 null,签名入口必须红色拒绝。
  String? get actionTypeLabel => _squareActionTypeLabels[action];

  /// 用户确认页展示字段。字段名缺中文时返回 null,调用方必须拒绝签名。
  List<SquareReviewField>? get reviewFields {
    final actionType = actionTypeLabel;
    if (actionType == null) return null;
    final fields = <SquareReviewField>[];
    if (!_appendField(fields, 'action_type', actionType)) return null;
    if (!_appendField(fields, 'account_id', accountId)) return null;
    if (!_appendField(fields, 'challenge_id', challengeId)) return null;
    if (context != null &&
        !_appendField(fields, 'membership_level', context!)) {
      return null;
    }
    if (!_appendField(fields, 'expires_at', _formatExpiresAt(expiresAt))) {
      return null;
    }
    return fields;
  }
}

/// 广场账户子动作中文名，镜像 qr-protocol registry 的 square_account_action decoder。
const Map<String, String> _squareActionTypeLabels = {
  'subscribe_membership': '订阅会员',
  'cancel_membership': '取消订阅',
  'delete_account': '注销用户',
};

class SquareReviewField {
  const SquareReviewField({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

/// 解码 payloadHex。无法识别 / 布局不符 / 未知动作一律返回 null（调用方须禁止签名）。
SquareActionPayload? decodeSquareActionPayload(String payloadHex) {
  try {
    final bytes = _hexToBytes(payloadHex);
    var offset = 0;

    final (action, o1) = _readString(bytes, offset);
    offset = o1;
    if (!_squareActionTypeLabels.containsKey(action)) return null;

    final (accountId, o2) = _readString(bytes, offset);
    offset = o2;
    if (!isAccountIdText(accountId)) return null;
    final (challengeId, o3) = _readString(bytes, offset);
    offset = o3;

    String? context;
    if (action == 'subscribe_membership') {
      final (level, o4) = _readString(bytes, offset);
      context = level;
      offset = o4;
    }

    // 结尾必须正好剩 u64（8 字节）过期时间，多一分少一分都拒。
    if (bytes.length - offset != 8) return null;
    final expiresAt = _u64Le(bytes, offset);

    final decoded = SquareActionPayload(
      action: action,
      accountId: accountId,
      challengeId: challengeId,
      expiresAt: expiresAt,
      context: context,
    );
    if (decoded.reviewFields == null) return null;
    return decoded;
  } on Object {
    return null;
  }
}

bool _appendField(List<SquareReviewField> fields, String key, String value) {
  // 原确认页中文标签逐字保留；这是App展示资源，不属于SDK协议能力。
  final label = switch (key) {
    'action_type' => '操作类型',
    'account_id' => '账户',
    'challenge_id' => '挑战编号',
    'membership_level' => '会员等级',
    'expires_at' => '过期时间',
    _ => null,
  };
  if (label == null || label.isEmpty) return false;
  fields.add(SquareReviewField(key: key, label: label, value: value));
  return true;
}

String _formatExpiresAt(int value) {
  final millis = value > 1000000000000 ? value : value * 1000;
  return DateTime.fromMillisecondsSinceEpoch(millis).toLocal().toString();
}

(String, int) _readString(Uint8List bytes, int offset) {
  final (len, next) = _readCompact(bytes, offset);
  final end = next + len;
  final str = utf8.decode(bytes.sublist(next, end));
  return (str, end);
}

/// SCALE compact 解码（支持 1/2/4 字节模式，覆盖 payload 各字段长度）。
(int, int) _readCompact(Uint8List bytes, int offset) {
  final first = bytes[offset];
  final mode = first & 0x03;
  if (mode == 0) {
    return (first >> 2, offset + 1);
  }
  if (mode == 1) {
    final value = (first | (bytes[offset + 1] << 8)) >> 2;
    return (value, offset + 2);
  }
  if (mode == 2) {
    final raw = first |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    return (raw >>> 2, offset + 4);
  }
  throw const FormatException('SCALE compact big-integer 不支持');
}

int _u64Le(Uint8List bytes, int offset) {
  var value = 0;
  for (var i = 7; i >= 0; i--) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

Uint8List _hexToBytes(String input) {
  final text = input.startsWith('0x') || input.startsWith('0X')
      ? input.substring(2)
      : input;
  if (text.length.isOdd) {
    throw const FormatException('hex 长度必须为偶数');
  }
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
