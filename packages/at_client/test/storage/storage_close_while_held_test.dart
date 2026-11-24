import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/hive.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';
import '../test_utils/no_keys.dart';
import '../test_utils/transport.dart';

/// Holds [openBackend] until [proceed] completes, and completes [reached]
/// once an attach is inside it.
mixin _HeldOpen on AtClientStorageBase {
  final Completer<void> reached = Completer<void>();
  final Completer<void> proceed = Completer<void>();

  @override
  Future<void> openBackend() async {
    if (!reached.isCompleted) reached.complete();
    await proceed.future;
    await super.openBackend();
  }
}

class _HeldOpenMemory extends InMemoryAtClientStorage with _HeldOpen {
  _HeldOpenMemory({required super.atSign});
}

class _HeldOpenHive extends HiveAtClientStorage with _HeldOpen {
  _HeldOpenHive({required super.atSign, required super.storagePath});
}

class _HeldOpenSqlite extends SqliteAtClientStorage with _HeldOpen {
  _HeldOpenSqlite({required super.atSign, required super.storagePath})
      : super.under();
}

/// A client-closed storage that implements [AtClientStorage] without
/// extending [AtClientStorageBase], over a memory storage, recording the
/// attach, detach and close calls made on it.
class _InterfaceOnlyStorage implements AtClientStorage {
  _InterfaceOnlyStorage(String atSign)
      : inner = InMemoryAtClientStorage(atSign: atSign);

  final InMemoryAtClientStorage inner;
  final List<String> calls = [];

  @override
  bool get closedByClient => true;

  @override
  Future<void> attach(AtClient owner) {
    calls.add('attach');
    return inner.attach(owner);
  }

  @override
  Future<void> detach(AtClient owner) {
    calls.add('detach');
    return inner.detach(owner);
  }

  @override
  Future<void> close() {
    calls.add('close');
    return inner.close();
  }

  @override
  bool isHeldBy(AtClient client) => inner.isHeldBy(client);

  @override
  get keyStore => inner.keyStore;

  @override
  get syncQueue => inner.syncQueue;

  @override
  Future<void> forgetPrincipal() => inner.forgetPrincipal();

  @override
  Future<void> clear() => inner.clear();
}

/// A backend the tests run on.
class _Backend {
  const _Backend(this.name, this.make, this.makeHeldOpen,
      {required this.sharesLocation});

  final String name;
  final AtClientStorage Function(String atSign, String dir,
      {bool closedByClient}) make;
  final _HeldOpen Function(String atSign, String dir) makeHeldOpen;

  /// Whether two storages built for one atSign in one directory are one
  /// store, so that the second is refused while the first is open.
  final bool sharesLocation;
}

final List<_Backend> _backends = [
  _Backend(
      'memory',
      (atSign, dir, {closedByClient = false}) => InMemoryAtClientStorage(
          atSign: atSign, closedByClient: closedByClient),
      (atSign, dir) => _HeldOpenMemory(atSign: atSign),
      sharesLocation: false),
  _Backend(
      'hive',
      (atSign, dir, {closedByClient = false}) => HiveAtClientStorage(
          atSign: atSign, storagePath: dir, closedByClient: closedByClient),
      (atSign, dir) => _HeldOpenHive(atSign: atSign, storagePath: dir),
      sharesLocation: true),
  _Backend(
      'sqlite',
      (atSign, dir, {closedByClient = false}) => SqliteAtClientStorage.under(
          atSign: atSign, storagePath: dir, closedByClient: closedByClient),
      (atSign, dir) => _HeldOpenSqlite(atSign: atSign, storagePath: dir),
      sharesLocation: true),
];

/// The refusal of a close() while [principal] holds the storage.
Matcher _refusal(String principal) => throwsA(isA<StateError>()
    .having((e) => e.message, 'message',
        contains('held by $principal; stop that client first'))
    .having((e) => e.message, 'message', isNot(contains('detach'))));

