import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../signers/at_telemetry_ed25519_signer.dart';

// The value of an atServer's public telemetry key record. The key id is a
// short hash of the public key, so a record cannot name a key it does not
// hold.
final class AtTelemetryPublicKeyRecord {
  static const int _keyIdBytes = 12;
  static final RegExp keyIdPattern = RegExp(r'^[A-Za-z0-9_-]{16}$');

  final String keyId;
  final String algorithm;
  final Uint8List publicKey;

  AtTelemetryPublicKeyRecord._(this.keyId, this.algorithm, this.publicKey);

  factory AtTelemetryPublicKeyRecord({
    required String algorithm,
    required List<int> publicKey,
  }) {
    if (algorithm != AtTelemetryEd25519Signer.algorithmName) {
      throw ArgumentError.value(algorithm, 'algorithm', 'is not supported');
    }
    if (publicKey.length != AtTelemetryEd25519Signer.publicKeyLength) {
      throw ArgumentError.value(
        publicKey.length,
        'publicKey',
        'must be ${AtTelemetryEd25519Signer.publicKeyLength} bytes',
      );
    }
    return AtTelemetryPublicKeyRecord._(
      keyIdFor(publicKey),
      algorithm,
      Uint8List.fromList(publicKey),
    );
  }

  factory AtTelemetryPublicKeyRecord.parse(String value) {
    final Object? json;
    try {
      json = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Telemetry public key record is not JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Telemetry public key record is not an '
          'object');
    }
    final Object? keyId = json['keyId'];
    final Object? algorithm = json['alg'];
    final Object? publicKey = json['publicKey'];
    if (keyId is! String || algorithm is! String || publicKey is! String) {
      throw const FormatException('Telemetry public key record needs keyId, '
          'alg and publicKey strings');
    }
    final AtTelemetryPublicKeyRecord record;
    try {
      record = AtTelemetryPublicKeyRecord(
        algorithm: algorithm,
        publicKey: base64Decode(publicKey),
      );
    } on Object {
      throw const FormatException('Invalid telemetry public key');
    }
    if (record.keyId != keyId) {
      throw const FormatException('Telemetry key id does not match its key');
    }
    return record;
  }

  // The first 12 bytes of the key's SHA-256, as 16 base64url characters
  static String keyIdFor(List<int> publicKey) {
    final List<int> digest = sha256.convert(publicKey).bytes;
    return base64Url.encode(digest.sublist(0, _keyIdBytes));
  }

  String encode() {
    return jsonEncode(<String, String>{
      'keyId': keyId,
      'alg': algorithm,
      'publicKey': base64Encode(publicKey),
    });
  }
}
