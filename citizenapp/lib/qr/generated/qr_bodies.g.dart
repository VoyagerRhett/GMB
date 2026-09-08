// 本文件由 citizenchain/crates/qr-protocol/registry/kinds.yaml 生成，禁止手改。
import 'dart:convert';
import 'dart:typed_data';

enum QrKind {
  signRequest(1, temporary: true),
  signResponse(2, temporary: true),
  userContact(3, temporary: false),
  userTransfer(4, temporary: true),
  accountIdCode(5, temporary: false),
  accountDataKeyResponse(6, temporary: true);

  const QrKind(this.code, {required this.temporary});
  final int code;
  final bool temporary;
  bool get fixed => !temporary;

  static QrKind fromWire(Object? wire) {
    if (wire is! int) throw FormatException('k 必须为整数,实际: $wire');
    for (final kind in values) {
      if (kind.code == wire) return kind;
    }
    throw FormatException('未知 k: $wire');
  }
}

class GeneratedQrBodySchema {
  const GeneratedQrBodySchema._();

  static final List<Map<String, dynamic>> _kinds =
      (jsonDecode(r'''[
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "positive_int",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "action",
        "min_bytes": null,
        "required": true,
        "wire_key": "a"
      },
      {
        "allowed_ints": [
          1
        ],
        "constraint": "enum_int",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "sig_alg",
        "min_bytes": null,
        "required": true,
        "wire_key": "g"
      },
      {
        "allowed_ints": [],
        "constraint": "signer_public_key",
        "empty_for_action_codes": [
          10,
          11
        ],
        "exact_bytes": null,
        "field_key": "signer_public_key",
        "min_bytes": null,
        "required": true,
        "wire_key": "u"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "review_payload",
        "min_bytes": 1,
        "required": true,
        "wire_key": "d"
      }
    ],
    "kind_code": 1,
    "kind_key": "sign_request",
    "optional_pairs": [],
    "temporary": true
  },
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 32,
        "field_key": "signer_public_key",
        "min_bytes": null,
        "required": true,
        "wire_key": "u"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 64,
        "field_key": "signature",
        "min_bytes": null,
        "required": true,
        "wire_key": "s"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 32,
        "field_key": "current_account_id",
        "min_bytes": null,
        "required": false,
        "wire_key": "o"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 64,
        "field_key": "current_account_signature",
        "min_bytes": null,
        "required": false,
        "wire_key": "r"
      }
    ],
    "kind_code": 2,
    "kind_key": "sign_response",
    "optional_pairs": [
      [
        "o",
        "r"
      ]
    ],
    "temporary": true
  },
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "cid_number",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "cid_number",
        "min_bytes": null,
        "required": true,
        "wire_key": "c"
      },
      {
        "allowed_ints": [],
        "constraint": "account_id",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "account_id",
        "min_bytes": null,
        "required": true,
        "wire_key": "n"
      }
    ],
    "kind_code": 3,
    "kind_key": "user_contact",
    "optional_pairs": [],
    "temporary": false
  },
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "account_id",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "account_id",
        "min_bytes": null,
        "required": true,
        "wire_key": "n"
      },
      {
        "allowed_ints": [],
        "constraint": "text_nonempty",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "amount",
        "min_bytes": null,
        "required": true,
        "wire_key": "v"
      },
      {
        "allowed_ints": [],
        "constraint": "text_nonempty",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "symbol",
        "min_bytes": null,
        "required": true,
        "wire_key": "t"
      },
      {
        "allowed_ints": [],
        "constraint": "text",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "memo",
        "min_bytes": null,
        "required": true,
        "wire_key": "m"
      },
      {
        "allowed_ints": [],
        "constraint": "cid_number",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "bank_cid_number",
        "min_bytes": null,
        "required": true,
        "wire_key": "l"
      }
    ],
    "kind_code": 4,
    "kind_key": "user_transfer",
    "optional_pairs": [],
    "temporary": true
  },
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "account_id",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "account_id",
        "min_bytes": null,
        "required": true,
        "wire_key": "n"
      }
    ],
    "kind_code": 5,
    "kind_key": "account_id_code",
    "optional_pairs": [],
    "temporary": false
  },
  {
    "fields": [
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 32,
        "field_key": "signer_public_key",
        "min_bytes": null,
        "required": true,
        "wire_key": "u"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 64,
        "field_key": "signature",
        "min_bytes": null,
        "required": true,
        "wire_key": "s"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 32,
        "field_key": "key_exchange_public_key",
        "min_bytes": null,
        "required": true,
        "wire_key": "x"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": 12,
        "field_key": "encryption_nonce",
        "min_bytes": null,
        "required": true,
        "wire_key": "q"
      },
      {
        "allowed_ints": [],
        "constraint": "b64u_bytes",
        "empty_for_action_codes": [],
        "exact_bytes": null,
        "field_key": "ciphertext",
        "min_bytes": 17,
        "required": true,
        "wire_key": "z"
      }
    ],
    "kind_code": 6,
    "kind_key": "account_data_key_response",
    "optional_pairs": [],
    "temporary": true
  }
]''') as List<dynamic>)
          .cast<Map<String, dynamic>>();

