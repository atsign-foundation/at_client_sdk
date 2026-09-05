import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class FakeClient extends Mock implements AtClient {
  FakeClient(this._atSign, this._enrollmentId);
  final String _atSign;
  final String? _enrollmentId;
  @override
  String? getCurrentAtSign() => _atSign;
  @override
  String? get enrollmentId => _enrollmentId;
}

/// The claim and clear rules every [AtClientStorage] must satisfy.
///
/// [make] builds a fresh, unopened storage for [atSign]; the contract closes
/// what it opens.
void runStorageContract(
    String backend, AtClientStorage Function(String atSign) make) {
  final opened = <AtClientStorage>[];
  AtClientStorage storageFor(String atSign) {
    final s = make(atSign);
    opened.add(s);
    return s;
  }

  tearDown(() async {
    for (final s in opened) {
      await s.close();
    }
    opened.clear();
  });

  group('$backend: attach', () {
    test('the same client attaching twice is a no-op', () async {
      final s = storageFor('@${backend}c1') as AtClientStorageBase;
      final owner = FakeClient('@${backend}c1', 'e1');
      await s.attach(owner);
      await s.attach(owner);
      expect(s.isAttached, isTrue);
    });

    test('a different client is refused, and the message names the holder',
        () async {
      final s = storageFor('@${backend}c2');
      await s.attach(FakeClient('@${backend}c2', 'e1'));
      expect(
          () => s.attach(FakeClient('@${backend}c2', 'e2')),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('is held by @${backend}c2|e1'))),
          reason: 'two clients on one store is the silent sharing this '
              'exists to refuse');
    });

    test('after detach the same principal attaches again as a new instance',
        () async {
      final s = storageFor('@${backend}c3') as AtClientStorageBase;
      final first = FakeClient('@${backend}c3', 'e1');
      await s.attach(first);
      await s.detach(first);
      await s.attach(FakeClient('@${backend}c3', 'e1'));
      expect(s.isAttached, isTrue,
          reason: 'a restart within the process is the legitimate reuse');
    });

    test('after detach a different principal is refused until forgetPrincipal',
        () async {
      final s = storageFor('@${backend}c4') as AtClientStorageBase;
      final first = FakeClient('@${backend}c4', 'e1');
      await s.attach(first);
      await s.detach(first);
      final second = FakeClient('@${backend}c4', 'e2');
      expect(
          () => s.attach(second),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('last held by @${backend}c4|e1'))),
          reason: 'records and queued pushes are that principal\'s; a '
              'different enrollment must not inherit them by accident');
      await s.forgetPrincipal();
      await s.attach(second);
      expect(s.isAttached, isTrue,
          reason: 'forgetPrincipal is the deliberate hand-over');
    });

    test('forgetPrincipal refuses while attached', () async {
      final s = storageFor('@${backend}c5');
      await s.attach(FakeClient('@${backend}c5', 'e1'));
      expect(() => s.forgetPrincipal(), throwsA(isA<StateError>()));
    });
  });

  group('$backend: data', () {
    test('a write is readable through the keystore and the queue', () async {
      final s = storageFor('@${backend}c6');
      await s.attach(FakeClient('@${backend}c6', 'e1'));
      await s.syncQueue.enqueue('k@${backend}c6', SyncQueueOp.updateAll);
      await s.keyStore.put('k@${backend}c6', AtData()..data = 'v');
      expect(s.syncQueue.size, 1);
      expect((await s.keyStore.get('k@${backend}c6'))?.data, 'v');
    });

    test('clear empties the queue and the keystore, and forgets the principal',
        () async {
      final s = storageFor('@${backend}c7') as AtClientStorageBase;
      final first = FakeClient('@${backend}c7', 'e1');
      await s.attach(first);
      await s.syncQueue.enqueue('k@${backend}c7', SyncQueueOp.updateAll);
      await s.keyStore.put('k@${backend}c7', AtData()..data = 'v');
      await s.detach(first);
      await s.clear();

      expect(s.syncQueue.size, 0,
          reason: 'a queue carrying another test\'s entries is what '
              'poisoned the functional pack');
      expect(await s.keyStore.exists('k@${backend}c7'), isFalse);
      await s.attach(FakeClient('@${backend}c7', 'e2'));
      expect(s.isAttached, isTrue,
          reason: 'clear also forgets the principal, so the next holder need '
              'not be the last');
    });

    test('a holder that clears and keeps writing is stamped again on detach',
        () async {
      final s = storageFor('@${backend}c8');
      final first = FakeClient('@${backend}c8', 'e1');
      await s.attach(first);
      await s.clear();
      await s.syncQueue.enqueue('k@${backend}c8', SyncQueueOp.updateAll);
      await s.detach(first);
      expect(() => s.attach(FakeClient('@${backend}c8', 'e2')),
          throwsA(isA<StateError>()),
          reason: 'clear cannot license inheriting what was written after it');
    });
  });

  group('$backend: close', () {
    test('close is idempotent and drops the claim', () async {
      final s = storageFor('@${backend}c9') as AtClientStorageBase;
      await s.attach(FakeClient('@${backend}c9', 'e1'));
      await s.close();
      await s.close();
      expect(s.isAttached, isFalse);
    });
  });
}
