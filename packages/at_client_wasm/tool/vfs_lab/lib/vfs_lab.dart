import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' show max;

import 'package:sqlite3/wasm.dart';

export 'package:sqlite3/common.dart' show CommonDatabase;

typedef CommonDatabaseHandle = CommonDatabase;

typedef TxCheck = ({
  bool integrityOk,
  bool counterOk,
  int maxCommit,
  List<int> torn,
});

enum LabVfs {
  indexedDb,
  simpleOpfs,
}

bool get isDedicatedWorker {
  if (globalContext.has('window')) return false;
  if (globalContext.has('DedicatedWorkerGlobalScope')) {
    final ctor = globalContext['DedicatedWorkerGlobalScope'];
    if (ctor != null) {
      return globalContext.instanceof(ctor as JSFunction);
    }
  }
  return false;
}

Future<WasmSqlite3> _loadWasm([Uri? customUri]) async {
  if (customUri != null) {
    return await WasmSqlite3.loadFromUrl(customUri);
  }
  final candidateUris = [
    if (Uri.base.path.contains('/test/'))
      Uri.base.resolve('../build/payload/sqlite3.wasm'),
    Uri.parse('sqlite3.wasm'),
    Uri.parse('build/payload/sqlite3.wasm'),
  ];
  for (final uri in candidateUris) {
    try {
      return await WasmSqlite3.loadFromUrl(uri);
    } catch (_) {}
  }
  return await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
}

final _idbFileSystems = Expando<IndexedDbFileSystem>();

/// Awaits the IndexedDB VFS's pending writes for [db]; a no-op for SimpleOPFS,
/// whose writes are synchronous. [IndexedDbFileSystem] persists asynchronously,
/// so a page that closes (or dies) before this completes loses its tail.
Future<void> flushLabDb(CommonDatabase db) async =>
    _idbFileSystems[db]?.flush();

/// Opens a SQLite-wasm database over the selected VFS.
///
/// For [LabVfs.simpleOpfs], [name] is the OPFS directory; a distinct [vfsName]
/// lets one worker register several such file systems.
///
/// Throws [StateError] if [LabVfs.simpleOpfs] is requested outside a dedicated worker.
Future<CommonDatabaseHandle> openLabDb({
  required LabVfs vfs,
  required String name,
  String? vfsName,
  Uri? wasmUri,
}) async {
  if (vfs == LabVfs.simpleOpfs) {
    if (!isDedicatedWorker) {
      throw StateError('simpleOpfs requires a dedicated worker');
    }
    final sqlite3 = await _loadWasm(wasmUri);
    final fs = await SimpleOpfsFileSystem.loadFromStorage(name,
        vfsName: vfsName ?? 'simple-opfs');
    sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
    return sqlite3.open('/database', vfs: fs.name);
  }

  // LabVfs.indexedDb
  final sqlite3 = await _loadWasm(wasmUri);
  final fs = await IndexedDbFileSystem.open(dbName: name);
  sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
  final dbPath = name.startsWith('/') ? name : '/$name';
  final db = sqlite3.open(dbPath, vfs: fs.name);
  _idbFileSystems[db] = fs;
  return db;
}

