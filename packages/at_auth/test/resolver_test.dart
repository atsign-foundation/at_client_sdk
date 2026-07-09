import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/serialization/resolver.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysDocumentResolver', () {
    const resolver = AtKeysDocumentResolver();

    test('resolves document records to typed keys', () {
      final document = AtKeysDocument(
        version: AtKeysJsonCodec.supportedVersion,
        atsign: '@alice'.toAtsign(),
        legacyJson: const {},
        keys: [
          KeyRecord(
            id: 'public-pair',
            pairId: 'pair',
            kind: KeyRecordKind.public,
            algorithm: 'RSA',
            bytes: AtBytes.fromString('cHVibGlj'),
          ),
          KeyRecord(
            id: 'private-pair',
            pairId: 'pair',
            kind: KeyRecordKind.private,
            algorithm: 'RSA',
            protection: const KeyProtection(
              keyRef: 'symmetric',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
          ),
          KeyRecord(
            id: 'symmetric',
            kind: KeyRecordKind.symmetric,
            algorithm: 'AES-256',
            bytes: AtBytes.fromString('c2VjcmV0'),
          ),
          // The two records an enrollment used to bundle as one AtKeyPackage:
          // an APKAM public key and its symmetric secret, grouped by enrollmentId.
          KeyRecord(
            id: 'enroll-public',
            pairId: 'enroll-pair',
            kind: KeyRecordKind.public,
            algorithm: 'RSA',
            bytes: AtBytes.fromString('ZW5yb2xsUHVibGlj'),
            enrollmentId: 'enroll-1',
          ),
          KeyRecord(
            id: 'enroll-secret',
            kind: KeyRecordKind.symmetric,
            algorithm: 'AES-256',
            protection: const KeyProtection(
              keyRef: 'symmetric',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            bytes: AtBytes.fromString('ZW5yb2xsU2VjcmV0'),
            enrollmentId: 'enroll-1',
          ),
        ],
      );

      final keys = resolver.resolve(document);

      expect(keys.atsign, document.atsign);
      expect(keys.getKey<AtPublicKey>('pair')?.bytes.toString(), 'cHVibGlj');
      expect(
        keys.getKey<AtPrivateKey>('pair')?.protection?.keyRef,
        'symmetric',
      );
      expect(
        keys.getKey<AtSymmetricKey>('symmetric')?.bytes.toString(),
        'c2VjcmV0',
      );
      expect(
        keys
            .keysForEnrollment('enroll-1')
            .map((material) => material.id)
            .toSet(),
        {'enroll-pair', 'enroll-secret'},
      );
    });

    test('resolves typed keys to document records', () {
      final keys = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [
          AtPublicKey(
            pairId: 'pair',
            algorithm: 'RSA',
            bytes: AtBytes.fromString('cHVibGlj'),
          ),
          AtPrivateKey(
            pairId: 'pair',
            algorithm: 'RSA',
            protection: const KeyProtection(
              keyRef: 'symmetric',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
          ),
          AtSymmetricKey(
            id: 'symmetric',
            algorithm: 'AES-256',
            bytes: AtBytes.fromString('c2VjcmV0'),
          ),
          AtPublicKey(
            pairId: 'enroll-pair',
            algorithm: 'RSA',
            bytes: AtBytes.fromString('ZW5yb2xsUHVibGlj'),
            enrollmentId: 'enroll-1',
          ),
          AtSymmetricKey(
            id: 'enroll-secret',
            algorithm: 'AES-256',
            protection: const KeyProtection(
              keyRef: 'symmetric',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            bytes: AtBytes.fromString('ZW5yb2xsU2VjcmV0'),
            enrollmentId: 'enroll-1',
          ),
        ],
      );

      final document = resolver.resolveToDocument(keys);

      expect(document.version, AtKeysJsonCodec.supportedVersion);
      expect(document.atsign, keys.atsign);
      expect(document.keys.map((record) => record.kind), [
        KeyRecordKind.public,
        KeyRecordKind.private,
        KeyRecordKind.symmetric,
        KeyRecordKind.public,
        KeyRecordKind.symmetric,
      ]);
      expect(document.keys[0].id, 'public:pair');
      expect(document.keys[1].id, 'private:pair');
      expect(document.keys[1].protection?.keyRef, 'symmetric');
      expect(document.keys[2].id, 'symmetric');
      expect(document.keys[3].id, 'public:enroll-pair');
      expect(document.keys[3].enrollmentId, 'enroll-1');
      expect(document.keys[4].id, 'enroll-secret');
      expect(document.keys[4].enrollmentId, 'enroll-1');
      expect(document.keys[4].protection?.keyRef, 'symmetric');
    });

    test('resolveToDocument preserves atSign-less keys as legacy document', () {
      final document = resolver.resolveToDocument(AtKeys());

      expect(document, isA<LegacyAtKeysDocument>());
      expect(document.legacyJson, isNotNull);
    });
  });
}
