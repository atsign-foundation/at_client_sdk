import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysAssuranceException extends AtKeysValidationException {
  AtKeysAssuranceException(super.message);
}

/// Single home for all atKeys validation: low-level parsing/value checks
/// (`expect*`/`optional*`, called by the models' `fromJson`) and cross-material
/// structural invariants (`validateKeyMaterials`, `validateAddKey`,
/// `validateMapUpdate`).
class AtKeysAssurance {
  const AtKeysAssurance();

  // Must stay identical to AtKeys._reservedTopLevelKeys: this decides which
  // fields are "legacy" for the update assurance, and that one decides it for
  // the parse. Disagreeing means a field one of them treats as structure the
  // other treats as a legacy value to be preserved verbatim.
  static const _reservedTopLevelKeys = {
    'version',
    'atsign',
    'enrollments',
    'atSignKeys',
  };

  // ---- low-level parsing/value primitives, called by the models' fromJson ----

  String expectNonEmptyString(Object? value, String fieldName) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw AtKeysParseException('Expected string in $fieldName');
  }

  String? optionalString(Object? value, String fieldName) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw AtKeysParseException('Expected string at $fieldName');
  }

  List<String> optionalStringList(Object? value, String fieldName) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw AtKeysParseException('Expected array at $fieldName');
    }
    return value
        .asMap()
        .entries
        .map((entry) =>
            expectNonEmptyString(entry.value, '$fieldName[${entry.key}]'))
        .toList();
  }

  int expectInt(Object? value, String fieldName) {
    if (value is int) {
      return value;
    }
    throw AtKeysParseException('Expected integer in $fieldName');
  }

  Map<String, dynamic> expectMap(Object? value, String fieldName) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw AtKeysParseException('Expected object at $fieldName');
  }

  List<dynamic> expectList(Object? value, String fieldName) {
    if (value is List) {
      return value;
    }
    throw AtKeysParseException('Expected array at $fieldName');
  }

  AtBytes expectBytes(Object? value, String fieldName) {
    final token = expectNonEmptyString(value, fieldName);
    try {
      base64Decode(token);
    } on FormatException catch (e) {
      throw AtKeysValidationException('Malformed base64 at $fieldName: $e');
    }
    return AtBytes.fromString(token);
  }

  T expectEnum<T extends Enum>(
    Object? value,
    List<T> values,
    String fieldName,
  ) {
    final token = expectNonEmptyString(value, fieldName);
    for (final candidate in values) {
      if (candidate.name == token) {
        return candidate;
      }
    }
    throw AtKeysValidationException('Unsupported value "$token" at $fieldName');
  }

  DateTime expectDateTime(Object? value, String fieldName) {
    final token = expectNonEmptyString(value, fieldName);
    try {
      return DateTime.parse(token);
    } on FormatException catch (e) {
      throw AtKeysParseException('Malformed date at $fieldName: $e');
    }
  }

  // ---- cross-record structural invariants ----

  /// An enrollment may not contribute more than one **active** material of
  /// the same `(CryptographicKeyType, KeyAlgorithmType)`.
  /// (Duplicate `keyId`s within a container are rejected earlier, by
  /// [parseAtKeysDocument].)
  ///
  /// ⚠️ **This is the READ path and it tolerates several live enrollments.**
  /// One live enrollment per install is what this build *writes*, and
  /// [refuseSecondLiveEnrollment] is where that is enforced. Refusing a
  /// second one here as well would make the plurality unenableable: the first
  /// build to emit two would be unreadable by every build that predates it,
  /// so no build could ever start emitting them. A document holding two is
  /// read, and the ambiguity surfaces at
  /// `AtKeys.resolveAuthenticatingEnrollment()` — the point where a caller
  /// actually needs one answer — rather than taking the whole keyfile down at
  /// parse.
  ///
  /// Only active material counts, so retiring a key frees its slot for a
  /// replacement. Counting every status instead would make a same-enrollment
  /// rotation impossible: the superseded key is retained forever — the bytes
  /// are still needed to verify what they signed — so its slot would never
  /// come free and every new generation would need a new enrollment.
  ///
  /// Uniqueness is per algorithm, not per role, because signature agility
  /// means an enrollment holds one active SIGNING key for each algorithm it
  /// still signs with — several active `privateSigning` materials at once is
  /// the normal state, and only a second one of the same algorithm is a
  /// duplicate.
  ///
  /// The document-wide authentication rule is deliberately NOT per-algorithm:
  /// one live enrollment per install is the model, so a second active
  /// authentication key is a corrupt keyfile whatever algorithm it names.
  ///
  /// ⚠️ It no longer answers "which enrollment does this keyfile authenticate
  /// as" — that is the caller's to state, with
  /// `AtKeys.resolveAuthenticatingEnrollment()` there for a cold start that
  /// has nothing to state it from. This rule is a write-side invariant now,
  /// and a reader meeting a document with two live enrollments gets a refusal
  /// from here rather than a silently chosen one.
  void validateKeyMaterials(List<AtKeysMaterial> materials) {
    final typesByEnrollment = <String, Set<String>>{};
    for (final material in materials) {
      if (material.status != KeyPartStatus.active) {
        continue;
      }
      final enrollmentId = material.enrollmentId;
      if (enrollmentId == null) {
        continue;
      }
      final types = typesByEnrollment.putIfAbsent(enrollmentId, () => {});
      if (!types.add(
          '${material.keyPartType}/${material.keyAlgorithmType}')) {
        throw AtKeysEnrollmentException(
            'Enrollment "$enrollmentId" has more than one active '
            '${material.keyPartType} key material for '
            '${material.keyAlgorithmType}');
      }
    }
  }

  /// Names an enrollment in a diagnostic, distinguishing "no enrollment id"
  /// from an enrollment literally called `null`.
  String _enrollmentLabel(String? enrollmentId) =>
      enrollmentId == null ? 'no enrollment id' : '"$enrollmentId"';

  /// All of `AtKeys.addKey`'s validation in one place. Rejects, in order:
  /// a duplicate `(enrollmentId, keyId, keyPartType)`, and a second material
  /// of the same `keyPartType` for one enrollment across keyIds (the
  /// [validateKeyMaterials] invariant, held incrementally).
  ///
  /// ⚠️ **The duplicate check is per owner, not per keyId.** Identity is
  /// `(enrollment, keyId)`: two enrollments may each hold `auth:mldsa65:1`,
  /// and they land in separate containers. What used to be a second rule
  /// here — that every material sharing a keyId must agree on its
  /// enrollmentId — is what that change removes, not something it relaxes:
  /// the container states the owner once, so there is no longer a
  /// document-wide keyId group for them to disagree about.
  ///
  /// Throws [ArgumentError] rather than an [AtKeysValidationException]:
  /// addKey misuse is a caller programming error, not a malformed file.
  void validateAddKey({
    required Iterable<AtKeysMaterial> existing,
    required AtKeysMaterial candidate,
  }) {
    for (final material in existing) {
      if (material.keyId == candidate.keyId &&
          material.enrollmentId == candidate.enrollmentId) {
        if (material.keyPartType == candidate.keyPartType) {
          throw ArgumentError.value(candidate.keyId, 'material',
              'AtKeys already contains a ${candidate.keyPartType} material for this keyId');
        }
      } else if (candidate.status == KeyPartStatus.active &&
          material.status == KeyPartStatus.active &&
          candidate.enrollmentId != null &&
          material.enrollmentId == candidate.enrollmentId &&
          material.keyPartType == candidate.keyPartType &&
          material.keyAlgorithmType == candidate.keyAlgorithmType) {
        throw ArgumentError.value(candidate.enrollmentId, 'material',
            'Enrollment "${candidate.enrollmentId}" already has an active '
            '${candidate.keyPartType} key material for '
            '${candidate.keyAlgorithmType}');
      }
    }
  }

  /// Refuses a **second live enrollment** — a second active
  /// [CryptographicKeyType.privateAuthentication] anywhere in the document.
  ///
  /// The one rule here that is a **policy about what this build writes**
  /// rather than a structural invariant, which is why it is separate and why
  /// only `AtKeys.addKey` calls it. One live enrollment per install is the
  /// model; a writer producing two would be producing a keyfile whose
  /// authenticating enrollment nothing can determine.
  ///
  /// ⚠️ **The parse deliberately does NOT apply this.** A reader that refused
  /// a second entry would make plurality unenableable — the first build to
  /// write two breaks every build that predates it, so no build could ever
  /// start. Reading is tolerant; the ambiguity surfaces at
  /// `AtKeys.resolveAuthenticatingEnrollment()`, where a caller is asking for
  /// the one answer that does not exist.
  void refuseSecondLiveEnrollment({
    required Iterable<AtKeysMaterial> existing,
    required AtKeysMaterial candidate,
  }) {
    if (candidate.status != KeyPartStatus.active ||
        candidate.keyPartType != CryptographicKeyType.privateAuthentication) {
      return;
    }
    for (final material in existing) {
      if (material.status != KeyPartStatus.active ||
          material.keyPartType !=
              CryptographicKeyType.privateAuthentication) {
        continue;
      }
      // Whatever the owner, and whatever the algorithm. The same enrollment
      // filing a second under a different algorithm is refused too: an
      // enrollment holds at most one active authentication pair, which is
      // what CryptographicKeyType.privateAuthentication documents and what
      // the per-(role, algorithm) rule above cannot see, since the two name
      // different algorithms.
      throw ArgumentError.value(candidate.enrollmentId, 'material',
          'AtKeys already holds an active authentication key, for '
          '${_enrollmentLabel(material.enrollmentId)}; retire it before '
          'filing another');
    }
  }

  void validateMapUpdate({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> candidate,
  }) {
    final existingMaterials = _decode(existing);
    final candidateMaterials = _decode(candidate);

    final existingLegacy = _legacyJsonOf(existing);

    // A legacy -> typed-keys upgrade legitimately introduces the atsign and
    // version, so only pin them when the existing file is already a
    // typed-keys document.
    if (existing.containsKey('version')) {
      _assertSame(existing['atsign'], candidate['atsign'], 'map.atsign');
      _assertSame(existing['version'], candidate['version'], 'map.version');
    } else if (candidate.containsKey('version') &&
        existingLegacy.containsKey('atsign')) {
      // A legacy document may already name its owner under `atsign` — the
      // keychain has always recorded it there, so every entry a published
      // release wrote has one — and the typed shape reserves that same name.
      // The upgrade re-homes the value rather than dropping it, so it is
      // checked here against the reserved field and taken out of the legacy
      // comparison below; leaving it in would refuse the first flush onto
      // every keyset already in the field. Compared normalized, because
      // `AtKeys.fromJson` has already normalized the reserved side.
      _assertSame(_asAtsign(existingLegacy.remove('atsign')),
          _asAtsign(candidate['atsign']), 'map.atsign');
    }
    _assertLegacyPreserved(
      existingLegacy,
      _legacyJsonOf(candidate),
      'map.legacy',
    );
    _assertMaterialsPreserved(existingMaterials, candidateMaterials);
  }

  /// Both typed containers of [json], flattened — every material carrying the
  /// owner its container names.
  List<AtKeysMaterial> _decode(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return const [];
    }
    final materials = <AtKeysMaterial>[];
    if (json.containsKey('atSignKeys')) {
      materials.addAll(parseAtKeysDocument(
          expectList(json['atSignKeys'], 'atSignKeys'),
          fieldPrefix: 'atSignKeys'));
    }
    if (json.containsKey('enrollments')) {
      final enrollments = expectList(json['enrollments'], 'enrollments');
      for (final entry in enrollments.asMap().entries) {
        final prefix = 'enrollments[${entry.key}]';
        final entryJson = expectMap(entry.value, prefix);
        final enrollmentId = expectNonEmptyString(
            entryJson['enrollmentId'], '$prefix.enrollmentId');
        materials.addAll(parseAtKeysDocument(
            expectList(entryJson['keys'], '$prefix.keys'),
            enrollmentId: enrollmentId,
            fieldPrefix: '$prefix.keys'));
      }
    }
    validateKeyMaterials(materials);
    return materials;
  }

  /// Legacy fields are just "everything except the reserved typed-keys
  /// top-level keys" — no separate nested blob to unwrap. Always a copy: the
  /// caller takes the owner out of it before comparing the rest.
  Map<String, dynamic> _legacyJsonOf(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return Map<String, dynamic>.of(json);
    }
    return {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// An atSign in the one spelling both sides can be compared in. A value that
  /// is not an atSign at all is returned unchanged, so it fails the comparison
  /// rather than the parse.
  Object? _asAtsign(Object? value) {
    if (value is! String) return value;
    try {
      return value.toAtsign().toString();
    } on InvalidAtSignException {
      return value;
    }
  }

  /// Every existing `(enrollmentId, keyId, keyPartType)` must survive in the
  /// candidate with identical fields, except `status`, which may move forward
  /// (active → retired → dead) but never backward. New keyIds — and new parts
  /// on an existing keyId — are additions, not losses, so they pass.
  ///
  /// Keyed by owner as well as keyId because identity is
  /// `(enrollment, keyId)`. Without it, two enrollments each holding
  /// `auth:mldsa65:1` alias one another in this map, and dropping one
  /// enrollment's key entirely reads as preserved because the other's answers
  /// for it.
  void _assertMaterialsPreserved(
    List<AtKeysMaterial> existing,
    List<AtKeysMaterial> candidate,
  ) {
    final candidateByPart = {
      for (final material in candidate)
        (material.enrollmentId, material.keyId, material.keyPartType): material,
    };

    for (final material in existing) {
      final owner = material.enrollmentId ?? 'atSign';
      final path = 'map.keys.$owner.${material.keyId}.${material.keyPartType}';
      final counterpart = candidateByPart[
          (material.enrollmentId, material.keyId, material.keyPartType)];
      if (counterpart == null) {
        throw AtKeysAssuranceException('$path is not preserved');
      }
      if (material.withStatus(counterpart.status) != counterpart) {
        throw AtKeysAssuranceException('$path changed during AtKeys assurance');
      }
      final before = KeyPartStatus.rankOf(material.status);
      final after = KeyPartStatus.rankOf(counterpart.status);
      if (before == null || after == null) {
        // At least one side carries a status this build does not know, so it
        // has no position in the forward order and "moved backward" is not a
        // question that can be answered. What CAN be checked is the round-trip
        // promise: such a material must come back unchanged. Requiring
        // equality is the strictest reading available, and the only one that
        // cannot silently let an unknown status be rewritten.
        if (material.status != counterpart.status) {
          throw AtKeysAssuranceException(
              '$path status changed to or from a value this build does not '
              'know (${material.status} → ${counterpart.status}), and an '
              'unrecognised status must round-trip unmodified');
        }
      } else if (after < before) {
        throw AtKeysAssuranceException(
            '$path status moved backward (${material.status} → ${counterpart.status})');
      }
    }
  }

  void _assertLegacyPreserved(
    Map<String, dynamic> existing,
    Map<String, dynamic> candidate,
    String path,
  ) {
    if (existing.isEmpty) {
      return;
    }

    for (final entry in existing.entries) {
      if (!candidate.containsKey(entry.key)) {
        throw AtKeysAssuranceException('$path.${entry.key} is not preserved');
      }
      _assertSame(entry.value, candidate[entry.key], '$path.${entry.key}');
    }
  }

  void _assertSame(Object? existing, Object? candidate, String path) {
    if (_canonicalJson(existing) != _canonicalJson(candidate)) {
      throw AtKeysAssuranceException('$path changed during AtKeys assurance');
    }
  }

  String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

  Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonicalValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalValue).toList();
    }
    return value;
  }
}
