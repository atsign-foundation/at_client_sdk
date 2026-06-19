// SQLite-backed local store, one per name (alice's store, bob's store).
// Multiple actors of the same name connect to the same file via WAL mode.

import 'package:sqlite3/sqlite3.dart';

class Store {
  final String name;
  final Database db;

  Store._(this.name, this.db);

  static Store open(String name) {
    final db = sqlite3.open('${name}_store.db');
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');
    db.execute('PRAGMA busy_timeout=5000;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS records (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS inbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_device TEXT NOT NULL,
        from_name TEXT NOT NULL,
        from_device TEXT,
        msg_type TEXT NOT NULL,
        value TEXT NOT NULL,
        ts INTEGER NOT NULL,
        consumed_by TEXT NOT NULL DEFAULT '[]'
      );
    ''');
    return Store._(name, db);
  }

  /// Opens a peer name's store (read + write — to put rows in their inbox).
  static Database openPeer(String peerName) {
    final db = sqlite3.open('${peerName}_store.db');
    db.execute('PRAGMA busy_timeout=5000;');
    return db;
  }

  void close() => db.dispose();
}
