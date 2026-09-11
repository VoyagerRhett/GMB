import 'dart:typed_data';

/// Product-independent transform applied by CitizenSDK before sr25519 signing.
enum CitizenSigningTransformKind { raw, substrateSigningPayload, blake2Domain }

/// A bounded transform descriptor. Domain bytes are opaque protocol data and never interpreted as
/// an application action by CitizenSDK.
final class CitizenSigningTransform {
  CitizenSigningTransform.raw()
    : kind = CitizenSigningTransformKind.raw,
      domain = Uint8List(0).asUnmodifiableView();

  CitizenSigningTransform.substrateSigningPayload()
    : kind = CitizenSigningTransformKind.substrateSigningPayload,
      domain = Uint8List(0).asUnmodifiableView();

  CitizenSigningTransform.blake2Domain(Uint8List domain)
    : kind = CitizenSigningTransformKind.blake2Domain,
      domain = Uint8List.fromList(domain).asUnmodifiableView() {
    if (this.domain.isEmpty || this.domain.length > 32) {
      throw ArgumentError.value(this.domain.length, 'domain', '必须包含 1..32 字节');
    }
  }

  final CitizenSigningTransformKind kind;
  final Uint8List domain;
}

enum CitizenExternalSignerTransport { qrV1 }

/// Opaque signing request supplied by any consumer application.
final class CitizenSigningIntent {
  CitizenSigningIntent({
    required this.accountId,
    required Uint8List payload,
    required this.transform,
    this.externalSignerTransport,
    this.opaqueAction = 0,
    this.ttlSeconds = 120,
  }) : payload = Uint8List.fromList(payload).asUnmodifiableView();

  final String accountId;
  final Uint8List payload;
  final CitizenSigningTransform transform;
  final CitizenExternalSignerTransport? externalSignerTransport;

  /// QR_V1 transport metadata owned by the calling application. Core never allowlists or decodes it.
  final int opaqueAction;
  final int ttlSeconds;
}

sealed class CitizenSigningOutcome {
  const CitizenSigningOutcome({
    required this.accountId,
    required this.payloadHash,
  });

  final String accountId;
  final String payloadHash;
}

final class CitizenSigningCompleted extends CitizenSigningOutcome {
  CitizenSigningCompleted({
    required super.accountId,
    required super.payloadHash,
    required Uint8List signature,
  }) : signature = Uint8List.fromList(signature).asUnmodifiableView() {
    if (this.signature.length != 64) {
      throw ArgumentError.value(
        this.signature.length,
        'signature',
        '必须是 64 字节',
      );
    }
  }

  final Uint8List signature;
}

final class CitizenExternalSigningPending extends CitizenSigningOutcome {
  const CitizenExternalSigningPending({
    required super.accountId,
    required super.payloadHash,
    required this.transport,
    required this.expiresAt,
    required this.sessionId,
    required this.transportRequest,
  });

  final CitizenExternalSignerTransport transport;
  final BigInt expiresAt;
  final String sessionId;
  final String transportRequest;
}

sealed class CitizenDefaultAccountChangeOutcome {
  const CitizenDefaultAccountChangeOutcome({
    required this.currentDefaultAccountId,
    required this.payloadHash,
  });

  final String currentDefaultAccountId;
  final String payloadHash;
}

final class CitizenDefaultAccountChangeCompleted
    extends CitizenDefaultAccountChangeOutcome {
  const CitizenDefaultAccountChangeCompleted({
    required super.currentDefaultAccountId,
    required super.payloadHash,
    required this.committedRevision,
  });

  final BigInt committedRevision;
}

final class CitizenDefaultAccountChangePending
    extends CitizenDefaultAccountChangeOutcome {
  const CitizenDefaultAccountChangePending({
    required super.currentDefaultAccountId,
    required super.payloadHash,
    required this.transport,
    required this.expiresAt,
    required this.sessionId,
    required this.transportRequest,
  });

  final CitizenExternalSignerTransport transport;
  final BigInt expiresAt;
  final String sessionId;
  final String transportRequest;
}
