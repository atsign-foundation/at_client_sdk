import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:at_client/at_client.dart' hide Predicate;
import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart' hide KeyType;

import 'idb_util.dart';

@JS()
extension type IdbRecord._(JSObject _) implements JSObject {
  external factory IdbRecord({
    String json,
    int? expiresAt,
    int? availableAt,
  });

  external String get json;
  external int? get expiresAt;
  external int? get availableAt;

  /// True when the record is born (`availableAt < now`) and not expired
  /// (`expiresAt >= now`); a null bound is unbounded.
  bool isVisibleAt(int now) {
    final expires = expiresAt;
    final available = availableAt;
    return (expires == null || expires >= now) &&
        (available == null || available < now);
  }
}

class IndexedDbAtKeyValueStore
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final IDBDatabase _db;
  final String atSign;

  final StreamController<KeyStoreChange> _changes =
      StreamController<KeyStoreChange>.broadcast();

  @override
  final List<Future<void> Function(String key, {required bool skipCommit})>
      preRemoveHooks = [];

  @override
  final List<Future<void> Function(String key, {required bool skipCommit})>
      postRemoveHooks = [];

  static const int maxKeyLength = 255;
  static const int maxKeyLengthWithoutCached = 248;

  IndexedDbAtKeyValueStore(this._db, this.atSign);

  @override
  Future<void> initialize() async {}

  @override
  AtCommitLog? get commitLog => null;

  @override
  set commitLog(AtCommitLog? log) {}

  String _normalize(String key) => canonicalAtKey(key);

  String _validateAndNormalize(String key) {
    final normalized = _normalize(key);
    if (AtKey.getKeyType(normalized, enforceNameSpace: false) ==
        KeyType.invalidKey) {
      throw InvalidAtKeyException('Key $key is invalid');
    }
    return normalized;
  }

  void _checkMaxLength(String key) {
    final maxLength =
        key.startsWith('cached:') ? maxKeyLength : maxKeyLengthWithoutCached;
    if (key.length > maxLength) {
      throw DataStoreException(
          'key length ${key.length} is greater than max allowed $maxLength chars');
    }
  }

  IdbRecord _toRecord(AtData data) {
    final m = data.metaData;
    int? expiresAt;
    int? availableAt;
    if (m != null) {
      if (m.expiresAt != null) {
        expiresAt = m.expiresAt!.toUtc().millisecondsSinceEpoch;
      }
      if (m.availableAt != null) {
        availableAt = m.availableAt!.toUtc().millisecondsSinceEpoch;
      }
    }
    return IdbRecord(
      json: jsonEncode(data.toJson()),
      expiresAt: expiresAt,
      availableAt: availableAt,
    );
  }

  AtData _fromRecord(IdbRecord record, String key) {
    final data =
        AtData().fromJson(jsonDecode(record.json) as Map<String, dynamic>);
    data.key = key;
    return data;
  }

  @override
  Future<AtData?> get(String key) async {
    final k = _normalize(key);
    final tx = _db.transaction('records'.toJS, 'readonly');
    final store = tx.objectStore('records');
    final request = store.get(k.toJS);
    final jsResult = await requestToFuture<JSAny?>(request);
    await transactionToFuture(tx);
    if (jsResult == null) {
      throw KeyNotFoundException('$key does not exist in keystore');
    }
    return _fromRecord(jsResult as IdbRecord, k);
  }

  AtData _built(String? data, AtMetaData? newMetaData, AtData? existing,
          AtAssertedTimestamps? asserted) =>
      AtData()
        ..data = data
        ..metaData = AtMetadataBuilder(
          atSign: atSign,
          newAtMetaData: newMetaData,
          existingMetaData: existing?.metaData,
          asserted: asserted,
        ).build();

  /// Reads [k] and writes `next(existing)` in one readwrite transaction,
  /// completing with the record that was there before, or null.
  ///
  /// [next] runs synchronously inside the read's success callback, so the
  /// transaction never sees a non-IDB await.
  Future<AtData?> _readModifyWrite(
      String k, AtData Function(AtData? existing) next) async {
    final tx = _db.transaction('records'.toJS, 'readwrite');
    final store = tx.objectStore('records');
    final read = store.get(k.toJS);
    AtData? existing;
    Object? failure;
    StackTrace? failureTrace;
    read.onsuccess = (Event _) {
      try {
        final result = read.result;
        existing = result == null ? null : _fromRecord(result as IdbRecord, k);
        store.put(_toRecord(next(existing)) as JSObject, k.toJS);
      } catch (e, st) {
        failure = e;
        failureTrace = st;
        tx.abort();
      }
    }.toJS;
    try {
      await transactionToFuture(tx);
    } catch (_) {
      if (failure != null) Error.throwWithStackTrace(failure!, failureTrace!);
      rethrow;
    }
    return existing;
  }

  @override
  Future<int?> put(String key, AtData value,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validateAndNormalize(key);
    _checkMaxLength(k);
    final existing = await _readModifyWrite(
        k, (e) => _built(value.data, value.metaData, e, assertedTimestamps));
    _changes.add(existing == null ? KeyAdded(k) : KeyUpdated(k));
    return skipCommit ? -1 : 0;
  }

  @override
  Future<int?> create(String key, AtData value,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validateAndNormalize(key);
    _checkMaxLength(k);
    final record =
        _toRecord(_built(value.data, value.metaData, null, assertedTimestamps));
    final tx = _db.transaction('records'.toJS, 'readwrite');
    tx.objectStore('records').put(record as JSObject, k.toJS);
    await transactionToFuture(tx);

    _changes.add(KeyAdded(k));
    return skipCommit ? -1 : 0;
  }

  @override
  Future<int?> putAll(String key, AtData value, AtMetaData? metadata) async {
    final k = _validateAndNormalize(key);
    final existing =
        await _readModifyWrite(k, (e) => _built(value.data, metadata, e, null));
    _changes.add(existing == null ? KeyAdded(k) : KeyUpdated(k));
    return 0;
  }

  @override
  Future<int?> putMeta(String key, AtMetaData? metadata,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validateAndNormalize(key);
    await _readModifyWrite(
        k, (e) => _built(e?.data, metadata, e, assertedTimestamps));
    _changes.add(KeyUpdated(k));
    return skipCommit ? -1 : 0;
  }

  @override
  Future<AtMetaData?> getMeta(String key) async {
    try {
      return (await get(key))?.metaData;
    } on KeyNotFoundException {
      return null;
    }
  }

  @override
  Future<void> restore(String key, AtData value) async {
    final k = _validateAndNormalize(key);
    _checkMaxLength(k);

    final record = _toRecord(value);
    final tx = _db.transaction('records'.toJS, 'readwrite');
    tx.objectStore('records').put(record as JSObject, k.toJS);
    await transactionToFuture(tx);
  }

  @override
  Future<int?> remove(String key,
      {bool skipCommit = false, DateTime? deletedAt}) async {
    final lowered = key.toLowerCase();
    for (final hook in preRemoveHooks) {
      await hook(lowered, skipCommit: skipCommit);
    }

    final k = _normalize(key);
    final tx = _db.transaction('records'.toJS, 'readwrite');
    tx.objectStore('records').delete(k.toJS);
    await transactionToFuture(tx);

    _changes.add(KeyRemoved(k));

    for (final hook in postRemoveHooks) {
      await hook(lowered, skipCommit: skipCommit);
    }

    return skipCommit ? -1 : 0;
  }

  @override
  Future<int> removeMany(List<String> keys, {bool skipCommit = false}) async {
    final normalized = keys.map(_normalize).toSet().toList();
    if (normalized.isEmpty) return 0;

    final toFire = <String>[];
    final tx = _db.transaction('records'.toJS, 'readwrite');
    final store = tx.objectStore('records');
    for (final k in normalized) {
      final probe = store.getKey(k.toJS);
      probe.onsuccess = (Event _) {
        if (probe.result == null) return;
        store.delete(k.toJS);
        toFire.add(k);
      }.toJS;
    }
    await transactionToFuture(tx);

    for (final k in toFire) {
      _changes.add(KeyRemoved(k));
    }
    return toFire.length;
  }

  @override
  Future<Map<String, AtData>> getMany(List<String> keys) async {
    if (keys.isEmpty) return {};
    final normalized = keys.map(_normalize).toList();

    final tx = _db.transaction('records'.toJS, 'readonly');
    final store = tx.objectStore('records');

    final result = <String, AtData>{};
    final requests = <String, IDBRequest>{};

    for (final k in normalized) {
      requests[k] = store.get(k.toJS);
    }

    await transactionToFuture(tx);

    for (final k in normalized) {
      final jsResult = requests[k]!.result;
      if (jsResult != null) {
        result[k] = _fromRecord(jsResult as IdbRecord, k);
      }
    }

    return result;
  }

  @override
  Future<bool> exists(String key) async {
    final k = _normalize(key);
    final tx = _db.transaction('records'.toJS, 'readonly');
    final request = tx.objectStore('records').count(k.toJS);
    await transactionToFuture(tx);
    return (request.result as JSNumber).toDartInt > 0;
  }

  @override
  Future<Stream<String>> getExpiredKeys() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final tx = _db.transaction('records'.toJS, 'readonly');
    final index = tx.objectStore('records').index('expiresAt');

    // expiresAt <= now
    final range = IDBKeyRange.upperBound(now.toJS);
    final request = index.getAllKeys(range);

    await transactionToFuture(tx);

    final keys = request.result as JSArray;
    final dartKeys = <String>[];
    for (var i = 0; i < keys.length; i++) {
      dartKeys.add((keys[i] as JSString).toDart);
    }
    return Stream.fromIterable(dartKeys);
  }

  @override
  Future<bool> deleteExpiredKeys() async {
    final expiredStream = await getExpiredKeys();
    final keys = await expiredStream.toList();
    for (final k in keys) {
      await remove(k, skipCommit: true);
    }
    return true;
  }

  @override
  Future<DateTime?> nextExpiresAt() async {
    final tx = _db.transaction('records'.toJS, 'readonly');
    final index = tx.objectStore('records').index('expiresAt');

    // open cursor to get the first one (which is the minimum due to index sorting)
    final request = index.openCursor();
    await transactionToFuture(tx);

    final cursor = request.result as IDBCursorWithValue?;
    if (cursor != null) {
      final record = cursor.value as IdbRecord;
      if (record.expiresAt != null) {
        return DateTime.fromMillisecondsSinceEpoch(record.expiresAt!,
            isUtc: true);
      }
    }
    return null;
  }

  @override
  Future<Stream<String>> peekExpired({DateTime? asOf, int? limit}) async {
    final cutoff = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final tx = _db.transaction('records'.toJS, 'readonly');
    final index = tx.objectStore('records').index('expiresAt');

    final range = IDBKeyRange.upperBound(cutoff.toJS);
    // Limit is supported by getAllKeys(query, count)
    final request = limit != null
        ? index.getAllKeys(range, limit)
        : index.getAllKeys(range);

    await transactionToFuture(tx);

    final keys = request.result as JSArray;
    final dartKeys = <String>[];
    for (var i = 0; i < keys.length; i++) {
      dartKeys.add((keys[i] as JSString).toDart);
    }
    return Stream.fromIterable(dartKeys);
  }

  @override
  Future<DateTime?> nextAvailableAt({DateTime? asOf}) async {
    final now = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final tx = _db.transaction('records'.toJS, 'readonly');
    final index = tx.objectStore('records').index('availableAt');

    final range =
        IDBKeyRange.lowerBound(now.toJS, true); // true = open lower bound (>)
    final request = index.openCursor(range);
    await transactionToFuture(tx);

    final cursor = request.result as IDBCursorWithValue?;
    if (cursor != null) {
      final record = cursor.value as IdbRecord;
      if (record.availableAt != null) {
        return DateTime.fromMillisecondsSinceEpoch(record.availableAt!,
            isUtc: true);
      }
    }
    return null;
  }

  @override
  Future<Stream<String>> peekNewlyAvailable({
    required DateTime since,
    DateTime? asOf,
    int? limit,
  }) async {
    final lo = since.toUtc().millisecondsSinceEpoch;
    final hi = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;

    final tx = _db.transaction('records'.toJS, 'readonly');
    final index = tx.objectStore('records').index('availableAt');

    // lo < availableAt <= hi
    final range = IDBKeyRange.bound(lo.toJS, hi.toJS, true, false);
    final request = limit != null
        ? index.getAllKeys(range, limit)
        : index.getAllKeys(range);

    await transactionToFuture(tx);

    final keys = request.result as JSArray;
    final dartKeys = <String>[];
    for (var i = 0; i < keys.length; i++) {
      dartKeys.add((keys[i] as JSString).toDart);
    }
    return Stream.fromIterable(dartKeys);
  }

  @override
  Future<Stream<String>> getKeys({String? regex}) async {
    final re = RegExp(regex ?? '.*'); // Eager validation
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    final tx = _db.transaction('records'.toJS, 'readonly');
    final store = tx.objectStore('records');

    final request = store.openCursor();

    final completer = Completer<List<String>>();
    final candidateKeys = <String>[];

    request.onsuccess = (Event e) {
      final cursor = request.result as IDBCursorWithValue?;
      if (cursor != null) {
        final record = cursor.value as IdbRecord;
        final key = (cursor.key as JSString).toDart;

        if (record.isVisibleAt(now)) {
          candidateKeys.add(key);
        }

        cursor.continue_();
      } else {
        completer.complete(candidateKeys);
      }
    }.toJS;

    request.onerror = (Event e) {
      completer.completeError(request.error ?? Exception('Cursor failed'));
    }.toJS;

    final candidates = await completer.future;
    final matched = candidates.where((k) => re.hasMatch(k)).toList();
    return Stream.fromIterable(matched);
  }

  @override
  Future<Stream<String>> scanKeys(
    KeyPattern pattern, {
    bool includeExpired = false,
    OrderByKey? orderBy,
    int? limit,
    int? skip,
  }) async {
    throw UnsupportedError('scanKeys is not supported');
  }

  @override
  Stream<KeyStoreChange> get changes => _changes.stream;

  @override
  Future<R> transaction<R>(
      Future<R> Function(KeyStoreTxn<String, AtData, dynamic> txn) body) async {
    throw UnsupportedError('transaction is not supported');
  }

  @override
  bool get supportsSnapshots => false;

  @override
  Future<AtKeyValueStoreSnapshot<String, AtData, AtMetaData?>>
      snapshot() async {
    throw UnsupportedError('snapshot is not supported');
  }

  @override
  bool get supportsPathQueries => false;

  @override
  Stream<KeyEntry<String, AtData, AtMetaData?>> queryByPath({
    required KeyPattern keyPattern,
    required Predicate predicate,
    OrderByKey? orderBy,
    int? limit,
    int? skip,
  }) {
    throw UnsupportedError('queryByPath is not supported');
  }

  @override
  Future<KeyStoreStats> stats() async {
    throw UnsupportedError('stats is not supported');
  }

  @override
  Stream<Object> compact(bool dryRun) => const Stream.empty();

  Future<void> clear() async {
    final tx = _db.transaction('records'.toJS, 'readwrite');
    tx.objectStore('records').clear();
    await transactionToFuture(tx);
  }

  Future<void> close() async {}
}
