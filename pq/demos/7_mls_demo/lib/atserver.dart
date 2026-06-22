// SQLite-backed local store, one per actor name.
// alice opens alice.db, bob opens bob.db — no shared database.

import 'dart:io' show sleep;
import 'package:sqlite3/sqlite3.dart';

class Store {
  final String name;
  final Database db;

  Store._(this.name, this.db);

  static Store open(String name) {
    for (var attempt = 0; attempt < 5; attempt++) {
      Database? db;
      try {
        db = sqlite3.open('${name}.db');
        try { db.execute('PRAGMA journal_mode=WAL;'); } catch (_) {}
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
      } catch (_) {
        db?.dispose();
        if (attempt < 4) sleep(Duration(milliseconds: 80 * (attempt + 1)));
      }
    }
    throw StateError('Could not open ${name}.db after 5 attempts');
  }

  void close() => db.dispose();
}
