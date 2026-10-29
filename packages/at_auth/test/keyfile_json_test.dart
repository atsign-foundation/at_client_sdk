import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/holds_none_of.dart';

/// Reading an atKeys file that is not a JSON object.
///
/// Catalogue: features/at_auth/keyfile_not_json.feature
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

  Future<Object> errorReading(String text, {String? passPhrase}) async {
    final path = '${dir.path}/@alice_key.atKeys';
    await File(path).writeAsString(text);
    try {
      await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase)
          .read('@alice');
    } catch (e) {
      return e;
    }
    fail('the read succeeded');
  }

  /// What the JSON parser itself reports for [text].
  FormatException parserErrorOf(String text) {
    try {
      jsonDecode(text);
    } on FormatException catch (e) {
      return e;
    }
    fail('the text parsed');
  }

  test('A keyfile cut short names the parser\'s reason and the character',
      () async {
    final text = await cutShortKeyfile();
    final parserError = parserErrorOf(text);

    final error = await errorReading(text);

    expect(
        error,
        isA<AtKeysFormatException>()
            .having((e) => e.reason, 'reason', parserError.message)
            .having((e) => e.position, 'position', text.length + 1)
            .having((e) => e.offset, 'offset', text.length)
            .having((e) => e.source, 'source', isNull));
    expect(error, isA<FormatException>(),
        reason: 'a catch written for a FormatException still catches it');
    final format = error as AtKeysFormatException;
    for (final held in ['$error', format.message, format.reason]) {
      expect(held, holdsNoneOf(text),
          reason: 'the error holds none of the file\'s text');
    }
    expect('$error', contains('is not valid JSON'));
    expect('$error', contains('(at character ${text.length + 1})'));
  });

  test('A keyfile that is valid JSON but not an object says so', () async {
    final text = jsonEncode([randomBase64(32)]);

    final error = await errorReading(text);

    expect(
        error,
        isA<AtKeysFormatException>()
            .having((e) => e.reason, 'reason', 'not a JSON object')
            .having((e) => e.position, 'position', isNull)
            .having((e) => e.source, 'source', isNull));
    expect('$error', contains('is not a JSON object'));
    expect('$error', holdsNoneOf(text),
        reason: 'the error holds none of the file\'s text');
  });

  test('A decrypted keyfile that does not parse is a decryption failure',
      () async {
    final plaintext = await cutShortKeyfile();
    final passPhrase = randomBase64(12);
    final envelope = await const AtKeysPassphraseEnvelopeCodec()
        .encode(plaintext, passPhrase);

    final error = await errorReading(envelope, passPhrase: passPhrase);

    expect('$error', holdsNoneOf(plaintext),
        reason: 'the error holds none of the decrypted text');
    expect(error, isA<AtDecryptionException>(),
        reason: 'an incorrect passphrase usually leaves text that does not '
            'parse, so this stays a decryption failure');
    expect('$error', contains('is not valid JSON'));
    expect('$error', contains('(at character ${plaintext.length + 1})'));
  });
}
