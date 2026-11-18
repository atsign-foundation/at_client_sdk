import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart' show PasskeyHintStore;
import 'package:web/web.dart';

/// A [PasskeyHintStore] that persists to IndexedDB.
///
/// Holds a passkey's credential id and the enrollment id per atSign, and no
/// key material.
class IndexedDbHintStore implements PasskeyHintStore {
  IndexedDbHintStore._(this._dbName, IDBDatabase db) : _db = db {
    _watchVersionChange(db);
  }

  /// A store over an already open [db], for tests.
  ///
  /// It cannot reopen itself once [db] is closed.
  IndexedDbHintStore.forDatabase(IDBDatabase db)
      : _db = db,
        _dbName = null;

  /// The database name, or null when the store cannot reopen.
  final String? _dbName;

  /// The open connection, or null after it was closed for a newer version.
  IDBDatabase? _db;

  Future<IDBDatabase>? _reopening;
  bool _closed = false;

  static const _credentialsStore = 'at_client_wasm_credentials';
  static const _enrollmentsStore = 'at_client_wasm_enrollments';
  static const _defaultDbName = 'at_client_wasm';

  /// The object stores earlier versions created, which an upgrade deletes
  /// with whatever they hold.
  static const _retiredStores = [
    'at_client_wasm_pending',
    'at_client_wasm_keys'
  ];

  /// The schema version this code creates; a database already at a higher
  /// version is opened as it is.
  static const _schemaVersion = 4;

  /// Opens the IndexedDB instance, running migrations if necessary.
  ///
  /// Fails with [IndexedDbException] when another connection holds the
  /// database open and blocks an upgrade.
  static Future<IndexedDbHintStore> open(
      {String dbName = _defaultDbName}) async {
    final db = await _openDatabase(dbName, _schemaVersion);
    return IndexedDbHintStore._(dbName, db);
  }

  static Future<IDBDatabase> _openDatabase(String dbName, int? version) {
    final request = version == null
        ? window.indexedDB.open(dbName)
        : window.indexedDB.open(dbName, version);

    request.onupgradeneeded = (Event event) {
      final db = request.result as IDBDatabase;
      for (final retired in _retiredStores) {
        if (db.objectStoreNames.contains(retired)) {
          db.deleteObjectStore(retired);
        }
      }
      if (!db.objectStoreNames.contains(_credentialsStore)) {
        db.createObjectStore(_credentialsStore);
      }
      if (!db.objectStoreNames.contains(_enrollmentsStore)) {
        db.createObjectStore(_enrollmentsStore);
      }
    }.toJS;

    final opened = Completer<IDBDatabase>();
    request.onsuccess = (Event event) {
      final db = request.result as IDBDatabase;
      if (opened.isCompleted) {
        // The open was reported as blocked; nobody is waiting for it.
        db.close();
      } else {
        opened.complete(db);
      }
    }.toJS;
    request.onerror = (Event event) {
      if (opened.isCompleted) return;
      opened.completeError(
          IndexedDbException('open failed: ${request.error?.message}'));
    }.toJS;
    request.onblocked = (Event event) {
      if (opened.isCompleted) return;
      opened.completeError(
          IndexedDbException('open blocked by another connection'));
    }.toJS;
    return opened.future;
  }

  /// Closes [db] when another connection asks to change the database version
  /// and forgets it, so the next operation reopens.
  void _watchVersionChange(IDBDatabase db) {
    db.onversionchange = (Event event) {
      db.close();
      if (identical(_db, db)) _db = null;
    }.toJS;
  }

  Future<IDBDatabase> _connection() {
    if (_closed) {
      return Future.error(IndexedDbException('store is closed'));
    }
    final db = _db;
    if (db != null) return Future.value(db);
    final name = _dbName;
    if (name == null) {
      return Future.error(IndexedDbException('database connection is closed'));
    }
    return _reopening ??= _reopen(name);
  }

  Future<IDBDatabase> _reopen(String name) async {
    try {
      // No version: open whatever version the other connection left.
      final db = await _openDatabase(name, null);
      if (_closed) {
        db.close();
        throw IndexedDbException('store is closed');
      }
      _watchVersionChange(db);
      return _db = db;
    } finally {
      _reopening = null;
    }
  }

  Future<void> _put(String storeName, String atSign, List<int> bytes) async {
    final db = await _connection();
    final tx = db.transaction(storeName.toJS, 'readwrite');
    final store = tx.objectStore(storeName);
    final copy = Uint8List.fromList(bytes);
    store.put(copy.toJS, atSign.toJS);
    await _transactionToFuture(tx);
  }

  Future<Uint8List?> _get(String storeName, String atSign) async {
    final db = await _connection();
    final tx = db.transaction(storeName.toJS, 'readonly');
    final store = tx.objectStore(storeName);
    final request = store.get(atSign.toJS);
    final result = await _requestToFuture<JSAny?>(request);
    if (result == null) return null;
    final jsArray = result as JSUint8Array;
    return Uint8List.fromList(jsArray.toDart);
  }

  /// Stores a passkey [id] associated with the [atSign].
  @override
  Future<void> putCredentialId(String atSign, Uint8List id) =>
      _put(_credentialsStore, atSign, id);

  /// Stores the passkey [credentialId] and the [enrollmentId] of the [atSign]
  /// in one transaction: either both are stored or, when the transaction
  /// fails or is aborted, neither.
  @override
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    final db = await _connection();
    final tx = db.transaction(
        [_credentialsStore.toJS, _enrollmentsStore.toJS].toJS, 'readwrite');
    final done = _transactionToFuture(tx);
    try {
      tx
          .objectStore(_credentialsStore)
          .put(Uint8List.fromList(credentialId).toJS, atSign.toJS);
      tx
          .objectStore(_enrollmentsStore)
          .put(Uint8List.fromList(utf8.encode(enrollmentId)).toJS, atSign.toJS);
    } on Object {
      // A request that throws does not end the transaction: without the abort
      // the put before it would commit alone.
      tx.abort();
      // The aborted transaction's own failure; the error rethrown is the one that matters.
      await done.catchError((_) {});
      rethrow;
    }
    await done;
  }

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

  /// Closes the database connection; the store does not reopen afterwards.
  void close() {
    _closed = true;
    _db?.close();
    _db = null;
  }
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
    if (completer.isCompleted) return;
    completer.completeError(IndexedDbException(
        'transaction failed: ${tx.error?.message ?? 'unknown error'}'));
  }.toJS;
  tx.onabort = (Event event) {
    if (completer.isCompleted) return;
    completer.completeError(IndexedDbException(
        'transaction aborted: ${tx.error?.message ?? 'unknown reason'}'));
  }.toJS;
  return completer.future;
}

/// Thrown when an IndexedDB open or transaction does not complete.
class IndexedDbException implements Exception {
  /// Creates the exception with [message].
  IndexedDbException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'IndexedDbException: $message';
}
