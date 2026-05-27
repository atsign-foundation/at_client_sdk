// SQLite-backed local store per party.
//
// Two tables:
//   records — key/value store for published bundles (and anything else
//             a party wants to publish for peers to read).
//   inbox   — FIFO queue of incoming notifications written by peers.

import 'package:sqlite3/sqlite3.dart';

class Store {
  final String name;
  final Database db;

  Store._(this.name, this.db);

  static Store open(String name) {
    final db = sqlite3.open('${name}_store.db');
    // WAL allows other processes to read concurrently while we write.
    // Without it, peer plookups deadlock against our writes.
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
        from_name TEXT NOT NULL,
        value TEXT NOT NULL,
        ts INTEGER NOT NULL,
        consumed INTEGER NOT NULL DEFAULT 0
      );
    ''');
    return Store._(name, db);
  }

  /// Read-write handle to a peer's DB (we need to INSERT into their inbox).
  /// WAL must already be enabled by the peer's process (when they opened it).
  static Database openPeer(String peerName) {
    final db = sqlite3.open('${peerName}_store.db');
    db.execute('PRAGMA busy_timeout=5000;');
    return db;
  }

  void close() => db.dispose();
}
