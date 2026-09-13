import 'dart:convert';

import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/qr/generated/qr_bodies.g.dart';
import 'package:citizenapp/qr/bodies/sign_request_body.dart';
import 'package:citizenapp/qr/bodies/sign_response_body.dart';
import 'package:citizenapp/qr/bodies/user_contact_body.dart';
import 'package:citizenapp/qr/bodies/user_transfer_body.dart';
import 'package:citizenapp/qr/bodies/account_data_key_response_body.dart';

/// QR_V1 统一 envelope。
///
/// 所有二维码 JSON 顶层结构:
/// ```
/// {
///   "p": "QR_V1",
///   "k": 1,
///   "i": "<临时码必填,固定码省略>",
///   "e": 1780000000,
///   "b": { ... }
/// }
/// ```
class QrEnvelope<T extends QrBody> {
  const QrEnvelope({
    required this.kind,
    required this.id,
    required this.issuedAt,
    required this.expiresAt,
    required this.body,
  });

  final QrKind kind;

  /// 临时码必填,固定码为 null(JSON 中字段不出现)。
  final String? id;

  /// 临时码必填(unix 秒),固定码为 null。
  final int? issuedAt;

  /// 临时码必填(unix 秒),固定码为 null。
  final int? expiresAt;

  final T body;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'p': QrProtocol.qrV1, 'k': kind.code};
    if (kind.temporary) {
      if (id == null || expiresAt == null) {
        throw StateError('临时码 ${kind.code} 必须包含 i/e');
      }
      map['i'] = id;
      map['e'] = expiresAt;
    } else {
      if (id != null || issuedAt != null || expiresAt != null) {
        throw StateError('固定码 ${kind.code} 不能包含 i/e');
      }
    }
    map['b'] = body.toJson();
    return map;
  }

  String toRawJson() => jsonEncode(toJson());

  /// 从原始 JSON 字符串解析。kind 未知或字段不符均抛 FormatException。
  static QrEnvelope<QrBody> parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR 内容不是 JSON 对象');
    }
    return fromJson(decoded);
  }

  static QrEnvelope<QrBody> fromJson(Map<String, dynamic> data) {
    if (data['p'] == QrProtocol.qrV1 &&
        data['k'] == QrKind.accountIdCode.code) {
      throw const FormatException('通用账户码必须由 CitizenSDK 解析');
    }
    GeneratedQrBodySchema.validateEnvelope(data);
    final kind = QrKind.fromWire(data['k']);

    String? id;
    int? issuedAt;
    int? expiresAt;
    if (kind.temporary) {
      id = data['i'] as String;
      expiresAt = data['e'] as int;
    }

    final bodyRaw = data['b'];
    if (bodyRaw is! Map<String, dynamic>) {
      throw const FormatException('缺少 b 对象');
    }

    final QrBody body;
    switch (kind) {
      case QrKind.signRequest:
        body = SignRequestBody.fromJson(bodyRaw);
      case QrKind.signResponse:
        body = SignResponseBody.fromJson(bodyRaw);
      case QrKind.userContact:
        body = UserContactBody.fromJson(bodyRaw);
      case QrKind.userTransfer:
        body = UserTransferBody.fromJson(bodyRaw);
      case QrKind.accountIdCode:
        throw const FormatException('通用账户码必须由 CitizenSDK 解析');
      case QrKind.accountDataKeyResponse:
        body = AccountDataKeyResponseBody.fromJson(bodyRaw);
    }

    return QrEnvelope<QrBody>(
      kind: kind,
      id: id,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      body: body,
    );
  }
}

/// 所有 body 类型的父接口。
abstract class QrBody {
  Map<String, dynamic> toJson();
}
