import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

import 'x_wing_test_vectors.dart';

void main() {
  const algo = XWingPureDartAlgo.instance;

  group('draft-connolly-cfrg-xwing-kem-10 test vector 1', () {
    final seed = XWingVector1.seed;
    final eseed = XWingVector1.eseed;
    final ct = XWingVector1.ct;
    final expectedSs = XWingVector1.expectedSs;

    test('key generation derives the vector public key', () async {
      final kp = await algo.generateKeyPair(seed);
      expect(kp.publicKey.length, XWingPureDartAlgo.publicKeyLength);
      expect(kp.secretKey, seed);
      final pkHex = toHex(kp.publicKey);
      // Prefix per the draft's vector listing. The suffix below is pinned
      // from this implementation, cross-validated by the byte-exact ct and
      // ss vector matches in the following tests (ct_M binds to pk_M and
      // the combiner binds ss to pk_X, so those equalities prove the pk).
      expect(pkHex.substring(0, 16), 'e2236b35a8c24b39');
      expect(pkHex.substring(pkHex.length - 32),
          '23593d4ba32d9abac8cd049040ef6534');
    });

    test('derandomized encapsulation reproduces the vector ct and ss',
        () async {
      final kp = await algo.generateKeyPair(seed);
      final result = await algo.encapsulateDerand(kp.publicKey, eseed);
      expect(toHex(result.ciphertext), toHex(ct));
      expect(result.sharedSecret, expectedSs);
    });

    test('decapsulation of the vector ciphertext yields the vector ss',
        () async {
      expect(ct.length, XWingPureDartAlgo.ciphertextLength);
      final ss = await algo.decapsulate(seed, ct);
      expect(ss, expectedSs);
    });
  });

  group('round trip and behavior', () {
    test('random-key round trip agrees on the shared secret', () async {
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, 1216);
      expect(kp.secretKey.length, 32);

      final enc = await algo.encapsulate(kp.publicKey);
      expect(enc.ciphertext.length, 1120);
      expect(enc.sharedSecret.length, 32);

      final ss = await algo.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test('two encapsulations against one key produce distinct secrets',
        () async {
      final kp = await algo.generateKeyPair();
      final a = await algo.encapsulate(kp.publicKey);
      final b = await algo.encapsulate(kp.publicKey);
      expect(a.sharedSecret, isNot(equals(b.sharedSecret)));
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });

    test(
        'a tampered ciphertext decapsulates to a different secret '
        '(implicit rejection), not an error', () async {
      final kp = await algo.generateKeyPair();
      final enc = await algo.encapsulate(kp.publicKey);
      final tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;
      final ss = await algo.decapsulate(kp.secretKey, tampered);
      expect(ss.length, 32);
      expect(ss, isNot(equals(enc.sharedSecret)));
    });

    test('wrong-size inputs are rejected', () async {
      expect(() => algo.generateKeyPair(Uint8List(31)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.encapsulate(Uint8List(1215)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.decapsulate(Uint8List(32), Uint8List(1119)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.decapsulate(Uint8List(33), Uint8List(1120)),
          throwsA(isA<ArgumentError>()));
    });

    test('XWingKeyPair.generate round-trips via base64', () async {
      final atKp = await XWingKeyPair.generate();
      final pub = base64Decode(atKp.atPublicKey.publicKey);
      final seed = base64Decode(atKp.atPrivateKey.privateKey);
      final enc = await algo.encapsulate(pub);
      final ss = await algo.decapsulate(seed, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });
  });
}
