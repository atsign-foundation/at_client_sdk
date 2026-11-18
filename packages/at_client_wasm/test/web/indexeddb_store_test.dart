@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart'
    show PendingOnboardingRecord, UnsupportedPasskeyRecordException;
import 'package:at_client_wasm/src/keys/indexeddb_store.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

Future<IDBDatabase> _rawOpen(String name, int version,
    {void Function(IDBDatabase db)? upgrade}) {
  final completer = Completer<IDBDatabase>();
  final request = window.indexedDB.open(name, version);
  request.onupgradeneeded = (Event e) {
    upgrade?.call(request.result as IDBDatabase);
  }.toJS;
  request.onsuccess = (Event e) {
    completer.complete(request.result as IDBDatabase);
  }.toJS;
  request.onerror = (Event e) {
    completer.completeError(Exception('raw open failed'));
  }.toJS;
  return completer.future;
}

/// Puts [value] under [key] in [storeName] of [db] and waits for it to commit.
Future<void> _rawPut(
    IDBDatabase db, String storeName, String key, List<int> value) {
  final done = Completer<void>();
  final tx = db.transaction(storeName.toJS, 'readwrite');
  tx.oncomplete = (Event e) {
    done.complete();
  }.toJS;
  tx.objectStore(storeName).put(Uint8List.fromList(value).toJS, key.toJS);
  return done.future;
}

