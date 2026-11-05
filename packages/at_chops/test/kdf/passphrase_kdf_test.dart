import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const argon = Argon2idParams(memoryKiB: 128, iterations: 1, parallelism: 1);

  group('Pbkdf2Sha256Kdf', () {
    // PBKDF2-HMAC-SHA256, P = "password", S = "salt", dkLen = 32.
    const vectors = {
      1: '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      2: 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      4096: 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    };
    for (final MapEntry(key: iterations, value: expected) in vectors.entries) {
      test('$iterations iterations', () async {
        final derived = await const Pbkdf2Sha256Kdf().derive(
            bytesOf('password'),
            bytesOf('salt'),
            Pbkdf2Sha256Params(iterations: iterations));
        expect(hexOf(derived), expected);
      });
    }
  });

  group('Argon2idKdf', () {
    final secret = bytesOf('secret');
    final salt = bytesOf('somesalt');
    const kdf = Argon2idKdf();

    test('is deterministic', () async {
      expect(await kdf.derive(secret, salt, argon),
          await kdf.derive(secret, salt, argon));
    });

    test('a different salt or params gives different bytes', () async {
      final base = await kdf.derive(secret, salt, argon);
      expect(
          await kdf.derive(secret, bytesOf('somesalt2'), argon), isNot(base));
      expect(
          await kdf.derive(
              secret,
              salt,
              const Argon2idParams(
                  memoryKiB: 128, iterations: 2, parallelism: 1)),
          isNot(base));
    });

    test('honours length', () async {
      expect(await kdf.derive(secret, salt, argon, length: 16), hasLength(16));
    });

    test('matches Argon2idHashingAlgo given the same salt', () async {
      final hash = await Argon2idHashingAlgo().hash('password',
          hashParams: ArgonHashParams()
            ..memory = 128
            ..iterations = 1
            ..parallelism = 1
            ..hashLength = 32
            ..salt = salt);
      expect(await kdf.derive(bytesOf('password'), salt, argon),
          base64Decode(hash));
    });
  });

  group('kdfFor', () {
    const pbkdf2 = Pbkdf2Sha256Params(iterations: 1000);

    test('picks the KDF the params belong to', () {
      expect(kdfFor(argon), isA<Argon2idKdf>());
      expect(kdfFor(pbkdf2), isA<Pbkdf2Sha256Kdf>());
    });

    test('a KDF given another KDF\'s params throws ArgumentError', () {
      final secret = Uint8List(16);
      final salt = Uint8List(16);
      expect(() => const Argon2idKdf().derive(secret, salt, pbkdf2),
          throwsArgumentError);
      expect(() => const Pbkdf2Sha256Kdf().derive(secret, salt, argon),
          throwsArgumentError);
    });
  });
}
