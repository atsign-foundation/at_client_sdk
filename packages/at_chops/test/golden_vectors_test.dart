/// Known-answer tests that pin at_chops' **wire formats**, independent of which
/// library backs each algorithm.
///
/// Every other crypto test in this package is a round-trip: encrypt-then-decrypt
/// with the same code on both sides. Those pass happily while the bytes on the
/// wire change underneath, which is exactly the failure mode that matters when a
/// backing library is swapped. Data already written by shipped clients — and
/// atKeys envelopes already derived from a passphrase — has to keep decrypting.
///
/// Where a published vector exists (NIST GCM, RFC 8032, RFC 7748, RFC 1321/6234)
/// it is used, so the fixture asserts *correctness* and not merely *continuity*.
/// The rest were captured from the implementations shipped in at_chops 3.x.
///
/// **If one of these fails, the wire format moved.** Re-baselining a value here
/// is not a fix — it is a decision to break every client holding older data.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// `The quick brown fox jumps over the lazy dog` — 43 bytes, deliberately not a
/// multiple of the 16-byte AES block, so PKCS#7 padding is exercised.
final Uint8List plainText = Uint8List.fromList(
    utf8.encode('The quick brown fox jumps over the lazy dog'));

/// Deterministic AES key of [length] bytes: `00 01 02 ... `.
Uint8List keyOfLength(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => i));

/// Deterministic 16-byte AES-CTR IV: `10 11 12 ... 1f`.
final InitialisationVector ctrIv = InitialisationVector(
    Uint8List.fromList(List<int>.generate(16, (i) => 0x10 + i)));

