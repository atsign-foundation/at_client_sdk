import 'dart:async';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// The update contract every [WrittenAtKeysIo] keeps: a change that returns
/// false or throws leaves the store as it was, whatever it did to the keys it
/// was handed, and one that returns true is stored.
void main() {
  final alice = '@alice'.toAtsign();

  group('Given a FileAtKeysIo holding keys for @alice', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('at_keys_update_contract');
    });
    tearDown(() => dir.delete(recursive: true));

    _updateContract(() async {
      final io = FileAtKeysIo(filePath: (_) => '${dir.path}/keys.atKeys');
      await io.write('@alice', legacyAtKeys(atsign: alice));
      return io;
    });
  });

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
        'when an update starts while the second of two queued updates is '
        'running, then it waits for the second to end', () async {
      final io = holding();
      final secondRunning = Completer<void>();
      final release = Completer<void>();
      var thirdRan = false;

      final first = io.update(alice, (keys) {
        keys.addKey(symmetricKey('first'));
        return true;
      });
      final second = io.update(alice, (keys) async {
        secondRunning.complete();
        await release.future;
        keys.addKey(symmetricKey('second'));
        return true;
      });
      await secondRunning.future;
      final third = io.update(alice, (keys) {
        thirdRan = true;
        keys.addKey(symmetricKey('third'));
        return true;
      });
      await pumpEventQueue();

      expect(thirdRan, isFalse,
          reason: 'the third update waits for the second, which is running');
      release.complete();
      await Future.wait([first, second, third]);
      final read = await io.read('@alice');
      for (final keyId in ['first', 'second', 'third']) {
        expect(read.atSignKeysForKeyId(keyId), isNotEmpty, reason: keyId);
      }
    });

    test(
        'when a change on @alice calls update on @bob, whose change calls '
        'update on @alice, then that innermost update throws StateError',
        () async {
      final io = holding();
      final bob = '@bob'.toAtsign();
      await io.write('@bob', legacyAtKeys(atsign: bob));
      var innermostRan = false;

      await io.update(alice, (_) async {
        await io.update(bob, (_) async {
          await expectLater(
              io.update(alice, (_) {
                innermostRan = true;
                return true;
              }),
              throwsA(isA<StateError>()));
          return false;
        });
        return false;
      });

      expect(innermostRan, isFalse);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(
        'when a change schedules an update on the same Atsign that starts after '
        'its own update has ended, then that update runs', () async {
      final io = holding();
      var outerEnded = false;
      final later = Completer<void>();

      await io.update(alice, (_) {
        Timer(const Duration(milliseconds: 1), () {
          later.complete(Future.sync(() {
            expect(outerEnded, isTrue,
                reason: 'control: the update that scheduled this has ended');
            return io.update(alice, (keys) {
              keys.addKey(symmetricKey('later'));
              return true;
            });
          }));
        });
        return false;
      });
      outerEnded = true;
      await later.future;

      expect((await io.read('@alice')).atSignKeysForKeyId('later'), isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(
        'when an update edits a nested metadata value and returns false, then '
        'a read holds the value as it was', () async {
      final io = holding(legacyAtKeys(atsign: alice)
        ..metadata['extra'] = <String, dynamic>{'n': 1});

      await io.update(alice, (keys) {
        (keys.metadata['extra'] as Map)['n'] = 2;
        return false;
      });

      expect((await io.read('@alice')).metadata['extra'], {'n': 1});
    });

    test(
        'when an update adds a key and returns true, then a read holds '
        'everything the store held besides', () async {
      AtKeys held() => legacyAtKeys(atsign: alice)
        ..addKey(symmetricKey('held'))
        ..recordEnrollmentSnapshot(_enrollment,
            namespaces: {'wavi': 'rw'}, appName: 'app', deviceName: 'device')
        ..addKey(symmetricKey('enrolled', enrollmentId: _enrollment))
        ..metadata['note'] = 'kept';
      final io = holding(held());

      await io.update(alice, (keys) {
        keys.addKey(symmetricKey('added'));
        return true;
      });

      final read = await io.read('@alice');
      expect(read, held()..addKey(symmetricKey('added')),
          reason: 'the stored keys keep their flat fields, materials and '
              'metadata');
      final snapshot = read.enrollmentInfo(_enrollment)!;
      expect(snapshot.namespaces, {'wavi': 'rw'});
      expect(snapshot.appName, 'app');
      expect(snapshot.deviceName, 'device');
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
        'when an update on typed keys that record no Atsign returns false, then '
        'the change is handed keys that record @alice and a read records no '
        'Atsign', () async {
      final io = holding(AtKeys()..addKey(symmetricKey('held')));
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
      final io = holding(AtKeys()..addKey(symmetricKey('held')));

      await expectLater(
          io.update(alice, (_) => throw _Refused()), throwsA(isA<_Refused>()));

      expect((await io.read('@alice')).atsign, isNull);
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

/// The enrollment `legacyAtKeys` records.
const _enrollment = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';

class _Refused implements Exception {}
