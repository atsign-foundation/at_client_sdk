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

enum KeyRotationStatus {
  active,
  retired,
  dead,
}

class KeyFingerprint {
  final String algorithm;
  final AtBytes value;

  const KeyFingerprint({
    required this.algorithm,
    required this.value,
  });

  @override
  bool operator ==(Object other) {
    return other is KeyFingerprint &&
        other.algorithm == algorithm &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(algorithm, value);
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

  @override
  bool operator ==(Object other) {
    return other is KeyProtection &&
        other.keyRef == keyRef &&
        other.algorithm == algorithm &&
        other.iv == iv;
  }

  @override
  int get hashCode => Object.hash(keyRef, algorithm, iv);
}

class KeyRotation {
  final KeyRotationStatus status;
  final DateTime createdAt;
  final DateTime retiredAt;

  const KeyRotation({
    required this.status,
    required this.createdAt,
    required this.retiredAt,
  });

  @override
  bool operator ==(Object other) {
    return other is KeyRotation &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.retiredAt == retiredAt;
  }

  @override
  int get hashCode => Object.hash(status, createdAt, retiredAt);
}

class AtKeysSet {
  final Atsign atsign;
  String? enrollmentId;
  final Map<String, AtKeyPair> _keyPairs;
  final Map<String, AtSymmetricKey> _symmetricKeys;

  AtKeysSet({
    required this.atsign,
    required List<AtKeyPair> keyPairs,
    required List<AtSymmetricKey> symmetricKeys,
    this.enrollmentId,
  })  : _keyPairs = _indexAsymmetricKeys(keyPairs),
        _symmetricKeys = _indexSymmetricKeys(symmetricKeys);

  List<AtKeyPair> get asymmetricKeys => List.unmodifiable(_keyPairs.values);

  List<AtSymmetricKey> get symmetricKeys =>
      List.unmodifiable(_symmetricKeys.values);

  void addKey(AtKeysMaterial key) {
    switch (key) {
      case AtKeyPair():
        _addKeyPair(key);
      case AtSymmetricKey():
        _addSymmetricKey(key);
    }
  }

  void addKeys(Iterable<AtKeysMaterial> keys) {
    for (final key in keys) {
      addKey(key);
    }
  }

  void _addKeyPair(AtKeyPair key) {
    if (_keyPairs.containsKey(key.pairId)) {
      throw ArgumentError.value(key.pairId, 'pairId', 'Duplicate key pair');
    }
    _keyPairs[key.pairId] = key;
  }

  void _addSymmetricKey(AtSymmetricKey key) {
    if (_symmetricKeys.containsKey(key.id)) {
      throw ArgumentError.value(key.id, 'id', 'Duplicate symmetric key');
    }
    _symmetricKeys[key.id] = key;
  }

  AtKeyPair? getKeyPair(String pairId) {
    return _keyPairs[pairId];
  }

  AtSymmetricKey? getSymmetricKey(String id) {
    return _symmetricKeys[id];
  }

  @override
  bool operator ==(Object other) {
    return other is AtKeysSet &&
        other.atsign == atsign &&
        other.enrollmentId == enrollmentId &&
        _listEquals(other.asymmetricKeys, asymmetricKeys) &&
        _listEquals(other.symmetricKeys, symmetricKeys);
  }

  @override
  int get hashCode => Object.hash(
        atsign,
        enrollmentId,
        Object.hashAll(asymmetricKeys),
        Object.hashAll(symmetricKeys),
      );

  static Map<String, AtKeyPair> _indexAsymmetricKeys(
    List<AtKeyPair> keys,
  ) {
    final result = <String, AtKeyPair>{};
    for (final key in keys) {
      if (result.containsKey(key.pairId)) {
        throw ArgumentError.value(key.pairId, 'pairId', 'Duplicate key pair');
      }
      result[key.pairId] = key;
    }
    return result;
  }

  static Map<String, AtSymmetricKey> _indexSymmetricKeys(
    List<AtSymmetricKey> keys,
  ) {
    final result = <String, AtSymmetricKey>{};
    for (final key in keys) {
      if (result.containsKey(key.id)) {
        throw ArgumentError.value(key.id, 'id', 'Duplicate symmetric key');
      }
      result[key.id] = key;
    }
    return result;
  }
}

sealed class AtKeysMaterial {
  const AtKeysMaterial();

  String get purpose;
  String get algorithm;
}

class AtKeyPair extends AtKeysMaterial {
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
  final KeyRotation? rotation;
  final List<String> operations;

  const AtKeyPair({
    required this.pairId,
    required this.purpose,
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
    this.fingerprint,
    this.publicKeyProtection,
    this.privateKeyProtection,
    this.rotation,
    this.operations = const [],
  }) : super();

  @override
  bool operator ==(Object other) {
    return other is AtKeyPair &&
        other.pairId == pairId &&
        other.purpose == purpose &&
        other.algorithm == algorithm &&
        other.fingerprint == fingerprint &&
        other.publicKey == publicKey &&
        other.privateKey == privateKey &&
        other.publicKeyProtection == publicKeyProtection &&
        other.privateKeyProtection == privateKeyProtection &&
        other.rotation == rotation &&
        _listEquals(other.operations, operations);
  }

  @override
  int get hashCode => Object.hash(
        pairId,
        purpose,
        algorithm,
        fingerprint,
        publicKey,
        privateKey,
        publicKeyProtection,
        privateKeyProtection,
        rotation,
        Object.hashAll(operations),
      );
}

class AtSymmetricKey extends AtKeysMaterial {
  final String id;
  @override
  final String purpose;
  @override
  final String algorithm;
  final AtBytes bytes;
  final KeyProtection? protection;
  final KeyRotation? rotation;
  final List<String> operations;

  const AtSymmetricKey({
    required this.id,
    required this.purpose,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.rotation,
    this.operations = const [],
  }) : super();

  @override
  bool operator ==(Object other) {
    return other is AtSymmetricKey &&
        other.id == id &&
        other.purpose == purpose &&
        other.algorithm == algorithm &&
        other.bytes == bytes &&
        other.protection == protection &&
        other.rotation == rotation &&
        _listEquals(other.operations, operations);
  }

  @override
  int get hashCode => Object.hash(
        id,
        purpose,
        algorithm,
        bytes,
        protection,
        rotation,
        Object.hashAll(operations),
      );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
