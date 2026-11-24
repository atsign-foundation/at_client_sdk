import 'package:at_auth/at_auth.dart'
    show
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole;
import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// The update contract every `WrittenAtKeysIo` keeps: a change that returns
/// false or throws leaves the store as it was, whatever it did to the keys it
/// was handed. A session store takes no flush, so a change that returns true
/// is refused and leaves it as it was too.
void main() {
  final alice = '@alice'.toAtsign();

  CryptographicMaterial key(String keyId, {String value = 'YWRkZWQ='}) =>
      CryptographicMaterial(
        keyId: keyId,
        role: CryptographicMaterialRole.symmetricEncryption,
        algorithm: CryptographicMaterialAlgorithm.aes256,
        bytes: AtBytes.fromString(value),
        createdAt: DateTime.utc(2026, 1, 1),
      );

  bool holdsAdded(AtKeys keys) => keys.atSignKeysForKeyId('added').isNotEmpty;

  group('Given a SessionKeysIo holding keys for @alice', () {
    late SessionKeysIo io;

    setUp(() => io = SessionKeysIo('@alice', classicalAtKeys(atsign: alice)));

    void addKey(AtKeys keys) {
      keys.addKey(key('added'));
      expect(holdsAdded(keys), isTrue,
          reason: 'control: the change added the key to the keys it was '
              'handed');
    }

    test(
        'when an update adds a key and returns false, then a read does not '
        'hold the key', () async {
      await io.update(alice, (keys) {
        addKey(keys);
        return false;
      });

      expect(holdsAdded(await io.read('@alice')), isFalse);
      expect(io.refusedFlushes, 0);
    });

    test(
        'when an update adds a key and then throws, then the throw reaches the '
        'caller and a read does not hold the key', () async {
      await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            throw _Refused();
          }),
          throwsA(isA<_Refused>()));

      expect(holdsAdded(await io.read('@alice')), isFalse);
    });

    test(
        'when an update adds one key and a second add throws, then a read '
        'holds neither key', () async {
      await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            keys.addKey(key('added', value: 'b3RoZXI='));
            return true;
          }),
          throwsA(isA<ArgumentError>()),
          reason: 'the keys refuse a second key with the same id and role');

      expect(holdsAdded(await io.read('@alice')), isFalse);
    });

    test(
        'when an update adds a key and returns true, then the flush throws '
        'StateError and a read does not hold the key', () async {
      await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            return true;
          }),
          throwsA(isA<StateError>()));

      expect(io.refusedFlushes, 1);
      expect(holdsAdded(await io.read('@alice')), isFalse);
    });

    test(
        'when an update edits a nested metadata value and returns false, then '
        'a read holds the value as it was', () async {
      io = SessionKeysIo('@alice',
          classicalAtKeys(atsign: alice)..metadata['extra'] = {'n': 1});

      await io.update(alice, (keys) {
        (keys.metadata['extra'] as Map)['n'] = 2;
        return false;
      });

      expect((await io.read('@alice')).metadata['extra'], {'n': 1});
    });

    test(
        'when an update on typed keys that record no Atsign returns false, then '
        'the change is handed keys that record @alice and a read records no '
        'Atsign', () async {
      io = SessionKeysIo('@alice', classicalAtKeys()..addKey(key('held')));
      Atsign? handed;

      await io.update(alice, (keys) {
        handed = keys.atsign;
        return false;
      });

      expect(handed, alice);
      expect((await io.read('@alice')).atsign, isNull);
    });

    test(
        'when an update on typed keys that record no Atsign throws, then a '
        'read records no Atsign', () async {
      io = SessionKeysIo('@alice', classicalAtKeys()..addKey(key('held')));

      await expectLater(
          io.update(alice, (_) => throw _Refused()), throwsA(isA<_Refused>()));

      expect((await io.read('@alice')).atsign, isNull);
    });

    test(
        'when an update runs on keys that record another Atsign, then they '
        'still record it', () async {
      final bob = '@bob'.toAtsign();
      io = SessionKeysIo('@alice', classicalAtKeys(atsign: bob));
      Atsign? handed;

      await io.update(alice, (keys) {
        handed = keys.atsign;
        keys.addKey(key('added'));
        return false;
      });

      expect(handed, bob);
      expect((await io.read('@alice')).atsign, bob);
    });
  });
}

class _Refused implements Exception {}