  static Map<String, dynamic> validateEnvelope(Map<String, dynamic> data) {
    final kindCode = data['k'];
    if (data['p'] != 'QR_V1' || kindCode is! int) {
      throw const FormatException('QR envelope 必须使用 QR_V1 与整数 k');
    }
    final kind = _kinds.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['kind_code'] == kindCode,
          orElse: () => null,
        );
    if (kind == null) throw FormatException('未知 k: $kindCode');
    final temporary = kind['temporary'] as bool;
    _exactKeys(data, temporary ? const {'p', 'k', 'i', 'e', 'b'} : const {'p', 'k', 'b'}, 'QR envelope');
    if (temporary) {
      if (data['i'] is! String || (data['i'] as String).isEmpty ||
          data['e'] is! int || (data['e'] as int) <= 0) {
        throw const FormatException('临时码必须包含非空 i 与正整数 e');
      }
    }
    final body = data['b'];
    if (body is! Map<String, dynamic>) throw const FormatException('缺少 b 对象');
    validateBody(kindCode, body);
    return kind;
  }

  static void validateBody(int kindCode, Map<String, dynamic> body) {
    final kind = _kinds.firstWhere(
      (item) => item['kind_code'] == kindCode,
      orElse: () => throw FormatException('未知 k: $kindCode'),
    );
    final fields = (kind['fields'] as List<dynamic>).cast<Map<String, dynamic>>();
    final allowed = fields.map((field) => field['wire_key'] as String).toSet();
    final required = fields
        .where((field) => field['required'] == true)
        .map((field) => field['wire_key'] as String)
        .toSet();
    if (body.keys.any((key) => !allowed.contains(key)) ||
        required.any((key) => !body.containsKey(key))) {
      throw FormatException('${kind['kind_key']}.b 字段集合不符合 QR_V1');
    }
    for (final pairRaw in kind['optional_pairs'] as List<dynamic>) {
      final pair = (pairRaw as List<dynamic>).cast<String>();
      if (body.containsKey(pair[0]) != body.containsKey(pair[1])) {
        throw FormatException('b.${pair[0]} 与 b.${pair[1]} 必须成对出现');
      }
    }
    for (final field in fields) {
      final key = field['wire_key'] as String;
      if (!body.containsKey(key)) continue;
      _validateField(body[key], field, body);
    }
  }

  static Uint8List decodeBase64Url(String input, String field) {
    if (input.isEmpty || input.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(input)) {
      throw FormatException('$field 必须为无填充 base64url');
    }
    final padded = input.padRight(input.length + ((4 - input.length % 4) % 4), '=');
    try {
      final bytes = Uint8List.fromList(base64Url.decode(padded));
      if (base64Url.encode(bytes).replaceAll('=', '') != input) throw const FormatException();
      return bytes;
    } catch (_) {
      throw FormatException('$field 必须为规范无填充 base64url');
    }
  }

  static void _validateField(Object? value, Map<String, dynamic> field, Map<String, dynamic> body) {
    final key = field['wire_key'] as String;
    switch (field['constraint']) {
      case 'positive_int':
        if (value is! int || value <= 0) throw FormatException('b.$key 必须为正整数');
      case 'enum_int':
        if (value is! int || !(field['allowed_ints'] as List<dynamic>).contains(value)) {
          throw FormatException('b.$key 不在允许值中');
        }
      case 'signer_public_key':
        if (value is! String) throw FormatException('b.$key 必须为字符串');
        final emptyActions = (field['empty_for_action_codes'] as List<dynamic>).cast<int>();
        if (emptyActions.contains(body['a'])) {
          if (value.isNotEmpty) throw FormatException('b.$key 在当前动作必须留空');
        } else if (decodeBase64Url(value, 'b.$key').length != 32) {
          throw FormatException('b.$key 必须解码为 32 字节');
        }
      case 'b64u_bytes':
        if (value is! String) throw FormatException('b.$key 必须为字符串');
        final bytes = decodeBase64Url(value, 'b.$key');
        final exact = field['exact_bytes'] as int?;
        final min = field['min_bytes'] as int?;
        if (exact != null && bytes.length != exact) throw FormatException('b.$key 必须解码为 $exact 字节');
        if (min != null && bytes.length < min) throw FormatException('b.$key 至少解码为 $min 字节');
      case 'cid_number':
        if (value is! String || !RegExp(r'^[A-Za-z0-9-]{1,32}$').hasMatch(value)) {
          throw FormatException('b.$key 必须为 1 到 32 位字母数字与连字符');
        }
      case 'account_id':
        if (value is! String || !RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
          throw FormatException('b.$key 必须为小写 0x 加 64 位十六进制');
        }
      case 'text_nonempty':
        if (value is! String || value.isEmpty) throw FormatException('b.$key 必须为非空字符串');
      case 'text':
        if (value is! String) throw FormatException('b.$key 必须为字符串');
      default:
        throw FormatException('b.$key 使用未知约束');
    }
  }

  static void _exactKeys(Map<String, dynamic> data, Set<String> expected, String context) {
    final actual = data.keys.toSet();
    if (actual.length != expected.length || !actual.containsAll(expected) || !expected.containsAll(actual)) {
      throw FormatException('$context 字段集合不符合 QR_V1');
    }
  }
}
