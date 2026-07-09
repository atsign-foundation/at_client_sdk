import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysAssurance', () {
    const assurance = AtKeysAssurance();
    const codec = AtKeysJsonCodec();

    test('archiveSuffix formats UTC timestamps for filenames', () {
      final timestamp = DateTime.utc(2026, 7, 9, 15, 4, 5, 0, 123);

      expect(
        AtKeysAssurance.archiveSuffix(timestamp),
        '20260709.150405.000123',
      );
    });

    test('archiveNameFor appends timestamp suffix to file name', () {
      final timestamp = DateTime.utc(2026, 7, 9, 15, 4, 5, 0, 123);

      expect(
        AtKeysAssurance.archiveNameFor('/tmp/@alice_key.atKeys', timestamp),
        '/tmp/@alice_key.atKeys.20260709.150405.000123',
      );
    });

    test('populates legacy records when round-tripping fixture into v1', () {
      final existing = _fixtureLegacyJson();
      final existingDocument = codec.decodeDocument(existing);
      final candidate = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@alice🛠'.toAtsign(),
          legacyJson: existingDocument.legacyJson,
          keys: [_symmetricRecord()],
        ),
      );
      final roundTripped = codec.decodeDocument(candidate);

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        returnsNormally,
      );
      for (final entry in existing.entries) {
        expect(
          roundTripped.legacyJson[entry.key],
          entry.value,
          reason: '${entry.key} must survive legacy -> v1 round trip',
        );
      }
    });

    test('rejects map update when any legacy field value changes', () {
      final existing = _fixtureLegacyJson();

      for (final key in auth_constants.keySchemaList) {
        final changedLegacy = Map<String, dynamic>.from(existing);
        changedLegacy[key] = 'changed-${changedLegacy[key]}';
        final candidate = _candidateWithLegacy(codec, changedLegacy);

        expect(
          () => assurance.validateMapUpdate(
            existing: existing,
            candidate: candidate,
          ),
          throwsA(isA<AtKeysAssuranceException>()),
          reason: '$key must not change during safety-assured write',
        );
      }
    });

    test('rejects map update when a legacy field is missing', () {
      final existing = _fixtureLegacyJson();

      for (final key in auth_constants.keySchemaList) {
        final changedLegacy = Map<String, dynamic>.from(existing)..remove(key);
        final candidate = _candidateWithLegacy(codec, changedLegacy);

        expect(
          () => assurance.validateMapUpdate(
            existing: existing,
            candidate: candidate,
          ),
          throwsA(isA<AtKeysAssuranceException>()),
          reason: '$key must not be removed during safety-assured write',
        );
      }
    });

    test('rejects map update when non-schema legacy metadata is missing', () {
      final existing = _fixtureLegacyJson();
      final changedLegacy = Map<String, dynamic>.from(existing)
        ..remove('@alice🛠');
      final candidate = _candidateWithLegacy(codec, changedLegacy);

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when candidate has no legacy payload', () {
      final existing = _fixtureLegacyJson();
      final candidate = {
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice🛠',
        'keys': [_recordJson()],
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysParseException>()),
      );
    });

    test('rejects map update when candidate legacy payload is malformed', () {
      final existing = _fixtureLegacyJson();
      final candidate = {
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice🛠',
        'legacy': 'not json',
        'keys': [_recordJson()],
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(anything),
      );
    });

    test('rejects map update when legacy value types change', () {
      final existing = _fixtureLegacyJson();

      for (final key in auth_constants.keySchemaList) {
        final changedLegacy = Map<String, dynamic>.from(existing);
        changedLegacy[key] = const [];
        final candidate = _candidateWithLegacy(codec, changedLegacy);

        expect(
          () => assurance.validateMapUpdate(
            existing: existing,
            candidate: candidate,
          ),
          throwsA(isA<AtKeysAssuranceException>()),
          reason: '$key must not change type during safety-assured write',
        );
      }
    });

    test('rejects map update when legacy fields are copied to wrong nesting',
        () {
      final existing = _fixtureLegacyJson();
      final candidate = {
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice🛠',
        'keys': [_recordJson()],
        ...existing,
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysParseException>()),
      );
    });

    test('rejects map update when an existing key record changes', () {
      final existing = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@alice'.toAtsign(),
          legacyJson: const {},
          keys: [_symmetricRecord()],
        ),
      );
      final candidate = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@alice'.toAtsign(),
          legacyJson: const {},
          keys: [
            _symmetricRecord(bytes: 'Y2hhbmdlZA=='),
          ],
        ),
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when an existing key record is missing', () {
      final existing = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@alice'.toAtsign(),
          legacyJson: const {},
          keys: [_symmetricRecord()],
        ),
      );
      final candidate = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@alice'.toAtsign(),
          legacyJson: const {},
          keys: const [],
        ),
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when optional key record fields change', () {
      final existing = _documentMap(
        codec,
        keys: [_wrapperRecord(), _enrollRecord()],
      );
      final candidates = [
        _documentMap(
          codec,
          keys: [
            _wrapperRecord(),
            _enrollRecord(operations: const ['sign']),
          ],
        ),
        _documentMap(
          codec,
          keys: [
            _wrapperRecord(),
            _enrollRecord(
              protection: const KeyProtection(
                keyRef: 'wrapper',
                algorithm: 'AES-128-GCM',
                iv: 'aXY=',
              ),
            ),
          ],
        ),
        _documentMap(
          codec,
          keys: [
            _wrapperRecord(),
            _enrollRecord(pairId: 'changed-pair'),
          ],
        ),
        _documentMap(
          codec,
          keys: [
            _wrapperRecord(),
            _enrollRecord(enrollmentId: 'changed-enroll'),
          ],
        ),
      ];

      for (final candidate in candidates) {
        expect(
          () => assurance.validateMapUpdate(
            existing: existing,
            candidate: candidate,
          ),
          throwsA(isA<AtKeysAssuranceException>()),
        );
      }
    });

    test('rejects map update when optional key record fields are removed', () {
      final existing = _documentMap(
        codec,
        keys: [_wrapperRecord(), _enrollRecord()],
      );
      final candidate = _documentMap(
        codec,
        keys: [
          _wrapperRecord(),
          KeyRecord(
            id: 'enroll-priv',
            pairId: 'enroll-pair',
            kind: KeyRecordKind.private,
            algorithm: 'RSA',
            bytes: AtBytes.fromString('c2VjcmV0'),
          ),
        ],
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when candidate has duplicate key ids', () {
      final existing = _documentMap(codec, keys: [_symmetricRecord()]);
      final candidate = {
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'legacy': const {},
        'keys': [
          _recordJson(id: 'duplicate'),
          _recordJson(id: 'duplicate'),
        ],
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects map update when the atSign changes on a v1 rewrite', () {
      final existing = _documentMap(
        codec,
        keys: [_symmetricRecord()],
      );
      final candidate = codec.encodeDocument(
        AtKeysDocument(
          version: AtKeysJsonCodec.supportedVersion,
          atsign: '@bob'.toAtsign(),
          legacyJson: const {},
          keys: [_symmetricRecord()],
        ),
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when candidate breaks protection references', () {
      final existing = _documentMap(
        codec,
        keys: [_wrapperRecord(), _enrollRecord()],
      );
      final candidate = {
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'legacy': const {},
        'keys': [
          _recordJson(
            id: 'enroll-priv',
            kind: 'private',
            pairId: 'enroll-pair',
            protection: const {
              'keyRef': 'missing-wrapper',
              'algorithm': 'AES-256-GCM',
              'iv': 'aXY=',
            },
          ),
        ],
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysProtectionException>()),
      );
    });
  });
}

