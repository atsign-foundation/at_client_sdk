import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysJsonCodec', () {
    final codec = AtKeysJsonCodec();

    test('round-trips optional key record fields', () {
      final document = AtKeysDocument(
        version: AtKeysJsonCodec.supportedVersion,
        atsign: '@alice'.toAtsign(),
        legacyJson: const {},
        keys: [
          KeyRecord(
            id: 'wrapper',
            kind: KeyRecordKind.symmetric,
            algorithm: 'AES-256',
            operations: const ['encrypt', 'decrypt'],
            bytes: AtBytes.fromString('d3JhcHBlcg=='),
          ),
          KeyRecord(
            id: 'enroll-public',
            pairId: 'enroll-pair',
            kind: KeyRecordKind.public,
            algorithm: 'RSA',
            operations: const ['verify'],
            bytes: AtBytes.fromString('ZW5yb2xsUHVibGlj'),
            enrollmentId: 'enroll-1',
          ),
          KeyRecord(
            id: 'enroll-secret',
            kind: KeyRecordKind.symmetric,
            algorithm: 'AES-256',
            protection: const KeyProtection(
              keyRef: 'wrapper',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            bytes: AtBytes.fromString('ZW5yb2xsU2VjcmV0'),
            enrollmentId: 'enroll-1',
          ),
        ],
      );

      final encoded = codec.encodeDocument(document);
      final decoded = codec.decodeDocument(encoded);
      final public =
          decoded.keys.singleWhere((key) => key.id == 'enroll-public');
      final secret =
          decoded.keys.singleWhere((key) => key.id == 'enroll-secret');

      expect(public.pairId, 'enroll-pair');
      expect(public.operations, const ['verify']);
      expect(public.enrollmentId, 'enroll-1');
      expect(secret.enrollmentId, 'enroll-1');
      expect(secret.protection?.keyRef, 'wrapper');
      expect(secret.protection?.algorithm, 'AES-256-GCM');
      expect(secret.protection?.iv, 'aXY=');
    });

    test('rejects duplicate ids', () {
      final json = <String, dynamic>{
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'legacy': const {},
        'keys': [
          _recordJson(id: 'duplicate'),
          _recordJson(id: 'duplicate'),
        ],
      };

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects unknown protection key references', () {
      final json = <String, dynamic>{
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'legacy': const {},
        'keys': [
          _recordJson(
            id: 'private',
            kind: 'private',
            pairId: 'private-pair',
            protection: const {
              'keyRef': 'missing',
              'algorithm': 'AES-256-GCM',
              'iv': 'aXY=',
            },
          ),
        ],
      };

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysProtectionException>()),
      );
    });

    test('rejects more than one key of a kind sharing an enrollmentId', () {
      final json = <String, dynamic>{
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'legacy': const {},
        'keys': [
          _recordJson(
            id: 'first',
            kind: 'public',
            pairId: 'first-pair',
            enrollmentId: 'enroll-1',
          ),
          _recordJson(
            id: 'second',
            kind: 'public',
            pairId: 'second-pair',
            enrollmentId: 'enroll-1',
          ),
        ],
      };

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysEnrollmentException>()),
      );
    });

    test('treats a document with no version field as legacy', () {
      final decoded = codec.decodeDocument(<String, dynamic>{
        'aabbcc': 'some-legacy-key-value',
      });

      expect(decoded, isA<LegacyAtKeysDocument>());
    });

    test('rejects an unsupported version', () {
      expect(
        () => codec.decodeDocument(<String, dynamic>{
          'version': 999,
          'atSign': '@alice',
          'legacy': const {},
          'keys': const [],
        }),
        throwsA(isA<AtKeysUnsupportedVersionException>()),
      );
    });

    test('rejects a missing atSign', () {
      expect(
        () => codec.decodeDocument(<String, dynamic>{
          'version': AtKeysJsonCodec.supportedVersion,
          'legacy': const {},
          'keys': const [],
        }),
        throwsA(isA<AtKeysParseException>()),
      );
    });

    test('rejects a non-list keys field', () {
      expect(
        () => codec.decodeDocument(<String, dynamic>{
          'version': AtKeysJsonCodec.supportedVersion,
          'atSign': '@alice',
          'legacy': const {},
          'keys': const <String, dynamic>{},
        }),
        throwsA(isA<AtKeysParseException>()),
      );
    });

    test('rejects a malformed base64 value', () {
      expect(
        () => codec.decodeDocument(<String, dynamic>{
          'version': AtKeysJsonCodec.supportedVersion,
          'atSign': '@alice',
          'legacy': const {},
          'keys': [
            {
              'id': 'symmetric',
              'kind': 'symmetric',
              'algorithm': 'AES-256',
              'value': 'not valid base64!!!',
            },
          ],
        }),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects a symmetric key that carries a pairId', () {
      expect(
        () => codec.decodeDocument(_singleKeyDoc(
          _recordJson(id: 'symmetric', kind: 'symmetric', pairId: 'pair'),
        )),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects an asymmetric key without a pairId', () {
      expect(
        () => codec.decodeDocument(_singleKeyDoc(
          _recordJson(id: 'public', kind: 'public'),
        )),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects a protected public key', () {
      expect(
        () => codec.decodeDocument(_singleKeyDoc(
          _recordJson(
            id: 'public',
            kind: 'public',
            pairId: 'public-pair',
            protection: const {
              'keyRef': 'wrapper',
              'algorithm': 'AES-256-GCM',
              'iv': 'aXY=',
            },
          ),
        )),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('rejects a key that protects itself', () {
      expect(
        () => codec.decodeDocument(_singleKeyDoc(
          _recordJson(
            id: 'private',
            kind: 'private',
            pairId: 'private-pair',
            protection: const {
              'keyRef': 'private',
              'algorithm': 'AES-256-GCM',
              'iv': 'aXY=',
            },
          ),
        )),
        throwsA(isA<AtKeysProtectionException>()),
      );
    });
  });
}

Map<String, dynamic> _singleKeyDoc(Map<String, dynamic> record) {
  return <String, dynamic>{
    'version': AtKeysJsonCodec.supportedVersion,
    'atSign': '@alice',
    'legacy': const {},
    'keys': [record],
  };
}

Map<String, dynamic> _recordJson({
  required String id,
  String kind = 'symmetric',
  String? pairId,
  Map<String, dynamic>? protection,
  String? enrollmentId,
}) {
  return {
    'id': id,
    if (pairId != null) 'pairId': pairId,
    'kind': kind,
    'algorithm': 'AES-256',
    if (protection != null) 'protection': protection,
    if (enrollmentId != null) 'enrollmentId': enrollmentId,
    'value': 'dmFsdWU=',
  };
}
