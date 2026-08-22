import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_commons/at_commons.dart';

/// Known values for [CryptographicMaterial.keyAlgorithmType] — the algorithm family
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
/// value: readers keyed on the old string stop recognizing it, and it drops
/// out of [known], whose membership `test/atkey_material_test.dart` pins
/// exactly. New algorithms get a new token appended; existing tokens are
/// permanent once shipped. See
/// `test/atkey_material_test.dart` for the tripwire test that pins these.
abstract final class KeyAlgorithmType {
  static const String aes256 = 'aes256';
  static const String rsa2048 = 'rsa2048';
  static const String eccSecp256r1 = 'ecc_secp256r1';
  static const String ed25519 = 'ed25519';
  static const String x25519 = 'x25519';
  static const String mlKem768 = 'mlkem768';
  static const String mlDsa65 = 'mldsa65';

  /// X-Wing hybrid KEM (ML-KEM-768 + X25519) — one of the two KEMs an APKAM
  /// key package or nskey keypair may use. The atSign-level `pq_signing_root`
  /// is not on this list: it is ML-DSA-65, a signing key with nothing to
  /// encapsulate to.
  static const String xWing = 'xwing';

  /// Pure ML-KEM-1024 (FIPS 203) — the other, for deployments that need key
  /// establishment with no non-FIPS component and no hybrid combiner. Which of
  /// the two an atSign uses is its own configuration; a holder's key package
  /// and nskey advertisement say which they hold.
  static const String mlKem1024 = 'mlkem1024';

  /// The tokens this version knows about. For warn-level tooling only —
  /// never reject a value for not being in this set.
  static const Set<String> known = {
    aes256,
    rsa2048,
    eccSecp256r1,
    ed25519,
    x25519,
    mlKem768,
    mlKem1024,
    mlDsa65,
    xWing,
  };
}

/// Known values for [CryptographicMaterial.keyPartType] — the mechanical role a key
/// material plays, independent of the algorithm family (see
/// [KeyAlgorithmType]).
///
/// An open `String` with the same forward-compatibility contract as
/// [KeyAlgorithmType]. Roles describe what the mathematics does; whether an
/// algorithm is classical, post-quantum or hybrid is a property of the
/// [KeyAlgorithmType] token, and deployment purpose belongs in the keyId
/// and [CryptographicMaterial.operations].
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

  /// The APKAM keypair an enrollment **authenticates** with, and nothing
  /// else — the key PKAM proves possession of.
  ///
  /// Distinct from [privateSigning] / [publicVerification], which are the
  /// keys an enrollment makes durable attestations with: signed envelopes,
  /// key packages, chain links. One key served both jobs until the two were
  /// separated, and reusing an authentication key to sign attestations is a
  /// cross-protocol surface with no reason to exist.
  ///
  /// An enrollment holds at most one ACTIVE pair of these; several active
  /// signing keys are normal, because signature agility means holding one per
  /// algorithm.
  static const String privateAuthentication = 'privateAuthentication';
  static const String publicAuthentication = 'publicAuthentication';

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
    privateAuthentication,
    publicAuthentication,
  };
}

/// Whether a key material is in use, withdrawn, or gone.
///
/// An **open `String`**, exactly like [KeyAlgorithmType] and
/// [CryptographicKeyType] beside it, and for the reason
/// [KeyAlgorithmType]'s own documentation gives: a reader must accept — and
/// round-trip unmodified on flush — values it does not recognise, so a keyfile
/// written by a newer client stays readable and losslessly flushable by an
/// older one.
///
/// This was an `enum` until 2026-08-14, which made that promise false for this
/// one field. The parse ran through a throwing `expectEnum`, so a keyfile
/// carrying any status a build did not know was refused **in its entirety** —
/// not the entry, the whole document, and the document is the user's key
/// material. Adding a value was therefore a breaking at-rest change forever.
///
/// **Do not change any existing value below.** They are persisted in `.atKeys`
/// files already on disk.
class KeyPartStatus {
  const KeyPartStatus._();

  /// In use. The default when a document omits the field entirely.
  static const String active = 'active';

  /// Withdrawn from use, kept because it is what verifies or opens what it
  /// already produced.
  static const String retired = 'retired';

  /// Not adopted at all.
  static const String dead = 'dead';

  /// The tokens this version knows about. For warn-level tooling only —
  /// never reject a value for not being in this set.
  static const Set<String> known = {active, retired, dead};

  /// Where [status] sits in the forward order, or null when this build has
  /// never heard of it.
  ///
  /// Status only moves forward. As an enum that order was declaration index,
  /// which is to say it was implicit and free; an open String has no such
  /// order, so it is stated here instead. Stating it is the better position
  /// anyway — reordering the declarations used to silently redefine every
  /// transition check in the package.
  ///
  /// **An unrecognised status has no rank, and that is not a gap to fill.**
  /// A build cannot know whether a token it has never seen sits before or
  /// after `retired`, so callers refuse a transition involving one rather
  /// than guessing a direction. Guessing "newest is furthest forward" would
  /// let a future value silently reactivate a key its owner withdrew.
  static int? rankOf(String status) => switch (status) {
        active => 0,
        retired => 1,
        dead => 2,
        _ => null,
      };
}

