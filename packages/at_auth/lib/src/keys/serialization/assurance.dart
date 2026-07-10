import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysAssuranceException extends AtKeysValidationException {
  AtKeysAssuranceException(super.message);
}

/// Single home for all atKeys validation: low-level parsing/value checks
/// (`expect*`/`optional*`, called by the models' `fromJson`) and cross-record
/// structural invariants (`validateKeyRecords`, `validateMapUpdate`).
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

  void expectAtKeyMatches(String atKey, String expected, String fieldName) {
    if (atKey != expected) {
      throw AtKeysValidationException(
          'atKey "$atKey" at $fieldName does not match derived "$expected"');
    }
  }

  // ---- cross-record structural invariants ----

  /// No two records may share a `keyId`, and an enrollment may not
  /// contribute more than one material of the same `CryptographicKeyType`
  /// (formerly one atomic `AtKeyPackage`) across all of its records.
  void validateKeyRecords(List<AtKeysRecord> records) {
    _validateDuplicateKeyIds(records);
    _validateEnrollmentGrouping(records);
  }

  void validateMapUpdate({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> candidate,
  }) {
    final existingRecords = _decode(existing);
    final candidateRecords = _decode(candidate);

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
    _assertRecordsPreserved(existingRecords, candidateRecords);
  }

  static String archiveSuffix([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    // Full sub-second precision: utc.microsecond is only the 0..999 sub-ms
    // component, so it drops the millisecond field entirely and lets two
    // archives in the same second collide on the filename.
    final subSecond =
        utc.microsecondsSinceEpoch % Duration.microsecondsPerSecond;
    return '${_four(utc.year)}${_two(utc.month)}${_two(utc.day)}.'
        '${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}.'
        '${_six(subSecond)}';
  }

  static String archiveNameFor(String name, [DateTime? now]) {
    return '$name.${archiveSuffix(now)}';
  }

  List<AtKeysRecord> _decode(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      return const [];
    }
    final keysJson = json['keys'];
    if (keysJson is! List) {
      return const [];
    }
    final records = keysJson.asMap().entries.map((entry) {
      final recordJson = expectMap(entry.value, 'keys[${entry.key}]');
      return AtKeysRecord.fromJson(recordJson, index: entry.key);
    }).toList();
    validateKeyRecords(records);
    return records;
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
    final records = _decode(candidate);
    final reencoded = records.map((record) => record.toJson()).toList();
    final redecoded = reencoded
        .asMap()
        .entries
        .map((entry) => AtKeysRecord.fromJson(entry.value, index: entry.key))
        .toList();

    _assertSame(
      _recordsFingerprint(records),
      _recordsFingerprint(redecoded),
      'map.codecRoundTrip',
    );
  }
}

void _assertRecordsPreserved(
  List<AtKeysRecord> existing,
  List<AtKeysRecord> candidate,
) {
  final candidateByKeyId = {
    for (final record in candidate) record.keyId: record,
  };

  for (final existingRecord in existing) {
    final candidateRecord = candidateByKeyId[existingRecord.keyId];
    if (candidateRecord == null) {
      throw AtKeysAssuranceException(
        'Map key record "${existingRecord.keyId}" is not preserved',
      );
    }
    _assertSame(
      _recordFingerprint(existingRecord),
      _recordFingerprint(candidateRecord),
      'map.keys.${existingRecord.keyId}',
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

List<Map<String, dynamic>> _recordsFingerprint(
  List<AtKeysRecord> records,
) {
  return records.map(_recordFingerprint).toList();
}

Map<String, dynamic> _recordFingerprint(AtKeysRecord record) {
  return {
    'keyId': record.keyId,
    'keyGroup': record.keyGroup,
    'enrollmentId': record.enrollmentId,
    'materials': {
      for (final entry in record.materials.entries)
        entry.key.name: _materialFingerprint(entry.value),
    },
  };
}

Map<String, dynamic> _materialFingerprint(AtKeysMaterial material) {
  return {
    'visibility': material.visibility.name,
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

void _validateDuplicateKeyIds(List<AtKeysRecord> records) {
  final seen = <String>{};
  for (final record in records) {
    if (!seen.add(record.keyId)) {
      throw AtKeysValidationException(
          'Duplicate atKeys keyId "${record.keyId}"');
    }
  }
}

// An enrollment (formerly one AtKeyPackage) produces at most one material of
// each CryptographicKeyType, across all of the records it's tagged on.
void _validateEnrollmentGrouping(List<AtKeysRecord> records) {
  final typesByEnrollment = <String, Set<CryptographicKeyType>>{};
  for (final record in records) {
    final enrollmentId = record.enrollmentId;
    if (enrollmentId == null) {
      continue;
    }
    final types = typesByEnrollment.putIfAbsent(enrollmentId, () => {});
    for (final partType in record.materials.keys) {
      if (!types.add(partType)) {
        throw AtKeysEnrollmentException(
            'Enrollment "$enrollmentId" has more than one ${partType.name} key material');
      }
    }
  }
}
