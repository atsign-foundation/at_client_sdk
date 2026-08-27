import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:test/test.dart';

/// Tripwire tests: [CryptographicMaterialAlgorithm] and [CryptographicMaterialRole] values are
/// persisted in `.atKeys` files and enrollment payloads already on disk and
/// on the wire across the Atsign Protocol ecosystem. These tests pin the exact
/// string literal for every existing token so an accidental rename, re-case,
/// or "cleanup" fails CI immediately instead of silently orphaning key
/// material written with the old value. Do NOT update an expected value to
/// make a failing test pass here — if this test fails, the source change is
/// the bug, not the test.
void main() {
  group('CryptographicMaterialAlgorithm tripwire', () {
    test('existing token values never change', () {
      expect(CryptographicMaterialAlgorithm.aes256, 'aes256');
      expect(CryptographicMaterialAlgorithm.rsa2048, 'rsa2048');
      expect(CryptographicMaterialAlgorithm.eccSecp256r1, 'ecc_secp256r1');
      expect(CryptographicMaterialAlgorithm.ed25519, 'ed25519');
      expect(CryptographicMaterialAlgorithm.x25519, 'x25519');
      expect(CryptographicMaterialAlgorithm.mlKem768, 'mlkem768');
      expect(CryptographicMaterialAlgorithm.mlKem1024, 'mlkem1024');
      expect(CryptographicMaterialAlgorithm.mlDsa65, 'mldsa65');
      expect(CryptographicMaterialAlgorithm.xWing, 'xwing');
    });

    test('known contains exactly the declared tokens, nothing more or less',
        () {
      expect(
        CryptographicMaterialAlgorithm.known,
        equals({
          'aes256',
          'rsa2048',
          'ecc_secp256r1',
          'ed25519',
          'x25519',
          'mlkem768',
          'mlkem1024',
          'mldsa65',
          'xwing',
        }),
      );
    });
  });

  group('CryptographicMaterialRole tripwire', () {
    test('existing token values never change', () {
      expect(
          CryptographicMaterialRole.symmetricEncryption, 'symmetricEncryption');
      expect(CryptographicMaterialRole.symmetricAuthentication,
          'symmetricAuthentication');
      expect(CryptographicMaterialRole.publicEncryption, 'publicEncryption');
      expect(CryptographicMaterialRole.privateDecryption, 'privateDecryption');
      expect(
          CryptographicMaterialRole.publicVerification, 'publicVerification');
      expect(CryptographicMaterialRole.privateSigning, 'privateSigning');
      expect(
          CryptographicMaterialRole.publicEncapsulation, 'publicEncapsulation');
      expect(CryptographicMaterialRole.privateDecapsulation,
          'privateDecapsulation');
      expect(
          CryptographicMaterialRole.publicKeyAgreement, 'publicKeyAgreement');
      expect(
          CryptographicMaterialRole.privateKeyAgreement, 'privateKeyAgreement');
      expect(CryptographicMaterialRole.privateAuthentication,
          'privateAuthentication');
      expect(CryptographicMaterialRole.publicAuthentication,
          'publicAuthentication');
    });

    test('known contains exactly the declared tokens, nothing more or less',
        () {
      expect(
        CryptographicMaterialRole.known,
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
          'privateAuthentication',
          'publicAuthentication',
        }),
      );
    });
  });
}
