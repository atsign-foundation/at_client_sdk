// ignore_for_file: avoid_relative_lib_imports
import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:web/web.dart' as web;

import '../vfs_lab/lib/vfs_lab.dart';
import 'common.dart';

/// Minimal keystore adapter exercising get/put/remove/getKeys over the real
/// schema from at_persistence_secondary_server.
class SqliteKeystoreAdapter {
  final CommonDatabase db;

  SqliteKeystoreAdapter(this.db);

  void put(String key, String value, {String metadata = '{}'}) {
    db.execute('BEGIN TRANSACTION;');
    try {
      db.execute(
        'INSERT OR REPLACE INTO at_data (atkey, value, metadata) VALUES (?, ?, ?);',
        [key, value, metadata],
      );
      final nextCommitId = _nextCommitId();
      db.execute(
        'INSERT OR REPLACE INTO commit_log (atkey, commit_id, operation, op_time) VALUES (?, ?, ?, ?);',
        [key, nextCommitId, '+', DateTime.now().millisecondsSinceEpoch],
      );
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  String? get(String key) {
    final rows = db.select('SELECT value FROM at_data WHERE atkey = ?;', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  void remove(String key) {
    db.execute('BEGIN TRANSACTION;');
    try {
      db.execute('DELETE FROM at_data WHERE atkey = ?;', [key]);
      final nextCommitId = _nextCommitId();
      db.execute(
        'INSERT OR REPLACE INTO commit_log (atkey, commit_id, operation, op_time) VALUES (?, ?, ?, ?);',
        [key, nextCommitId, '-', DateTime.now().millisecondsSinceEpoch],
      );
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<String> getKeys({String? regex}) {
    final rows = db.select('SELECT atkey FROM at_data;');
    final keys = rows.map((r) => r['atkey'] as String).toList();
    if (regex != null) {
      final regExp = RegExp(regex);
      return keys.where(regExp.hasMatch).toList();
    }
    return keys;
  }

  int _nextCommitId() {
    final rows = db.select("SELECT value FROM counters WHERE name = 'last_commit_id';");
    final current = rows.isEmpty ? 0 : (rows.first['value'] as int);
    final next = current + 1;
    db.execute(
      "INSERT OR REPLACE INTO counters (name, value) VALUES ('last_commit_id', ?);",
      [next],
    );
    return next;
  }
}

/// Payload variant including SQLite-wasm, IndexedDB VFS, vfs_lab core, and a
/// real schema keystore adapter exercising get/put/remove/getKeys.
Future<void> main() async {
  if (web.window.location.search.contains('run')) {
    final db = await openLabDb(vfs: LabVfs.indexedDb, name: 'payload_adapter');
    applySchema(db);

    final adapter = SqliteKeystoreAdapter(db);
    adapter.put('phone.wavi', '+1234567890');
    adapter.get('phone.wavi');
    adapter.getKeys();
    adapter.remove('phone.wavi');
    db.dispose();
  }

  final remote = RemoteSecondary('@payload', AtClientPreference());
  await exercise(
      RemoteOnlyAtClientStorage(atSign: '@payload', remoteSecondary: remote));
}
