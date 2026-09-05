import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/sqlite/sqlite_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/sqlite.dart';
import 'package:path/path.dart' as p;

/// Keystore and sync queue in one SQLite database at [dbPath].
///
/// [dbPath] may be `:memory:`, which is what [InMemoryAtClientStorage] passes.
class SqliteAtClientStorage extends AtClientStorageBase {
  SqliteAtClientStorage({required this.atSign, required this.dbPath});

  /// The database under [storagePath] laid out as the upstream factory does.
  SqliteAtClientStorage.under(
      {required this.atSign, required String storagePath})
      : dbPath =
            SqlitePersistenceConfig.clientDefaults(storagePath: storagePath)
                .dbPathFor(atSign);

  final String atSign;
  final String dbPath;

  SqliteDatabase? _db;
  SqliteAtKeyValueStore? _keyStore;
  AtSyncQueue? _queue;

  /// The path SQLite treats as "not a file": a database private to its own
  /// connection.
  static const String inMemoryPath = ':memory:';

  /// The store this points at: the canonicalised database file plus the atSign
  /// its keystore is keyed by, since one file can hold more than one atSign.
  /// An in-memory database is private to the connection that opened it, so it
  /// reports a token unique to this instance instead — two of those share
  /// nothing and must not be refused as one store.
  @override
  String get location => dbPath == inMemoryPath
      ? '$inMemoryPath#${identityHashCode(this)}'
      : '${p.canonicalize(dbPath)}::$atSign';

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      _keyStore ?? (throw StateError('storage for $atSign is not open'));

  @override
  AtSyncQueue get syncQueue =>
      _queue ?? (throw StateError('storage for $atSign is not open'));

  @override
  Future<void> openBackend() async {
    if (_db != null) return;
    final db = SqliteDatabase.open(atSign, dbPath);
    final keyStore = SqliteAtKeyValueStore(db, atSign);
    await keyStore.initialize();
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open(store: SqliteSyncQueueStore(db));
    _db = db;
    _keyStore = keyStore;
    _queue = queue;
  }

  @override
  Future<void> clearData() async {
    await (_keyStore ?? (throw StateError('storage for $atSign is not open')))
        .clear();
    await syncQueue.clear();
  }

  @override
  Future<void> closeBackend() async {
    await _queue?.close();
    await _keyStore?.close();
    _db?.close();
  }
}

/// Keystore and sync queue in memory: a SQLite database that is never written
/// to disk.
class InMemoryAtClientStorage extends SqliteAtClientStorage {
  InMemoryAtClientStorage({required super.atSign})
      : super(dbPath: SqliteAtClientStorage.inMemoryPath);
}
