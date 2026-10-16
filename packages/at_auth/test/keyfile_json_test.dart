import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:test/test.dart';

import 'test_utils/holds_none_of.dart';

void main() {
  final random = Random.secure();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('keyfile_json');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String randomBase64(int bytes) =>
      base64Encode(List.generate(bytes, (_) => random.nextInt(256)));

  /// The text of a keyfile written by the reader's own writer, cut short
  /// partway through its selfEncryptionKey.
  Future<String> cutShortKeyfile() async {
    final selfEncryptionKey = randomBase64(32);
    final path = '${dir.path}/written.atKeys';
    await FileAtKeysIo(filePath: (_) => path).write(
        '@alice',
        AtKeys.legacy(
          apkamPublicKey: randomBase64(64),
          apkamPrivateKey: randomBase64(64),
          apkamSymmetricKey: randomBase64(32),
          encryptionPublicKey: randomBase64(64),
          encryptionPrivateKey: randomBase64(64),
          selfEncryptionKey: selfEncryptionKey,
        ));
    final text = await File(path).readAsString();
    await File(path).delete();
    return text.substring(0, text.indexOf(selfEncryptionKey) + 20);
  }

  Future<String> errorReading(String text, {String? passPhrase}) async {
    final path = '${dir.path}/@alice_key.atKeys';
    await File(path).writeAsString(text);
    try {
      await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase)
          .read('@alice');
    } catch (e) {
      return '$e';
    }
    fail('the read succeeded');
  }

  group('Given an atKeys file that isn\'t complete JSON', () {
    test(
        'when at_auth reads it, then the error says the file isn\'t valid '
        'JSON, with the position where it stops, and holds none of the '
        'file\'s text', () async {
      final text = await cutShortKeyfile();

      final error = await errorReading(text);

      expect(error, holdsNoneOf(text),
          reason: 'the error holds none of the file\'s text');
      expect(error, contains('is not valid JSON'));
      expect(error, contains('(at character ${text.length + 1})'));
    });
  });

  group(
      'Given a passphrase-protected atKeys file whose decrypted content '
      'isn\'t valid JSON', () {
    test(
        'when at_auth reads it with the right passphrase, then the error '
        'says so, with the position, and holds none of the decrypted text',
        () async {
      final plaintext = await cutShortKeyfile();
      final passPhrase = randomBase64(12);
      final envelope = await const AtKeysPassphraseEnvelopeCodec()
          .encode(plaintext, passPhrase);

      final error = await errorReading(envelope, passPhrase: passPhrase);

      expect(error, holdsNoneOf(plaintext),
          reason: 'the error holds none of the decrypted text');
      expect(error, contains('is not valid JSON'));
      expect(error, contains('(at character ${plaintext.length + 1})'));
    });
  });
}
