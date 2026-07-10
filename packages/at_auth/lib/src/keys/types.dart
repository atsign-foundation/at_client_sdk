import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_commons/at_commons.dart';

/// The algorithm family used by a key material (independent of its
/// cryptographic role — see [CryptographicKeyType]).
enum KeyAlgorithmType {
  aes,
  des,
  rsa,
  ecc,
  mlKem,
  mlDsa,
  slhDsa,
  falcon,
  userDefined
}

/// The cryptographic role a key material plays. This is the richer, PQ-ready
/// successor to the old public/private/symmetric split (still present as
/// [AtKeyVisibility], used only to derive a material's atKey prefix).
enum CryptographicKeyType {
  symmetricDataEncryption,
  symmetricMessageAuthentication,
  session,
  keyWrapping,
  masterDerivation,
  classicalPublicEncryption,
  classicalPrivateDecryption,
  classicalPublicVerification,
  classicalPrivateSigning,
  classicalKeyAgreement,
  postQuantumPublicVerification,
  postQuantumPrivateSigning,
  postQuantumEncapsulation,
  postQuantumDecapsulation,
  statefulHashPrivateSigning,
  statefulHashPublicVerification,
  hybridPublic,
  hybridPrivate,
  userDefined,
}

/// Drives a material's atKey prefix (`'$visibility:$keyId'`) — matches the
/// atServer's real key-naming convention, independent of [CryptographicKeyType].
enum AtKeyVisibility { public, private, symmetric }

enum KeyPartStatus { active, retired }

/// One cryptographic key material — e.g. the public half of an encryption
/// keypair. This is the object app code interacts with everywhere in
/// [AtKeys]'s API (`addKey`, `getMaterial`, `keysForEnrollment`, ...); it is
/// fully self-describing (`keyId`/`keyGroup`/`enrollmentId` included) so it
/// never needs an owning wrapper to be meaningful on its own.
final class AtKeysMaterial {
  final String keyId;
  final String keyGroup;
  final String? enrollmentId;
  final CryptographicKeyType keyPartType;
  final AtKeyVisibility visibility;
  final KeyAlgorithmType keyAlgorithmType;
  final AtBytes bytes;
  final List<String> operations;
  final DateTime createdAt;
  final KeyPartStatus status;

  const AtKeysMaterial({
    required this.keyId,
    required this.keyGroup,
    this.enrollmentId,
    required this.keyPartType,
    required this.visibility,
    required this.keyAlgorithmType,
    required this.bytes,
    this.operations = const [],
    required this.createdAt,
    this.status = KeyPartStatus.active,
  });

  /// The atServer-facing key name for this material, derived (not stored) —
  /// matches the atServer's real key-naming convention.
  String get atKey => '${visibility.name}:$keyId';

  factory AtKeysMaterial.fromJson(
    Map<String, dynamic> json, {
    required String keyId,
    required String keyGroup,
    String? enrollmentId,
    required String fieldPrefix,
  }) {
    const assurance = AtKeysAssurance();
    final material = AtKeysMaterial(
      keyId: keyId,
      keyGroup: keyGroup,
      enrollmentId: enrollmentId,
      keyPartType: assurance.expectEnum(json['keyPartType'],
          CryptographicKeyType.values, '$fieldPrefix.keyPartType'),
      visibility: assurance.expectEnum(json['visibility'],
          AtKeyVisibility.values, '$fieldPrefix.visibility'),
      keyAlgorithmType: assurance.expectEnum(json['keyAlgorithmType'],
          KeyAlgorithmType.values, '$fieldPrefix.keyAlgorithmType'),
      bytes: assurance.expectBytes(json['bytes'], '$fieldPrefix.bytes'),
      operations: assurance.optionalStringList(
          json['operations'], '$fieldPrefix.operations'),
      createdAt:
          assurance.expectDateTime(json['createdAt'], '$fieldPrefix.createdAt'),
      status: assurance.expectEnum(json['status'] ?? KeyPartStatus.active.name,
          KeyPartStatus.values, '$fieldPrefix.status'),
    );
    final wireAtKey =
        assurance.expectNonEmptyString(json['atKey'], '$fieldPrefix.atKey');
    assurance.expectAtKeyMatches(
        wireAtKey, material.atKey, '$fieldPrefix.atKey');
    return material;
  }

