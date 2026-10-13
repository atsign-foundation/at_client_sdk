import 'dart:io';

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

/// Makes the file at [path] unreadable, and returns what makes it readable
/// again, or null when the process reads it whatever its mode says.
void Function()? unreadable(String path) {
  if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
    return null;
  }
  expect(Process.runSync('chmod', ['000', path]).exitCode, 0);
  return () => Process.runSync('chmod', ['600', path]);
}

/// The open, claim and clear rules every [AtClientStorage] must satisfy.
///
/// [make] builds a fresh, unopened storage for [atSign]; the contract closes
/// what it opens. [breakOpen] leaves the storage [make] builds for an atSign
/// unable to open, and returns what puts it right, or null when it cannot
/// break it here; pass null for a backend with nothing that can stop it
/// opening.
void runStorageContract(
    String backend, AtClientStorage Function(String atSign) make,
    {required void Function()? Function(String atSign)? breakOpen}) {
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

  final breaker = breakOpen;
  if (breaker != null) {
    group('$backend: open', () {
      test('a failed open reaches the caller once, and a later open works',
          () async {
        final atSign = '@${backend}c10';
        final first = storageFor(atSign);
        await first.attach(FakeClient(atSign, 'e1'));
        await first.close();
        final restore = breaker(atSign);
        if (restore == null) {
          markTestSkipped('$backend cannot be made to fail to open here');
          return;
        }
        addTearDown(restore);

        final s = storageFor(atSign);
        await expectLater(
            s.attach(FakeClient(atSign, 'e1')), throwsA(isA<Exception>()));
        // NOTE: an unhandled second report would arrive after the caller's,
        // and fails this test only if it lands before the test ends.
        await pumpEventQueue();

        restore();
        await s.attach(FakeClient(atSign, 'e1'));
        await s.keyStore.put('k$atSign', AtData()..data = 'v');
        expect((await s.keyStore.get('k$atSign'))?.data, 'v',
            reason: 'the failure left nothing behind that stops a later open');
      });
    });
  }

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
