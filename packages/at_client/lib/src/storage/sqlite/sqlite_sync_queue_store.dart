import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_persistence_secondary_server/sqlite.dart';

/// A [SyncQueueStore] in a `sync_queue` table on the keystore's own database.
class SqliteSyncQueueStore implements SyncQueueStore {
  SqliteSyncQueueStore(this._db) {
    _db.raw.execute('CREATE TABLE IF NOT EXISTS sync_queue ('
        'atkey TEXT PRIMARY KEY, record TEXT NOT NULL)');
  }
  final SqliteDatabase _db;

  @override
  Iterable<String> get keys => _db.raw
      .select('SELECT atkey FROM sync_queue')
      .map((row) => row['atkey'] as String)
      .toList();

  @override
  String? get(String atKey) {
    final rows = _db.raw
        .select('SELECT record FROM sync_queue WHERE atkey = ?', [atKey]);
    return rows.isEmpty ? null : rows.first['record'] as String;
  }

  @override
  Future<void> put(String atKey, String record) async => _db.raw.execute(
      'INSERT OR REPLACE INTO sync_queue (atkey, record) VALUES (?, ?)',
      [atKey, record]);

  @override
  Future<void> delete(String atKey) async =>
      _db.raw.execute('DELETE FROM sync_queue WHERE atkey = ?', [atKey]);

  @override
  Future<void> clear() async => _db.raw.execute('DELETE FROM sync_queue');

  @override
  Future<void> close() async {}
}
