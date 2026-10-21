import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'at_telemetry_signer.dart';

// Signs with an Ed25519 key held as its 32-byte seed
final class AtTelemetryEd25519Signer implements AtTelemetrySigner {
  static const String algorithmName = 'ed25519';
  static const int seedLength = 32;
  static const int publicKeyLength = 32;
  static const int signatureLength = 64;
  static final Ed25519 _ed25519 = Ed25519();

  final Uint8List seed;
  final Uint8List publicKey;
  final SimpleKeyPair _keyPair;

  AtTelemetryEd25519Signer._(this.seed, this.publicKey, this._keyPair);

  static Future<AtTelemetryEd25519Signer> fromSeed(List<int> seed) async {
    if (seed.length != seedLength) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'must be $seedLength bytes',
      );
    }
    final Uint8List copy = Uint8List.fromList(seed);
    final SimpleKeyPair keyPair = await _ed25519.newKeyPairFromSeed(copy);
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    return AtTelemetryEd25519Signer._(
      copy,
      Uint8List.fromList(publicKey.bytes),
      keyPair,
    );
  }

  static Future<AtTelemetryEd25519Signer> generate({Random? random}) {
    final Random source = random ?? Random.secure();
    return fromSeed(
      List<int>.generate(seedLength, (int _) => source.nextInt(256)),
    );
  }

  static Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    if (signature.length != signatureLength ||
        publicKey.length != publicKeyLength) {
      return false;
    }
    try {
      return await _ed25519.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  @override
  String get algorithm => algorithmName;

  @override
  Future<Uint8List> sign(List<int> message) async {
    final Signature signature = await _ed25519.sign(message, keyPair: _keyPair);
    return Uint8List.fromList(signature.bytes);
  }
}