Matcher _closedRefusal() => throwsA(isA<StateError>().having(
    (e) => e.message, 'message', contains('closed and cannot be reopened')));

Future<AtClient> _clientOn(AtClientStorage storage, String atSign) =>
    buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: loopbackPreference(),
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor(atSign),
        storage: storage);

/// Runs [body] in a zone that calls [check] each time one of its callbacks
/// returns, so [check] sees the state at every point another task could run.
Future<T> _checkedAtEveryTurn<T>(
        Future<T> Function() body, void Function() check) =>
    Zone.current
        .fork(
            specification: ZoneSpecification(
          run: <R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
            final result = parent.run(zone, f);
            check();
            return result;
          },
          runUnary: <R, A>(Zone self, ZoneDelegate parent, Zone zone,
              R Function(A) f, A arg) {
            final result = parent.runUnary(zone, f, arg);
            check();
            return result;
          },
          runBinary: <R, A, B>(Zone self, ZoneDelegate parent, Zone zone,
              R Function(A, B) f, A arg1, B arg2) {
            final result = parent.runBinary(zone, f, arg1, arg2);
            check();
            return result;
          },
        ))
        .run(body);

/// Writes a record through [keyStore] and reads it back.
Future<void> _answers(
    AtKeyValueStore<String, AtData, AtMetaData?> keyStore, String key,
    {required String reason}) async {
  await keyStore.put(key, AtData()..data = 'v');
  expect((await keyStore.get(key))?.data, 'v', reason: reason);
}

