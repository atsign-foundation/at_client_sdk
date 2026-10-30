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

    test('a tampered message does not verify', () async {
      final algo = RsaSignatureAlgo.rsa4096();
      final sig = await algo.signBytes(message, secretKey: kp.secretKey);
      final tampered = Uint8List.fromList(message)..[0] ^= 0xff;
      expect(
          await algo.verifyBytes(tampered,
              signature: sig, publicKey: kp.publicKey),
          isFalse);
    });

    test('signing with sha256 does not verify under sha512', () async {
      final sig = await RsaSignatureAlgo.rsa4096()
          .signBytes(message, secretKey: kp.secretKey);
      final verifier =
          RsaSignatureAlgo.rsa4096(hashing: HashingAlgoType.sha512);
      expect(
          await verifier.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isFalse);
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

    test('a 2048-bit public key does not verify, and does not throw', () async {
      final small = await RsaSignatureAlgo.rsa2048().generateKeyPair();
      final sig = await RsaSignatureAlgo.rsa2048()
          .signBytes(message, secretKey: small.secretKey);
      expect(
          await RsaSignatureAlgo.rsa4096()
              .verifyBytes(message, signature: sig, publicKey: small.publicKey),
          isFalse);
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
              e.toString().contains('PKCS#8 PrivateKeyInfo'))));
    });

    // verifyBytes is the boundary where wire-supplied bytes arrive, so every
    // shape of bad input has to come back as false rather than as an
    // exception the caller is obliged to catch.
    test('unparseable public key verifies false', () async {
      expect(
          await RsaSignatureAlgo.rsa2048().verifyBytes(message,
              signature: Uint8List.fromList([1, 2, 3]),
              publicKey: Uint8List.fromList([1, 2, 3])),
          isFalse);
    });

    test('an empty public key verifies false', () async {
      expect(
          await RsaSignatureAlgo.rsa2048().verifyBytes(message,
              signature: Uint8List(0), publicKey: Uint8List(0)),
          isFalse);
    });

    test('a malformed signature verifies false against a good key', () async {
      final kp = await RsaSignatureAlgo.rsa2048().generateKeyPair();
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List(4096), // right ballpark of length, all zero bytes
      ]) {
        expect(
            await RsaSignatureAlgo.rsa2048()
                .verifyBytes(message, signature: bad, publicKey: kp.publicKey),
            isFalse,
            reason: 'signature of ${bad.length} bytes should not verify');
      }
    });
  });

  group(
      'RsaSignatureAlgo — interoperability with the deprecated RsaSigningAlgo',
      () {
    // The migration from RsaSigningAlgo to RsaSignatureAlgo is only safe if the
    // two produce the same bytes. RSASSA-PKCS1-v1_5 is deterministic, so this
    // asserts identity rather than merely that each signature is independently
    // valid — anything weaker would pass even if the two diverged on the wire.
    test('the two produce byte-identical signatures and verify each other',
        () async {
      final pair = RsaKeyPair.generate();
      // ignore: deprecated_member_use_from_same_package
      final legacy = RsaSigningAlgo(pair, HashingAlgoType.sha256);
      final modern = RsaSignatureAlgo.rsa2048();

      final legacySig = legacy.sign(message);
      final modernSig = await modern.signBytes(message,
          secretKey: base64Decode(pair.atPrivateKey.privateKey));

      expect(modernSig, equals(legacySig));
      expect(legacy.verify(message, modernSig), isTrue);
      expect(
          await modern.verifyBytes(message,
              signature: legacySig,
              publicKey: base64Decode(pair.atPublicKey.publicKey)),
          isTrue);
    });
  });

  group('RsaSignatureAlgo — known-answer vectors', () {
    // Every other test here signs and verifies with itself, so all of them
    // would stay green if the construction changed underneath (PKCS#1 v1.5 to
    // PSS, say) — the round trip would still close while the wire changed.
    // These raw literals pin the actual output. They were captured from this
    // implementation and are frozen: an intended change to the signature format
    // edits them in the same commit, and that edit is the review.
    //
    // Test-only key pair, generated for this file and used nowhere else.
    const String secretKeyB64 =
        'MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCjbdPCKkrVFg6Y'
        'TWQmml2kB3ZFIMC2kQZpRYdnRbkw99ss4I8FyZ68qmuwE6+GAlz/2MTsQ5gXWNd4'
        'W2ltseiJfsyJfI+pS3ptf//EDu/ArDk6BGA1YDFqa0u+nwNS7pSfai/e0BWtRZ4m'
        'yY/64zz4DwglxXqWeM+fFI9sJ3srw2xZ9QvsT/hb0VcU5f/pPNhCf8mPpOdVxPBz'
        'lScbGqChsxILY/y2nSHVDcI1dXqm9RiII3jN4XOEaSd74Q4p7CLHyO/qiFq+QCLB'
        '2jMlGYrqjLDDmUH6Qv57Io7gMXv7HBWwvCao6/ES2FYlg0qb0KhN+H+g4M7UonYY'
        'D2E6sGhhAgMBAAECggEBAIYTZjTXCYmDjPm6FD3vSn91d7wCwNeGZyIaXpmFBAd+'
        'cBuDJxLyc/4IOky7+bYRXkavie7jDXWp9yvQos/RsxqKIjdxL1MOjyQibKxmLJ9/'
        'K3vDd0KS5jeOSxfZ0JpLDTczoI5FXGNIyBS+LBcCMlS30FFcj9O+zWaPMZLjWRNu'
        '7SKvoFIo4MEFPeKckn9zAvczr89y/ePMTv6SnFJEzmyk9W/Y2PqyK3grPZHYJ9B+'
        'Vpdxvxg+yc7kGCsCsSsZUu8MlMEkieesIRAC2i2OOwkFQ+9auE8u9K9vgdzpyyrs'
        'SFSCt20HAVKbTD57MOszfIVXChunYjvbNEi+XRTrQ3kCgYEA9C0YcJtR6kUzvg8I'
        '0ITx1IKWL+uuD0qsQECNT3ALYXPuOwaADr37Bvgz6GEzhHpXU4NemTMWPeoMfirO'
        'E1xNcpgsP+qFkh7QHaWhqD9+Kf59OmTKoN/MNODOD3bMEygIwiRMcO40P4o2N/Td'
        'PCL+tH2j4OoP0QbtlpdW7ZLg9SMCgYEAq1fCElBKofLR02EF6JvtYCD5iVKWqtXJ'
        'gyvttTERW4fWhfUoTIjGCJFhPK36P1gO7slTkbpJO7CFmDpFyF8pxv2+ZiInPcVH'
        '4zpGapMjVQDRjOrRJRk/pFQ2kjBFU7McOWLE9TMfAQzuCerK39PiXIWgbuWpQ1ee'
        'HO8uaS8UTqsCgYEAgJV+2U3xxTzMEro4GhbogtCB5ppl/weDzhIwWDTYyWkTe2Hg'
        '7eJ93x21uBn31zvV4NS9bE/K1q/6BDbmbquc3UvlgYMu89PmJLakesV02wh5Sdbq'
        'He28y9vWp64Xqb7bXeFfn9jRCuTtyGnaV2DWYJYJRtf7nEfZtgPccx9196ECgYEA'
        'gmEz9xWLxPHtgkhI47iLB2PwHfNvXK1zOlIZ/o9I4vpZXfOv55UIBAsED9VfIAZU'
        'zpT592DmSvpGnhBxe0gWlSoOUM9aRuGwkxKL9Jrj/tGxouYnoXA2AkhmghUjG86m'
        'AnDK6L4usHDzTS6Rk4I6tCambtxpUSoB0YibK0S80iMCgYAk31wvq9OL0oR8uhto'
        'rpobw34wj3lynO680R2gbCI1c8svMucwgVBrsKWi+gTNNq3m9ds82Y8oNSd2ouPE'
        'Y4DHjtHk6CBcBtKxyCteNyiq7DtcOG/o0w1SQ1LR+iJu52+DhFFMZ/W2C6vHtkhd'
        '3J63N7YEEduoVUgi/jbY+PjFIA==';
    const String publicKeyB64 =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAo23TwipK1RYOmE1kJppd'
        'pAd2RSDAtpEGaUWHZ0W5MPfbLOCPBcmevKprsBOvhgJc/9jE7EOYF1jXeFtpbbHo'
        'iX7MiXyPqUt6bX//xA7vwKw5OgRgNWAxamtLvp8DUu6Un2ov3tAVrUWeJsmP+uM8'
        '+A8IJcV6lnjPnxSPbCd7K8NsWfUL7E/4W9FXFOX/6TzYQn/Jj6TnVcTwc5UnGxqg'
        'obMSC2P8tp0h1Q3CNXV6pvUYiCN4zeFzhGkne+EOKewix8jv6ohavkAiwdozJRmK'
        '6oyww5lB+kL+eyKO4DF7+xwVsLwmqOvxEthWJYNKm9CoTfh/oODO1KJ2GA9hOrBo'
        'YQIDAQAB';
    const String sha256SignatureB64 =
        'mwqQA8F5H6E3WcqUzCXnEP2qchwhT5RxC1vY1R78qKKE68Ow4T064j7cmVq9UVqh'
        'JBTZQuq+4h3MkSVdbAbHYoGdw+ApPXRkFIf7MQKOfmfJi/eHfkg6Vz4/ILrNWsec'
        'gNGsED+YrLqtmnrqsH9X/GuL49qh3P1z+hmQOM4nuNUYHUzJD/5eJX72tF3K1AiX'
        'C1/ndYsDjww3boBd+24YkCKwoIJam1PJru78D0dMlb/dWUY7x5lTISUF2YuzCHv8'
        'etDtyj0zN9kDk6ZeB536GN+99mEplocSyzaJ4aUfo2KYyKYbRzeth3H6RbwJGFf0'
        'oBz62HH6Sf+WTl1ekqZILg==';
    const String sha512SignatureB64 =
        'Mn3a49qeM10gWYynWxa7s4zri6A2i8KrmULM71cGyNriapAzCOKNm3psLJn3OaZa'
        '1i7nqxPwPMQ3wrml0P+Pd+Kp/0vc5gRxkHTesnusg8ABRm7e8SULgvGjORlfUcpm'
        'NfwezpUezKklv+jp5uTha28rTUftDYboA0z7Vmsvrrdre8KrGKOopXkekOHGj3/i'
        'n6KZQFouAZNMzmJOKIIkOvheaCR7k2/A6l7G11rdXonFVTFQqz3Xt6hykdP9wWkM'
        'bSF1kIKV/mtYCkf9XVH6dDvcAwynyePHBjAhK7aEeq/8F94gkMeryHx4ImcB7zSH'
        'mqWDMekGOb8nGAUtsI1JSg==';

    test('rsa2048 + sha256 reproduces the pinned signature', () async {
      final sig = await RsaSignatureAlgo.rsa2048()
          .signBytes(message, secretKey: base64Decode(secretKeyB64));
      expect(base64Encode(sig), equals(sha256SignatureB64));
    });

    test('rsa2048 + sha512 reproduces the pinned signature', () async {
      final sig =
          await RsaSignatureAlgo.rsa2048(hashing: HashingAlgoType.sha512)
              .signBytes(message, secretKey: base64Decode(secretKeyB64));
      expect(base64Encode(sig), equals(sha512SignatureB64));
    });

    test('the pinned signature verifies against the pinned public key',
        () async {
      expect(
          await RsaSignatureAlgo.rsa2048().verifyBytes(message,
              signature: base64Decode(sha256SignatureB64),
              publicKey: base64Decode(publicKeyB64)),
          isTrue);
    });
  });
}
