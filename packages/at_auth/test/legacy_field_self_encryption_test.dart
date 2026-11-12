/// Pins the self-encryption of a `.atKeys` document's legacy flat fields.
///
/// This is an at-rest format: every `.atKeys` file in the world holds these
/// four fields encrypted exactly this way, so the bytes are the contract and
/// not an implementation detail. AES-256-CTR under the document's own
/// `selfEncryptionKey`, PKCS#7-padded to 16 bytes, with an all-zero 16-byte
/// initialisation vector, base64-encoded.
///
/// The ciphertexts below were captured with openssl rather than with the code
/// they check, so they are evidence about the format and not a restatement of
/// what this package happens to do:
///
/// ```
///   printf '%s' 'YXQtcmVzdCE=' | <pad PKCS#7 to 16> |
///     openssl enc -aes-256-ctr \
///       -K 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f \
///       -iv 00000000000000000000000000000000 | base64
/// ```
///
/// The zero IV is what makes the transform deterministic, and therefore
/// pinnable at all. An intended change to the format edits these literals in
/// the same commit, and that edit is the review.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// Bytes 0 to 31, so nothing here resembles a real key.
const selfEncryptionKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

/// A plaintext of 12 bytes, so PKCS#7 pads it with 4. Every flat field holds
/// base64, which is why the plaintexts here are base64 too.
const shortPlaintext = 'YXQtcmVzdCE=';
const shortCiphertext = 'q8hRwkkkyarNsN9X2SpzhA==';

/// A plaintext that is exactly two blocks, so PKCS#7 adds a whole third one —
/// the case an implementation that pads only when it has to gets wrong.
const alignedPlaintext = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A';
const alignedCiphertext =
    'v9lJ9GMj3p7rlPEbtUUex8kqRuwL6Nqj57fUcgmTDnwerKXOpTyTrRi4uSUIPIGJ';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('legacy_field_self_enc');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> writtenDocument(AtKeys keys) async {
    final path = '${dir.path}/@alice_key.atKeys';
    await FileAtKeysIo(filePath: (_) => path).write('@alice', keys);
    return jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  }

  AtKeys pinnedKeys() => AtKeys()
    ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey)
    ..apkamPublicKey = AtBytes.fromString(shortPlaintext)
    ..apkamPrivateKey = AtBytes.fromString(alignedPlaintext);

  group('the at-rest self-encryption of the legacy fields', () {
    test('emits the ciphertext openssl produces for the same input', () async {
      final document = await writtenDocument(pinnedKeys());

      expect(document[auth_constants.apkamPublicKey], shortCiphertext);
      expect(document[auth_constants.apkamPrivateKey], alignedCiphertext);
    });

    test('leaves the self-encryption key itself in the clear', () async {
      // It is the key the other four are encrypted under, so a reader that
      // could not see it could not decrypt anything.
      final document = await writtenDocument(pinnedKeys());

      expect(document[auth_constants.defaultSelfEncryptionKey],
          selfEncryptionKey);
    });

    test('reads back what openssl says those ciphertexts mean', () async {
      final path = '${dir.path}/@alice_key.atKeys';
      await File(path).writeAsString(jsonEncode({
        auth_constants.defaultSelfEncryptionKey: selfEncryptionKey,
        auth_constants.apkamPublicKey: shortCiphertext,
        auth_constants.apkamPrivateKey: alignedCiphertext,
      }));

      final keys = await FileAtKeysIo(filePath: (_) => path).read('@alice');

      expect(keys.apkamPublicKey.toString(), shortPlaintext);
      expect(keys.apkamPrivateKey.toString(), alignedPlaintext);
    });

    test('refuses a document whose fields it cannot decrypt', () async {
      // The key is required, not optional: silently leaving the ciphertext in
      // place would hand a caller an unusable key that looks like a key.
      final path = '${dir.path}/@alice_key.atKeys';
      await File(path).writeAsString(jsonEncode({
        auth_constants.apkamPublicKey: shortCiphertext,
      }));

      await expectLater(() => FileAtKeysIo(filePath: (_) => path).read('@alice'),
          throwsA(isA<AtException>()));
    });
  });

  group('a keyfile written by an older build', () {
    // The committed fixture is the only at-rest evidence in the tree that was
    // not produced by the code under test. Re-encrypting what it decrypts to
    // has to reproduce its bytes exactly, or every `.atKeys` file already on
    // disk is one this build cannot round-trip.
    final fixture = File('test/data/@alice🛠_key.atKeys');

    test('round-trips to byte-identical ciphertext', () async {
      final original =
          jsonDecode(await fixture.readAsString()) as Map<String, dynamic>;
      final keys = await FileAtKeysIo(filePath: (_) => fixture.path)
          .read('@alice🛠');

      final rewritten = await writtenDocument(keys);

      for (final field in [
        auth_constants.apkamPublicKey,
        auth_constants.apkamPrivateKey,
        auth_constants.defaultEncryptionPublicKey,
        auth_constants.defaultEncryptionPrivateKey,
      ]) {
        expect(rewritten[field], original[field],
            reason: '$field was re-encrypted to different bytes');
      }
    });

    test('decrypts to the key material openssl finds in it', () async {
      // Not the fixture's own values restated: the prefix below is what
      // `openssl enc -d -aes-256-ctr` returns for its aesEncryptPublicKey
      // under the key the document carries in the clear. A DER-encoded RSA
      // 2048-bit public key starts exactly this way.
      final keys = await FileAtKeysIo(filePath: (_) => fixture.path)
          .read('@alice🛠');

      expect(keys.defaultEncryptionPublicKey.toString(),
          startsWith('MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA'));
      expect(keys.defaultEncryptionPublicKey.toString(), hasLength(392));
    });
  });
}
