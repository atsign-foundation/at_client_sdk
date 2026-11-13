import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'key_bytes_store.dart';

/// A [KeyBytesStore], [CredentialHintStore] and [EnrollmentIdStore] that
/// persists to IndexedDB.
class IndexedDbKeyBytesStore
    implements KeyBytesStore, CredentialHintStore, EnrollmentIdStore {
  IndexedDbKeyBytesStore._(this._db);

  final IDBDatabase _db;

  static const _keysStore = 'at_client_wasm_keys';
  static const _credentialsStore = 'at_client_wasm_credentials';
  static const _enrollmentsStore = 'at_client_wasm_enrollments';
  static const _dbName = 'at_client_wasm';

  /// Opens the IndexedDB instance, running migrations if necessary.
  static Future<IndexedDbKeyBytesStore> open({String dbName = _dbName}) async {
    final request = window.indexedDB.open(dbName, 2);

    request.onupgradeneeded = (Event event) {
      final db = request.result as IDBDatabase;
      if (!db.objectStoreNames.contains(_keysStore)) {
        db.createObjectStore(_keysStore);
      }
      if (!db.objectStoreNames.contains(_credentialsStore)) {
        db.createObjectStore(_credentialsStore);
      }
      if (!db.objectStoreNames.contains(_enrollmentsStore)) {
        db.createObjectStore(_enrollmentsStore);
      }
    }.toJS;

    final db = await _requestToFuture<IDBDatabase>(request);
    return IndexedDbKeyBytesStore._(db);
  }

  Future<void> _put(String storeName, String atSign, List<int> bytes) async {
    final tx = _db.transaction(storeName.toJS, 'readwrite');
    final store = tx.objectStore(storeName);
    final copy = Uint8List.fromList(bytes);
    store.put(copy.toJS, atSign.toJS);
    await _transactionToFuture(tx);
  }

  Future<Uint8List?> _get(String storeName, String atSign) async {
    final tx = _db.transaction(storeName.toJS, 'readonly');
    final store = tx.objectStore(storeName);
    final request = store.get(atSign.toJS);
    final result = await _requestToFuture<JSAny?>(request);
    if (result == null) return null;
    final jsArray = result as JSUint8Array;
    return Uint8List.fromList(jsArray.toDart);
  }

  /// Writes key envelope [bytes] for the [atSign] to the store.
  @override
  Future<void> put(String atSign, Uint8List bytes) =>
      _put(_keysStore, atSign, bytes);

  /// Reads the key envelope bytes for [atSign] from the store.
  @override
  Future<Uint8List?> get(String atSign) => _get(_keysStore, atSign);

  /// Deletes all keys, credentials and enrollment ids associated with
  /// [atSign].
  @override
  Future<void> delete(String atSign) async {
    final tx = _db.transaction(
        [_keysStore.toJS, _credentialsStore.toJS, _enrollmentsStore.toJS].toJS,
        'readwrite');
    tx.objectStore(_keysStore).delete(atSign.toJS);
    tx.objectStore(_credentialsStore).delete(atSign.toJS);
    tx.objectStore(_enrollmentsStore).delete(atSign.toJS);
    await _transactionToFuture(tx);
  }

  /// Stores a passkey [id] associated with the [atSign].
  @override
  Future<void> putCredentialId(String atSign, Uint8List id) =>
      _put(_credentialsStore, atSign, id);

  /// Retrieves the passkey credential ID for the [atSign].
  @override
  Future<Uint8List?> credentialId(String atSign) =>
      _get(_credentialsStore, atSign);

  /// Stores the enrollment [id] associated with the [atSign].
  @override
  Future<void> putEnrollmentId(String atSign, String id) =>
      _put(_enrollmentsStore, atSign, utf8.encode(id));

  /// Retrieves the enrollment id for the [atSign].
  @override
  Future<String?> enrollmentId(String atSign) async {
    final bytes = await _get(_enrollmentsStore, atSign);
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Closes the database connection.
  void close() => _db.close();
}

Future<T> _requestToFuture<T>(IDBRequest request) {
  final completer = Completer<T>();
  request.onsuccess = (Event event) {
    // ignore: invalid_runtime_check_with_js_interop_types
    completer.complete(request.result as T);
  }.toJS;
  request.onerror = (Event event) {
    completer.completeError(request.error ?? Exception('IDBRequest failed'));
  }.toJS;
  return completer.future;
}

Future<void> _transactionToFuture(IDBTransaction tx) {
  final completer = Completer<void>();
  tx.oncomplete = (Event event) {
    completer.complete();
  }.toJS;
  tx.onerror = (Event event) {
    completer.completeError(tx.error ?? Exception('IDBTransaction failed'));
  }.toJS;
  return completer.future;
}