KeyRecord _symmetricRecord({String bytes = 'dmFsdWU='}) {
  return KeyRecord(
    id: 'symmetric',
    kind: KeyRecordKind.symmetric,
    algorithm: 'AES-256',
    bytes: AtBytes.fromString(bytes),
  );
}

KeyRecord _wrapperRecord() {
  return KeyRecord(
    id: 'wrapper',
    kind: KeyRecordKind.symmetric,
    algorithm: 'AES-256',
    bytes: AtBytes.fromString('d3JhcHBlcg=='),
  );
}

KeyRecord _enrollRecord({
  String pairId = 'enroll-pair',
  String enrollmentId = 'enroll-1',
  List<String> operations = const ['decrypt'],
  KeyProtection protection = const KeyProtection(
    keyRef: 'wrapper',
    algorithm: 'AES-256-GCM',
    iv: 'aXY=',
  ),
}) {
  return KeyRecord(
    id: 'enroll-priv',
    pairId: pairId,
    kind: KeyRecordKind.private,
    algorithm: 'RSA',
    operations: operations,
    protection: protection,
    bytes: AtBytes.fromString('c2VjcmV0'),
    enrollmentId: enrollmentId,
  );
}

Map<String, dynamic> _documentMap(
  AtKeysJsonCodec codec, {
  required List<KeyRecord> keys,
  Map<String, dynamic> legacyJson = const {},
}) {
  return codec.encodeDocument(
    AtKeysDocument(
      version: AtKeysJsonCodec.supportedVersion,
      atsign: '@alice'.toAtsign(),
      legacyJson: legacyJson,
      keys: keys,
    ),
  );
}

Map<String, dynamic> _candidateWithLegacy(
  AtKeysJsonCodec codec,
  Map<String, dynamic> legacyJson,
) {
  return codec.encodeDocument(
    AtKeysDocument(
      version: AtKeysJsonCodec.supportedVersion,
      atsign: '@alice🛠'.toAtsign(),
      legacyJson: legacyJson,
      keys: [_symmetricRecord()],
    ),
  );
}

Map<String, dynamic> _fixtureLegacyJson() {
  final fixture = _fixtureFile();
  return jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
}

File _fixtureFile() {
  final packageRelative = File('test/data/@alice🛠_key.atKeys');
  if (packageRelative.existsSync()) {
    return packageRelative;
  }
  return File('packages/at_auth/test/data/@alice🛠_key.atKeys');
}

Map<String, dynamic> _recordJson({
  String id = 'symmetric',
  String kind = 'symmetric',
  String? pairId,
  Map<String, dynamic>? protection,
}) {
  return {
    'id': id,
    if (pairId != null) 'pairId': pairId,
    'kind': kind,
    'algorithm': 'AES-256',
    if (protection != null) 'protection': protection,
    'value': 'dmFsdWU=',
  };
}