/// Catalogue: features/at_client/storage_close_while_held.feature
void main() {
  for (final backend in _backends) {
    group('${backend.name} storage:', () {
      late Directory dir;
      final made = <AtClientStorage>[];
      final fakes = <FakeClient>[];

      AtClientStorage make(String atSign, {bool closedByClient = false}) {
        final storage =
            backend.make(atSign, dir.path, closedByClient: closedByClient);
        made.add(storage);
        return storage;
      }

      FakeClient fake(String atSign, String? enrollmentId) {
        final client = FakeClient(atSign, enrollmentId);
        fakes.add(client);
        return client;
      }

      setUp(() =>
          dir = Directory.systemTemp.createTempSync('at_client_close_held_'));
      tearDown(() async {
        final failures = <(Object, StackTrace)>[];
        for (final c
            in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
          try {
            await c.stop();
          } catch (e, stack) {
            failures.add((e, stack));
          }
        }
        for (final storage in made) {
          for (final client in fakes) {
            await storage.detach(client);
          }
          try {
            await storage.close();
          } catch (e, stack) {
            failures.add((e, stack));
          }
        }
        made.clear();
        fakes.clear();
        dir.deleteSync(recursive: true);
        if (failures.isNotEmpty) {
          Error.throwWithStackTrace(failures.first.$1, failures.first.$2);
        }
      });

      test('Closing a storage a client holds is refused', () async {
        final atSign = '@closeheld${backend.name}';
        final storage = make(atSign);
        final client = await _clientOn(storage, atSign);
        final keyStore = storage.keyStore;

        await expectLater(storage.close(), _refusal('$atSign|legacy'),
            reason: 'closing it would leave the client running on a closed '
                'backend');

        expect(storage.isHeldBy(client), isTrue,
            reason: 'the refusal closed nothing, so the client still holds it');
        await _answers(keyStore, 'public:held$atSign',
            reason: 'the backend is still open under the client');
      });

      test('Closing a storage once its client has stopped closes it', () async {
        final atSign = '@closestopped${backend.name}';
        final storage = make(atSign);
        final client = await _clientOn(storage, atSign);
        final keyStore = storage.keyStore;
        final key = 'public:stopped$atSign';
        await _answers(keyStore, key,
            reason: 'the control: the keystore answers while open');
        await client.stop();
        expect(storage.isHeldBy(client), isFalse,
            reason: 'the premise: stop() detached the client');

        final next = make(atSign);
        if (backend.sharesLocation) {
          await expectLater(
              next.attach(fake(atSign, 'e2')),
              throwsA(isA<StateError>().having(
                  (e) => e.message, 'message', contains('already open at'))),
              reason: 'the control: a borrowed storage stays open after its '
                  'client stops, so its location is still claimed');
        }

        await storage.close();

        await expectLater(keyStore.get(key), throwsA(anything),
            reason: 'the backend closed');
        if (backend.sharesLocation) {
          final owner = fake(atSign, 'e2');
          await next.attach(owner);
          expect(next.isHeldBy(owner), isTrue,
              reason: 'the location is free for another storage');
          await next.detach(owner);
        }
      });

      test('Closing a storage while a client is attaching is refused',
          () async {
        final atSign = '@closeattaching${backend.name}';
        final storage = backend.makeHeldOpen(atSign, dir.path);
        made.add(storage);
        final building = _clientOn(storage, atSign);
        await storage.reached.future;

        await expectLater(storage.close(), _refusal('$atSign|legacy'),
            reason: 'an attach still opening the backend holds the storage '
                'as surely as one that has finished');

        storage.proceed.complete();
        final client = await building;
        expect(storage.isHeldBy(client), isTrue,
            reason: 'the attach completed with the client as owner');
        await _answers(storage.keyStore, 'public:attaching$atSign',
            reason: 'the attach completed with the backend open');
      });

      test('A client that owns its storage closes it on stop without error',
          () async {
        final atSign = '@closeowned${backend.name}';
        final storage = make(atSign, closedByClient: true);
        final client = await _clientOn(storage, atSign);
        final keyStore = storage.keyStore;
        final key = 'public:owned$atSign';
        await _answers(keyStore, key,
            reason: 'the control: the keystore answers while open');

        await client.stop();

        await expectLater(keyStore.get(key), throwsA(anything),
            reason: 'stop() closed the storage the client owns');
        await expectLater(storage.attach(fake(atSign, 'e2')), _closedRefusal(),
            reason: 'the storage is closed, not only detached');
      });

      test(
          'Given a client that owns its storage, when a client of the same '
          'principal attaches the moment the stop releases the storage, then '
          'that attach is refused as closed and the stop completes', () async {
        final atSign = '@closeownedgap${backend.name}';
        final storage = make(atSign, closedByClient: true);
        final client = await _clientOn(storage, atSign);
        final latecomer = fake(atSign, null);
        final testZone = Zone.current;
        Future<void>? latecomerAttach;

        final stopping = _checkedAtEveryTurn(client.stop, () {
          if (latecomerAttach != null || storage.isHeldBy(client)) return;
          latecomerAttach = testZone
              .run<Future<void>>(() => storage.attach(latecomer))
            ..ignore();
        });

        await expectLater(stopping, completes,
            reason: 'a client\'s own stop() closes a storage it owns without '
                'being refused');
        expect(storage.isHeldBy(client), isFalse,
            reason: 'the stop released the storage');
        expect(latecomerAttach, isNotNull,
            reason: 'the premise: the latecomer attached as soon as the stop '
                'no longer held the storage');
        await expectLater(latecomerAttach, _closedRefusal(),
            reason: 'the stop dropped its claim and closed the storage in one '
                'step, so no attach found it unheld and open');
      });

      test(
          'close() during a client\'s stop() throws, then succeeds once the '
          'stop completes', () async {
        final atSign = '@closestopping${backend.name}';
        final storage = make(atSign);
        final client = await _clientOn(storage, atSign);
        final keyStore = storage.keyStore;
        final key = 'public:stopping$atSign';
        await _answers(keyStore, key,
            reason: 'the control: the keystore answers while open');

        final stopping = client.stop();
        expect(client.isStopped, isTrue,
            reason: 'the premise: the stop has begun');
        expect(storage.isHeldBy(client), isTrue,
            reason: 'the premise: the stop has not yet released the storage');
        await expectLater(storage.close(), _refusal('$atSign|legacy'),
            reason: 'until the stop releases the storage the client still '
                'holds it');

        await stopping;
        await storage.close();
        await expectLater(keyStore.get(key), throwsA(anything),
            reason: 'once the stop has released it, close() closes it');
      });

      test('a storage never attached, or detached, closes', () async {
        final never = make('@closenever${backend.name}');
        await never.close();
        await expectLater(
            never.attach(fake('@closenever${backend.name}', 'e1')),
            _closedRefusal(),
            reason: 'a storage nobody attached closes');

        final atSign = '@closedetached${backend.name}';
        final detached = make(atSign);
        final owner = fake(atSign, 'e1');
        await detached.attach(owner);
        await detached.detach(owner);
        await detached.close();
        await expectLater(detached.attach(owner), _closedRefusal(),
            reason: 'a storage whose client detached closes');
      });

      test('a second close() returns', () async {
        final atSign = '@closetwice${backend.name}';
        final storage = make(atSign);
        final owner = fake(atSign, 'e1');
        await storage.attach(owner);
        await storage.detach(owner);
        await storage.close();

        await storage.close();

        final refused =
            expectLater(storage.attach(fake(atSign, 'e2')), _closedRefusal());
        await storage.close();
        await refused;
      });

      test(
          'Given a storage whose client has detached, when another '
          'principal\'s refused attach has not yet settled, then close() '
          'closes the storage', () async {
        final atSign = '@closerefused${backend.name}';
        final storage = make(atSign);
        final first = fake(atSign, 'e1');
        await storage.attach(first);
        await storage.detach(first);

        final refused = expectLater(
            storage.attach(fake(atSign, 'e2')),
            throwsA(isA<StateError>().having((e) => e.message, 'message',
                contains('last held by $atSign|e1'))),
            reason: 'the premise: a different principal is refused');
        await storage.close();
        await refused;

        await expectLater(storage.attach(first), _closedRefusal(),
            reason: 'the refused attach never held the storage, so close() '
                'closed it');
      });

      if (backend.sharesLocation) {
        test(
            'a refused close() keeps the location claimed until a later '
            'close() releases it', () async {
          final atSign = '@closeclaim${backend.name}';
          final storage = make(atSign);
          final owner = fake(atSign, 'e1');
          await storage.attach(owner);
          await expectLater(storage.close(), _refusal('$atSign|e1'));

          final next = make(atSign);
          final nextOwner = fake(atSign, 'e2');
          await expectLater(
              next.attach(nextOwner),
              throwsA(isA<StateError>().having(
                  (e) => e.message, 'message', contains('already open at'))),
              reason: 'the refusal closed nothing, so the location is still '
                  'claimed by the open storage');

          await storage.detach(owner);
          await storage.close();
          await next.attach(nextOwner);
          expect(next.isHeldBy(nextOwner), isTrue,
              reason: 'the close that followed the refusal released the '
                  'location');
          await next.detach(nextOwner);
        });
      }
    });
  }

  test(
      'Given a client whose storage only implements AtClientStorage and is '
      'closed by the client, when the client stops, then it detaches from the '
      'storage and then closes it', () async {
    const atSign = '@closeinterfaceonly';
    final storage = _InterfaceOnlyStorage(atSign);
    final client = await _clientOn(storage, atSign);
    addTearDown(() async {
      await client.stop();
      await storage.inner.detach(client);
      await storage.inner.close();
    });

    await client.stop();

    expect(storage.calls, ['attach', 'detach', 'close'],
        reason: 'stop() detaches from a storage that is not an '
            'AtClientStorageBase, then closes it because the client owns it');
    await expectLater(
        storage.inner.attach(FakeClient(atSign, 'e2')), _closedRefusal(),
        reason: 'the storage is closed, not only detached');
  });
}
