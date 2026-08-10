import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart' show AtException;
import 'package:test/test.dart';

void main() {
  group('EncryptionAlgoType', () {
    test('names are the wire identifiers', () {
      expect(EncryptionAlgoType.values.map((a) => a.name),
          equals(['aesctr', 'aesgcm256', 'rsa']),
          reason: 'these strings are what an algorithm reports as its name — '
              'renaming a constant changes a protocol identifier');
    });

    test('fromString round-trips every value', () {
      for (final EncryptionAlgoType algo in EncryptionAlgoType.values) {
        expect(EncryptionAlgoType.fromString(algo.name), equals(algo));
      }
    });

    test('fromString is case-insensitive', () {
      expect(EncryptionAlgoType.fromString('AESGCM256'),
          equals(EncryptionAlgoType.aesgcm256));
    });

    test('fromString throws on an unknown name', () {
      expect(() => EncryptionAlgoType.fromString('chacha20'),
          throwsA(isA<AtException>()));
    });
  });

  group('KemAlgoType', () {
    test('names are the wire identifiers', () {
      expect(
          KemAlgoType.values.map((a) => a.name), equals(['mlkem768', 'xwing']));
    });

    test('fromString round-trips every value', () {
      for (final KemAlgoType algo in KemAlgoType.values) {
        expect(KemAlgoType.fromString(algo.name), equals(algo));
      }
    });

    test('fromString throws on an unknown name', () {
      expect(() => KemAlgoType.fromString('mlkem1024'),
          throwsA(isA<AtException>()));
    });
  });

  group('KeyAgreementAlgoType', () {
    test('names are the wire identifiers', () {
      expect(
          KeyAgreementAlgoType.values.map((a) => a.name), equals(['x25519']));
    });

    test('fromString round-trips every value', () {
      for (final KeyAgreementAlgoType algo in KeyAgreementAlgoType.values) {
        expect(KeyAgreementAlgoType.fromString(algo.name), equals(algo));
      }
    });

    test('fromString throws on an unknown name', () {
      expect(() => KeyAgreementAlgoType.fromString('x448'),
          throwsA(isA<AtException>()));
    });
  });

  group('SigningAlgoType', () {
    test('fromString round-trips every value', () {
      for (final SigningAlgoType algo in SigningAlgoType.values) {
        expect(SigningAlgoType.fromString(algo.name), equals(algo));
      }
    });

    test('fromString round-trips the one camelCase constant', () {
      expect(SigningAlgoType.fromString('eccSecp256r1'),
          equals(SigningAlgoType.eccSecp256r1),
          reason: 'lowercasing only the argument, as HashingAlgoType did, '
              'would never match eccSecp256r1');
    });

    test('fromString throws on an unknown name', () {
      expect(() => SigningAlgoType.fromString('mldsa87'),
          throwsA(isA<AtException>()));
    });
  });

  group('algorithm implementations report their enum name', () {
    test('both AES-256-GCM backends share one identifier', () {
      expect(AesGcm256EncryptionAlgo().name, equals('aesgcm256'));
    });

    test('AES-CTR', () {
      expect(AesCtrEncryptionAlgo(32).name, equals('aesctr'));
    });

    test('RSA', () {
      expect(RsaEncryptionAlgo().name, equals('rsa'));
    });

    test('ML-KEM-768', () {
      expect(MlKem768PureDartAlgo.instance.name, equals('mlkem768'));
    });

    test('X-Wing', () {
      expect(XWingPureDartAlgo.instance.name, equals('xwing'));
    });

    test('X25519', () {
      expect(X25519PureDartAlgo.instance.name, equals('x25519'));
    });
  });
}
