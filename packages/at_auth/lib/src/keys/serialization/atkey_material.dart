import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_commons/at_commons.dart';

/// Known values for [AtKeysMaterial.keyAlgorithmType] — the algorithm family
/// used by a key material, independent of its cryptographic role (see
/// [CryptographicKeyType]).
///
/// The field is an open `String`, not an enum: a reader must accept — and
/// round-trip unmodified on flush — values it does not recognise, so a
/// keyfile written by a newer client stays readable and losslessly
/// flushable by an older one. Tokens carry their parameter set and reuse
/// the literals the Atsign Protocol already uses elsewhere (the
/// pkam/enrollment `signingAlgo` values `rsa2048`/`mldsa65`/
/// `ecc_secp256r1`). Values are case-sensitive.
///
/// **Do not change any existing value below.** These strings are persisted
/// in `.atKeys` files and enrollment payloads already sitting on disk and on
/// the wire across the Atsign Protocol ecosystem (this client, other at_client
/// implementations, atServer). Renaming or re-casing one — even to fix a
/// typo — orphans every key material that was already written with the old
/// value: readers keyed on the old string stop recognizing it, and it fails
/// [known]'s membership check used by warn-level tooling. New algorithms get
/// a new token appended; existing tokens are permanent once shipped. See
/// `test/atkey_material_test.dart` for the tripwire test that pins these.
abstract final class KeyAlgorithmType {
  static const String aes256 = 'aes256';
  static const String rsa2048 = 'rsa2048';
  static const String eccSecp256r1 = 'ecc_secp256r1';
  static const String ed25519 = 'ed25519';
  static const String x25519 = 'x25519';
  static const String mlKem768 = 'mlkem768';
  static const String mlDsa65 = 'mldsa65';

  /// X-Wing hybrid KEM (ML-KEM-768 + X25519) — the KEM used for APKAM key
  /// packages, nskey keypairs and `pqpublickey`.
  static const String xWing = 'xwing';

  /// The tokens this version knows about. For warn-level tooling only —
  /// never reject a value for not being in this set.
  static const Set<String> known = {
    aes256,
    rsa2048,
    eccSecp256r1,
    ed25519,
    x25519,
    mlKem768,
    mlDsa65,
    xWing,
  };
}

/// Known values for [AtKeysMaterial.keyPartType] — the mechanical role a key
/// material plays, independent of the algorithm family (see
/// [KeyAlgorithmType]).
///
/// An open `String` with the same forward-compatibility contract as
/// [KeyAlgorithmType]. Roles describe what the mathematics does; whether an
/// algorithm is classical, post-quantum or hybrid is a property of the
/// [KeyAlgorithmType] token, and deployment purpose belongs in the keyId
/// and [AtKeysMaterial.operations].
///
/// **Do not change any existing value below** — same rationale as
/// [KeyAlgorithmType]: these strings are already persisted on disk and on
/// the wire, so renaming one orphans existing key material. See
/// `test/atkey_material_test.dart` for the tripwire test that pins these.
abstract final class CryptographicKeyType {
  static const String symmetricEncryption = 'symmetricEncryption';
  static const String symmetricAuthentication = 'symmetricAuthentication';
  static const String publicEncryption = 'publicEncryption';
  static const String privateDecryption = 'privateDecryption';
  static const String publicVerification = 'publicVerification';
  static const String privateSigning = 'privateSigning';
  static const String publicEncapsulation = 'publicEncapsulation';
  static const String privateDecapsulation = 'privateDecapsulation';
  static const String publicKeyAgreement = 'publicKeyAgreement';
  static const String privateKeyAgreement = 'privateKeyAgreement';

  /// The tokens this version knows about. For warn-level tooling only —
  /// never reject a value for not being in this set.
  static const Set<String> known = {
    symmetricEncryption,
    symmetricAuthentication,
    publicEncryption,
    privateDecryption,
    publicVerification,
    privateSigning,
    publicEncapsulation,
    privateDecapsulation,
    publicKeyAgreement,
    privateKeyAgreement,
  };
}

enum KeyPartStatus { active, retired, dead }

/// One cryptographic key material — e.g. the public half of an encryption
/// keypair. This is the object app code interacts with everywhere in
/// [AtKeys]'s API (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`,
/// `retireKey`); it is fully self-describing (`keyId`/`enrollmentId`
/// included) so it never needs an owning wrapper to be meaningful on
/// its own.
final class AtKeysMaterial {
  final String keyId;
  final String? enrollmentId;

  /// The material's cryptographic role — see [CryptographicKeyType] for the
  /// known tokens. Unknown values are preserved, never rejected.
  final String keyPartType;

  /// The material's algorithm family — see [KeyAlgorithmType] for the known
  /// tokens. Unknown values are preserved, never rejected.
  final String keyAlgorithmType;

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
      keyPartType:
          assurance.expectNonEmptyString(json['keyPartType'], 'keyPartType'),
      keyAlgorithmType: assurance.expectNonEmptyString(
          json['keyAlgorithmType'], 'keyAlgorithmType'),
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
      'keyPartType': keyPartType,
      'keyAlgorithmType': keyAlgorithmType,
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
    final enrollmentId = assurance.optionalString(
        entryJson['enrollmentId'], '$fieldPrefix.enrollmentId');
    final keyPartsJson =
        assurance.expectList(entryJson['keyParts'], '$fieldPrefix.keyParts');

    final seenKeyPartTypes = <String>{};
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
            'Duplicate keyPartType "${material.keyPartType}" for keyId "$keyId"');
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
            'Duplicate keyPartType "${material.keyPartType}" for keyId "${material.keyId}"');
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