// DDL copied verbatim from package at_persistence_secondary_server (version 5.3.0),
// file lib/src/impl/sqlite/sqlite_schema.dart
const List<String> schemaStatements = [
  'PRAGMA journal_mode = TRUNCATE;',
  'PRAGMA synchronous = NORMAL;',
  'PRAGMA busy_timeout = 5000;',
  '''
CREATE TABLE IF NOT EXISTS at_data (
  atkey        TEXT PRIMARY KEY NOT NULL,
  value        TEXT,
  metadata     TEXT NOT NULL,
  expires_at   INTEGER,
  available_at INTEGER,
  refresh_at   INTEGER
) WITHOUT ROWID;
''',
  'CREATE INDEX IF NOT EXISTS at_data_expires_at ON at_data (expires_at) WHERE expires_at IS NOT NULL;',
  'CREATE INDEX IF NOT EXISTS at_data_available_at ON at_data (available_at) WHERE available_at IS NOT NULL;',
  'CREATE INDEX IF NOT EXISTS at_data_refresh_at ON at_data (refresh_at) WHERE refresh_at IS NOT NULL;',
  '''
CREATE TABLE IF NOT EXISTS commit_log (
  atkey     TEXT PRIMARY KEY NOT NULL,
  commit_id INTEGER NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('+', '#', '*', '-')),
  op_time   INTEGER
) WITHOUT ROWID;
''',
  'CREATE UNIQUE INDEX IF NOT EXISTS commit_log_commit_id ON commit_log (commit_id);',
  '''
CREATE TABLE IF NOT EXISTS counters (
  name  TEXT PRIMARY KEY NOT NULL,
  value INTEGER NOT NULL
) WITHOUT ROWID;
''',
  "INSERT OR IGNORE INTO counters (name, value) VALUES ('last_commit_id', 0);",
  '''
CREATE TABLE IF NOT EXISTS notifications (
  id                    TEXT PRIMARY KEY NOT NULL,
  payload               TEXT NOT NULL,
  notification_datetime INTEGER NOT NULL,
  type                  TEXT NOT NULL,
  status                TEXT NOT NULL,
  expires_at            INTEGER
) WITHOUT ROWID;
''',
  'CREATE INDEX IF NOT EXISTS notifications_datetime ON notifications (notification_datetime);',
  'CREATE INDEX IF NOT EXISTS notifications_status ON notifications (status);',
  'CREATE INDEX IF NOT EXISTS notifications_expires_at ON notifications (expires_at) WHERE expires_at IS NOT NULL;',
  '''
CREATE TABLE IF NOT EXISTS access_log (
  seq         INTEGER PRIMARY KEY,
  from_atsign TEXT,
  request_at  INTEGER NOT NULL,
  verb_name   TEXT,
  lookup_key  TEXT
);
''',
  'CREATE INDEX IF NOT EXISTS access_log_request_at ON access_log (request_at);',
  'PRAGMA user_version = 1;',
];

/// Applies the canonical schema to [db].
void applySchema(CommonDatabase db) {
  for (final statement in schemaStatements) {
    db.execute(statement);
  }
}

/// One synced write, as the real keystore does it: the keystore row, its
/// commit-log row, and the `last_commit_id` counter bump, all bearing [i], in a
/// single transaction. This is the atomicity unit crash tests check.
Future<void> writeTx(CommonDatabase db, int i) async {
  db.execute('BEGIN TRANSACTION;');
  try {
    db.execute(
      'INSERT OR REPLACE INTO at_data (atkey, value, metadata) VALUES (?, ?, ?);',
      ['key_$i', 'val_$i', '{}'],
    );
    db.execute(
      'INSERT OR REPLACE INTO commit_log (atkey, commit_id, operation, op_time) VALUES (?, ?, ?, ?);',
      ['key_$i', i, '+', i],
    );
    db.execute(
      "UPDATE counters SET value = ? WHERE name = 'last_commit_id';",
      [i],
    );
    db.execute('COMMIT;');
  } catch (_) {
    db.execute('ROLLBACK;');
    rethrow;
  }
}

Set<int> _ints(CommonDatabase db, String sql) =>
    {for (final row in db.select(sql)) row.values.first as int};

/// Checks the [writeTx] invariant: SQLite's own integrity check passes, every
/// id is in both `at_data` and `commit_log` (else it is `torn`), and the
/// counter equals the highest commit id (else `counterOk` is false).
TxCheck checkInvariant(CommonDatabase db) {
  final keyIds =
      _ints(db, 'SELECT CAST(substr(atkey, 5) AS INTEGER) FROM at_data;');
  final commitIds = _ints(db, 'SELECT commit_id FROM commit_log;');
  final counter =
      _ints(db, "SELECT value FROM counters WHERE name = 'last_commit_id';")
          .single;
  final maxCommit = commitIds.isEmpty ? 0 : commitIds.reduce(max);

  return (
    integrityOk:
        db.select('PRAGMA integrity_check;').first.values.first == 'ok',
    counterOk: counter == maxCommit,
    maxCommit: maxCommit,
    torn: keyIds
        .difference(commitIds)
        .union(commitIds.difference(keyIds))
        .toList()
      ..sort(),
  );
}
