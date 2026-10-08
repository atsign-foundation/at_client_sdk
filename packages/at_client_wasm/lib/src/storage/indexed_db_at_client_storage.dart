// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:js_interop';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:web/web.dart';

import 'idb_util.dart';
import 'indexed_db_at_key_value_store.dart';
import 'indexed_db_sync_queue_store.dart';

class IndexedDbAtClientStorage extends AtClientStorageBase {
  final String atSign;
  final String enrollmentId;

  IDBDatabase? _db;
  IndexedDbAtKeyValueStore? _keyStore;
  AtSyncQueue? _queue;

  IndexedDbAtClientStorage({
    required this.atSign,
    required this.enrollmentId,
    super.closedByClient,
  }) {
    if (atSign.isEmpty) {
      throw ArgumentError.value(atSign, 'atSign', 'must not be empty');
    }
    if (enrollmentId.isEmpty) {
      throw ArgumentError.value(
          enrollmentId, 'enrollmentId', 'must not be empty');
    }
  }

  static String _dbName(String atSign, String enrollmentId) =>
      'at_client_data::$atSign::$enrollmentId';

  String get dbName => _dbName(atSign, enrollmentId);

  @override
  String get location => 'idb:$dbName';

  IndexedDbAtKeyValueStore get _openKeyStore =>
      _keyStore ?? (throw StateError('storage for $atSign is not open'));

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore => _openKeyStore;

  @override
  AtSyncQueue get syncQueue =>
      _queue ?? (throw StateError('storage for $atSign is not open'));

  @override
  Future<void> openBackend() async {
    if (_db != null) return;

    final request = window.indexedDB.open(dbName, 1);
    request.onupgradeneeded = (Event e) {
      final db = request.result as IDBDatabase;
      if (!db.objectStoreNames.contains('records')) {
        final records = db.createObjectStore('records');
        records.createIndex(
            'expiresAt', 'expiresAt'.toJS, IDBIndexParameters(unique: false));
        records.createIndex('availableAt', 'availableAt'.toJS,
            IDBIndexParameters(unique: false));
      }
      if (!db.objectStoreNames.contains('sync_queue')) {
        db.createObjectStore('sync_queue');
      }
    }.toJS;

    final db = await requestToFuture<IDBDatabase>(request);
    db.onversionchange = ((Event _) => db.close()).toJS;

    final keyStore = IndexedDbAtKeyValueStore(db, atSign);
    await keyStore.initialize();

    final queueStore = await IndexedDbSyncQueueStore.load(db);
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open(store: queueStore);

    _db = db;
    _keyStore = keyStore;
    _queue = queue;
  }

  @override
  Future<void> clearData() async {
    await _openKeyStore.clear();
    await syncQueue.clear();
  }

  @override
  Future<void> closeBackend() async {
    await _queue?.close();
    await _keyStore?.close();
    _db?.close();
    _queue = null;
    _keyStore = null;
    _db = null;
  }

  static Future<void> deleteDatabase(
      {required String atSign, required String enrollmentId}) async {
    final request =
        window.indexedDB.deleteDatabase(_dbName(atSign, enrollmentId));
    await requestToFuture<JSAny?>(request);
  }
}
