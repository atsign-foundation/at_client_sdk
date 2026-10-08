import 'package:at_client/src/storage/sqlite/sqlite_at_client_storage.dart';

/// Keystore and sync queue in memory: a SQLite database that is never written
/// to disk.
class InMemoryAtClientStorage extends SqliteAtClientStorage {
  InMemoryAtClientStorage({required super.atSign, super.closedByClient})
      : super(dbPath: SqliteAtClientStorage.inMemoryPath);
}
