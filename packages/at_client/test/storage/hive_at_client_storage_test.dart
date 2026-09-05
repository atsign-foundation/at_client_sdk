import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _FakeClient extends Mock implements AtClient {
  _FakeClient(this._atSign, this._enrollmentId);
  final String _atSign;
  final String? _enrollmentId;
  @override
  String? getCurrentAtSign() => _atSign;
  @override
  String? get enrollmentId => _enrollmentId;
}

void main() {
  late Directory dir;
  final opened = <HiveAtClientStorage>[];

  HiveAtClientStorage storageFor(String atSign) {
    final s = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    opened.add(s);
    return s;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('at_client_storage_');
  });

  tearDown(() async {
    for (final s in opened) {
      await s.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  group('attach', () {
    test('the same client attaching twice is a no-op', () async {
      final s = storageFor('@hivestore1');
      final owner = _FakeClient('@hivestore1', 'e1');
      await s.attach(owner);
      await s.attach(owner);
      expect(s.isAttached, isTrue);
    });

    test('a different client is refused, and the message names the holder',
        () async {
      final s = storageFor('@hivestore2');
      await s.attach(_FakeClient('@hivestore2', 'e1'));
      expect(
          () => s.attach(_FakeClient('@hivestore2', 'e2')),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('is held by @hivestore2|e1'))),
          reason: 'two clients on one store is the silent sharing this '
              'exists to refuse');
    });

    test('after detach the same principal attaches again as a new instance',
        () async {
      final s = storageFor('@hivestore3');
      final first = _FakeClient('@hivestore3', 'e1');
      await s.attach(first);
      await s.detach(first);
      await s.attach(_FakeClient('@hivestore3', 'e1'));
      expect(s.isAttached, isTrue,
          reason: 'a restart within the process is the legitimate reuse');
    });

    test('after detach a different principal is refused until forgetPrincipal',
        () async {
      final s = storageFor('@hivestore4');
      final first = _FakeClient('@hivestore4', 'e1');
      await s.attach(first);
      await s.detach(first);
      final second = _FakeClient('@hivestore4', 'e2');
      expect(
          () => s.attach(second),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('last held by @hivestore4|e1'))),
          reason: 'records and queued pushes are that principal\'s; a '
              'different enrollment must not inherit them by accident');
      await s.forgetPrincipal();
      await s.attach(second);
      expect(s.isAttached, isTrue,
          reason: 'forgetPrincipal is the deliberate hand-over');
    });

    test('forgetPrincipal refuses while attached', () async {
      final s = storageFor('@hivestore5');
      await s.attach(_FakeClient('@hivestore5', 'e1'));
      expect(() => s.forgetPrincipal(), throwsA(isA<StateError>()));
    });
  });

  group('clear', () {
    test('empties the queue and the keystore, and forgets the principal',
        () async {
      final s = storageFor('@hivestore6');
      final first = _FakeClient('@hivestore6', 'e1');
      await s.attach(first);
      await s.syncQueue.enqueue('k@hivestore6', SyncQueueOp.updateAll);
      await s.keyStore.put('k@hivestore6', AtData()..data = 'v');
      expect(s.syncQueue.size, 1);
      expect(await s.keyStore.exists('k@hivestore6'), isTrue);

      await s.detach(first);
      await s.clear();

      expect(s.syncQueue.size, 0,
          reason: 'a queue carrying another test\'s '
              'entries is what poisoned the functional pack');
      expect(await s.keyStore.exists('k@hivestore6'), isFalse);
      await s.attach(_FakeClient('@hivestore6', 'e2'));
      expect(s.isAttached, isTrue,
          reason: 'clear also forgets the principal, so the next holder need '
              'not be the last');
    });

    test('a holder that clears and keeps writing is stamped again on detach',
        () async {
      final s = storageFor('@hivestore9');
      final first = _FakeClient('@hivestore9', 'e1');
      await s.attach(first);
      await s.clear();
      await s.syncQueue.enqueue('k@hivestore9', SyncQueueOp.updateAll);
      await s.detach(first);
      expect(() => s.attach(_FakeClient('@hivestore9', 'e2')),
          throwsA(isA<StateError>()),
          reason: 'clear cannot license inheriting what was written after it');
    });
  });

  group('close', () {
    test('close is idempotent and drops the claim', () async {
      final s = storageFor('@hivestore8');
      await s.attach(_FakeClient('@hivestore8', 'e1'));
      await s.close();
      await s.close();
      expect(s.isAttached, isFalse);
    });
  });
}
