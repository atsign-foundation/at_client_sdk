import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

abstract interface class AtTelemetrySigner {
  Future<Uint8List> sign(List<int> message);
}

final class AtTelemetryRsaSigner implements AtTelemetrySigner {
  final Uint8List _secretKey;

  AtTelemetryRsaSigner.fromBase64(String privateKey)
      : _secretKey = base64Decode(privateKey);

  @override
  Future<Uint8List> sign(List<int> message) =>
      RsaSignatureAlgo.rsa2048().signBytes(
        Uint8List.fromList(message),
        secretKey: _secretKey,
      );
}
