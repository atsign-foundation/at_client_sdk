// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:js_interop';

import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:web/web.dart';

import 'idb_util.dart';

class IndexedDbSyncQueueStore implements SyncQueueStore {
  final IDBDatabase _db;
  final Map<String, String> _cache;

  IndexedDbSyncQueueStore._(this._db, this._cache);

  static Future<IndexedDbSyncQueueStore> load(IDBDatabase db) async {
    final tx = db.transaction('sync_queue'.toJS, 'readonly');
    final store = tx.objectStore('sync_queue');
    final request = store.openCursor();

    final completer = Completer<Map<String, String>>();
    final cache = <String, String>{};

    request.onsuccess = (Event e) {
      final cursor = request.result as IDBCursorWithValue?;
      if (cursor != null) {
        final key = (cursor.key as JSString).toDart;
        final value = (cursor.value as JSString).toDart;
        cache[key] = value;
        cursor.continue_();
      } else {
        completer.complete(cache);
      }
    }.toJS;

    request.onerror = (Event e) {
      completer.completeError(
          request.error ?? Exception('Failed to load sync_queue'));
    }.toJS;

    final loadedCache = await completer.future;
    return IndexedDbSyncQueueStore._(db, loadedCache);
  }

  @override
  Iterable<String> get keys => _cache.keys;

  @override
  String? get(String atKey) => _cache[atKey];

  @override
  Future<void> put(String atKey, String record) async {
    _cache[atKey] = record;
    final tx = _db.transaction('sync_queue'.toJS, 'readwrite');
    tx.objectStore('sync_queue').put(record.toJS, atKey.toJS);
    await transactionToFuture(tx);
  }

  @override
  Future<void> delete(String atKey) async {
    _cache.remove(atKey);
    final tx = _db.transaction('sync_queue'.toJS, 'readwrite');
    tx.objectStore('sync_queue').delete(atKey.toJS);
    await transactionToFuture(tx);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    final tx = _db.transaction('sync_queue'.toJS, 'readwrite');
    tx.objectStore('sync_queue').clear();
    await transactionToFuture(tx);
  }

  @override
  Future<void> close() async {}
}
