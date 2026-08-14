import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  group('legacy AtKeys survival', () {
    test('bare legacy json has no version field', () {
      final legacyKeys = legacyAtKeys();
      final json = legacyKeys.toJson();

      expect(json.containsKey('version'), isFalse);
      expectLegacyAtKeys(AtKeys.fromJson(json), legacyKeys);
    });

    test('typed-keys document preserves legacy payload', () {
      final legacyKeys = legacyAtKeys(atsign: '@alice'.toAtsign());
      final encoded = legacyKeys.toJson();
      final decoded = AtKeys.fromJson(encoded);

      // Legacy fields merge flatly into the top level alongside version/atSign/keys.
      expect(encoded['enrollmentId'], legacyKeys.enrollmentId);
      expectLegacyAtKeys(decoded, legacyKeys);
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
        final legacyKeys = legacyAtKeys();

        await fileAtKeysIo.write('@alice', legacyKeys);
        final readKeys = await fileAtKeysIo.read('@alice');

        expectLegacyAtKeys(readKeys, legacyKeys);
      });

      test(
          'FileAtKeysIo flush() upgrades legacy AtKeys'
          '${passPhrase == null ? '' : ' with passphrase'}', () async {
        final tempDir = await Directory.systemTemp.createTemp('at_keys_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final path = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(
          filePath: (_) => path,
          passPhrase: passPhrase,
        );
        final legacyKeys = legacyAtKeys();

        await fileAtKeysIo.write('@alice', legacyKeys);

        final keys = await fileAtKeysIo.read('@alice');
        keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
        await fileAtKeysIo.flush('@alice'.toAtsign(), keys);

        final files = tempDir.listSync().whereType<File>().toList();
        expect(
          files.map((file) => file.path).toSet(),
          {path, '$path.bak'},
        );

        final readKeys = await fileAtKeysIo.read('@alice');
        expectLegacyAtKeys(readKeys, legacyKeys);
        expect(readKeys.atSignKeysForKeyId('appended'), isNotEmpty);
      });
    }
  });
}