@Deprecated('Use CryptographicMaterial instead. This will be removed in v4')
typedef AtKeysMaterial = CryptographicMaterial;

/// One cryptographic key material — e.g. the public half of an encryption
/// keypair. This is the object app code interacts with everywhere in
/// [AtKeys]'s API (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`,
/// `retireKey`); it is fully self-describing (`keyId`/`enrollmentId`
/// included) so it never needs an owning wrapper to be meaningful on
/// its own.
final class CryptographicMaterial {
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

  /// Whether this material is in use — see [KeyPartStatus] for the known
  /// tokens. Unknown values are preserved, never rejected.
  final String status;

  const CryptographicMaterial({
    required this.keyId,
    this.enrollmentId,
    required this.keyPartType,
    required this.keyAlgorithmType,
    required this.bytes,
    this.operations = const [],
    required this.createdAt,
    this.status = KeyPartStatus.active,
  });

  factory CryptographicMaterial.fromJson(
    Map<String, dynamic> json, {
    required String keyId,
    String? enrollmentId,
  }) {
    const assurance = AtKeysAssurance();
    final material = CryptographicMaterial(
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
      // Deliberately NOT validated against [KeyPartStatus.known]: a token this
      // build has never seen is carried through and re-emitted by [toJson],
      // which is what keeps a keyfile written by a newer client readable and
      // losslessly flushable here. It still has no rank, so it is never
      // selected as active and no transition may move it.
      status: assurance.expectNonEmptyString(
          json['status'] ?? KeyPartStatus.active, 'status'),
    );
    return material;
  }

  /// A copy of this material with only [status] replaced.
  CryptographicMaterial withStatus(String status) {
    return CryptographicMaterial(
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
      // Verbatim, whatever it is. This is the half of the round-trip promise
      // that the parse's tolerance would be worthless without.
      'status': status,
      'bytes': bytes.toString(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CryptographicMaterial) return false;
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

/// Parses one container's `keys` array into a flat list of [CryptographicMaterial],
/// validating each entry's `keyParts` (no duplicate `keyPartType` within one
/// `keyId`) and rejecting a `keyId` that repeats within this container.
///
/// [enrollmentId] is the owner every material in the array is tagged with —
/// the enclosing `enrollments[]` entry's id, or null for the document's
/// `atsignKeys[]`. The container states it once and the entries do not carry
/// it: two stored copies of one fact can disagree with nothing to arbitrate.
/// An entry that carries one anyway is refused rather than ignored, because
/// ignoring it would silently file the material under a different owner than
/// the document says.
///
/// ⚠️ **A keyId is unique within its container, not within the document.**
/// Two enrollments may each hold `auth:mldsa65:1`; identity is
/// `(enrollment, keyId)`.
///
/// [fieldPrefix] names this container in parse diagnostics.
List<CryptographicMaterial> parseAtKeysDocument(
  List<dynamic> keysJson, {
  String? enrollmentId,
  String fieldPrefix = 'keys',
}) {
  const assurance = AtKeysAssurance();
  final materials = <CryptographicMaterial>[];
  final seenKeyIds = <String>{};

  for (final entry in keysJson.asMap().entries) {
    final entryPrefix = '$fieldPrefix[${entry.key}]';
    final entryJson = assurance.expectMap(entry.value, entryPrefix);
    final keyId = assurance.expectNonEmptyString(
        entryJson['keyId'], '$entryPrefix.keyId');
    if (!seenKeyIds.add(keyId)) {
      throw AtKeysValidationException('Duplicate atKeys keyId "$keyId"');
    }
    if (entryJson.containsKey('enrollmentId')) {
      throw AtKeysValidationException(
          '$entryPrefix carries an enrollmentId. Key entries state no owner of '
          'their own — the container states it once. A document written this '
          'way predates the enrollments[]/atsignKeys[] shape and must be '
          'regenerated.');
    }
    final keyPartsJson =
        assurance.expectList(entryJson['keyParts'], '$entryPrefix.keyParts');

    final seenKeyPartTypes = <String>{};
    for (final part in keyPartsJson.asMap().entries) {
      final partJson =
          assurance.expectMap(part.value, '$fieldPrefix.keyParts[${part.key}]');
      final material = CryptographicMaterial.fromJson(
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

/// Encodes one container's materials into its nested `keys` shape, grouping
/// materials that share a `keyId` (e.g. the public+private halves of a
/// keypair) and validating that every material in a group agrees on
/// `enrollmentId` and doesn't repeat a `keyPartType`.
///
/// The owner is **not** emitted: the enclosing `enrollments[]` entry states it
/// once, and `atsignKeys[]` states it by being where it is. The agreement
/// check stays, because a group whose halves name different owners is a
/// programming error that would now be encoded as if it had none.
List<Map<String, dynamic>> encodeAtKeysDocument(
  Iterable<CryptographicMaterial> materials,
) {
  final groups = <String, List<CryptographicMaterial>>{};
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
