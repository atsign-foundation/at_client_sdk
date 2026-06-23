import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysSet maps', () {
    test('exposes map-backed keys as list-like getters', () {
      final keyPair = _keyPair(pairId: 'default-pkam');
      final symmetricKey = _symmetricKey(id: 'self-encryption');
      final keys = _atKeysSet(
        keyPair: keyPair,
        symmetricKey: symmetricKey,
      );

      expect(keys.asymmetricKeys, [keyPair]);
      expect(keys.symmetricKeys, [symmetricKey]);
      expect(
        () => keys.asymmetricKeys.add(_keyPair(pairId: 'other-pkam')),
        throwsUnsupportedError,
      );
    });

    test('rejects duplicate identities in constructor and add', () {
      expect(
        () => AtKeysSet(
          atsign: '@alice'.toAtsign(),
          keyPairs: [
            _keyPair(pairId: 'duplicate'),
            _keyPair(pairId: 'duplicate'),
          ],
          symmetricKeys: const [],
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
}

AtKeysSet _atKeysSet({
  AtKeyPair? keyPair,
  AtSymmetricKey? symmetricKey,
}) {
  return AtKeysSet(
    atsign: '@alice'.toAtsign(),
    enrollmentId: 'enrollment',
    keyPairs: [keyPair ?? _keyPair()],
    symmetricKeys: [symmetricKey ?? _symmetricKey()],
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
    rotation: KeyRotation(
      status: KeyRotationStatus.active,
      createdAt: DateTime.utc(2026),
      retiredAt: DateTime.utc(2027),
    ),
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
    rotation: KeyRotation(
      status: KeyRotationStatus.active,
      createdAt: DateTime.utc(2026),
      retiredAt: DateTime.utc(2027),
    ),
    operations: const ['encrypt', 'decrypt'],
  );
}
