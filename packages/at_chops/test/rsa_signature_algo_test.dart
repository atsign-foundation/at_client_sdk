import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  final Uint8List message = Uint8List.fromList(
      '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4'.codeUnits);

  group('RsaSignatureAlgo — 2048', () {
    late ({Uint8List publicKey, Uint8List secretKey}) kp;

    setUpAll(() async {
      kp = await RsaSignatureAlgo.rsa2048().generateKeyPair();
    });

    test('sign/verify round-trip yields true', () async {
      final algo = RsaSignatureAlgo.rsa2048();
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isTrue);
    });

    test('sha512 round-trip yields true', () async {
      final algo = RsaSignatureAlgo.rsa2048(hashing: HashingAlgoType.sha512);
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isTrue);
    });

    test('signing with sha256 does not verify under sha512', () async {
      final sig = await RsaSignatureAlgo.rsa2048()
          .signBytes(message, secretKey: kp.secretKey);
      final verifier =
          RsaSignatureAlgo.rsa2048(hashing: HashingAlgoType.sha512);
      expect(
          await verifier.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isFalse);
    });

    test('a tampered message does not verify', () async {
      final algo = RsaSignatureAlgo.rsa2048();
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      final tampered = Uint8List.fromList(message)..[0] ^= 0xff;
      expect(
          await algo.verifyBytes(tampered,
              signature: sig, publicKey: kp.publicKey),
          isFalse);
    });

    test('another key pair does not verify', () async {
      final algo = RsaSignatureAlgo.rsa2048();
      final other = await algo.generateKeyPair();
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: other.publicKey),
          isFalse);
    });

    test('generateKeyPair returns DER that RsaKeyPair can round-trip',
        () async {
      // The doc comment promises base64 is the only step between these two
      // representations. If that stops being true, callers migrating an
      // existing RsaKeyPair silently lose the ability to sign with it.
      final algo = RsaSignatureAlgo.rsa2048();
      final fromStrings = RsaKeyPair.generate();
      final sig = await algo.signBytes(message,
          secretKey: base64Decode(fromStrings.atPrivateKey.privateKey));
      expect(
          await algo.verifyBytes(message,
              signature: sig,
              publicKey: base64Decode(fromStrings.atPublicKey.publicKey)),
          isTrue);
    });

    test('reports rsa2048 and its digest for the wire', () {
      final algo = RsaSignatureAlgo.rsa2048();
      expect(algo.signingAlgoType, equals(SigningAlgoType.rsa2048));
      expect(algo.signingAlgoType.name, equals('rsa2048'));
      expect(algo.hashingAlgoType, equals(HashingAlgoType.sha256));
      expect(
          RsaSignatureAlgo.rsa2048(hashing: HashingAlgoType.sha512)
              .hashingAlgoType,
          equals(HashingAlgoType.sha512));
    });
  });

  group('RsaSignatureAlgo — 4096', () {
    late ({Uint8List publicKey, Uint8List secretKey}) kp;

    setUpAll(() async {
      kp = await RsaSignatureAlgo.rsa4096().generateKeyPair();
    });

    test('sign/verify round-trip yields true', () async {
      final algo = RsaSignatureAlgo.rsa4096();
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isTrue);
    });

    test('reports rsa4096', () {
      expect(RsaSignatureAlgo.rsa4096().signingAlgoType,
          equals(SigningAlgoType.rsa4096));
    });

    test('rejects a 2048-bit secret key rather than mislabelling it', () async {
      final small = await RsaSignatureAlgo.rsa2048().generateKeyPair();
      expect(
          () => RsaSignatureAlgo.rsa4096()
              .signBytes(message, secretKey: small.secretKey),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains('2048-bit') &&
              e.toString().contains('rsa4096'))));
    });

    test('rejects a 2048-bit public key on verify', () async {
      final small = await RsaSignatureAlgo.rsa2048().generateKeyPair();
      final sig = await RsaSignatureAlgo.rsa2048()
          .signBytes(message, secretKey: small.secretKey);
      expect(
          () => RsaSignatureAlgo.rsa4096()
              .verifyBytes(message, signature: sig, publicKey: small.publicKey),
          throwsA(predicate((e) =>
              e is AtSigningVerificationException &&
              e.toString().contains('2048-bit'))));
    });

    // RSA-4096 key generation is slow and probabilistic; the default 30s
    // timeout is not a safe margin for two of them on a loaded machine.
  }, timeout: Timeout(Duration(minutes: 5)));

  group('RsaSignatureAlgo — rejected inputs', () {
    test('a digest other than sha256/sha512 is rejected at construction', () {
      for (final bad in [HashingAlgoType.md5, HashingAlgoType.argon2id]) {
        expect(
            () => RsaSignatureAlgo.rsa2048(hashing: bad),
            throwsA(predicate((e) =>
                e is AtSigningException &&
                e.toString().contains('invalid/not supported'))),
            reason: '$bad should not construct');
      }
    });

    test('unparseable secret key throws AtSigningException', () {
      expect(
          () => RsaSignatureAlgo.rsa2048()
              .signBytes(message, secretKey: Uint8List.fromList([1, 2, 3])),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains('PKCS#8 RSA private key'))));
    });

    test('unparseable public key throws AtSigningVerificationException', () {
      expect(
          () => RsaSignatureAlgo.rsa2048().verifyBytes(message,
              signature: Uint8List.fromList([1, 2, 3]),
              publicKey: Uint8List.fromList([1, 2, 3])),
          throwsA(predicate((e) =>
              e is AtSigningVerificationException &&
              e.toString().contains('X.509 RSA public key'))));
    });
  });
}
