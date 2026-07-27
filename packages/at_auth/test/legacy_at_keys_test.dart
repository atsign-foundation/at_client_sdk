import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  group('legacy AtKeys survival', () {
    test('a legacy-only AtKeys upgrades to the typed shape on toJson', () {
      final legacyKeys = legacyAtKeys();
      final json = legacyKeys.toJson();

      // Upgrade, not a format swap: the typed envelope appears with empty
      // keys, and the flat legacy fields still round-trip.
      expect(json.containsKey('version'), isTrue);
      expect(json['keys'], isEmpty);
      expectLegacyAtKeys(AtKeys.fromJson(json), legacyKeys);
    });

    test('fromJson takes the atsign from the reader for a legacy blob', () {
      // A legacy .atKeys file is the flat shape with no version/atsign/keys.
      final legacyBlob = Map<String, dynamic>.from(legacyAtKeys().toJson())
        ..remove('version')
        ..remove('atsign')
        ..remove('keys');

      final keys = AtKeys.fromJson(legacyBlob, atsign: '@bob'.toAtsign());
      expect(keys.atsign, '@bob'.toAtsign());

      // No atsign in the file and none supplied — nothing to build the model.
      expect(
        () => AtKeys.fromJson(legacyBlob),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('fromJson rejects an atsign that disagrees with a typed keyfile', () {
      final typed = legacyAtKeys(atsign: '@alice'.toAtsign()).toJson();
      expect(
        () => AtKeys.fromJson(typed, atsign: '@bob'.toAtsign()),
        throwsA(isA<AtKeysValidationException>()),
      );
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
        expect(readKeys.keysForKeyId('appended'), isNotEmpty);
      });
    }
  });
}
