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
/// successor to the old public/private/symmetric split.
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

enum KeyPartStatus { active, retired, dead }

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
    required this.keyAlgorithmType,
    required this.bytes,
    this.operations = const [],
    required this.createdAt,
    this.status = KeyPartStatus.active,
  });

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
    return material;
  }

  Map<String, dynamic> toJson() {
    return {
      'keyPartType': keyPartType.name,
      'keyAlgorithmType': keyAlgorithmType.name,
      if (operations.isNotEmpty) 'operations': operations,
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
        keyAlgorithmType,
        bytes.toString(),
        Object.hashAll(operations),
        createdAt,
        status,
      );
}

/// Parses the v1 document's `keys` array into a flat list of
/// [AtKeysMaterial], validating each entry's `keyParts` (no duplicate
/// `keyPartType` within one `keyId`) and rejecting a `keyId` that repeats
/// across separate entries.
List<AtKeysMaterial> parseAtKeysDocument(List<dynamic> keysJson) {
  const assurance = AtKeysAssurance();
  final materials = <AtKeysMaterial>[];
  final seenKeyIds = <String>{};

  for (final entry in keysJson.asMap().entries) {
    final fieldPrefix = 'keys[${entry.key}]';
    final entryJson = assurance.expectMap(entry.value, fieldPrefix);
    final keyId = assurance.expectNonEmptyString(
        entryJson['keyId'], '$fieldPrefix.keyId');
    if (!seenKeyIds.add(keyId)) {
      throw AtKeysValidationException('Duplicate atKeys keyId "$keyId"');
    }
    final keyGroup = assurance.expectNonEmptyString(
        entryJson['keyGroup'], '$fieldPrefix.keyGroup');
    final enrollmentId = assurance.optionalString(
        entryJson['enrollmentId'], '$fieldPrefix.enrollmentId');
    final keyPartsJson =
        assurance.expectList(entryJson['keyParts'], '$fieldPrefix.keyParts');

    final seenKeyPartTypes = <CryptographicKeyType>{};
    for (final part in keyPartsJson.asMap().entries) {
      final partPrefix = '$fieldPrefix.keyParts[${part.key}]';
      final partJson = assurance.expectMap(part.value, partPrefix);
      final material = AtKeysMaterial.fromJson(
        partJson,
        keyId: keyId,
        keyGroup: keyGroup,
        enrollmentId: enrollmentId,
        fieldPrefix: partPrefix,
      );
      if (!seenKeyPartTypes.add(material.keyPartType)) {
        throw AtKeysValidationException(
            'Duplicate keyPartType "${material.keyPartType.name}" for keyId "$keyId"');
      }
      materials.add(material);
    }
  }
  return materials;
}

/// Encodes a flat list of [AtKeysMaterial] into the v1 document's nested
/// `keys` shape, grouping materials that share a `keyId` (e.g. the
/// public+private halves of a keypair) and validating that every material in
/// a group agrees on `keyGroup`/`enrollmentId` and doesn't repeat a
/// `keyPartType`.
List<Map<String, dynamic>> encodeAtKeysDocument(
  Iterable<AtKeysMaterial> materials,
) {
  final groups = <String, List<AtKeysMaterial>>{};
  for (final material in materials) {
    final group = groups.putIfAbsent(material.keyId, () => []);
    if (group.isNotEmpty) {
      final first = group.first;
      if (material.keyGroup != first.keyGroup ||
          material.enrollmentId != first.enrollmentId) {
        throw AtKeysValidationException(
            'Material for keyId "${material.keyId}" does not match the keyGroup/enrollmentId of its group');
      }
      if (group
          .any((existing) => existing.keyPartType == material.keyPartType)) {
        throw AtKeysValidationException(
            'Duplicate keyPartType "${material.keyPartType.name}" for keyId "${material.keyId}"');
      }
    }
    group.add(material);
  }
  return groups.entries.map((entry) {
    final group = entry.value;
    return {
      'keyId': entry.key,
      'keyGroup': group.first.keyGroup,
      if (group.first.enrollmentId != null)
        'enrollmentId': group.first.enrollmentId,
      'keyParts': group.map((material) => material.toJson()).toList(),
    };
  }).toList();
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
