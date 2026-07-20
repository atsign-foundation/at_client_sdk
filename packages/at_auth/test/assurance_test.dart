import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysAssurance', () {
    const assurance = AtKeysAssurance();

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
        'atsign': '@alice🛠',
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

    test('accepts map update when a key status moves forward', () {
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = _documentMap(
        keys: [_symmetricMaterial().withStatus(KeyPartStatus.retired)],
      );

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
    });

    test('rejects map update when a key status moves backward', () {
      final existing = _documentMap(
        keys: [_symmetricMaterial().withStatus(KeyPartStatus.dead)],
      );
      final candidate = _documentMap(
        keys: [_symmetricMaterial().withStatus(KeyPartStatus.retired)],
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('accepts map update adding a new part to an existing keyId', () {
      final pair = _rsaPairMaterials();
      final existing = _documentMap(keys: [pair.first]);
      final candidate = _documentMap(keys: pair);

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
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
        'atsign': '@alice',
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

    test('rejects map update when the atsign changes on a typed-keys rewrite',
        () {
      final existing = _documentMap(keys: [_symmetricMaterial()]);
      final candidate = _documentMap(
        atsign: '@bob',
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

    test('rejects map update when a versioned document has a non-list keys',
        () {
      // A corrupted keys field must not silently skip material preservation.
      final corrupted = {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'keys': 'garbage',
      };
      final wellFormed = _documentMap(keys: [_symmetricMaterial()]);

      expect(
        () => assurance.validateMapUpdate(
          existing: corrupted,
          candidate: wellFormed,
        ),
        throwsA(isA<AtKeysParseException>()),
      );
      expect(
        () => assurance.validateMapUpdate(
          existing: wellFormed,
          candidate: corrupted,
        ),
        throwsA(isA<AtKeysParseException>()),
      );
    });
  });
}

final _createdAt = DateTime.utc(2024, 1, 1);

AtKeysMaterial _symmetricMaterial({String bytes = 'dmFsdWU='}) {
  return AtKeysMaterial(
    keyId: 'symmetric',
    keyPartType: CryptographicKeyType.symmetricEncryption,
    keyAlgorithmType: KeyAlgorithmType.aes256,
    bytes: AtBytes.fromString(bytes),
    createdAt: _createdAt,
  );
}

List<AtKeysMaterial> _rsaPairMaterials() {
  return [
    AtKeysMaterial(
      keyId: 'pair',
      keyPartType: CryptographicKeyType.publicEncryption,
      keyAlgorithmType: KeyAlgorithmType.rsa2048,
      bytes: AtBytes.fromString('cHVibGlj'),
      createdAt: _createdAt,
    ),
    AtKeysMaterial(
      keyId: 'pair',
      keyPartType: CryptographicKeyType.privateDecryption,
      keyAlgorithmType: KeyAlgorithmType.rsa2048,
      bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
      createdAt: _createdAt,
    ),
  ];
}

AtKeysMaterial _wrapperMaterial() {
  return AtKeysMaterial(
    keyId: 'wrapper',
    keyPartType: CryptographicKeyType.symmetricEncryption,
    keyAlgorithmType: KeyAlgorithmType.aes256,
    bytes: AtBytes.fromString('d3JhcHBlcg=='),
    createdAt: _createdAt,
  );
}

AtKeysMaterial _enrollMaterial({
  String keyId = 'enroll-priv',
  String enrollmentId = 'enroll-1',
  List<String> operations = const ['decrypt'],
}) {
  return AtKeysMaterial(
    keyId: keyId,
    enrollmentId: enrollmentId,
    keyPartType: CryptographicKeyType.privateDecryption,
    keyAlgorithmType: KeyAlgorithmType.rsa2048,
    operations: operations,
    bytes: AtBytes.fromString('c2VjcmV0'),
    createdAt: _createdAt,
  );
}

Map<String, dynamic> _documentMap({
  required List<AtKeysMaterial> keys,
  Map<String, dynamic> legacyJson = const {},
  String atsign = '@alice',
}) {
  return {
    ...legacyJson,
    'version': AtKeys.supportedVersion,
    'atsign': atsign,
    'keys': encodeAtKeysDocument(keys),
  };
}

Map<String, dynamic> _candidateWithLegacy(Map<String, dynamic> legacyJson) {
  return _documentMap(
    atsign: '@alice🛠',
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
    'keyParts': [
      {
        'keyPartType': CryptographicKeyType.symmetricEncryption,
        'keyAlgorithmType': KeyAlgorithmType.aes256,
        'createdAt': _createdAt.toIso8601String(),
        'status': KeyPartStatus.active.name,
        'bytes': 'dmFsdWU=',
      },
    ],
  };
}
