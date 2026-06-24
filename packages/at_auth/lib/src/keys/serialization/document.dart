import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_commons/at_commons.dart';

enum KeyRecordKind {
  public,
  private,
  symmetric,
}

KeyRecordKind? keyKindFromJsonToken(String token) {
  return switch (token) {
    'public' => KeyRecordKind.public,
    'private' => KeyRecordKind.private,
    'symmetric' => KeyRecordKind.symmetric,
    _ => null,
  };
}

extension KeyKindJson on KeyRecordKind {
  String get jsonToken {
    return switch (this) {
      KeyRecordKind.public => 'public',
      KeyRecordKind.private => 'private',
      KeyRecordKind.symmetric => 'symmetric',
    };
  }

  bool get isAsymmetric => this != KeyRecordKind.symmetric;
}

class AtKeysDocument {
  final int version;
  final String atsign;
  final String? enrollmentId;
  final List<KeyRecord> keys;

  const AtKeysDocument({
    required this.version,
    required this.atsign,
    required this.keys,
    this.enrollmentId,
  });
}

class KeyRecord {
  final String id;
  final String? pairId;
  final String purpose;
  final KeyRecordKind kind;
  final String algorithm;
  final KeyFingerprint? fingerprint;
  final KeyRotation? rotation;
  final List<String> operations;
  final KeyProtection? protection;
  final AtBytes bytes;

  const KeyRecord({
    required this.id,
    required this.purpose,
    required this.kind,
    required this.algorithm,
    required this.bytes,
    this.pairId,
    this.fingerprint,
    this.rotation,
    this.operations = const [],
    this.protection,
  });

  bool get isAsymmetric => kind.isAsymmetric;
}
