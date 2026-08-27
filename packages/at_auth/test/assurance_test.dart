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

    test('accepts the upgrade of a legacy document that names its own atSign',
        () {
      // The keychain records the owner under a top-level `atsign` key, which
      // predates the typed shape reserving that name — so every entry a
      // published at_client_flutter wrote has one. Upgrading re-homes the
      // value into the reserved field rather than dropping it; treating it as
      // a lost legacy entry would make the FIRST flush onto any pre-existing
      // entry impossible, which is every device already in the field.
      final existing = {..._fixtureLegacyJson(), 'atsign': '@alice🛠'};
      final candidate = _documentMap(
        atsign: '@alice🛠',
        legacyJson: _fixtureLegacyJson(),
        keys: [_symmetricMaterial()],
      );

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
    });

    test('accepts the first flush onto a keyfile at_auth 3.3.0 wrote', () {
      // 3.3.0's `toJson` emitted `version`, `atsign` and a top-level `keys`
      // array together whenever the atSign was set — which is every normal
      // keyfile — with `keys` empty while it held no typed material, and it
      // reserved that name itself. This build drops the field in
      // `AtKeys.fromJson` and never writes one, so unless it stays RESERVED
      // here the assurance reads it as a legacy value the candidate failed to
      // preserve and refuses the write. That refusal lands on the first
      // enrollment, retrofit or key-filing save onto any keyfile 3.3.0 wrote,
      // and the mutation is lost rather than reported.
      //
      // The fixture alone does not cover this: it predates 3.3.0 and carries
      // neither `version` nor `keys`.
      final existing = {
        ..._fixtureLegacyJson(),
        'atsign': '@alice🛠',
        'version': AtKeys.supportedVersion,
        'keys': <dynamic>[],
      };
      final candidate = _documentMap(
        atsign: '@alice🛠',
        legacyJson: _fixtureLegacyJson(),
        keys: [_symmetricMaterial()],
      );

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
    });

    test(
        'accepts the upgrade when the legacy spelling normalizes to the '
        'candidate atSign', () {
      // `AtKeys.fromJson` normalizes the reserved field through `toAtsign()`,
      // so the two sides are only comparable in that form: a legacy entry
      // stored as the user typed it names the same atSign.
      final existing = {..._fixtureLegacyJson(), 'atsign': '@Colin.Constable'};
      final candidate = _documentMap(
        atsign: '@colinconstable',
        legacyJson: _fixtureLegacyJson(),
        keys: [_symmetricMaterial()],
      );

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
    });

    test('rejects the upgrade when the candidate claims a different atSign',
        () {
      final existing = {..._fixtureLegacyJson(), 'atsign': '@alice🛠'};
      final candidate = _documentMap(
        atsign: '@bob🛠',
        legacyJson: _fixtureLegacyJson(),
        keys: [_symmetricMaterial()],
      );

      expect(
        () => assurance.validateMapUpdate(
          existing: existing,
          candidate: candidate,
        ),
        throwsA(isA<AtKeysAssuranceException>()
            .having((e) => e.message, 'message', contains('map.atsign'))),
        reason: 'writing one atSign\'s keys over another\'s is the loss this '
            'check exists to refuse — and it must be the owner check that '
            'catches it, not the legacy comparison it was taken out of',
      );
    });

    test('rejects map update when candidate drops all legacy fields', () {
      final existing = _fixtureLegacyJson();
      final candidate = {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice🛠',
        'atsignKeys': [_recordJson()],
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
        keys: [_symmetricMaterial().withStatus(CryptographicMaterialStatus.retired)],
      );

      assurance.validateMapUpdate(existing: existing, candidate: candidate);
    });

    test('rejects map update when a key status moves backward', () {
      final existing = _documentMap(
        keys: [_symmetricMaterial().withStatus(CryptographicMaterialStatus.dead)],
      );
      final candidate = _documentMap(
        keys: [_symmetricMaterial().withStatus(CryptographicMaterialStatus.retired)],
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
        // The owner is no longer a field on the material at rest — the
        // container states it — so changing it means MOVING the material into
        // another container, and the atSign-scope entry it left is a loss.
        _documentMap(
          keys: [_wrapperMaterial()],
          enrollments: {
            'changed-enroll': [_enrollMaterial(enrollmentId: 'changed-enroll')],
          },
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
        'atsignKeys': [
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
      // A corrupted container must not silently skip material preservation.
      final corrupted = {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'atsignKeys': 'garbage',
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

    group('one live enrollment per keyfile', () {
      CryptographicMaterial authMaterial(String keyId,
              {String? enrollmentId}) =>
          CryptographicMaterial(
            keyId: keyId,
            enrollmentId: enrollmentId,
            role: CryptographicMaterialRole.privateAuthentication,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            bytes: AtBytes.fromString('dmFsdWU='),
            createdAt: _createdAt,
          );

      // ⚠️ These moved from validateKeyMaterials (the READ path) to
      // refuseSecondLiveEnrollment (the WRITE path). The rule did not go away
      // — one live enrollment per keyfile is still what this build produces —
      // but a READER that refused a second would make the plurality
      // unenableable, since the first build to write two would break every
      // build that predates it. Read tolerance is pinned in
      // plural_enrollments_test.dart.
      test(
          'a second active authentication key is refused when both name an '
          'enrollment', () {
        expect(
          () => assurance.refuseSecondLiveEnrollment(
            existing: [authMaterial('auth:rsa2048:1', enrollmentId: 'e1')],
            candidate: authMaterial('auth:rsa2048:1', enrollmentId: 'e2'),
          ),
          throwsArgumentError,
        );
      });

      test(
          'a second active authentication key is refused when NEITHER names '
          'one', () {
        // The other arm of the same rule. enrollmentId is optional, so null
        // is a legitimate value the check must survive — reading it as "none
        // seen yet" let the second key through.
        expect(
          () => assurance.refuseSecondLiveEnrollment(
            existing: [authMaterial('auth:rsa2048:1')],
            candidate: authMaterial('auth:rsa2048:2'),
          ),
          throwsArgumentError,
        );
      });

      test('and refused for ONE enrollment naming two algorithms', () {
        // The case the per-(role, algorithm) rule structurally cannot see,
        // because the two materials do not share an algorithm. An enrollment
        // holds at most one active authentication pair whatever it is made
        // of, which is what privateAuthentication's own dartdoc states.
        expect(
          () => assurance.refuseSecondLiveEnrollment(
            existing: [authMaterial('auth:rsa2048:1', enrollmentId: 'e1')],
            candidate: CryptographicMaterial(
              keyId: 'auth:mldsa65:1',
              enrollmentId: 'e1',
              role: CryptographicMaterialRole.privateAuthentication,
              algorithm: CryptographicMaterialAlgorithm.mlDsa65,
              bytes: AtBytes.fromString('dmFsdWU='),
              createdAt: _createdAt,
            ),
          ),
          throwsArgumentError,
        );
      });

      test('the refusal says "no enrollment id" rather than naming null', () {
        expect(
          () => assurance.refuseSecondLiveEnrollment(
            existing: [authMaterial('auth:rsa2048:1')],
            candidate: authMaterial('auth:rsa2048:2', enrollmentId: 'e2'),
          ),
          throwsA(isA<ArgumentError>().having(
              (e) => e.toString(), 'message', contains('no enrollment id'))),
        );
      });

      test('one active authentication key with no enrollment id is fine', () {
        // Guards against over-correction: a single anonymous authentication
        // key is a legacy shape, not a corrupt keyfile.
        expect(
          () => assurance.validateKeyMaterials([authMaterial('apkam:anon:1')]),
          returnsNormally,
        );
      });
    });
  });
}

final _createdAt = DateTime.utc(2024, 1, 1);

CryptographicMaterial _symmetricMaterial({String bytes = 'dmFsdWU='}) {
  return CryptographicMaterial(
    keyId: 'symmetric',
    role: CryptographicMaterialRole.symmetricEncryption,
    algorithm: CryptographicMaterialAlgorithm.aes256,
    bytes: AtBytes.fromString(bytes),
    createdAt: _createdAt,
  );
}

List<CryptographicMaterial> _rsaPairMaterials() {
  return [
    CryptographicMaterial(
      keyId: 'pair',
      role: CryptographicMaterialRole.publicEncryption,
      algorithm: CryptographicMaterialAlgorithm.rsa2048,
      bytes: AtBytes.fromString('cHVibGlj'),
      createdAt: _createdAt,
    ),
    CryptographicMaterial(
      keyId: 'pair',
      role: CryptographicMaterialRole.privateDecryption,
      algorithm: CryptographicMaterialAlgorithm.rsa2048,
      bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
      createdAt: _createdAt,
    ),
  ];
}

CryptographicMaterial _wrapperMaterial() {
  return CryptographicMaterial(
    keyId: 'wrapper',
    role: CryptographicMaterialRole.symmetricEncryption,
    algorithm: CryptographicMaterialAlgorithm.aes256,
    bytes: AtBytes.fromString('d3JhcHBlcg=='),
    createdAt: _createdAt,
  );
}

CryptographicMaterial _enrollMaterial({
  String keyId = 'enroll-priv',
  String enrollmentId = 'enroll-1',
  List<String> operations = const ['decrypt'],
}) {
  return CryptographicMaterial(
    keyId: keyId,
    enrollmentId: enrollmentId,
    role: CryptographicMaterialRole.privateDecryption,
    algorithm: CryptographicMaterialAlgorithm.rsa2048,
    operations: operations,
    bytes: AtBytes.fromString('c2VjcmV0'),
    createdAt: _createdAt,
  );
}

/// A typed document. [keys] are the atSign's own; [enrollments] maps an
/// enrollment id to the materials filed under it, for the cases where WHICH
/// container a material sits in is the thing under test.
Map<String, dynamic> _documentMap({
  required List<CryptographicMaterial> keys,
  Map<String, List<CryptographicMaterial>> enrollments = const {},
  Map<String, dynamic> legacyJson = const {},
  String atsign = '@alice',
}) {
  // Every material these fixtures build is untagged, so it belongs to the
  // atSign's own container. An enrollment's would sit under enrollments[].
  return {
    ...legacyJson,
    'version': AtKeys.supportedVersion,
    'atsign': atsign,
    'atsignKeys': encodeAtKeysDocument(keys),
    if (enrollments.isNotEmpty)
      'enrollments': [
        for (final entry in enrollments.entries)
          {
            'enrollmentId': entry.key,
            'keys': encodeAtKeysDocument(entry.value),
          },
      ],
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
    'material': [
      {
        'role': CryptographicMaterialRole.symmetricEncryption,
        'algorithm': CryptographicMaterialAlgorithm.aes256,
        'createdAt': _createdAt.toIso8601String(),
        'status': CryptographicMaterialStatus.active,
        'bytes': 'dmFsdWU=',
      },
    ],
  };
}
