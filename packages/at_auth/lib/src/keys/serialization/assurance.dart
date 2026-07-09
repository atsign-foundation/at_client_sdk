import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';

class AtKeysAssuranceException extends AtKeysValidationException {
  AtKeysAssuranceException(super.message);
}

class AtKeysAssurance {
  final AtKeysCodec codec;

  const AtKeysAssurance({
    this.codec = const AtKeysJsonCodec(),
  });

  void validateMapUpdate({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> candidate,
  }) {
    final existingDocument = codec.decodeDocument(existing);
    final candidateDocument = codec.decodeDocument(candidate);

    _assertCodecRoundTrip(candidate);
    // A legacy -> v1 upgrade legitimately introduces the atSign and version, so
    // only pin them when the existing file is already a v1 document.
    if (existingDocument is! LegacyAtKeysDocument) {
      _assertSame(
        existingDocument.atsign.toString(),
        candidateDocument.atsign.toString(),
        'map.atSign',
      );
      _assertSame(
        existingDocument.version,
        candidateDocument.version,
        'map.version',
      );
    }
    _assertLegacyPreserved(
      existingDocument.legacyJson,
      candidateDocument.legacyJson,
      'map.legacy',
    );
    _assertDocumentKeysPreserved(
      existingDocument,
      candidateDocument,
    );
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

  void _assertCodecRoundTrip(Map<String, dynamic> candidate) {
    final document = codec.decodeDocument(candidate);
    final encoded = codec.encodeDocument(document);
    final decoded = codec.decodeDocument(encoded);

    _assertSame(
      _documentFingerprint(document),
      _documentFingerprint(decoded),
      'map.codecRoundTrip',
    );
  }
}

void _assertDocumentKeysPreserved(
  AtKeysDocument existing,
  AtKeysDocument candidate,
) {
  final candidateById = {
    for (final record in candidate.keys) record.id: record,
  };

  for (final existingRecord in existing.keys) {
    final candidateRecord = candidateById[existingRecord.id];
    if (candidateRecord == null) {
      throw AtKeysAssuranceException(
        'Map key record "${existingRecord.id}" is not preserved',
      );
    }
    _assertSame(
      _recordFingerprint(existingRecord),
      _recordFingerprint(candidateRecord),
      'map.keys.${existingRecord.id}',
    );
  }
}

void _assertLegacyPreserved(
  Map<String, dynamic>? existing,
  Map<String, dynamic>? candidate,
  String path,
) {
  if (existing == null || existing.isEmpty) {
    return;
  }
  if (candidate == null) {
    throw AtKeysAssuranceException('$path is not preserved');
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

Map<String, dynamic> _documentFingerprint(AtKeysDocument document) {
  return {
    'version': document.version,
    'atSign': document.atsign.toString(),
    'legacy': _canonicalValue(document.legacyJson),
    'keys': document.keys.map(_recordFingerprint).toList(),
  };
}

Map<String, dynamic> _recordFingerprint(KeyRecord record) {
  return {
    'id': record.id,
    'kind': record.kind.name,
    'algorithm': record.algorithm,
    'operations': record.operations,
    'bytes': record.bytes.toString(),
    'protection': record.protection?.toJson(),
    'pairId': record.pairId,
    'enrollmentId': record.enrollmentId,
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
