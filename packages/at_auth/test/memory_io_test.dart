import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  group('InMemoryAtKeysIo', () {
    late InMemoryAtKeysIo io;

    setUp(() => io = InMemoryAtKeysIo());

    test('read throws when nothing is loaded for the atsign', () {
      expect(
        () => io.read('@alice'),
        throwsA(isA<AtKeysNotInMemoryException>()),
      );
    });

    test('write then read returns the same keys', () async {
      final keys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('a')]);
      await io.write('@alice', keys);

      expect(await io.read('@alice'), same(keys));
    });

    test('write replaces any existing keys for the atsign', () async {
      await io.write(
          '@alice',
          AtKeys(
              atsign: '@alice'.toAtsign(), keysList: [symmetricKey('first')]));
      final replacement = AtKeys(
          atsign: '@alice'.toAtsign(), keysList: [symmetricKey('second')]);
      await io.write('@alice', replacement);

      expect(await io.read('@alice'), same(replacement));
    });

    test('flush creates a key set when none exists', () async {
      await io.flush(
          '@alice'.toAtsign(),
          AtKeys(
              atsign: '@alice'.toAtsign(),
              keysList: [symmetricKey('flushed')]));

      final keys = await io.read('@alice');
      expect(keys.keysForKeyId('flushed'), isNotEmpty);
      expect(keys.atsign, '@alice'.toAtsign());
    });

    test('read, addKey, flush adds to an existing key set', () async {
      await io.write(
          '@alice',
          AtKeys(
              atsign: '@alice'.toAtsign(),
              keysList: [symmetricKey('existing')]));

      final keys = await io.read('@alice');
      keys.addKey(symmetricKey('appended'));
      await io.flush('@alice'.toAtsign(), keys);

      final reread = await io.read('@alice');
      expect(reread.keysForKeyId('existing'), isNotEmpty);
      expect(reread.keysForKeyId('appended'), isNotEmpty);
    });

    test('flush and read agree on the normalized atsign', () async {
      // flush stores under the normalized Atsign; read normalizes its String
      // arg. A differently-cased read must still resolve to the same slot.
      await io.flush(
          '@Alice'.toAtsign(),
          AtKeys(
              atsign: '@Alice'.toAtsign(),
              keysList: [symmetricKey('flushed')]));

      final keys = await io.read('@alice');
      expect(keys.keysForKeyId('flushed'), isNotEmpty);
    });
  });
}
