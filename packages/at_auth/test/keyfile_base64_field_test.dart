import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';
import 'test_utils/holds_none_of.dart';

/// A keyfile document in which [field] does not decode as base64, every form
/// of that field's value the error must not hold, the offset of the first
/// character a decoder rejects, and the type the read must refuse it with.
typedef Corrupted = ({
  Map<String, dynamic> document,
  String field,
  List<String> values,
  int at,
  String? passPhrase,
  TypeMatcher<Exception> refusedAs,
});

const _selfEncryptedFields = [
  auth_constants.apkamPublicKey,
  auth_constants.apkamPrivateKey,
  auth_constants.defaultEncryptionPublicKey,
  auth_constants.defaultEncryptionPrivateKey,
];

void main() {
  final random = Random.secure();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('keyfile_base64_field');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String randomBase64(int bytes) =>
      base64Encode(List.generate(bytes, (_) => random.nextInt(256)));

  /// Base64 of 30 random bytes with one character replaced by `!`, which is
  /// then the first character a decoder rejects.
  ({String value, int at}) notBase64() {
    final valid = randomBase64(30);
    final at = 8 + random.nextInt(valid.length - 16);
    return (value: valid.replaceRange(at, at + 1, '!'), at: at);
  }

  /// The document [keys] is written as, by the reader's own writer.
  Future<Map<String, dynamic>> written(AtKeys keys,
      {String? passPhrase}) async {
    final path = '${dir.path}/written.atKeys';
    await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase)
        .write('@alice', keys);
    final document =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    await File(path).delete();
    return document;
  }

  AtKeys legacyKeys(String selfEncryptionKey) => AtKeys.legacy(
        apkamPublicKey: randomBase64(64),
        apkamPrivateKey: randomBase64(64),
        apkamSymmetricKey: randomBase64(32),
        encryptionPublicKey: randomBase64(64),
        encryptionPrivateKey: randomBase64(64),
        selfEncryptionKey: selfEncryptionKey,
      );

  /// [plaintext] encrypted the way the legacy fields are held at rest.
  Future<String> selfEncrypted(String plaintext, String key) async =>
      base64Encode(await AESEncryptionAlgo(AESKey(key)).encrypt(
          Uint8List.fromList(utf8.encode(plaintext)),
          iv: InitialisationVector.legacy()));

  Future<Corrupted> replacing(String field,
      {String? passPhrase,
      TypeMatcher<Exception> refusedAs =
          const TypeMatcher<FormatException>()}) async {
    final bad = notBase64();
    final Map<String, dynamic> document;
    if (passPhrase != null) {
      document = await written(
          AtKeys.legacy(selfEncryptionKey: randomBase64(32)),
          passPhrase: passPhrase);
    } else {
      document = await written(legacyKeys(randomBase64(32)));
    }
    return (
      document: {...document, field: bad.value},
      field: field,
      values: [bad.value],
      at: bad.at,
      passPhrase: passPhrase,
      refusedAs: refusedAs,
    );
  }

  final cases = <String, Future<Corrupted> Function()>{
    'a typed material\'s bytes': () async {
      final bad = notBase64();
      final document = await written(
          AtKeys(atsign: '@alice'.toAtsign())..addKey(symmetricKey('k1')));
      final material = ((document['atsignKeys'] as List).single
          as Map<String, dynamic>)['material'] as List;
      (material.single as Map<String, dynamic>)['bytes'] = bad.value;
      return (
        document: document,
        field: 'bytes',
        values: [bad.value],
        at: bad.at,
        passPhrase: null,
        refusedAs: isA<AtKeysValidationException>(),
      );
    },
    for (final field in _selfEncryptedFields)
      '$field, as stored': () => replacing(field),
    'selfEncryptionKey, beside the fields it encrypts': () =>
        replacing(auth_constants.defaultSelfEncryptionKey),
    'selfEncryptionKey, with nothing to decrypt': () async {
      final bad = notBase64();
      final document =
          await written(AtKeys.legacy(selfEncryptionKey: randomBase64(32)));
      return (
        document: {
          ...document,
          auth_constants.defaultSelfEncryptionKey: bad.value
        },
        field: auth_constants.defaultSelfEncryptionKey,
        values: [bad.value],
        at: bad.at,
        passPhrase: null,
        refusedAs: isA<FormatException>(),
      );
    },
    'apkamSymmetricKey': () => replacing(auth_constants.apkamSymmetricKey),
    for (final field in _selfEncryptedFields)
      '$field, once decrypted': () async {
        final bad = notBase64();
        final key = randomBase64(32);
        final document = await written(legacyKeys(key));
        final stored = await selfEncrypted(bad.value, key);
        return (
          document: {...document, field: stored},
          field: field,
          values: [bad.value, stored],
          at: bad.at,
          passPhrase: null,
          refusedAs: isA<FormatException>(),
        );
      },
    for (final field in ['iv', 'content'])
      'the passphrase envelope\'s $field': () => replacing(field,
          passPhrase: randomBase64(12),
          refusedAs: isA<AtDecryptionException>()),
    'the passphrase envelope\'s salt': () =>
        replacing('salt', passPhrase: randomBase64(12)),
  };

  Future<Object> errorReading(Corrupted corrupted) async {
    final path = '${dir.path}/@alice_key.atKeys';
    await File(path).writeAsString(jsonEncode(corrupted.document));
    try {
      await FileAtKeysIo(
              filePath: (_) => path, passPhrase: corrupted.passPhrase)
          .read('@alice');
    } catch (e) {
      return e;
    }
    fail('the read succeeded');
  }

  group(
      'Given an atKeys file in which a field that should hold base64 doesn\'t',
      () {
    for (final MapEntry(key: label, value: corrupt) in cases.entries) {
      group(label, () {
        test(
            'when at_auth reads it, then the error names the field and says '
            'it isn\'t valid base64, with the position of the first bad '
            'character, holds none of the field\'s value, and is of the type '
            'that field is refused with', () async {
          final corrupted = await corrupt();

          final error = await errorReading(corrupted);
          final message = '$error';

          expect(error, corrupted.refusedAs);
          for (final value in corrupted.values) {
            expect(message, holdsNoneOf(value),
                reason: 'the error holds none of the field\'s value');
          }
          expect(message, contains('${corrupted.field} is not valid base64'));
          expect(message, contains('(at offset ${corrupted.at})'));
        });
      });
    }
  });
}
