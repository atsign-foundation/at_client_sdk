import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysAssurance', () {
    const assurance = AtKeysAssurance();

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
      final candidate = _documentMap(
        atSign: '@alice🛠',
        legacyJson: existing,
        keys: [_symmetricMaterial()],
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        returnsNormally,
      );
      for (final entry in existing.entries) {
        expect(
          candidate[entry.key],
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
        final candidate = _candidateWithLegacy(changedLegacy);

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
        final candidate = _candidateWithLegacy(changedLegacy);

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
      final candidate = _candidateWithLegacy(changedLegacy);

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when candidate drops all legacy fields', () {
      final existing = _fixtureLegacyJson();
      final candidate = {
        'version': AtKeys.supportedVersion,
        'atSign': '@alice🛠',
        'keys': [_recordJson()],
      };

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects map update when legacy value types change', () {
      final existing = _fixtureLegacyJson();

      for (final key in auth_constants.keySchemaList) {
        final changedLegacy = Map<String, dynamic>.from(existing);
        changedLegacy[key] = const [];
        final candidate = _candidateWithLegacy(changedLegacy);

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

    test('rejects map update when an existing key record changes', () {
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = _documentMap(
        keys: [_symmetricMaterial(bytes: 'Y2hhbmdlZA==')],
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
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = _documentMap(keys: const []);

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
        keys: [_wrapperMaterial(), _enrollMaterial()],
      );
      final candidates = [
        _documentMap(
          keys: [
            _wrapperMaterial(),
            _enrollMaterial(operations: const ['sign']),
          ],
        ),
        _documentMap(
          keys: [
            _wrapperMaterial(),
            _enrollMaterial(enrollmentId: 'changed-enroll'),
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
        keys: [_wrapperMaterial(), _enrollMaterial()],
      );
      final candidate = _documentMap(
        keys: [
          _wrapperMaterial(),
          _enrollMaterial(operations: const []),
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
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = {
        'version': AtKeys.supportedVersion,
        'atSign': '@alice',
        'keys': [
          _recordJson(keyId: 'duplicate'),
          _recordJson(keyId: 'duplicate'),
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
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = _documentMap(
        atSign: '@bob',
        keys: [_symmetricMaterial()],
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('rejects a key material whose atKey does not match the derived value',
        () {
      final json = _documentMap(keys: const []);
      json['keys'] = [
        {
          ..._recordJson(),
          'keyParts': [
            {
              ..._recordJson()['keyParts'][0] as Map<String, dynamic>,
              'atKey': 'symmetric:wrong-id',
            },
          ],
        },
      ];

      expect(
        () => AtKeys.fromDocumentJson(json),
        throwsA(isA<AtKeysValidationException>()),
      );
    });
  });
}

final _createdAt = DateTime.utc(2024, 1, 1);

AtKeysRecord _symmetricMaterial({String bytes = 'dmFsdWU='}) {
  return AtKeysRecord(
    keyId: 'symmetric',
    keyGroup: 'default',
    materials: [
      AtKeysMaterial(
        keyId: 'symmetric',
        keyGroup: 'default',
        keyPartType: CryptographicKeyType.symmetricDataEncryption,
        visibility: AtKeyVisibility.symmetric,
        keyAlgorithmType: KeyAlgorithmType.aes,
        bytes: AtBytes.fromString(bytes),
        createdAt: _createdAt,
      ),
    ],
  );
}

AtKeysRecord _wrapperMaterial() {
  return AtKeysRecord(
    keyId: 'wrapper',
    keyGroup: 'default',
    materials: [
      AtKeysMaterial(
        keyId: 'wrapper',
        keyGroup: 'default',
        keyPartType: CryptographicKeyType.keyWrapping,
        visibility: AtKeyVisibility.symmetric,
        keyAlgorithmType: KeyAlgorithmType.aes,
        bytes: AtBytes.fromString('d3JhcHBlcg=='),
        createdAt: _createdAt,
      ),
    ],
  );
}

AtKeysRecord _enrollMaterial({
  String keyId = 'enroll-priv',
  String enrollmentId = 'enroll-1',
  List<String> operations = const ['decrypt'],
}) {
  return AtKeysRecord(
    keyId: keyId,
    keyGroup: 'default',
    enrollmentId: enrollmentId,
    materials: [
      AtKeysMaterial(
        keyId: keyId,
        keyGroup: 'default',
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.classicalPrivateDecryption,
        visibility: AtKeyVisibility.private,
        keyAlgorithmType: KeyAlgorithmType.rsa,
        operations: operations,
        bytes: AtBytes.fromString('c2VjcmV0'),
        createdAt: _createdAt,
      ),
    ],
  );
}

Map<String, dynamic> _documentMap({
  required List<AtKeysRecord> keys,
  Map<String, dynamic> legacyJson = const {},
  String atSign = '@alice',
}) {
  return {
    ...legacyJson,
    'version': AtKeys.supportedVersion,
    'atSign': atSign,
    'keys': keys.map((record) => record.toJson()).toList(),
  };
}

Map<String, dynamic> _candidateWithLegacy(Map<String, dynamic> legacyJson) {
  return _documentMap(
    atSign: '@alice🛠',
    legacyJson: legacyJson,
    keys: [_symmetricMaterial()],
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

Map<String, dynamic> _recordJson({String keyId = 'symmetric'}) {
  return {
    'keyId': keyId,
    'keyGroup': 'default',
    'keyParts': [
      {
        'keyPartType': CryptographicKeyType.symmetricDataEncryption.name,
        'visibility': AtKeyVisibility.symmetric.name,
        'keyAlgorithmType': KeyAlgorithmType.aes.name,
        'atKey': '${AtKeyVisibility.symmetric.name}:$keyId',
        'createdAt': _createdAt.toIso8601String(),
        'status': KeyPartStatus.active.name,
        'bytes': 'dmFsdWU=',
      },
    ],
  };
}
