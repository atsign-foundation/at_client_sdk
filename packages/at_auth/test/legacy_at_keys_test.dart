import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/serialization/resolver.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  const codec = AtKeysJsonCodec();
  const resolver = AtKeysDocumentResolver();

  group('legacy AtKeys survival', () {
    test('bare legacy json resolves back to legacy AtKeys', () {
      final legacyKeys = createLegacyAtKeys();
      final document = codec.decodeDocument(legacyKeys.toJson());

      expect(document, isA<LegacyAtKeysDocument>());
      expectLegacyAtKeys(resolver.resolve(document), legacyKeys);
    });

    test('v1 document preserves legacy payload', () {
      final legacyKeys = createLegacyAtKeys(atsign: '@alice'.toAtsign());
      final document = resolver.resolveToDocument(legacyKeys);
      final encoded = codec.encodeDocument(document);
      final decoded = codec.decodeDocument(encoded);

      expect(decoded.legacyJson, isNotNull);
      expectLegacyAtKeys(resolver.resolve(decoded), legacyKeys);
    });

    for (final passPhrase in [null, 'passphrase']) {
      test(
          'FileAtKeysIo round-trips legacy AtKeys'
          '${passPhrase == null ? '' : ' with passphrase'}', () async {
        final tempDir = await Directory.systemTemp.createTemp('at_keys_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final fileAtKeysIo = FileAtKeysIo(
          filePath: (_) => '${tempDir.path}/@alice_key.atKeys',
          passPhrase: passPhrase,
        );
        final legacyKeys = createLegacyAtKeys();

        await fileAtKeysIo.write('@alice', legacyKeys);
        final readKeys = await fileAtKeysIo.read('@alice');

        expectLegacyAtKeys(readKeys, legacyKeys);
      });
    }
  });
}

AtKeys createLegacyAtKeys({Atsign? atsign}) {
  return AtKeys(atsign: atsign)
    ..apkamPublicKey =
        AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
    ..apkamPrivateKey =
        AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
    ..defaultEncryptionPublicKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultEncryptionPublicKey')))
    ..defaultEncryptionPrivateKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
    ..defaultSelfEncryptionKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultSelfEncryptionKey')))
    ..apkamSymmetricKey =
        AtBytes.fromString(base64Encode(utf8.encode('apkamSymmetricKey')))
    ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
}

void expectLegacyAtKeys(AtKeys actual, AtKeys expected) {
  expect(
      actual.apkamPrivateKey.toString(), expected.apkamPrivateKey.toString());
  expect(actual.apkamPublicKey.toString(), expected.apkamPublicKey.toString());
  expect(
    actual.apkamSymmetricKey.toString(),
    expected.apkamSymmetricKey.toString(),
  );
  expect(
    actual.defaultEncryptionPrivateKey.toString(),
    expected.defaultEncryptionPrivateKey.toString(),
  );
  expect(
    actual.defaultEncryptionPublicKey.toString(),
    expected.defaultEncryptionPublicKey.toString(),
  );
  expect(
    actual.defaultSelfEncryptionKey.toString(),
    expected.defaultSelfEncryptionKey.toString(),
  );
  expect(actual.enrollmentId, expected.enrollmentId);
}
