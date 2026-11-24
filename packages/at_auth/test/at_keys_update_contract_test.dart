import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// The update contract every [WrittenAtKeysIo] keeps: a change that returns
/// false or throws leaves the store as it was, whatever it did to the keys it
/// was handed, and one that returns true is stored.
void main() {
  final alice = '@alice'.toAtsign();

  group('Given an InMemoryAtKeysIo holding keys for @alice', () {
    InMemoryAtKeysIo holding([AtKeys? keys]) =>
        InMemoryAtKeysIo.holding('@alice', keys ?? legacyAtKeys(atsign: alice));

    _updateContract(() async => holding());

    test('when two updates each add a key at once, then a read holds both keys',
        () async {
      final io = holding();

      await Future.wait([
        io.update(alice, (keys) {
          keys.addKey(symmetricKey('first'));
          return true;
        }),
        io.update(alice, (keys) {
          keys.addKey(symmetricKey('second'));
          return true;
        }),
      ]);

      final read = await io.read('@alice');
      expect(read.atSignKeysForKeyId('first'), isNotEmpty);
      expect(read.atSignKeysForKeyId('second'), isNotEmpty,
          reason: 'the second update runs on what the first stored, so '
              'neither replaces the other\'s key');
    });

    test(
        'when an update throws, then the next update queued on the same Atsign '
        'still runs', () async {
      final io = holding();

      final first = io.update(alice, (_) => throw _Refused());
      final second = io.update(alice, (keys) {
        keys.addKey(symmetricKey('added'));
        return true;
      });

      await expectLater(first, throwsA(isA<_Refused>()));
      await second;
      expect((await io.read('@alice')).atSignKeysForKeyId('added'), isNotEmpty);
    });

    test(
        'when a change calls update on the same Atsign, then that inner update '
        'throws StateError', () async {
      final io = holding();
      var innerRan = false;

      await io.update(alice, (keys) async {
        await expectLater(
            io.update(alice, (_) {
              innerRan = true;
              return true;
            }),
            throwsA(isA<StateError>()));
        return false;
      });

      expect(innerRan, isFalse,
          reason: 'the inner change must not run inside the outer one');
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(
        'when updates for two Atsigns run at once, then neither waits for the '
        'other', () async {
      final io = holding();
      final bob = '@bob'.toAtsign();
      await io.write('@bob', legacyAtKeys(atsign: bob));
      final release = Completer<void>();
      final aliceWaiting = Completer<void>();
      var bobDone = false;

      final aliceUpdate = io.update(alice, (keys) async {
        aliceWaiting.complete();
        await release.future;
        keys.addKey(symmetricKey('alice-key'));
        return true;
      });
      await aliceWaiting.future;
      final bobUpdate = io.update(bob, (keys) {
        keys.addKey(symmetricKey('bob-key'));
        return true;
      }).then((_) => bobDone = true);
      await pumpEventQueue();

      expect(bobDone, isTrue,
          reason: "@bob's update ends while @alice's change is still waiting");
      release.complete();
      await Future.wait([aliceUpdate, bobUpdate]);
      expect((await io.read('@alice')).atSignKeysForKeyId('alice-key'),
          isNotEmpty);
      expect((await io.read('@bob')).atSignKeysForKeyId('bob-key'), isNotEmpty);
    });

    test(
        'when an update adds a key to keys that record no Atsign, then a read '
        'holds the key and records @alice', () async {
      final io = holding(AtKeys()..addKey(symmetricKey('held')));

      await io.update(alice, (keys) {
        keys.addKey(symmetricKey('added'));
        return true;
      });

      final read = await io.read('@alice');
      expect(read.atSignKeysForKeyId('added'), isNotEmpty);
      expect(read.atsign, alice);
    });

    test(
        'when an update runs on keys that record another Atsign, then they '
        'still record it', () async {
      final bob = '@bob'.toAtsign();
      final io = holding(AtKeys(atsign: bob)..addKey(symmetricKey('held')));

      await io.update(alice, (keys) {
        keys.addKey(symmetricKey('added'));
        return true;
      });

      final read = await io.read('@alice');
      expect(read.atSignKeysForKeyId('added'), isNotEmpty);
      expect(read.atsign, bob);
    });
  });
}

/// The four update contract tests, run against the store [holdingAlice]
/// returns, which holds @alice's keys and no key with the id `added`.
void _updateContract(Future<WrittenAtKeysIo> Function() holdingAlice) {
  final alice = '@alice'.toAtsign();

  bool holdsAdded(AtKeys keys) => keys.atSignKeysForKeyId('added').isNotEmpty;

  void addKey(AtKeys keys) {
    keys.addKey(symmetricKey('added'));
    expect(holdsAdded(keys), isTrue,
        reason: 'control: the change added the key to the keys it was handed');
  }

  test(
      'when an update adds a key and returns false, then a read does not hold '
      'the key', () async {
    final io = await holdingAlice();

    await io.update(alice, (keys) {
      addKey(keys);
      return false;
    });

    expect(holdsAdded(await io.read('@alice')), isFalse);
  });

  test(
      'when an update adds a key and then throws, then the throw reaches the '
      'caller and a read does not hold the key', () async {
    final io = await holdingAlice();

    await expectLater(
        io.update(alice, (keys) {
          addKey(keys);
          throw _Refused();
        }),
        throwsA(isA<_Refused>()));

    expect(holdsAdded(await io.read('@alice')), isFalse);
  });

  test(
      'when an update adds one key and a second add throws, then a read holds '
      'neither key', () async {
    final io = await holdingAlice();

    await expectLater(
        io.update(alice, (keys) {
          addKey(keys);
          keys.addKey(symmetricKey('added', value: 'b3RoZXI='));
          return true;
        }),
        throwsA(isA<ArgumentError>()),
        reason: 'the keys refuse a second key with the same id and role');

    expect(holdsAdded(await io.read('@alice')), isFalse);
  });

  test('when an update adds a key and returns true, then a read holds the key',
      () async {
    final io = await holdingAlice();

    await io.update(alice, (keys) {
      addKey(keys);
      return true;
    });

    final read = await io.read('@alice');
    expect(holdsAdded(read), isTrue);
    expect(read.atsign, alice);
  });
}

class _Refused implements Exception {}