void main() {
  group('AES-CTR wire format (captured from at_chops 3.x)', () {
    // PKCS#7-padded AES-CTR is the format every encrypted value written by a
    // shipped at_client is in. These ciphertexts must stay byte-identical.
    const expected = {
      16: 'U5aKVJCgag37Loxj4eP8s/StvSSyee9yNVkSFO6L/nyiRBgLVJ+BiwH57Smk0Dh/',
      24: 'x8ZeX+63gXb2JcTbmpUhDZ3SPK3XcMUrFweErnEt2qLC0d+zN0KL79Z7TgnosJ0O',
      32: 'vauKqsNBOoWbVP6kWZDGrp+uM7qR4amRxdL/NThZEKdOfVx+Vr6WX4FzEfcpONYA',
    };

    for (final MapEntry(key: keyLength, value: ciphertext)
        in expected.entries) {
      test('AES-${keyLength * 8} encrypts to the pinned ciphertext', () async {
        final encrypted = await AesCtrEncryptionAlgo(keyLength)
            .encrypt(plainText, keyOfLength(keyLength), iv: ctrIv);
        expect(base64Encode(encrypted), ciphertext);
      });

      test('AES-${keyLength * 8} decrypts the pinned ciphertext', () async {
        final decrypted = await AesCtrEncryptionAlgo(keyLength).decrypt(
            base64Decode(ciphertext), keyOfLength(keyLength),
            iv: ctrIv);
        expect(decrypted, plainText);
      });
    }

    test('the all-zeroes legacy IV still produces its pinned ciphertext',
        () async {
      // Data written back when at_client wasn't setting IVs at all. There is no
      // second chance at reading it if this drifts.
      const ciphertext =
          'pvhllls89rPC0/gYslkZoJYyDo4gzPKV1db0Ry2wFklm2ZWy1Fb6nWzHzjAdKZSc';
      final algo = AesCtrEncryptionAlgo(32);
      expect(
          base64Encode(await algo.encrypt(plainText, keyOfLength(32),
              iv: InitialisationVector.legacy())),
          ciphertext);
      expect(
          await algo.decrypt(base64Decode(ciphertext), keyOfLength(32),
              iv: InitialisationVector.legacy()),
          plainText);
    });
  });

  group('AES-256-GCM (NIST GCM test case 16)', () {
    // McGrew & Viega, "The Galois/Counter Mode of Operation", test case 16 —
    // 256-bit key with associated data. at_chops appends the tag to the
    // ciphertext, so the expected value is `C || T` from the vector.
    final key = _hex(
        'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308');
    final iv = InitialisationVector(_hex('cafebabefacedbaddecaf888'));
    final plain = _hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303'
        'd8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39');
    final aad = _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
    final cipherTextAndTag = _hex('522dc1f099567d07f47f37a32a84427d643a8cdcbfe5'
        'c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abc'
        'c9f66276fc6ece0f4e1768cddf8853bb2d551b');

    test('encrypt matches the vector', () async {
      final encrypted =
          await AesGcm256EncryptionAlgo().encrypt(plain, key, iv: iv, aad: aad);
      expect(encrypted, cipherTextAndTag);
    });

    test('decrypt matches the vector', () async {
      final decrypted = await AesGcm256EncryptionAlgo()
          .decrypt(cipherTextAndTag, key, iv: iv, aad: aad);
      expect(decrypted, plain);
    });

    test('a tampered tag is rejected', () async {
      final tampered = Uint8List.fromList(cipherTextAndTag)..last ^= 0x01;
      expect(
          () => AesGcm256EncryptionAlgo()
              .decrypt(tampered, key, iv: iv, aad: aad),
          throwsA(isA<AtDecryptionException>()));
    });

    test('the wrong aad is rejected', () async {
      expect(
          () => AesGcm256EncryptionAlgo()
              .decrypt(cipherTextAndTag, key, iv: iv, aad: const [0x00]),
          throwsA(isA<AtDecryptionException>()));
    });
  });

  group('RSA wire format (captured from at_chops 3.x)', () {
    // A throwaway 2048-bit key pair, DER as at_chops emits it: X.509
    // SubjectPublicKeyInfo for the public key, PKCS#8 for the private key.
    final publicKey = base64Decode(_rsaPublicKeyBase64);
    final privateKey = base64Decode(_rsaPrivateKeyBase64);

    test('SHA-256 signatures are byte-identical (PKCS#1 v1.5 is deterministic)',
        () async {
      final signature =
          await RsaSigningAlgo().signBytes(plainText, secretKey: privateKey);
      expect(base64Encode(signature), _rsaSignatureSha256Base64);
    });

    test('SHA-512 signatures are byte-identical', () async {
      final signature =
          await RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha512)
              .signBytes(plainText, secretKey: privateKey);
      expect(base64Encode(signature), _rsaSignatureSha512Base64);
    });

    test('the pinned signatures still verify', () async {
      expect(
          await RsaSigningAlgo().verifyBytes(plainText,
              signature: base64Decode(_rsaSignatureSha256Base64),
              publicKey: publicKey),
          isTrue);
      expect(
          await RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha512)
              .verifyBytes(plainText,
                  signature: base64Decode(_rsaSignatureSha512Base64),
                  publicKey: publicKey),
          isTrue);
    });

    test('a ciphertext written by 3.x still decrypts', () {
      // PKCS#1 v1.5 encryption is randomised, so only the decrypt direction can
      // be pinned — which is the direction that matters for stored data.
      expect(
          RsaEncryptionAlgo()
              .decrypt(base64Decode(_rsaCipherTextBase64), privateKey),
          plainText);
    });

    test('freshly encrypted data decrypts with the pinned private key', () {
      final rsa = RsaEncryptionAlgo();
      expect(rsa.decrypt(rsa.encrypt(plainText, publicKey), privateKey),
          plainText);
    });

    test('generated 2048-bit keys carry the standard DER headers', () async {
      final keyPair = await RsaSigningAlgo().generateKeyPair();
      // Fixed for every 2048-bit RSA SPKI with e=65537: SEQUENCE(2 bytes len),
      // AlgorithmIdentifier(rsaEncryption, NULL), BIT STRING(2 bytes len, 0).
      expect(
          keyPair.publicKey.sublist(0, 24),
          _hex('30820122300d06092a864886f70d0101010500038201'
              '0f00'));
      // PKCS#8 PrivateKeyInfo: SEQUENCE, version 0, then the same
      // AlgorithmIdentifier, then the PKCS#1 key inside an OCTET STRING.
      expect(keyPair.secretKey.sublist(0, 2), _hex('3082'));
      expect(keyPair.secretKey.sublist(4, 7), _hex('020100'));
      expect(keyPair.secretKey.sublist(7, 22),
          _hex('300d06092a864886f70d0101010500'));
    });
  });

  group('Argon2id (captured from at_chops 3.x)', () {
    // at_auth derives the atKeys passphrase envelope key with these defaults.
    // Drift here makes every envelope already in the field undecryptable.
    const passphrase = 'correct horse battery staple';

    test('default parameters', () async {
      expect(await Argon2idHashingAlgo().hash(passphrase),
          '9XTo7JZhehnGb89UDi1oMIzUHDFcfVP3meBYdNh4sj0=');
    });

    test('explicit parameters', () async {
      final params = ArgonHashParams()
        ..parallelism = 1
        ..memory = 512
        ..iterations = 1
        ..hashLength = 16;
      expect(await Argon2idHashingAlgo().hash(passphrase, hashParams: params),
          'hnX84ePrC9aV4X36bnG8SQ==');
    });

    test('a non-ASCII passphrase keeps its exact byte encoding', () async {
      // The salt is `password.codeUnits` while the secret is UTF-8 encoded.
      // Those disagree above U+00FF, so this vector pins the asymmetry rather
      // than leaving a reimplementation free to "tidy" it.
      expect(await Argon2idHashingAlgo().hash('pässwörd✓'),
          'XGzc8qzgibytHFwJ+hcv+HnPMkAY8e4ZMezIQFiQyKg=');
    });
  });

  group('ECDSA secp256r1 (captured from at_chops 3.x)', () {
    final publicKey = base64Decode(
        'BPAlkbyPTokzzPHaOEo6Aiqkk6/boZW8OWLoeTM9hOTf6ahoykMeAW4xC2mZfNyJ3Fzd'
        'AgiQ9FRbngV7RJ08rTk=');
    final privateKey =
        base64Decode('q4DTIUgWngNtY0pKGgh59HtCnTyyRYKcj3oUQOzHJ9o=');
    const signature = 'uTN3n1UXBN9T3jLsprzVScwXW47SG4bgXRej92uWug8g7/gfzVd85K2Q'
        'pLAMMNgGM4okXqZBPsHwMw980E5MZA==';

    test('a signature written by 3.x still verifies', () async {
      expect(
          await EccSigningAlgo().verifyBytes(plainText,
              signature: base64Decode(signature), publicKey: publicKey),
          isTrue);
    });

    test('a freshly written signature verifies against the pinned public key',
        () async {
      // Signature bytes deliberately aren't pinned: the 3.x backend picks a
      // random nonce, so only the (key encoding, signature encoding, curve,
      // digest) tuple is a compatibility surface — and that is what verifying
      // across the two exercises.
      final fresh =
          await EccSigningAlgo().signBytes(plainText, secretKey: privateKey);
      expect(
          await EccSigningAlgo()
              .verifyBytes(plainText, signature: fresh, publicKey: publicKey),
          isTrue);
      expect(fresh, hasLength(64));
    });

    test('key and signature encodings keep their fixed widths', () {
      expect(publicKey, hasLength(65)); // uncompressed SEC1: 0x04 || X || Y
      expect(publicKey.first, 0x04);
      expect(privateKey, hasLength(32)); // big-endian scalar
      expect(base64Decode(signature), hasLength(64)); // compact R || S
    });
  });

  group('Ed25519 (RFC 8032 section 7.1, test 1)', () {
    final seed = _hex(
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60');
    final publicKey = _hex(
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
    final signature = _hex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d87'
        '3e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe2465514143'
        '8e7a100b');
    final message = Uint8List(0);

    test('signing the empty message matches the RFC', () async {
      expect(await Ed25519SigningAlgo().signBytes(message, secretKey: seed),
          signature);
    });

    test('verifying the RFC signature succeeds', () async {
      expect(
          await Ed25519SigningAlgo()
              .verifyBytes(message, signature: signature, publicKey: publicKey),
          isTrue);
    });

    test('a flipped signature bit is rejected', () async {
      final tampered = Uint8List.fromList(signature)..first ^= 0x01;
      expect(
          await Ed25519SigningAlgo()
              .verifyBytes(message, signature: tampered, publicKey: publicKey),
          isFalse);
    });
  });

  group('X25519 (RFC 7748 section 6.1)', () {
    final alicePrivateKey = _hex(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
    final bobPrivateKey = _hex(
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb');
    final alicePublicKey = _hex(
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
    final bobPublicKey = _hex(
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');
    final sharedSecret = _hex(
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');

    test('both sides derive the RFC shared secret', () async {
      expect(
          await X25519PureDartAlgo.instance.dh(alicePrivateKey, bobPublicKey),
          sharedSecret);
      expect(
          await X25519PureDartAlgo.instance.dh(bobPrivateKey, alicePublicKey),
          sharedSecret);
    });
  });

  group('hash digests (RFC 1321, RFC 6234)', () {
    final abc = Uint8List.fromList(utf8.encode('abc'));

    test('MD5', () {
      expect(Md5HashingAlgo().hash(abc), '900150983cd24fb0d6963f7d28e17f72');
    });

    test('SHA-256', () {
      expect(SHA256HashingAlgo().hash(abc),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('SHA-512', () {
      expect(
          SHA512HashingAlgo().hash(abc),
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
          '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
    });

    test('digests are lowercase hex, not base64 or uppercase', () {
      expect(SHA256HashingAlgo().hash(abc), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(Md5HashingAlgo().hash(abc), matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });
}

Uint8List _hex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

const _rsaPublicKeyBase64 =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvoZPXAPRPUQmb3gmD91srZ0VBy9l'
    '2Mnw53R8gNQbLXtAfE1Lz3LwraCXKZOQPtgudEXEQ7xbhpeDoiaZYl0aG8OquX6LQ1+EybLc'
    '+q9bjw4u6gNgGvt45C5butBpsyDAQCBaDkCcllJRuOueNEKwSlLtSDwVTa8Ny5JjKYKB4S8R'
    '/J/cG4ZhsdXnA4stee0UH60QNk6wHa3CoiTmC8V9adbvH1efJt13MY1f17YLP2JGe5E1HOld'
    '7JX4Amp3RcHxxVYU+acJTifGE4T5hGzzMwCsK2mjo0uao8WfXg3qoTJfaElLxHhNu9yhIgQe'
    'WtMPA5EMIy5Dw8sk/OpDdswXIQIDAQAB';

const _rsaPrivateKeyBase64 =
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC+hk9cA9E9RCZveCYP3Wyt'
    'nRUHL2XYyfDndHyA1Bste0B8TUvPcvCtoJcpk5A+2C50RcRDvFuGl4OiJpliXRobw6q5fotD'
    'X4TJstz6r1uPDi7qA2Aa+3jkLlu60GmzIMBAIFoOQJyWUlG46540QrBKUu1IPBVNrw3LkmMp'
    'goHhLxH8n9wbhmGx1ecDiy157RQfrRA2TrAdrcKiJOYLxX1p1u8fV58m3XcxjV/Xtgs/YkZ7'
    'kTUc6V3slfgCandFwfHFVhT5pwlOJ8YThPmEbPMzAKwraaOjS5qjxZ9eDeqhMl9oSUvEeE27'
    '3KEiBB5a0w8DkQwjLkPDyyT86kN2zBchAgMBAAECggEAcmYFCrQEFCxyg6X5/LawhcJ3GNxd'
    '5ADFVMS96UDynKmP+9MRvRs/5pExkrZW+1Uk943Yne9gaX1afad9m/FZNuiS/1Q7XJXjDpUG'
    'WMOoT0pt4vdp4mmymhg33gE8JmF47kg+qqYjH6OIDGf1k12jqs0GSsRA6mc8+koInqkNQV7P'
    'oOlaeKibdOV8J8E/2KU2TxyYKuOR3FNPWIocnUeYGdtC35qYWbtlUvBNNh9RvFgyERnqRs6M'
    'kl/iBYftkBhZYHDSyu9uRCtScF87Mf5KmzOII73UqKwCNtFawwnbKzVKTdLqG5vPFbQItFD0'
    'Ofia1HHoLb2nvJsKi73s+jxk0QKBgQDlLkIz8c+TXUKg7DzZChQfFoP4E4ZEvJX5ZM1BJaD6'
    'EhxtJ5IGDTqHnkIyg5GkU4MoYIdkdApt0qaA12ho2IqxJ8Z1eowpDlbyW8CJH1UF+NA5xfxA'
    'N8YG6YTb+8Z44/yuq1Uwr8xRSEy9g/lGzT606rOrhd4ORtmhVLbIMfVjhQKBgQDU0gCoU1Rg'
    'T8tJSKDholSHyt0t3iapF3SYsI1/AGkjPV9INmJ/z5kyWJ9dTEEHAx9yxgEfBwA2Gf9czF2W'
    'wBWJnZrym0QdBS8RqmuLIZoIqHNyAQv8ECJKQUWjfBAlT7s2qSEz5WItFxC6nE6+UYjK+YJ7'
    '+P9FLyvFQQHH6pCx7QKBgQCOA+tMSwTJGZpnI9zU1ZUAarBecqLaR05cG6XBP/MP41cwILww'
    '+dOSJHR63uLKRGHbDG35xpqL0WQSJOlzRvQysSYeuFDQRC2Gw2p8ziieqb9GfbRBiw4wTFZj'
    'BxLG6Og0yMDiiZ1/pODA813uDNNVwraRjEO87xR/D4KwbZzVDQKBgFy8vgibdzMY0k621VQ9'
    'NnSN09++5D3euLIojSAAf9AZWEHRYQ6s2eb0c01mgxeZJsUOv0JT/KWWoo4/h7C/NyNmiDSb'
    'sAytS5t5Fa/lDogjT1soVZ6bMTYGR2A8GZUIr13cSVmh5Swc1u9aWX3ZbbB1FYUMNcBiE8K6'
    '1xnUfwTpAoGAXDP+ZaHdF8FHwtrJmJ8sBjVTZzYO1MVCFOzRp6pYMkf6NTElknLAA02KNXec'
    'Xx1gISN+SPp5X+xYu8k7RATw+ncfGLhX7BdQovqa0Rc/S9LxkKqeKZlWPZ1Mgn1uSD5weWif'
    'bscTzxBY0kQ05874bct0ZiEy/dXw061MkFln7eY=';

const _rsaSignatureSha256Base64 =
    'j9suHv14nBR4UCzVUJjevhQ2YFcY4PRw/ZUDqGPIxVzI/uYGo2DE9XclsjCDQlbaOmED1Kn3'
    'GxW+oNU7/0t4TV6tWO7r0f7i14OvnfnUUztLSPltLQHZlewBuYvk/jm+LQQLznER/jAyGymC'
    'nVxQPRdhOEgidNHVk51s9lE/Rxib8F73VO553CP7B4RU4cBZ2DfIkVgyZDwu9CrA8vZSd4Gx'
    '0xsWSPUwL8297O7Zs6r8929nZgyMiMdWarQ0F8ne2ROGouciHLLDduKWuxdEZWcbGylrC7V7'
    'Y3fKsJSUH/y7Xq6QnsUO0iRBwIkX2hifHtd/ztrmf7PFyR+iJcbgwg==';

const _rsaSignatureSha512Base64 =
    'N57w5fcr0uyjskgFuHePZf88rlekXltrWTbddDnr5y159c3NFLDuDKNASP+yrnw3WoF7dgTF'
    'CZ/igoeIeelXHnlUTTL/Ckj3nmiAQm+h5BdRBSkLBoykiZoimydT996hbwHQnT1MMUk26ynY'
    '54eaXafmYtw6sof0DhCGrqMyo+SMbBCBzn6mckXZaEG7y1JMpxcNEwQ9nlWGEb4/LQFswIJr'
    'sA36+p/u8aA3oZLC6CFivMi64JFQpUPYQjNkpHR5jnJ1OgeXJsN6tfVY67X9ia5wqYd32pIP'
    '1rUQO7C5mghLyxTdYejQTsMkHYWyEPZdu52MV0t4LmapP5N0IZHYGg==';

const _rsaCipherTextBase64 =
    'SenBKrWr8aUog2ZRnF8/Nh96BXtSfCS0I5GAR6cA/W9/9RqzZdMJvbN4eyMR7RUbWX+uDu9X'
    'LHDSSBW180VnYOBjatOHAKE4526IRUWl1Xsn+BaqT+O71eToRdoCs5cB3H8Pet/LYchhFGqa'
    'UbSRsjCdlO/Ih5lUgDUYD7TwWc0FTXETs0AZy/l6VpMQZuDi4PnZrD0d8po5LHjcj556aIbK'
    'KCnvDPWyDiOrPIgawBt1AgGNxvJRFpSK1w23FRZKR5NvXlgadZPQQXdg7L7FjVJSXaEG2Scy'
    'GFsoq3rQ+zy7DS+Uz9VTh81itQy38AT9Wau6bGcoCYguvO13BVVLlw==';
