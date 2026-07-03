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
        keys: [
          KeyRecord(
            id: 'wrapper',
            kind: KeyRecordKind.symmetric,
            algorithm: 'AES-256',
            operations: const ['encrypt', 'decrypt'],
            bytes: AtBytes.fromString('d3JhcHBlcg=='),
          ),
          KeyRecord(
            id: 'package',
            pairId: 'package-pair',
            kind: KeyRecordKind.package,
            algorithm: 'RSA',
            operations: const ['sign'],
            protection: const KeyProtection(
              keyRef: 'wrapper',
              algorithm: 'AES-256-GCM',
              iv: 'aXY=',
            ),
            publicKey: AtBytes.fromString('cHVibGlj'),
            bytes: AtBytes.fromString('c2VjcmV0'),
          ),
        ],
      );

      final encoded = codec.encodeDocument(document);
      final decoded = codec.decodeDocument(encoded);
      final package = decoded.keys.singleWhere((key) => key.id == 'package');

      expect(package.pairId, 'package-pair');
      expect(package.operations, const ['sign']);
      expect(package.protection?.keyRef, 'wrapper');
      expect(package.protection?.algorithm, 'AES-256-GCM');
      expect(package.protection?.iv, 'aXY=');
      expect(package.publicKey.toString(), 'cHVibGlj');
    });

    test('rejects duplicate ids', () {
      final json = <String, dynamic>{
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
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
  });
}

Map<String, dynamic> _recordJson({
  required String id,
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
