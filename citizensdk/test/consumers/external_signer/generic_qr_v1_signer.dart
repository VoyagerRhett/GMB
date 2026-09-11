import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';

/// Generic external signer built solely from CitizenSDK's public QR_V1 and
/// signing capabilities. It has no dependency on any external product implementation.
final class GenericQrV1Signer {
  const GenericQrV1Signer({required this.qr, required this.signing});

  final CitizenQr qr;
  final CitizenSigning signing;

  Future<GenericQrV1SignerResponse> respond(String canonicalRequest) async {
    final request = await qr.parse(canonicalRequest);
    if (request.kind != CitizenQrKind.signRequest ||
        request.requestId == null ||
        request.signerAccountId == null) {
      throw const FormatException('input is not a complete QR_V1 sign request');
    }

    final signed = await signing.signQrRequest(request.canonicalText);
    if (signed.signRequest != request.canonicalText ||
        signed.requestId != request.requestId ||
        signed.signerAccountId != request.signerAccountId ||
        signed.signature.length != 64) {
      throw const FormatException('signer output is not bound to its request');
    }

    final response = await qr.parse(signed.canonicalText);
    if (response.kind != CitizenQrKind.signResponse ||
        response.requestId != request.requestId ||
        response.signerAccountId != request.signerAccountId ||
        response.signature == null ||
        !_sameBytes(response.signature!, signed.signature)) {
      throw const FormatException(
        'QR_V1 response does not match signer output',
      );
    }

    return GenericQrV1SignerResponse(
      canonicalResponse: response.canonicalText,
      requestId: request.requestId!,
      signerAccountId: request.signerAccountId!,
      signature: response.signature!,
      image: signed.qrImage,
    );
  }
}

final class GenericQrV1SignerResponse {
  GenericQrV1SignerResponse({
    required this.canonicalResponse,
    required this.requestId,
    required this.signerAccountId,
    required Uint8List signature,
    required this.image,
  }) : signature = Uint8List.fromList(signature).asUnmodifiableView();

  final String canonicalResponse;
  final String requestId;
  final String signerAccountId;
  final Uint8List signature;
  final CitizenQrImage image;
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
