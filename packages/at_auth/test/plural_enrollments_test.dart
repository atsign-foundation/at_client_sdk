import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// A keyfile holding more than one live enrollment is READ, and only a WRITER
/// refuses to create one.
///
/// The asymmetry is the point, and it is the lesson this tree wrote after a
/// `.single` shipped on a widened collection: a reader that refuses a second
/// entry makes the plurality unenableable, because the first build to emit two
/// breaks every build that predates it — so no build can ever start emitting
/// them. Reading is tolerant from day one; the refusal sits on the write path,
/// and the ambiguity surfaces where a caller asks for the one answer that does
/// not exist.
void main() {
  Map<String, dynamic> authPart(String algorithm) => {
        'role': CryptographicMaterialRole.privateAuthentication,
        'algorithm': algorithm,
        'createdAt': '2026-08-14T00:00:00.000Z',
        'status': CryptographicMaterialStatus.active,
        'bytes': 'dmFsdWU=',
      };

  /// Two enrollments, each holding an ACTIVE authentication keypair — the
  /// document this build refuses to write and must still read.
  Map<String, dynamic> twoLiveEnrollments() => {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'enrollments': [
          {
            'enrollmentId': 'e1',
            'keys': [
              {
                'keyId': 'auth:rsa2048:1',
                'material': [authPart(CryptographicMaterialAlgorithm.rsa2048)],
              },
            ],
          },
          {
            'enrollmentId': 'e2',
            'keys': [
              {
                'keyId': 'auth:mldsa65:1',
                'material': [authPart(CryptographicMaterialAlgorithm.mlDsa65)],
              },
            ],
          },
        ],
      };

  CryptographicMaterial authMaterial(String enrollmentId, CryptographicMaterialAlgorithm algorithm) =>
      CryptographicMaterial(
        keyId: 'auth:$algorithm:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: algorithm,
        bytes: AtBytes.fromString('dmFsdWU='),
        createdAt: DateTime.utc(2026, 8, 14),
      );

  group('a keyfile holding two live enrollments', () {
    test('is read rather than refusing the whole document', () {
      final keys = AtKeys.fromJson(twoLiveEnrollments());

      expect(keys.enrollmentIds, containsAll(['e1', 'e2']));
      expect(keys.keysForEnrollment('e1'), hasLength(1));
      expect(keys.keysForEnrollment('e2'), hasLength(1));

      // The positive control: the same document with ONE enrollment reads
      // too, so "it parsed" above is not passing for some unrelated reason.
      final single = twoLiveEnrollments()
        ..['enrollments'] = [
          (twoLiveEnrollments()['enrollments'] as List).first
        ];
      expect(AtKeys.fromJson(single).enrollmentIds, ['e1']);
    });

    test('round-trips both enrollments on flush', () {
      // Tolerance on the read alone would be worse than refusing: toJson
      // re-encodes from what was parsed, so an enrollment dropped on the way
      // in is an enrollment destroyed on the next flush — and the entry is
      // somebody's key material.
      final flushed = AtKeys.fromJson(twoLiveEnrollments()).toJson();

      final enrollments = flushed['enrollments'] as List;
      expect(enrollments, hasLength(2));
      expect(enrollments.map((e) => (e as Map)['enrollmentId']),
          containsAll(['e1', 'e2']));
      expect(
          ((enrollments.firstWhere((e) => (e as Map)['enrollmentId'] == 'e2')
                  as Map)['keys'] as List)
              .single['keyId'],
          'auth:mldsa65:1',
          reason: 'the second enrollment survives with its material, not just '
              'with its id');
    });

    test(
        'refuses to name one of them, and says which two it could not '
        'choose between', () {
      final keys = AtKeys.fromJson(twoLiveEnrollments());

      expect(
          keys.resolveAuthenticatingEnrollment,
          throwsA(isA<AtKeysEnrollmentException>().having((e) => e.toString(),
              'message', allOf(contains('e1'), contains('e2')))),
          reason: 'this is where the ambiguity belongs — the caller is asking '
              'for one answer and there are two. Picking the first silently '
              'is how a client authenticates as the wrong principal');

      // The contrast arm: with one live enrollment it answers, so the throw
      // above is about the ambiguity rather than the method being broken.
      final single = twoLiveEnrollments()
        ..['enrollments'] = [
          (twoLiveEnrollments()['enrollments'] as List).first
        ];
      expect(AtKeys.fromJson(single).resolveAuthenticatingEnrollment(), 'e1');
    });

    test('a caller that names its enrollment is unaffected by the other', () {
      // The whole reason reading is tolerant: a client that knows which
      // enrollment it is gets its own keys, and the ambiguity never arises.
      final keys = AtKeys.fromJson(twoLiveEnrollments());

      expect(
          keys
              .getKey('e2', 'auth:mldsa65:1',
                  CryptographicMaterialRole.privateAuthentication)!
              .algorithm,
          CryptographicMaterialAlgorithm.mlDsa65);
      expect(keys.signingAlgorithmForEnrollment('e1'), SigningAlgoType.rsa2048);
      expect(keys.signingAlgorithmForEnrollment('e2'), SigningAlgoType.mldsa65);
    });

    test('but a WRITER still refuses to create one', () {
      // The control that makes the tolerance meaningful. If this passed too,
      // the read-side change would have removed the rule rather than moved
      // it, and this build would start producing the documents it merely
      // tolerates.
      final keys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
        authMaterial('e1', CryptographicMaterialAlgorithm.rsa2048),
      ]);

      expect(
          () => keys.addKey(
              authMaterial('e2', CryptographicMaterialAlgorithm.mlDsa65)),
          throwsArgumentError);

      // ...and retiring the sitting one frees it, which is what a retrofit
      // does and must still be allowed.
      keys.retireKey('e1', 'auth:rsa2048:1');
      keys.addKey(authMaterial('e2', CryptographicMaterialAlgorithm.mlDsa65));
      expect(keys.resolveAuthenticatingEnrollment(), 'e2');
    });
  });
}
