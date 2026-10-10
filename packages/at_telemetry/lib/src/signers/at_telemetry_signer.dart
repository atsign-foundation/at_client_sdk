import 'dart:typed_data';

abstract interface class AtTelemetrySigner {
  // The alg value a signature made by this signer carries, such as ed25519
  String get algorithm;

  Future<Uint8List> sign(List<int> message);
}
