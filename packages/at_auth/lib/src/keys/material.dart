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

  factory KeyRotation.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status'];
    if (statusValue is! String || statusValue.isEmpty) {
      throw ArgumentError.value(statusValue, 'status');
    }

    final createdAtValue = json['createdAt'];
    if (createdAtValue is! String || createdAtValue.isEmpty) {
      throw ArgumentError.value(createdAtValue, 'createdAt');
    }

    final retiredAtValue = json['retiredAt'];
    if (retiredAtValue is! String || retiredAtValue.isEmpty) {
      throw ArgumentError.value(retiredAtValue, 'retiredAt');
    }

    return KeyRotation(
      status: KeyRotationStatus.values.byName(statusValue),
      createdAt: DateTime.parse(createdAtValue),
      retiredAt: DateTime.parse(retiredAtValue),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'retiredAt': retiredAt.toUtc().toIso8601String(),
    };
  }

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