void main() {
  String generateDbName() =>
      'test_db_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond).toString()}';

  Future<void> deleteDb(String name) async {
    final completer = Completer<void>();
    final request = window.indexedDB.deleteDatabase(name);
    request.onsuccess = (Event e) {
      completer.complete();
    }.toJS;
    request.onerror = (Event e) {
      completer.completeError(Exception('Failed to delete DB'));
    }.toJS;
    await completer.future;
  }

  group('IndexedDbHintStore', () {
    String? currentDbName;
    List<IndexedDbHintStore> openStores = [];

    setUp(() {
      currentDbName = generateDbName();
      openStores = [];
    });

    tearDown(() async {
      for (final store in openStores) {
        store.close();
      }
      if (currentDbName != null) {
        await deleteDb(currentDbName!);
      }
    });

    Future<IndexedDbHintStore> open() async {
      final store = await IndexedDbHintStore.open(dbName: currentDbName!);
      openStores.add(store);
      return store;
    }

    test('putHint stores both ids', () async {
      final store = await open();
      await store.putHint('@alice', Uint8List.fromList([7, 8]), 'eid-1');
      expect(await store.credentialId('@alice'), [7, 8]);
      expect(await store.enrollmentId('@alice'), 'eid-1');
    });

    test('putHint replaces both ids together', () async {
      final store = await open();
      await store.putHint('@alice', Uint8List.fromList([1]), 'eid-1');
      await store.putHint('@alice', Uint8List.fromList([2]), 'eid-2');
      expect(await store.credentialId('@alice'), [2]);
      expect(await store.enrollmentId('@alice'), 'eid-2');
    });

    test('putHint writes neither id when its transaction aborts', () async {
      // The enrollments store keys its values in-line, so the second put of
      // the pair throws after the first was queued.
      final name = currentDbName!;
      final raw = await _rawOpen(name, 1, upgrade: (db) {
        db.createObjectStore('at_client_wasm_credentials');
        db.createObjectStore('at_client_wasm_enrollments',
            IDBObjectStoreParameters(keyPath: 'id'.toJS));
      });
      final store = IndexedDbHintStore.forDatabase(raw);
      await expectLater(
          store.putHint('@alice', Uint8List.fromList([1]), 'eid-1'),
          throwsA(isA<IndexedDbException>()
              .having((e) => e.message, 'message', contains('DataError'))));
      expect(await store.credentialId('@alice'), isNull);
      raw.close();
    });

    test(
        'every operation on a database without its object stores fails with '
        'an IndexedDbException naming the error', () async {
      final raw = await _rawOpen(currentDbName!, 1);
      addTearDown(() => raw.close());
      final store = IndexedDbHintStore.forDatabase(raw);
      final record = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([1]),
          enrollmentId: 'eid-1',
          encryptionPublicKey: 'pub-1',
          sealed: 'sealed-1');
      final operations = <String, Future<Object?> Function()>{
        'putCredentialId': () =>
            store.putCredentialId('@alice', Uint8List.fromList([1])),
        'credentialId': () => store.credentialId('@alice'),
        'putEnrollmentId': () => store.putEnrollmentId('@alice', 'eid-1'),
        'enrollmentId': () => store.enrollmentId('@alice'),
        'putHint': () =>
            store.putHint('@alice', Uint8List.fromList([1]), 'eid-1'),
        'deleteHints': () => store.deleteHints('@alice'),
        'put': () => store.put('@alice', record),
        'get': () => store.get('@alice'),
        'delete': () => store.delete('@alice'),
      };
      for (final MapEntry(key: name, value: operation) in operations.entries) {
        await expectLater(
            operation(),
            throwsA(isA<IndexedDbException>().having(
                (e) => e.message, 'message', contains('NotFoundError'))),
            reason: '$name fails as an IndexedDbException naming the error');
      }
    });

    test('a read whose transaction aborts fails naming the error', () async {
      final raw = await _rawOpen(currentDbName!, 2, upgrade: (db) {
        db.createObjectStore('at_client_wasm_credentials');
        db.createObjectStore('at_client_wasm_enrollments');
      });
      addTearDown(() => raw.close());
      final aborting = JSObject()
        ..setProperty(
            'transaction'.toJS,
            ((JSAny? stores, JSAny? mode) {
              final tx = raw.transaction(stores as JSString, 'readonly');
              Future.microtask(() => tx.abort());
              return tx;
            }).toJS);
      final store = IndexedDbHintStore.forDatabase(aborting as IDBDatabase);

      await expectLater(
          store.credentialId('@alice'),
          throwsA(isA<IndexedDbException>()
              .having((e) => e.message, 'message', contains('AbortError'))),
          reason: 'the aborted read request fails as an IndexedDbException '
              'naming the error');
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(
        'a transaction aborted with an error names that error, not the '
        'AbortError of a request it cancelled', () async {
      final raw = await _rawOpen(currentDbName!, 3, upgrade: (db) {
        db.createObjectStore('at_client_wasm_credentials').createIndex(
            'one_atsign_per_credential',
            ''.toJS,
            IDBIndexParameters(unique: true));
        db.createObjectStore('at_client_wasm_enrollments');
        db.createObjectStore('at_client_wasm_pending');
      });
      addTearDown(() => raw.close());
      await _rawPut(raw, 'at_client_wasm_credentials', '@bob', [7]);
      final quiet = JSObject()
        ..setProperty(
            'transaction'.toJS,
            ((JSAny? stores, JSAny? mode) {
              final tx = raw.transaction(stores!, (mode as JSString).toDart);
              tx.addEventListener(
                  'error',
                  ((Event e) => e.stopPropagation()).toJS,
                  AddEventListenerOptions(capture: true, once: true));
              return tx;
            }).toJS);
      final store = IndexedDbHintStore.forDatabase(quiet as IDBDatabase);

      await expectLater(
          store.putHint('@alice', Uint8List.fromList([7]), 'eid-1'),
          throwsA(isA<IndexedDbException>().having(
              (e) => e.message, 'message', contains('ConstraintError'))),
          reason: "the transaction's own error is named, not the AbortError "
              'of the put it cancelled');
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('an open the browser refuses outright fails naming the error',
        () async {
      final factory = window.indexedDB as JSObject;
      factory['open'] = globalContext.callMethod<JSFunction>(
          'Function'.toJS,
          'throw new DOMException("The operation is insecure.", '
                  '"SecurityError");'
              .toJS);
      addTearDown(() => factory.delete('open'.toJS));

      await expectLater(
          IndexedDbHintStore.open(dbName: currentDbName!),
          throwsA(isA<IndexedDbException>()
              .having((e) => e.message, 'message', contains('SecurityError'))),
          reason: 'the refused open fails as an IndexedDbException naming '
              'the error');
    });

    test('credentialId round-trips per atSign', () async {
      final store = await open();
      final credId = Uint8List.fromList([4, 5, 6]);

      expect(await store.credentialId('@alice'), isNull);
      await store.putCredentialId('@alice', credId);

      expect(await store.credentialId('@alice'), credId);
      expect(await store.credentialId('@bob'), isNull);
    });

    test('enrollmentId round-trips per atSign', () async {
      final store = await open();

      expect(await store.enrollmentId('@alice'), isNull);
      await store.putEnrollmentId('@alice', 'e1d2c3');
      expect(await store.enrollmentId('@alice'), 'e1d2c3');
      expect(await store.enrollmentId('@bob'), isNull);
    });

    test('stored credential bytes are a copy of the bytes given', () async {
      final store = await open();
      final credId = Uint8List.fromList([4, 5, 6]);
      await store.putCredentialId('@alice', credId);

      credId[0] = 99;

      expect(await store.credentialId('@alice'), [4, 5, 6]);
    });

    test('read credential bytes are a copy of the stored bytes', () async {
      final store = await open();
      await store.putCredentialId('@alice', Uint8List.fromList([4, 5, 6]));

      (await store.credentialId('@alice'))![0] = 99;

      expect(await store.credentialId('@alice'), [4, 5, 6]);
    });

    test('an aborted write fails instead of hanging', () async {
      final raw = await _rawOpen(currentDbName!, 2, upgrade: (db) {
        db.createObjectStore('at_client_wasm_credentials');
        db.createObjectStore('at_client_wasm_enrollments');
      });
      final aborting = JSObject()
        ..setProperty(
            'transaction'.toJS,
            ((JSAny? stores, JSAny? mode) {
              final tx = raw.transaction(stores as JSString, 'readwrite');
              Future.microtask(() => tx.abort());
              return tx;
            }).toJS);
      final store = IndexedDbHintStore.forDatabase(aborting as IDBDatabase);

      await expectLater(
          store.putCredentialId('@alice', Uint8List.fromList([1])),
          throwsA(isA<IndexedDbException>()));
      raw.close();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('opening while another connection blocks the upgrade fails', () async {
      final old = await _rawOpen(currentDbName!, 1);
      try {
        await expectLater(IndexedDbHintStore.open(dbName: currentDbName!),
            throwsA(isA<IndexedDbException>()));
      } finally {
        old.close();
      }
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('an open store closes for a newer version of the database', () async {
      await open();

      final newer = await _rawOpen(currentDbName!, 4);
      newer.close();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('a store closed for a newer version reopens on its next operation',
        () async {
      final store = await open();
      await store.putEnrollmentId('@alice', 'e1');

      final newer = await _rawOpen(currentDbName!, 4);
      newer.close();

      expect(await store.enrollmentId('@alice'), 'e1');
      await store.putCredentialId('@alice', Uint8List.fromList([7]));
      expect(await store.credentialId('@alice'), [7]);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('a store closed for a newer version reopens for a write first',
        () async {
      final store = await open();

      final newer = await _rawOpen(currentDbName!, 4);
      newer.close();

      await store.putEnrollmentId('@alice', 'e2');
      expect(await store.enrollmentId('@alice'), 'e2');
    }, timeout: const Timeout(Duration(seconds: 5)));

    group('pending onboarding records', () {
      PendingOnboardingRecord record(int n) => PendingOnboardingRecord(
          credentialId: Uint8List.fromList([n, n + 1]),
          enrollmentId: 'eid-$n',
          encryptionPublicKey: 'pub-$n',
          sealed: 'sealed-$n');

      test('are absent until put', () async {
        expect(await (await open()).get('@alice'), isNull);
      });

      test('round-trip, and survive a reopen of the database', () async {
        final store = await open();
        await store.put('@alice', record(1));
        store.close();

        final got = await (await open()).get('@alice');
        expect(got!.credentialId, [1, 2]);
        expect(got.enrollmentId, 'eid-1');
        expect(got.encryptionPublicKey, 'pub-1');
        expect(got.sealed, 'sealed-1');
      });

      test('are kept per atSign and replaced by a later put', () async {
        final store = await open();
        await store.put('@alice', record(1));
        await store.put('@bob', record(5));
        await store.put('@alice', record(3));

        expect((await store.get('@alice'))!.enrollmentId, 'eid-3');
        expect((await store.get('@bob'))!.enrollmentId, 'eid-5');
      });

      test('are deleted alone, and deleting none is fine', () async {
        final store = await open();
        await store.put('@alice', record(1));
        await store.put('@bob', record(5));

        await store.delete('@alice');
        await store.delete('@alice');

        expect(await store.get('@alice'), isNull);
        expect(await store.get('@bob'), isNotNull);
      });

      test('are kept apart from the hints', () async {
        final store = await open();
        await store.putHint('@alice', Uint8List.fromList([9]), 'eid-9');
        await store.put('@alice', record(1));
        await store.delete('@alice');

        expect(await store.credentialId('@alice'), [9]);
        expect(await store.enrollmentId('@alice'), 'eid-9');
      });

      test('that are not records fail typed on read', () async {
        final raw = await _rawOpen(currentDbName!, 3, upgrade: (db) {
          db.createObjectStore('at_client_wasm_credentials');
          db.createObjectStore('at_client_wasm_enrollments');
          db.createObjectStore('at_client_wasm_pending');
        });
        await _rawPut(
            raw, 'at_client_wasm_pending', '@alice', utf8.encode('nope'));
        raw.close();

        await expectLater((await open()).get('@alice'),
            throwsA(isA<UnsupportedPasskeyRecordException>()));
      });

      test('a database left at version 2 upgrades and keeps its hints',
          () async {
        final old = await _rawOpen(currentDbName!, 2, upgrade: (db) {
          db.createObjectStore('at_client_wasm_credentials');
          db.createObjectStore('at_client_wasm_enrollments');
        });
        await _rawPut(old, 'at_client_wasm_credentials', '@alice', [4, 2]);
        old.close();

        final store = await open();

        expect(await store.credentialId('@alice'), [4, 2]);
        await store.put('@alice', record(1));
        expect((await store.get('@alice'))!.enrollmentId, 'eid-1');
      });
    });

    test('a store closed by the caller does not reopen', () async {
      final store = await open();
      store.close();

      await expectLater(
          store.enrollmentId('@alice'), throwsA(isA<IndexedDbException>()));
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
