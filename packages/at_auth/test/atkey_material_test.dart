import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:test/test.dart';

/// Tripwire tests: [KeyAlgorithmType] and [CryptographicKeyType] values are
/// persisted in `.atKeys` files and enrollment payloads already on disk and
/// on the wire across the Atsign Protocol ecosystem. These tests pin the exact
/// string literal for every existing token so an accidental rename, re-case,
/// or "cleanup" fails CI immediately instead of silently orphaning key
/// material written with the old value. Do NOT update an expected value to
/// make a failing test pass here — if this test fails, the source change is
/// the bug, not the test.
void main() {
  group('KeyAlgorithmType tripwire', () {
    test('existing token values never change', () {
      expect(KeyAlgorithmType.aes256, 'aes256');
      expect(KeyAlgorithmType.rsa2048, 'rsa2048');
      expect(KeyAlgorithmType.eccSecp256r1, 'ecc_secp256r1');
      expect(KeyAlgorithmType.ed25519, 'ed25519');
      expect(KeyAlgorithmType.x25519, 'x25519');
      expect(KeyAlgorithmType.mlKem768, 'mlkem768');
      expect(KeyAlgorithmType.mlDsa65, 'mldsa65');
      expect(KeyAlgorithmType.xWing, 'xwing');
    });

    test('known contains exactly the declared tokens, nothing more or less',
        () {
      expect(
        KeyAlgorithmType.known,
        equals({
          'aes256',
          'rsa2048',
          'ecc_secp256r1',
          'ed25519',
          'x25519',
          'mlkem768',
          'mldsa65',
          'xwing',
        }),
      );
    });
  });

  group('CryptographicKeyType tripwire', () {
    test('existing token values never change', () {
      expect(CryptographicKeyType.symmetricEncryption, 'symmetricEncryption');
      expect(CryptographicKeyType.symmetricAuthentication,
          'symmetricAuthentication');
      expect(CryptographicKeyType.publicEncryption, 'publicEncryption');
      expect(CryptographicKeyType.privateDecryption, 'privateDecryption');
      expect(CryptographicKeyType.publicVerification, 'publicVerification');
      expect(CryptographicKeyType.privateSigning, 'privateSigning');
      expect(CryptographicKeyType.publicEncapsulation, 'publicEncapsulation');
      expect(CryptographicKeyType.privateDecapsulation, 'privateDecapsulation');
      expect(CryptographicKeyType.publicKeyAgreement, 'publicKeyAgreement');
      expect(CryptographicKeyType.privateKeyAgreement, 'privateKeyAgreement');
    });

    test('known contains exactly the declared tokens, nothing more or less',
        () {
      expect(
        CryptographicKeyType.known,
        equals({
          'symmetricEncryption',
          'symmetricAuthentication',
          'publicEncryption',
          'privateDecryption',
          'publicVerification',
          'privateSigning',
          'publicEncapsulation',
          'privateDecapsulation',
          'publicKeyAgreement',
          'privateKeyAgreement',
        }),
      );
    });
  });
}
