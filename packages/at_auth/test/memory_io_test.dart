import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryAtKeysIo', () {
    late InMemoryAtKeysIo io;

    setUp(() => io = InMemoryAtKeysIo());

    AtSymmetricKey symmetric(String id) => AtSymmetricKey(
          id: id,
          algorithm: 'AES-256',
          bytes: AtBytes.fromString('c2VjcmV0'),
        );

    test('read throws when nothing is loaded for the atSign', () {
      expect(
        () => io.read('@alice'),
        throwsA(isA<AtKeysNotInMemoryException>()),
      );
    });

    test('write then read returns the same keys', () async {
      final keys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetric('a')]);
      await io.write('@alice', keys);

      expect(await io.read('@alice'), same(keys));
    });

    test('write replaces any existing keys for the atSign', () async {
      await io.write('@alice',
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetric('first')]));
      final replacement =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetric('second')]);
      await io.write('@alice', replacement);

      expect(await io.read('@alice'), same(replacement));
    });

    test('append creates a key set when none exists', () async {
      await io.append('@alice'.toAtsign(), symmetric('appended'));

      final keys = await io.read('@alice');
      expect(keys.getKey<AtSymmetricKey>('appended'), isNotNull);
      expect(keys.atsign, '@alice'.toAtsign());
    });

    test('append adds to an existing key set', () async {
      await io.write(
          '@alice',
          AtKeys(
              atsign: '@alice'.toAtsign(), keysList: [symmetric('existing')]));
      await io.append('@alice'.toAtsign(), symmetric('appended'));

      final keys = await io.read('@alice');
      expect(keys.getKey<AtSymmetricKey>('existing'), isNotNull);
      expect(keys.getKey<AtSymmetricKey>('appended'), isNotNull);
    });

    test('append and read agree on the normalized atSign', () async {
      // append stores under the Atsign; read normalizes its String arg. A
      // differently-cased read must still resolve to the same slot.
      await io.append('@Alice'.toAtsign(), symmetric('appended'));

      final keys = await io.read('@alice');
      expect(keys.getKey<AtSymmetricKey>('appended'), isNotNull);
    });
  });
}
