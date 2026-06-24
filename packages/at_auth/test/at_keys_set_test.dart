import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/serialization/resolver.dart';
import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysSet maps', () {
    test('exposes map-backed keys as iterable getters', () {
      final keyPair = _keyPair(pairId: 'default-pkam');
      final symmetricKey = _symmetricKey(id: 'self-encryption');
      final keys = _atKeysSet(
        keyPair: keyPair,
        symmetricKey: symmetricKey,
      );

      expect(keys.keyPairs, [keyPair]);
      expect(keys.symmetricKeys, [symmetricKey]);
    });

    test('rejects duplicate identities in constructor and add', () {
      expect(
        () => WritableAtKeysSet(
          atsign: '@alice'.toAtsign(),
          keys: [
            _keyPair(pairId: 'duplicate'),
            _keyPair(pairId: 'duplicate'),
          ],
        ),
        throwsArgumentError,
      );

      final keys = _atKeysSet();

      expect(
        () => keys.addKey(_keyPair()),
        throwsArgumentError,
      );
      expect(
        () => keys.addKey(_symmetricKey()),
        throwsArgumentError,
      );
    });
  });

  group('AtKeysSet equality', () {
    test('compares asymmetric and symmetric keys by value', () {
      final left = _atKeysSet();
      final right = _atKeysSet();

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('changes when key material changes', () {
      final left = _atKeysSet();
      final right = _atKeysSet(
        symmetricKey: _symmetricKey(
          bytes: AtBytes.fromString('ZGlmZmVyZW50'),
        ),
      );

      expect(left, isNot(right));
    });
  });

  group('AtKeysMaterial equality', () {
    test('compares nested value objects and operations by value', () {
      final left = _keyPair();
      final right = _keyPair();

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('distinguishes different operations', () {
      final left = _keyPair(operations: ['authenticate']);
      final right = _keyPair(operations: ['verify']);

      expect(left, isNot(right));
    });
  });

  group('AtKeys rotation serialization', () {
    test('KeyRotation round trips through JSON', () {
      final rotation = _rotation();

      expect(KeyRotation.fromJson(rotation.toJson()), rotation);
      expect(rotation.toJson(), {
        'status': 'active',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'retiredAt': '2027-01-01T00:00:00.000Z',
      });
    });

    test('codec encodes and decodes rotation as an object', () {
      final codec = AtKeysJsonCodec();
      final rotation = _rotation();

      final document = codec.decodeDocument({
        'version': AtKeysJsonCodec.supportedVersion,
        'atSign': '@alice',
        'keys': [
          {
            'id': 'self-encryption',
            'purpose': KeyPurposes.selfEncryption,
            'kind': 'symmetric',
            'algorithm': 'aes-256',
            'rotation': rotation.toJson(),
            'value': 'c3ltbWV0cmlj',
          },
        ],
      });

      expect(document.keys.single.rotation, rotation);

      final encoded = codec.encodeDocument(document);
      final encodedKey = (encoded['keys'] as List).single as Map;
      expect(encodedKey['rotation'], rotation.toJson());
      expect(encodedKey.containsKey('status'), isFalse);
      expect(encodedKey.containsKey('createdAt'), isFalse);
      expect(encodedKey.containsKey('retiredAt'), isFalse);
    });

    test('resolver preserves rotation between document and AtKeysSet', () {
      final resolver = AtKeysDocumentResolver();
      final rotation = _rotation();
      final document = AtKeysDocument(
        version: AtKeysDocumentResolver.version,
        atsign: '@alice',
        keys: [
          KeyRecord(
            id: 'default-pkam-public',
            pairId: 'default-pkam',
            purpose: KeyPurposes.pkam,
            kind: KeyRecordKind.public,
            algorithm: 'rsa-2048',
            rotation: rotation,
            bytes: AtBytes.fromString('cHVibGlj'),
          ),
          KeyRecord(
            id: 'default-pkam-private',
            pairId: 'default-pkam',
            purpose: KeyPurposes.pkam,
            kind: KeyRecordKind.private,
            algorithm: 'rsa-2048',
            rotation: rotation,
            bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
          ),
          KeyRecord(
            id: 'self-encryption',
            purpose: KeyPurposes.selfEncryption,
            kind: KeyRecordKind.symmetric,
            algorithm: 'aes-256',
            rotation: rotation,
            bytes: AtBytes.fromString('c3ltbWV0cmlj'),
          ),
        ],
      );

      final keys = resolver.resolve(document);

      expect(keys.getKeyPair('default-pkam')!.rotation, rotation);
      expect(keys.getSymmetricKey('self-encryption')!.rotation, rotation);

      final resolvedDocument = resolver.resolveToDocument(keys);
      expect(
        resolvedDocument.keys.map((record) => record.rotation),
        everyElement(equals(rotation)),
      );
    });
  });
}

WritableAtKeysSet _atKeysSet({
  AtKeyPair? keyPair,
  AtSymmetricKey? symmetricKey,
}) {
  return WritableAtKeysSet(
    atsign: '@alice'.toAtsign(),
    enrollmentId: 'enrollment',
    keys: [
      keyPair ?? _keyPair(),
      symmetricKey ?? _symmetricKey(),
    ],
  );
}

AtKeyPair _keyPair({
  String pairId = 'default-pkam',
  List<String> operations = const ['authenticate', 'sign'],
}) {
  return AtKeyPair(
    pairId: pairId,
    purpose: KeyPurposes.pkam,
    algorithm: 'rsa-2048',
    fingerprint: KeyFingerprint(
      algorithm: 'sha-256',
      value: AtBytes.fromString('ZmluZ2VycHJpbnQ='),
    ),
    publicKey: AtBytes.fromString('cHVibGlj'),
    privateKey: AtBytes.fromString('cHJpdmF0ZQ=='),
    publicKeyProtection: const KeyProtection(
      keyRef: 'self-encryption',
      algorithm: 'aes-256-ctr',
      iv: 'AAAAAAAAAAAAAAAAAAAAAA==',
    ),
    privateKeyProtection: const KeyProtection(
      keyRef: 'self-encryption',
      algorithm: 'aes-256-ctr',
      iv: 'AAAAAAAAAAAAAAAAAAAAAA==',
    ),
    rotation: _rotation(),
    operations: operations,
  );
}

AtSymmetricKey _symmetricKey({
  String id = 'self-encryption',
  AtBytes? bytes,
}) {
  return AtSymmetricKey(
    id: id,
    purpose: KeyPurposes.selfEncryption,
    algorithm: 'aes-256',
    bytes: bytes ?? AtBytes.fromString('c3ltbWV0cmlj'),
    protection: const KeyProtection(
      keyRef: 'self-encryption',
      algorithm: 'aes-256-ctr',
      iv: 'AAAAAAAAAAAAAAAAAAAAAA==',
    ),
    rotation: _rotation(),
    operations: const ['encrypt', 'decrypt'],
  );
}

KeyRotation _rotation() {
  return KeyRotation(
    status: KeyRotationStatus.active,
    createdAt: DateTime.utc(2026),
    retiredAt: DateTime.utc(2027),
  );
}
