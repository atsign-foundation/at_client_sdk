import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  final alice = '@alice'.toAtsign();

  group('InMemoryAtKeysIo', () {
    late EphemeralAtKeysIo io;

    setUp(() => io = EphemeralAtKeysIo());

    test('read throws when nothing is loaded for the atsign', () {
      expect(
        () => io.read(alice),
        throwsA(isA<AtKeysNotInMemoryException>()),
      );
    });

    test('write then read returns the same keys', () async {
      final keys = AtKeys(atsign: alice, keysList: [symmetricKey('a')]);
      await io.write(alice, keys);

      expect(await io.read(alice), same(keys));
    });

    test('write replaces any existing keys for the atsign', () async {
      await io.write(
          alice, AtKeys(atsign: alice, keysList: [symmetricKey('first')]));
      final replacement =
          AtKeys(atsign: alice, keysList: [symmetricKey('second')]);
      await io.write(alice, replacement);

      expect(await io.read(alice), same(replacement));
    });

    test('append throws when nothing is loaded for the atsign', () {
      expect(
        () => io.append(alice, symmetricKey('a')),
        throwsA(isA<AtKeysNotInMemoryException>()),
      );
    });

    test('append adds to an existing key set', () async {
      await io.write(
          alice, AtKeys(atsign: alice, keysList: [symmetricKey('existing')]));

      final appended = symmetricKey('appended');
      expect(await io.append(alice, appended), same(appended));

      final reread = await io.read(alice);
      expect(reread.keysForKeyId('existing'), isNotEmpty);
      expect(reread.keysForKeyId('appended'), isNotEmpty);
    });

    test('retire retires the key in place rather than dropping it', () async {
      final key = symmetricKey('rotating');
      await io.write(alice, AtKeys(atsign: alice, keysList: [key]));

      final retired = await io.retire(alice, key);
      expect(retired.status, KeyPartStatus.retired);

      // Retired, not removed — the material is still readable.
      final reread = await io.read(alice);
      expect(reread.getKey('rotating', key.keyPartType)?.status,
          KeyPartStatus.retired);
    });

    test('dispose drops every atsign', () async {
      await io.write(alice, AtKeys(atsign: alice, keysList: []));
      await io.dispose();

      expect(
        () => io.read(alice),
        throwsA(isA<AtKeysNotInMemoryException>()),
      );
    });

    test('a non-canonical spelling resolves to the same slot', () async {
      // Normalization happens once, at the toAtsign() boundary: '@Alice' and
      // '@alice' are the same Atsign, so they address the same entry.
      await io.write('@Alice'.toAtsign(),
          AtKeys(atsign: alice, keysList: [symmetricKey('stored')]));

      final keys = await io.read(alice);
      expect(keys.keysForKeyId('stored'), isNotEmpty);
    });
  });
}