  Map<String, dynamic> toJson() {
    return {
      'keyPartType': keyPartType.name,
      'visibility': visibility.name,
      'keyAlgorithmType': keyAlgorithmType.name,
      if (operations.isNotEmpty) 'operations': operations,
      'atKey': atKey,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      'bytes': bytes.toString(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AtKeysMaterial) return false;
    return keyId == other.keyId &&
        keyGroup == other.keyGroup &&
        enrollmentId == other.enrollmentId &&
        keyPartType == other.keyPartType &&
        visibility == other.visibility &&
        keyAlgorithmType == other.keyAlgorithmType &&
        bytes.toString() == other.bytes.toString() &&
        _listEquals(operations, other.operations) &&
        createdAt == other.createdAt &&
        status == other.status;
  }

  @override
  int get hashCode => Object.hash(
        keyId,
        keyGroup,
        enrollmentId,
        keyPartType,
        visibility,
        keyAlgorithmType,
        bytes.toString(),
        Object.hashAll(operations),
        createdAt,
        status,
      );
}

/// Groups one `keyId`'s [AtKeysMaterial]s (e.g. the public+private halves of
/// a keypair) for the wire's nested shape and for cross-material validation
/// (consistent keyGroup/enrollmentId, no duplicate `keyPartType`). This is an
/// internal serialization/validation helper — [AtKeys]'s own API (`addKey`,
/// `getMaterial`, ...) works with flat [AtKeysMaterial]s, never this type.
final class AtKeysRecord {
  final String keyId;
  final String keyGroup;
  final String? enrollmentId;
  final Map<CryptographicKeyType, AtKeysMaterial> materials;

  AtKeysRecord({
    required this.keyId,
    required this.keyGroup,
    this.enrollmentId,
    required Iterable<AtKeysMaterial> materials,
  }) : materials = _materialsByType(materials, keyId, keyGroup, enrollmentId);

  static Map<CryptographicKeyType, AtKeysMaterial> _materialsByType(
    Iterable<AtKeysMaterial> materials,
    String keyId,
    String keyGroup,
    String? enrollmentId,
  ) {
    final byType = <CryptographicKeyType, AtKeysMaterial>{};
    for (final material in materials) {
      if (material.keyId != keyId ||
          material.keyGroup != keyGroup ||
          material.enrollmentId != enrollmentId) {
        throw AtKeysValidationException(
            'Material for keyId "${material.keyId}" does not match AtKeysRecord "$keyId"');
      }
      if (byType.containsKey(material.keyPartType)) {
        throw AtKeysValidationException(
            'Duplicate keyPartType "${material.keyPartType.name}" within one AtKeysRecord');
      }
      byType[material.keyPartType] = material;
    }
    return Map.unmodifiable(byType);
  }

  factory AtKeysRecord.fromJson(Map<String, dynamic> json, {int? index}) {
    const assurance = AtKeysAssurance();
    final fieldPrefix = index == null ? 'keys' : 'keys[$index]';
    final keyId =
        assurance.expectNonEmptyString(json['keyId'], '$fieldPrefix.keyId');
    final keyGroup = assurance.expectNonEmptyString(
        json['keyGroup'], '$fieldPrefix.keyGroup');
    final enrollmentId = assurance.optionalString(
        json['enrollmentId'], '$fieldPrefix.enrollmentId');
    final keyPartsJson =
        assurance.expectList(json['keyParts'], '$fieldPrefix.keyParts');

    final materials = keyPartsJson.asMap().entries.map((entry) {
      final partPrefix = '$fieldPrefix.keyParts[${entry.key}]';
      final partJson = assurance.expectMap(entry.value, partPrefix);
      return AtKeysMaterial.fromJson(
        partJson,
        keyId: keyId,
        keyGroup: keyGroup,
        enrollmentId: enrollmentId,
        fieldPrefix: partPrefix,
      );
    }).toList();

    return AtKeysRecord(
      keyId: keyId,
      keyGroup: keyGroup,
      enrollmentId: enrollmentId,
      materials: materials,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keyId': keyId,
      'keyGroup': keyGroup,
      if (enrollmentId != null) 'enrollmentId': enrollmentId,
      'keyParts':
          materials.values.map((material) => material.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AtKeysRecord) return false;
    return keyId == other.keyId &&
        keyGroup == other.keyGroup &&
        enrollmentId == other.enrollmentId &&
        _mapEquals(materials, other.materials);
  }

  @override
  int get hashCode => Object.hash(
        keyId,
        keyGroup,
        enrollmentId,
        Object.hashAllUnordered(materials.entries
            .map((entry) => Object.hash(entry.key, entry.value))),
      );
}

bool _listEquals<T>(List<T> left, List<T> right) {
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

bool _mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
