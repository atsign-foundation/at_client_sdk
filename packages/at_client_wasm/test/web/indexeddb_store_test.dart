@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import '../key_bytes_store_contract.dart';

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

  group('IndexedDbKeyBytesStore contract', () {
    String? currentDbName;
    List<IndexedDbKeyBytesStore> openStores = [];

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

    keyBytesStoreContract('IndexedDbKeyBytesStore', () async {
      final store = await IndexedDbKeyBytesStore.open(dbName: currentDbName!);
      openStores.add(store);
      return store;
    });
  });

  group('IndexedDbKeyBytesStore extras', () {
    String? currentDbName;
    List<IndexedDbKeyBytesStore> openStores = [];

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

    test('credentialId round-trip and delete clearing both', () async {
      final store = await IndexedDbKeyBytesStore.open(dbName: currentDbName!);
      openStores.add(store);

      final keyBytes = Uint8List.fromList([1, 2, 3]);
      final credId = Uint8List.fromList([4, 5, 6]);

      await store.put('@alice', keyBytes);
      await store.putCredentialId('@alice', credId);

      expect(await store.get('@alice'), keyBytes);
      expect(await store.credentialId('@alice'), credId);

      await store.delete('@alice');

      expect(await store.get('@alice'), isNull);
      expect(await store.credentialId('@alice'), isNull);
    });
  });
}
