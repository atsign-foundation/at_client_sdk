import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtSignatureAlgorithm wire identity', () {
    test('rsa declares its constructed size and hash', () {
      expect(RsaSigningAlgo().signingAlgoType, SigningAlgoType.rsa2048);
      expect(RsaSigningAlgo().hashingAlgoType, HashingAlgoType.sha256);
      expect(RsaSigningAlgo(keySize: 4096).signingAlgoType,
          SigningAlgoType.rsa4096);
      expect(
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha512)
              .hashingAlgoType,
          HashingAlgoType.sha512);
    });

    test('rsa throws for a key size the protocol cannot name', () {
      expect(() => RsaSigningAlgo(keySize: 3072).signingAlgoType,
          throwsA(isA<AtSigningException>()));
    });

    test('ecc declares secp256r1 over sha256', () {
      expect(EccSigningAlgo().signingAlgoType, SigningAlgoType.eccSecp256r1);
      expect(EccSigningAlgo().hashingAlgoType, HashingAlgoType.sha256);
    });

    test('ed25519 declares no separate hashing algo', () {
      expect(Ed25519SigningAlgo().signingAlgoType, SigningAlgoType.ed25519);
      expect(Ed25519SigningAlgo().hashingAlgoType, isNull);
    });

    test('ml-dsa-65 declares no separate hashing algo', () {
      expect(MlDsa65PureDartAlgo().signingAlgoType, SigningAlgoType.mldsa65);
      expect(MlDsa65PureDartAlgo().hashingAlgoType, isNull);
    });
  });
}
