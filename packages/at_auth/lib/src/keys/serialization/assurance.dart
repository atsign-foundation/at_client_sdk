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

  static const _reservedTopLevelKeys = {'version', 'atsign', 'keys'};

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

  /// An enrollment may not contribute more than one material of the same
  /// `CryptographicKeyType` across all of its materials. (Duplicate `keyId`s
  /// across document entries are rejected earlier, by [parseAtKeysDocument].)
  void validateKeyMaterials(List<AtKeysMaterial> materials) {
    final typesByEnrollment = <String, Set<CryptographicKeyType>>{};
    for (final material in materials) {
      final enrollmentId = material.enrollmentId;
      if (enrollmentId == null) {
        continue;
      }
      final types = typesByEnrollment.putIfAbsent(enrollmentId, () => {});
      if (!types.add(material.keyPartType)) {
        throw AtKeysEnrollmentException(
            'Enrollment "$enrollmentId" has more than one ${material.keyPartType.name} key material');
      }
    }
  }

  /// All of `AtKeys.addKey`'s validation in one place. Rejects, in order:
  /// a duplicate `(keyId, keyPartType)`, an enrollmentId that disagrees with
  /// the candidate's keyId group, and a second material of the same
  /// `keyPartType` for one enrollment across keyIds (the
  /// [validateKeyMaterials] invariant, held incrementally).
  ///
  /// Throws [ArgumentError] rather than an [AtKeysValidationException]:
  /// addKey misuse is a caller programming error, not a malformed file.
  void validateAddKey({
    required Iterable<AtKeysMaterial> existing,
    required AtKeysMaterial candidate,
  }) {
    for (final material in existing) {
      if (material.keyId == candidate.keyId) {
        if (material.keyPartType == candidate.keyPartType) {
          throw ArgumentError.value(candidate.keyId, 'material',
              'AtKeys already contains a ${candidate.keyPartType.name} material for this keyId');
        }
        if (material.enrollmentId != candidate.enrollmentId) {
          throw ArgumentError.value(candidate.keyId, 'material',
              'enrollmentId "${candidate.enrollmentId}" does not match "${material.enrollmentId}" already on this keyId');
        }
      } else if (candidate.enrollmentId != null &&
          material.enrollmentId == candidate.enrollmentId &&
          material.keyPartType == candidate.keyPartType) {
        throw ArgumentError.value(candidate.enrollmentId, 'material',
            'Enrollment "${candidate.enrollmentId}" already has a ${candidate.keyPartType.name} key material');
      }
    }
  }

  void validateMapUpdate({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> candidate,
  }) {
    final existingMaterials = _decode(existing);
    final candidateMaterials = _decode(candidate);

    // A legacy -> typed-keys upgrade legitimately introduces the atsign and
    // version, so only pin them when the existing file is already a
    // typed-keys document.
    if (existing.containsKey('version')) {
      _assertSame(existing['atsign'], candidate['atsign'], 'map.atsign');
      _assertSame(existing['version'], candidate['version'], 'map.version');
    }
    _assertLegacyPreserved(
      _legacyJsonOf(existing),
      _legacyJsonOf(candidate),
      'map.legacy',
    );
    _assertMaterialsPreserved(existingMaterials, candidateMaterials);
  }

  List<AtKeysMaterial> _decode(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return const [];
    }
    final materials = parseAtKeysDocument(expectList(json['keys'], 'keys'));
    validateKeyMaterials(materials);
    return materials;
  }

  /// Legacy fields are just "everything except the reserved typed-keys
  /// top-level keys" — no separate nested blob to unwrap.
  Map<String, dynamic> _legacyJsonOf(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return json;
    }
    return {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Every existing `(keyId, keyPartType)` must survive in the candidate with
  /// identical fields, except `status`, which may move forward
  /// (active → retired → dead) but never backward. New keyIds — and new parts
  /// on an existing keyId — are additions, not losses, so they pass.
  void _assertMaterialsPreserved(
    List<AtKeysMaterial> existing,
    List<AtKeysMaterial> candidate,
  ) {
    final candidateByPart = {
      for (final material in candidate)
        (material.keyId, material.keyPartType): material,
    };

    for (final material in existing) {
      final path = 'map.keys.${material.keyId}.${material.keyPartType.name}';
      final counterpart =
          candidateByPart[(material.keyId, material.keyPartType)];
      if (counterpart == null) {
        throw AtKeysAssuranceException('$path is not preserved');
      }
      if (material.withStatus(counterpart.status) != counterpart) {
        throw AtKeysAssuranceException('$path changed during AtKeys assurance');
      }
      if (counterpart.status.index < material.status.index) {
        throw AtKeysAssuranceException(
            '$path status moved backward (${material.status.name} → ${counterpart.status.name})');
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
