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

/// The cryptographic role a key material plays (independent of the algorithm
/// family — see [KeyAlgorithmType]).
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

enum KeyPartStatus { active, retired, revoked, dead }

/// One cryptographic key material — e.g. the public half of an encryption
/// keypair. This is the object app code interacts with everywhere in
/// [AtKeys]'s API (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`,
/// `retireKey`); it is fully self-describing (`keyId`/`enrollmentId`
/// included) so it never needs an owning wrapper to be meaningful on
/// its own.
final class AtKeysMaterial {
  final String keyId;
  final String? enrollmentId;
  final CryptographicKeyType keyPartType;
  final KeyAlgorithmType keyAlgorithmType;
  final AtBytes bytes;
  final List<String> operations;
  final DateTime createdAt;
  final KeyPartStatus status;

  const AtKeysMaterial({
    required this.keyId,
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
    String? enrollmentId,
  }) {
    const assurance = AtKeysAssurance();
    final material = AtKeysMaterial(
      keyId: keyId,
      enrollmentId: enrollmentId,
      keyPartType: assurance.expectEnum(
          json['keyPartType'], CryptographicKeyType.values, 'keyPartType'),
      keyAlgorithmType: assurance.expectEnum(json['keyAlgorithmType'],
          KeyAlgorithmType.values, 'keyAlgorithmType'),
      bytes: assurance.expectBytes(json['bytes'], 'bytes'),
      operations:
          assurance.optionalStringList(json['operations'], 'operations'),
      createdAt: assurance.expectDateTime(json['createdAt'], 'createdAt'),
      status: assurance.expectEnum(json['status'] ?? KeyPartStatus.active.name,
          KeyPartStatus.values, 'status'),
    );
    return material;
  }

  /// A copy of this material with only [status] replaced.
  AtKeysMaterial withStatus(KeyPartStatus status) {
    return AtKeysMaterial(
      keyId: keyId,
      enrollmentId: enrollmentId,
      keyPartType: keyPartType,
      keyAlgorithmType: keyAlgorithmType,
      bytes: bytes,
      operations: operations,
      createdAt: createdAt,
      status: status,
    );
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
        enrollmentId,
        keyPartType,
        keyAlgorithmType,
        bytes.toString(),
        Object.hashAll(operations),
        createdAt,
        status,
      );
}

/// Parses the typed-keys document's `keys` array into a flat list of
/// [AtKeysMaterial].
/// Validating each entry's `keyParts` (no duplicate
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
    final enrollmentId = assurance.optionalString(
        entryJson['enrollmentId'], '$fieldPrefix.enrollmentId');
    final keyPartsJson =
        assurance.expectList(entryJson['keyParts'], '$fieldPrefix.keyParts');

    final seenKeyPartTypes = <CryptographicKeyType>{};
    for (final part in keyPartsJson.asMap().entries) {
      final partJson =
          assurance.expectMap(part.value, '$fieldPrefix.keyParts[${part.key}]');
      final material = AtKeysMaterial.fromJson(
        partJson,
        keyId: keyId,
        enrollmentId: enrollmentId,
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

/// Encodes a flat list of [AtKeysMaterial] into the typed-keys document's
/// nested
/// `keys` shape, grouping materials that share a `keyId` (e.g. the
/// public+private halves of a keypair) and validating that every material in
/// a group agrees on `enrollmentId` and doesn't repeat a `keyPartType`.
List<Map<String, dynamic>> encodeAtKeysDocument(
  Iterable<AtKeysMaterial> materials,
) {
  final groups = <String, List<AtKeysMaterial>>{};
  for (final material in materials) {
    final group = groups.putIfAbsent(material.keyId, () => []);
    if (group.isNotEmpty) {
      final first = group.first;
      if (material.enrollmentId != first.enrollmentId) {
        throw AtKeysValidationException(
            'Material for keyId "${material.keyId}" does not match the enrollmentId of its group');
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
