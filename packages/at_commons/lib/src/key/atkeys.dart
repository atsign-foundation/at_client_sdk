import 'package:at_commons/at_commons.dart';

abstract final class KeyPurposes {
  static const pkam = 'pkam';
  static const encryption = 'encryption';
  static const signing = 'signing';
  static const selfEncryption = 'self-encryption';
  static const apkamSymmetric = 'apkam-symmetric';
}

bool? keyPurposeUsesAsymmetricPair(String purpose) {
  return switch (purpose) {
    KeyPurposes.pkam || KeyPurposes.encryption || KeyPurposes.signing => true,
    KeyPurposes.selfEncryption || KeyPurposes.apkamSymmetric => false,
    _ => null,
  };
}

class KeyFingerprint {
  final String algorithm;
  final AtBytes value;

  const KeyFingerprint({
    required this.algorithm,
    required this.value,
  });
}

class KeyProtection {
  final String keyRef;
  final String algorithm;
  final String iv;

  const KeyProtection({
    required this.keyRef,
    required this.algorithm,
    required this.iv,
  });
}

class AtKeysSet {
  final Atsign atsign;
  String? enrollmentId;
  final List<AtAsymmetricKey> asymmetricKeys;
  final List<AtSymmetricKey> symmetricKeys;

  AtKeysSet({
    required this.atsign,
    required this.asymmetricKeys,
    required this.symmetricKeys,
    this.enrollmentId,
  });

  void addKey(AtKeysMaterial key) {
    switch (key) {
      case AtAsymmetricKey():
        _addAsymmetricKey(key);
      case AtSymmetricKey():
        _addSymmetricKey(key);
    }
  }

  void addKeys(Iterable<AtKeysMaterial> keys) {
    for (final key in keys) {
      addKey(key);
    }
  }

  void _addAsymmetricKey(AtAsymmetricKey key) {
    if (getKeyPair(key.pairId) != null) {
      throw ArgumentError.value(key.pairId, 'pairId', 'Duplicate key pair');
    }
    asymmetricKeys.add(key);
  }

  void _addSymmetricKey(AtSymmetricKey key) {
    if (getSymmetricKey(key.id) != null) {
      throw ArgumentError.value(key.id, 'id', 'Duplicate symmetric key');
    }
    symmetricKeys.add(key);
  }

  AtAsymmetricKey? getKeyPair(String pairId) {
    for (final key in asymmetricKeys) {
      if (key.pairId == pairId) {
        return key;
      }
    }
    return null;
  }

  AtSymmetricKey? getSymmetricKey(String id) {
    for (final key in symmetricKeys) {
      if (key.id == id) {
        return key;
      }
    }
    return null;
  }
}

sealed class AtKeysMaterial {
  const AtKeysMaterial();

  String get purpose;
  String get algorithm;
}

class AtAsymmetricKey implements AtKeysMaterial {
  final String pairId;
  @override
  final String purpose;
  @override
  final String algorithm;
  final KeyFingerprint? fingerprint;
  final AtBytes publicKey;
  final AtBytes privateKey;
  final KeyProtection? publicKeyProtection;
  final KeyProtection? privateKeyProtection;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;

  const AtAsymmetricKey({
    required this.pairId,
    required this.purpose,
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
    this.fingerprint,
    this.publicKeyProtection,
    this.privateKeyProtection,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
  });
}

class AtSymmetricKey implements AtKeysMaterial {
  final String id;
  @override
  final String purpose;
  @override
  final String algorithm;
  final AtBytes bytes;
  final KeyProtection? protection;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;

  const AtSymmetricKey({
    required this.id,
    required this.purpose,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
  });
}
