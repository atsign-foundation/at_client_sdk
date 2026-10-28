import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// An [AtKeyValueStore] held in memory, in pure Dart, with the semantics of
/// the SQLite keystore: the same metadata built on write, the same key
/// validation and canonical form, and the same TTL and TTB visibility.
///
/// Each record keeps its metadata as the canonical JSON the SQLite keystore
/// stores, so every read decodes a fresh copy, as a SQLite read does, and
/// records are held in key order, the order the SQLite keystore answers in.
///
/// It keeps no commit log, as a client's keystore keeps none.
class MemoryAtKeyValueStore
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  MemoryAtKeyValueStore(this.atSign);

  /// The atSign owning this store, which the metadata builder stamps as
  /// `createdBy` and `updatedBy`.
  final String atSign;

  final SplayTreeMap<String, _Record> _records = SplayTreeMap();

  final StreamController<KeyStoreChange> _changes =
      StreamController<KeyStoreChange>.broadcast();

  @override
  final List<Future<void> Function(String key, {required bool skipCommit})>
      preRemoveHooks = [];
  @override
  final List<Future<void> Function(String key, {required bool skipCommit})>
      postRemoveHooks = [];

  static const int _maxKeyLength = 255;
  static const int _maxKeyLengthWithoutCached = 248;

  @override
  Future<void> initialize() async {}

  @override
  AtCommitLog? get commitLog => null;

  @override
  set commitLog(AtCommitLog? log) {
    if (log != null) {
      throw UnsupportedError('a memory keystore keeps no commit log');
    }
  }

  @override
  Future<AtData?> get(String key) async {
    final k = canonicalAtKey(key);
    final record = _records[k];
    if (record == null) {
      throw KeyNotFoundException('$key does not exist in keystore');
    }
    return record.toAtData(k);
  }

  @override
  Future<int?> put(String key, AtData value,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validated(key);
    final existing = _records[k];
    if (existing == null) {
      return create(key, value,
          skipCommit: skipCommit, assertedTimestamps: assertedTimestamps);
    }
    _records[k] = _Record.of(
        value.data,
        AtMetadataBuilder(
          atSign: atSign,
          newAtMetaData: value.metaData,
          existingMetaData: existing.metaData,
          asserted: assertedTimestamps,
        ).build());
    _changes.add(KeyUpdated(k));
    return skipCommit ? -1 : null;
  }

  @override
  Future<int?> create(String key, AtData value,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validated(key);
    _checkMaxLength(k);
    _records[k] = _Record.of(
        value.data,
        AtMetadataBuilder(
                atSign: atSign,
                newAtMetaData: value.metaData,
                asserted: assertedTimestamps)
            .build());
    _changes.add(KeyAdded(k));
    return skipCommit ? -1 : null;
  }

  @override
  Future<int?> putAll(String key, AtData value, AtMetaData? metadata) async {
    final k = _validated(key);
    final existing = _records[k];
    _records[k] = _Record.of(
        value.data,
        AtMetadataBuilder(
          atSign: atSign,
          newAtMetaData: metadata,
          existingMetaData: existing?.metaData,
        ).build());
    _changes.add(existing == null ? KeyAdded(k) : KeyUpdated(k));
    return null;
  }

  @override
  Future<int?> putMeta(String key, AtMetaData? metadata,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final k = _validated(key);
    final existing = _records[k];
    _records[k] = _Record.of(
        existing?.value,
        AtMetadataBuilder(
          atSign: atSign,
          newAtMetaData: metadata,
          existingMetaData: existing?.metaData,
          asserted: assertedTimestamps,
        ).build());
    _changes.add(KeyUpdated(k));
    return skipCommit ? -1 : null;
  }

  @override
  Future<AtMetaData?> getMeta(String key) async =>
      _records[canonicalAtKey(key)]?.metaData;

  @override
  Future<void> restore(String key, AtData value) async {
    final k = _validated(key);
    _checkMaxLength(k);
    _records[k] = _Record.of(value.data, value.metaData ?? AtMetaData());
  }

  @override
  Future<int?> remove(String key,
      {bool skipCommit = false, DateTime? deletedAt}) async {
    final lowered = key.toLowerCase();
    for (final hook in preRemoveHooks) {
      await hook(lowered, skipCommit: skipCommit);
    }
    final k = canonicalAtKey(key);
    _records.remove(k);
    _changes.add(KeyRemoved(k));
    for (final hook in postRemoveHooks) {
      await hook(lowered, skipCommit: skipCommit);
    }
    return skipCommit ? -1 : null;
  }

  @override
  Future<int> removeMany(List<String> keys, {bool skipCommit = false}) async {
    final removed = <String>[];
    for (final k in keys.map(canonicalAtKey).toSet()) {
      if (_records.remove(k) != null) removed.add(k);
    }
    for (final k in removed) {
      _changes.add(KeyRemoved(k));
    }
    return removed.length;
  }

  @override
  Future<Map<String, AtData>> getMany(List<String> keys) async => {
        for (final k in keys.map(canonicalAtKey))
          if (_records[k] case final record?) k: record.toAtData(k),
      };

  @override
  Future<bool> exists(String key) async =>
      _records.containsKey(canonicalAtKey(key));

  @override
  Future<Stream<String>> getExpiredKeys() async {
    final now = _nowMillis();
    return Stream.fromIterable([
      for (final MapEntry(:key, :value) in _records.entries)
        if (value.expiresAt case final at? when at <= now) key,
    ]);
  }

  @override
  Future<bool> deleteExpiredKeys() async {
    final expired = await (await getExpiredKeys()).toList();
    for (final k in expired) {
      await remove(k, skipCommit: true);
    }
    return true;
  }

  @override
  Future<DateTime?> nextExpiresAt() async =>
      _millisToDate(_minOf(_records.values.map((r) => r.expiresAt)));

  @override
  Future<Stream<String>> peekExpired({DateTime? asOf, int? limit}) async {
    final cutoff = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final expired = [
      for (final MapEntry(:key, :value) in _records.entries)
        if (value.expiresAt case final at? when at <= cutoff) (key, at),
    ]..sort(_byInstantThenKey);
    final keys = expired.map((e) => e.$1);
    return Stream.fromIterable(limit == null ? keys : keys.take(limit));
  }

  @override
  Future<DateTime?> nextAvailableAt({DateTime? asOf}) async {
    final now = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return _millisToDate(_minOf(_records.values
        .map((r) => r.availableAt)
        .where((at) => at != null && at > now)));
  }

  @override
  Future<Stream<String>> peekNewlyAvailable({
    required DateTime since,
    DateTime? asOf,
    int? limit,
  }) async {
    final lo = since.toUtc().millisecondsSinceEpoch;
    final hi = (asOf ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final available = [
      for (final MapEntry(:key, :value) in _records.entries)
        if (value.availableAt case final at? when at > lo && at <= hi)
          (key, at),
    ]..sort(_byInstantThenKey);
    final keys = available.map((e) => e.$1);
    return Stream.fromIterable(limit == null ? keys : keys.take(limit));
  }

  @override
  Future<Stream<String>> getKeys({String? regex}) async {
    // NOTE: compiled before anything is read, so a bad regex rejects the
    // Future rather than the Stream.
    final re = RegExp(regex ?? '.*');
    final now = _nowMillis();
    return Stream.fromIterable([
      for (final MapEntry(:key, :value) in _records.entries)
        if (value.isVisibleAt(now) && re.hasMatch(key)) key,
    ]);
  }

  @override
  Future<Stream<String>> scanKeys(
    KeyPattern pattern, {
    bool includeExpired = false,
    OrderByKey? orderBy,
    int? limit,
    int? skip,
  }) async {
    final now = _nowMillis();
    final entries = [
      for (final entry in _records.entries)
        if (includeExpired || entry.value.isVisibleAt(now)) entry,
    ];
    _order(entries, orderBy);
    Iterable<String> matched =
        entries.map((e) => e.key).where((k) => _matchesKeyPattern(k, pattern));
    if (skip != null) matched = matched.skip(skip);
    if (limit != null) matched = matched.take(limit);
    return Stream.fromIterable(matched.toList());
  }

  @override
  Stream<KeyStoreChange> get changes => _changes.stream;

  @override
  Future<R> transaction<R>(
      Future<R> Function(KeyStoreTxn<String, AtData, dynamic> txn) body) async {
    final txn = _MemoryKeyStoreTxn(this);
    final result = await body(txn);
    final fired = <KeyStoreChange>[];
    for (final op in txn._ops) {
      if (op.isRemove) {
        if (_records.remove(op.key) != null) fired.add(KeyRemoved(op.key));
      } else {
        final existing = _records[op.key];
        _records[op.key] = _Record.of(
            op.value!.data,
            AtMetadataBuilder(
              atSign: atSign,
              newAtMetaData: op.metadata,
              existingMetaData: existing?.metaData,
            ).build());
        fired.add(existing == null ? KeyAdded(op.key) : KeyUpdated(op.key));
      }
    }
    for (final change in fired) {
      _changes.add(change);
    }
    return result;
  }

  @override
  bool get supportsSnapshots => false;

  @override
  Future<AtKeyValueStoreSnapshot<String, AtData, AtMetaData?>>
      snapshot() async => _MemorySnapshot(this);

  @override
  bool get supportsPathQueries => false;

  @override
  Stream<KeyEntry<String, AtData, AtMetaData?>> queryByPath({
    required KeyPattern keyPattern,
    required Predicate predicate,
    OrderByKey? orderBy,
    int? limit,
    int? skip,
  }) =>
      throw UnsupportedError('a memory keystore answers no path queries; '
          'check supportsPathQueries before calling');

  @override
  Future<KeyStoreStats> stats() async {
    final created = [
      for (final record in _records.values)
        if (record.metaData.createdAt case final at?) at,
    ]..sort();
    return KeyStoreStats(
      totalKeys: _records.length,
      ttlKeys: _records.values.where((r) => r.expiresAt != null).length,
      ttbKeys: _records.values.where((r) => r.availableAt != null).length,
      sizeBytes: _records.values.fold<int>(
          0, (sum, r) => sum + (r.value?.length ?? 0) + r.metadataJson.length),
      oldestCreatedAt: created.isEmpty ? null : created.first,
      newestCreatedAt: created.isEmpty ? null : created.last,
    );
  }

  @override
  Stream<Object> compact(bool dryRun) => const Stream.empty();

  /// Drops every record.
  Future<void> clear() async => _records.clear();

  /// Ends the change stream.
  Future<void> close() async => _changes.close();

  String _validated(String key) {
    final k = canonicalAtKey(key);
    if (AtKey.getKeyType(k, enforceNameSpace: false) == KeyType.invalidKey) {
      throw InvalidAtKeyException('Key $key is invalid');
    }
    return k;
  }

  void _checkMaxLength(String key) {
    final maxLength =
        key.startsWith('cached:') ? _maxKeyLength : _maxKeyLengthWithoutCached;
    if (key.length > maxLength) {
      throw DataStoreException(
          'key length ${key.length} is greater than max allowed $maxLength chars');
    }
  }

  void _order(List<MapEntry<String, _Record>> entries, OrderByKey? orderBy) {
    switch (orderBy) {
      case OrderByKey.byKey:
        entries.sort((a, b) => a.key.compareTo(b.key));
      case OrderByKey.byExpiresAt:
        entries.sort((a, b) => _thenByKey(
            _nullsLast(a.value.expiresAt, b.value.expiresAt), a.key, b.key));
      case OrderByKey.byCreatedAt:
        entries.sort((a, b) => _thenByKey(
            _nullsFirst(a.value.metaData.createdAt?.millisecondsSinceEpoch,
                b.value.metaData.createdAt?.millisecondsSinceEpoch),
            a.key,
            b.key));
      case null:
        break;
    }
  }

  // NOTE: ties break by key because List.sort is not stable, and the SQLite
  // keystore answers ties in key order.
  static int _byInstantThenKey((String, int) a, (String, int) b) =>
      _thenByKey(a.$2.compareTo(b.$2), a.$1, b.$1);

  static int _thenByKey(int order, String a, String b) =>
      order != 0 ? order : a.compareTo(b);

  static int _nullsLast(int? a, int? b) => a == null
      ? (b == null ? 0 : 1)
      : b == null
          ? -1
          : a.compareTo(b);

  static int _nullsFirst(int? a, int? b) => a == null
      ? (b == null ? 0 : -1)
      : b == null
          ? 1
          : a.compareTo(b);

  static int? _minOf(Iterable<int?> values) {
    int? least;
    for (final v in values) {
      if (v != null && (least == null || v < least)) least = v;
    }
    return least;
  }

  static DateTime? _millisToDate(int? millis) => millis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  static int _nowMillis() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static bool _matchesKeyPattern(String keyString, KeyPattern pattern) {
    if (pattern.isUnrestricted) return true;
    final AtKey atKey;
    try {
      atKey = AtKey.fromString(keyString);
    } on Exception {
      return false;
    }
    if (pattern.sharedBy != null &&
        !_atSignEquals(atKey.sharedBy, pattern.sharedBy!)) {
      return false;
    }
    if (pattern.sharedWith != null &&
        !_atSignEquals(atKey.sharedWith, pattern.sharedWith!)) {
      return false;
    }
    if (pattern.namespace != null && atKey.namespace != pattern.namespace) {
      return false;
    }
    if (pattern.idPrefix != null && !atKey.key.startsWith(pattern.idPrefix!)) {
      return false;
    }
    return true;
  }

  static bool _atSignEquals(String? actual, String expected) {
    if (actual == null) return false;
    final a = actual.startsWith('@') ? actual.substring(1) : actual;
    final e = expected.startsWith('@') ? expected.substring(1) : expected;
    return a.toLowerCase() == e.toLowerCase();
  }
}

