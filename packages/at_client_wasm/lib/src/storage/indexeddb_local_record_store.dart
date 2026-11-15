import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:at_client/remote_only.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:web/web.dart';

const _storeName = 'at_client_wasm_local_records';

/// A [LocalRecordStore] persisted to IndexedDB, one database per
/// (atSign, enrollmentId) unless [IndexedDbLocalRecordStore.open] is given a
/// [dbName].
class IndexedDbLocalRecordStore implements LocalRecordStore {
  IndexedDbLocalRecordStore._(this.dbName, this._db);

  /// The name of the IndexedDB database this store reads and writes.
  final String dbName;

  final IDBDatabase _db;

  /// Opens the database for [atSign] and [enrollmentId], creating it on first
  /// use. Without [dbName] the database is `atclient-local:<atSign>:<enrollmentId>`.
  static Future<IndexedDbLocalRecordStore> open({
    required String atSign,
    required String enrollmentId,
    String? dbName,
  }) async {
    final name = dbName ?? 'atclient-local:$atSign:$enrollmentId';
    final request = window.indexedDB.open(name, 1);

    request.onupgradeneeded = (Event event) {
      final db = request.result as IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;

    final db = await _requestToFuture<IDBDatabase>(request);
    // Closes this connection when another connection asks to upgrade or
    // delete the database, so that request is not blocked by it.
    db.onversionchange = (Event event) {
      db.close();
    }.toJS;
    return IndexedDbLocalRecordStore._(name, db);
  }

  @override
  Future<AtData?> get(String key) async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final raw = await _requestToFuture<JSString?>(
        tx.objectStore(_storeName).get(key.toJS));
    return _decode(raw);
  }

  @override
  Future<void> put(String key, AtData value) async {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).put(_encode(value).toJS, key.toJS);
    await _transactionToFuture(tx);
  }

  @override
  Future<void> remove(String key) async {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).delete(key.toJS);
    await _transactionToFuture(tx);
  }

  @override
  Future<List<String>> keys() async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final keys = await _requestToFuture<JSArray<JSString>>(
        tx.objectStore(_storeName).getAllKeys());
    return [for (final key in keys.toDart) key.toDart];
  }

  /// Reads the value at [key], passes it to [apply] synchronously inside the
  /// same readwrite transaction that writes the result, so concurrent updates
  /// over this or another connection to the database serialize.
  @override
  Future<AtData?> update(
      String key, AtData? Function(AtData? current) apply) async {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    final store = tx.objectStore(_storeName);
    AtData? next;
    var applyFailed = false;
    Object? applyError;
    StackTrace? applyStack;

    final get = store.get(key.toJS);
    get.onsuccess = (Event event) {
      try {
        next = apply(_decode(get.result as JSString?));
        if (next == null) {
          store.delete(key.toJS);
        } else {
          store.put(_encode(next!).toJS, key.toJS);
        }
      } catch (e, s) {
        applyFailed = true;
        applyError = e;
        applyStack = s;
        tx.abort();
      }
    }.toJS;

    try {
      await _transactionToFuture(tx);
    } catch (_) {
      if (applyFailed) {
        Error.throwWithStackTrace(applyError!, applyStack!);
      }
      rethrow;
    }
    return next;
  }

  @override
  Future<void> close() async => _db.close();
}

String _encode(AtData value) => jsonEncode({
      'data': value.data,
      if (value.metaData != null) 'metaData': value.metaData!.toJson(),
    });

AtData? _decode(JSString? raw) {
  if (raw == null) return null;
  final json = jsonDecode(raw.toDart) as Map<String, dynamic>;
  final meta = json['metaData'] as Map<String, dynamic>?;
  return AtData()
    ..data = json['data'] as String?
    ..metaData = meta == null ? null : _decodeMetaData(meta);
}

final _placeholderTime =
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toString();

/// [AtMetaData.fromJson] parses `createdAt` and `updatedAt` unconditionally
/// and reads a null `version` as 0, so those nulls are restored after the parse.
AtMetaData _decodeMetaData(Map<String, dynamic> json) {
  final meta = AtMetaData().fromJson({
    ...json,
    'createdAt': json['createdAt'] ?? _placeholderTime,
    'updatedAt': json['updatedAt'] ?? _placeholderTime,
  });
  if (json['createdAt'] == null) meta.createdAt = null;
  if (json['updatedAt'] == null) meta.updatedAt = null;
  if (json['version'] == null) meta.version = null;
  return meta;
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
    if (!completer.isCompleted) {
      completer.completeError(tx.error ?? Exception('IDBTransaction failed'));
    }
  }.toJS;
  tx.onabort = (Event event) {
    if (!completer.isCompleted) {
      completer.completeError(tx.error ?? Exception('IDBTransaction aborted'));
    }
  }.toJS;
  return completer.future;
}
