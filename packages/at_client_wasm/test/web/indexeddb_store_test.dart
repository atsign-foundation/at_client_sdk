@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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

/// The bytes under [key] in [storeName] of [db], or null.
Future<List<int>?> _rawGet(IDBDatabase db, String storeName, String key) {
  final done = Completer<List<int>?>();
  final request =
      db.transaction(storeName.toJS).objectStore(storeName).get(key.toJS);
  request.onsuccess = (Event e) {
    done.complete((request.result as JSUint8Array?)?.toDart);
  }.toJS;
  request.onerror = (Event e) {
    done.completeError(Exception('raw get failed'));
  }.toJS;
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
          throwsA(
              isA<DOMException>().having((e) => e.name, 'name', 'DataError')));
      expect(await store.credentialId('@alice'), isNull);
      raw.close();
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

      final newer = await _rawOpen(currentDbName!, 5);
      newer.close();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('a store closed for a newer version reopens on its next operation',
        () async {
      final store = await open();
      await store.putEnrollmentId('@alice', 'e1');

      final newer = await _rawOpen(currentDbName!, 5);
      newer.close();

      expect(await store.enrollmentId('@alice'), 'e1');
      await store.putCredentialId('@alice', Uint8List.fromList([7]));
      expect(await store.credentialId('@alice'), [7]);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('a store closed for a newer version reopens for a write first',
        () async {
      final store = await open();

      final newer = await _rawOpen(currentDbName!, 5);
      newer.close();

      await store.putEnrollmentId('@alice', 'e2');
      expect(await store.enrollmentId('@alice'), 'e2');
    }, timeout: const Timeout(Duration(seconds: 5)));

    group('an upgrade to version 4', () {
      /// The object store names of the database, read on a raw connection
      /// that asks for no upgrade.
      Future<List<String>> storeNames() async {
        final raw = await _rawOpen(currentDbName!, 4);
        try {
          final names = raw.objectStoreNames;
          return [for (var i = 0; i < names.length; i++) names.item(i)!];
        } finally {
          raw.close();
        }
      }

      test('keeps a version 3 database\'s pending records and its hints',
          () async {
        final old = await _rawOpen(currentDbName!, 3, upgrade: (db) {
          db.createObjectStore('at_client_wasm_credentials');
          db.createObjectStore('at_client_wasm_enrollments');
          db.createObjectStore('at_client_wasm_pending');
        });
        await _rawPut(old, 'at_client_wasm_credentials', '@alice', [4, 2]);
        await _rawPut(
            old, 'at_client_wasm_enrollments', '@alice', utf8.encode('e1'));
        await _rawPut(old, 'at_client_wasm_pending', '@alice', [1, 2, 3]);
        old.close();

        final store = await open();
        expect(await store.credentialId('@alice'), [4, 2]);
        expect(await store.enrollmentId('@alice'), 'e1');
        store.close();

        expect(
            await storeNames(),
            unorderedEquals([
              'at_client_wasm_credentials',
              'at_client_wasm_enrollments',
              'at_client_wasm_pending',
            ]));
        final raw = await _rawOpen(currentDbName!, 4);
        try {
          expect(await _rawGet(raw, 'at_client_wasm_pending', '@alice'),
              [1, 2, 3]);
        } finally {
          raw.close();
        }
      });

      test('deletes a version 1 database\'s keys store', () async {
        final old = await _rawOpen(currentDbName!, 1, upgrade: (db) {
          db.createObjectStore('at_client_wasm_keys');
        });
        await _rawPut(old, 'at_client_wasm_keys', '@alice', [9, 9]);
        old.close();

        final store = await open();
        expect(await store.credentialId('@alice'), isNull);
        store.close();

        expect(
            await storeNames(),
            unorderedEquals(
                ['at_client_wasm_credentials', 'at_client_wasm_enrollments']));
      });

      test('keeps a version 2 database\'s hints', () async {
        final old = await _rawOpen(currentDbName!, 2, upgrade: (db) {
          db.createObjectStore('at_client_wasm_credentials');
          db.createObjectStore('at_client_wasm_enrollments');
        });
        await _rawPut(old, 'at_client_wasm_credentials', '@alice', [4, 2]);
        old.close();

        final store = await open();

        expect(await store.credentialId('@alice'), [4, 2]);
        await store.putEnrollmentId('@alice', 'e1');
        expect(await store.enrollmentId('@alice'), 'e1');
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