/// One stored record: its value, its metadata as canonical JSON, and the
/// instants that metadata names, in UTC epoch milliseconds.
class _Record {
  _Record(this.value, this.metadataJson, this.expiresAt, this.availableAt);

  factory _Record.of(String? value, AtMetaData metaData) => _Record(
      value,
      jsonEncode({
        for (final MapEntry(:key, :value) in metaData.toJson().entries)
          if (value != null) key: value,
      }),
      metaData.expiresAt?.toUtc().millisecondsSinceEpoch,
      metaData.availableAt?.toUtc().millisecondsSinceEpoch);

  final String? value;
  final String metadataJson;
  final int? expiresAt;
  final int? availableAt;

  /// A fresh copy of the stored metadata.
  AtMetaData get metaData =>
      AtMetaData().fromJson(jsonDecode(metadataJson) as Map);

  AtData toAtData(String key) => AtData()
    ..data = value
    ..metaData = metaData
    ..key = key;

  bool isVisibleAt(int now) =>
      (availableAt == null || availableAt! <= now) &&
      (expiresAt == null || expiresAt! > now);
}

/// Buffers a transaction's writes; reads see them over live state, and
/// [MemoryAtKeyValueStore.transaction] applies them in order.
class _MemoryKeyStoreTxn implements KeyStoreTxn<String, AtData, dynamic> {
  _MemoryKeyStoreTxn(this._store);

