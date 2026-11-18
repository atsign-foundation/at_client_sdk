@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:at_client_wasm/src/keys/indexeddb_store.dart';
import 'package:at_client_wasm/src/session/web_passkey_entry.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

Future<void> _deleteDb(String name) {
  final done = Completer<void>();
  final request = window.indexedDB.deleteDatabase(name);
  request.onsuccess = (Event e) {
    done.complete();
  }.toJS;
  request.onerror = (Event e) {
    done.completeError(Exception('Failed to delete DB'));
  }.toJS;
  return done.future;
}

void main() {
  group('runClosingStore', () {
    var dbCount = 0;
    late String dbName;

    setUp(() => dbName = 'web_passkey_entry_test_${dbCount++}');
    tearDown(() => _deleteDb(dbName));

    Future<IndexedDbHintStore> open() =>
        IndexedDbHintStore.open(dbName: dbName);

    test('closes the store once the run returns', () async {
      late IndexedDbHintStore used;
      final result = await runClosingStore(open, (store) async {
        used = store;
        await store.putEnrollmentId('@alice', 'e1');
        return 'done';
      });

      expect(result, 'done');
      await expectLater(
          used.enrollmentId('@alice'), throwsA(isA<IndexedDbException>()));
    });

    test('closes the store and rethrows when the run throws', () async {
      final error = StateError('run failed');
      late IndexedDbHintStore used;
      await expectLater(
          runClosingStore<void>(open, (store) async {
            used = store;
            throw error;
          }),
          throwsA(same(error)));

      await expectLater(
          used.credentialId('@alice'), throwsA(isA<IndexedDbException>()));
    });
  });
}
