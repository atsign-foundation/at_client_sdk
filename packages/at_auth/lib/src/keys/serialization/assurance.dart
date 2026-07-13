import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysAssuranceException extends AtKeysValidationException {
  AtKeysAssuranceException(super.message);
}

/// Single home for all atKeys validation: low-level parsing/value checks
/// (`expect*`/`optional*`, called by the models' `fromJson`) and cross-material
/// structural invariants (`validateKeyMaterials`, `validateMapUpdate`).
class AtKeysAssurance {
  const AtKeysAssurance();

  static const _reservedTopLevelKeys = {'version', 'atSign', 'keys'};

  // ---- low-level parsing/value primitives, called from types.dart/at_keys.dart ----

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
  /// `CryptographicKeyType` (formerly one atomic `AtKeyPackage`) across all
  /// of its materials. (Duplicate `keyId`s across document entries are
  /// rejected earlier, by [parseAtKeysDocument].)
  void validateKeyMaterials(List<AtKeysMaterial> materials) {
    _validateEnrollmentGrouping(materials);
  }

  void validateMapUpdate({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> candidate,
  }) {
    final existingMaterials = _decode(existing);
    final candidateMaterials = _decode(candidate);

    _assertCodecRoundTrip(candidate);
    // A legacy -> v1 upgrade legitimately introduces the atSign and version,
    // so only pin them when the existing file is already a v1 document.
    if (existing.containsKey('version')) {
      _assertSame(existing['atSign'], candidate['atSign'], 'map.atSign');
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
    final keysJson = json['keys'];
    if (keysJson is! List) {
      return const [];
    }
    final materials = parseAtKeysDocument(keysJson);
    validateKeyMaterials(materials);
    return materials;
  }

  /// Legacy fields are just "everything except the reserved top-level v1
  /// keys" — no separate nested blob to unwrap.
  Map<String, dynamic> _legacyJsonOf(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return json;
    }
    return {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  void _assertCodecRoundTrip(Map<String, dynamic> candidate) {
    final materials = _decode(candidate);
    final reencoded = encodeAtKeysDocument(materials);
    final redecoded = parseAtKeysDocument(reencoded);

    _assertSame(
      _materialsFingerprint(materials),
      _materialsFingerprint(redecoded),
      'map.codecRoundTrip',
    );
  }
}

void _assertMaterialsPreserved(
  List<AtKeysMaterial> existing,
  List<AtKeysMaterial> candidate,
) {
  final existingByKeyId = _groupByKeyId(existing);
  final candidateByKeyId = _groupByKeyId(candidate);

  for (final entry in existingByKeyId.entries) {
    final candidateGroup = candidateByKeyId[entry.key];
    if (candidateGroup == null) {
      throw AtKeysAssuranceException(
        'Map key record "${entry.key}" is not preserved',
      );
    }
    _assertSame(
      _materialGroupFingerprint(entry.key, entry.value),
      _materialGroupFingerprint(entry.key, candidateGroup),
      'map.keys.${entry.key}',
    );
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

Map<String, List<AtKeysMaterial>> _groupByKeyId(
  List<AtKeysMaterial> materials,
) {
  final byKeyId = <String, List<AtKeysMaterial>>{};
  for (final material in materials) {
    byKeyId.putIfAbsent(material.keyId, () => []).add(material);
  }
  return byKeyId;
}

List<Map<String, dynamic>> _materialsFingerprint(
  List<AtKeysMaterial> materials,
) {
  final byKeyId = _groupByKeyId(materials);
  return byKeyId.entries
      .map((entry) => _materialGroupFingerprint(entry.key, entry.value))
      .toList();
}

Map<String, dynamic> _materialGroupFingerprint(
  String keyId,
  List<AtKeysMaterial> group,
) {
  return {
    'keyId': keyId,
    'keyGroup': group.first.keyGroup,
    'enrollmentId': group.first.enrollmentId,
    'materials': {
      for (final material in group)
        material.keyPartType.name: _materialFingerprint(material),
    },
  };
}

Map<String, dynamic> _materialFingerprint(AtKeysMaterial material) {
  return {
    'keyAlgorithmType': material.keyAlgorithmType.name,
    'operations': material.operations,
    'bytes': material.bytes.toString(),
    'createdAt': material.createdAt.toIso8601String(),
    'status': material.status.name,
  };
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

String _two(int value) => value.toString().padLeft(2, '0');
String _four(int value) => value.toString().padLeft(4, '0');
String _six(int value) => value.toString().padLeft(6, '0');

// An enrollment (formerly one AtKeyPackage) produces at most one material of
// each CryptographicKeyType, across all of the materials it's tagged on.
void _validateEnrollmentGrouping(List<AtKeysMaterial> materials) {
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