  final MemoryAtKeyValueStore _store;
  final List<_BufferedOp> _ops = [];

  @override
  Future<void> put(String key, AtData value, dynamic metadata) async =>
      _ops.add(
          _BufferedOp.put(canonicalAtKey(key), value, metadata as AtMetaData?));

  @override
  Future<void> remove(String key) async =>
      _ops.add(_BufferedOp.remove(canonicalAtKey(key)));

  @override
  Future<AtData?> get(String key) async {
    final k = canonicalAtKey(key);
    for (final op in _ops.reversed) {
      if (op.key == k) return op.isRemove ? null : op.value;
    }
    return _store._records[k]?.toAtData(k);
  }

  @override
  Future<bool> exists(String key) async => (await get(key)) != null;
}

class _BufferedOp {
  _BufferedOp.put(this.key, this.value, this.metadata) : isRemove = false;
  _BufferedOp.remove(this.key)
      : isRemove = true,
        value = null,
        metadata = null;

  final String key;
  final bool isRemove;
  final AtData? value;
  final AtMetaData? metadata;
}

/// A snapshot that reads live state, as `supportsSnapshots` is false.
class _MemorySnapshot
    implements AtKeyValueStoreSnapshot<String, AtData, AtMetaData?> {
  _MemorySnapshot(this._store);

  final MemoryAtKeyValueStore _store;

  @override
  Future<AtData?> get(String key) async {
    final k = canonicalAtKey(key);
    return _store._records[k]?.toAtData(k);
  }

  @override
  Stream<String> scanKeys(KeyPattern pattern) =>
      Stream.fromIterable(_store._records.keys
          .where((k) => MemoryAtKeyValueStore._matchesKeyPattern(k, pattern))
          .toList());

  @override
  Future<void> release() async {}
}
