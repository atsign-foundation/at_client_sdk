// Transport API — SQL ops on top of Store.
//
//   put / get              — write/read records (own store)
//   peekActorKey           — read a record from another actor's DB
//   notifyActorDevice      — write into a specific device's inbox on an actor's DB
//   notifyActorBroadcast   — write a broadcast row into an actor's DB
//   pollInbox              — pull unconsumed rows targeting our device
//   discoverPeerActors     — find actor DBs in the current directory

import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:sqlite3/sqlite3.dart';
import 'atserver.dart';

void put(Store self, String key, String value) {
  final stmt = self.db.prepare(
      'INSERT OR REPLACE INTO records (key, value, updated_at) VALUES (?, ?, ?)');
  stmt.execute([key, value, DateTime.now().millisecondsSinceEpoch]);
  stmt.dispose();
}

String? get(Store self, String key) {
  final rs = self.db.select('SELECT value FROM records WHERE key = ?', [key]);
  if (rs.isEmpty) return null;
  return rs.first['value'] as String;
}

/// Read a record from another actor's DB without opening a full Store.
String? peekActorKey(String actorName, String key) {
  Database? db;
  try {
    db = sqlite3.open('${actorName}.db');
    db.execute('PRAGMA busy_timeout=5000;');
    final rs = db.select('SELECT value FROM records WHERE key = ?', [key]);
    if (rs.isEmpty) return null;
    return rs.first['value'] as String;
  } catch (_) {
    return null;
  } finally {
    db?.dispose();
  }
}

/// Ensure the inbox table exists in the given DB connection.
void _ensureInbox(Database db) {
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
}

/// Write a message into a specific device's inbox on the target actor's DB.
void notifyActorDevice(
  String actorName,
  String targetDevice,
  String fromName,
  String? fromDevice,
  String msgType,
  String value,
) {
  Database? db;
  try {
    db = sqlite3.open('${actorName}.db');
    db.execute('PRAGMA busy_timeout=5000;');
    _ensureInbox(db);
    final stmt = db.prepare(
        'INSERT INTO inbox (target_device, from_name, from_device, msg_type, value, ts) VALUES (?, ?, ?, ?, ?, ?)');
    stmt.execute([
      targetDevice,
      fromName,
      fromDevice,
      msgType,
      value,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.dispose();
  } finally {
    db?.dispose();
  }
}

/// Write a broadcast row (target_device = "*") into an actor's DB.
void notifyActorBroadcast(
  String actorName,
  String fromName,
  String? fromDevice,
  String msgType,
  String value,
) {
  notifyActorDevice(actorName, '*', fromName, fromDevice, msgType, value);
}

/// Scan the current directory for <name>.db files, excluding selfName.
List<String> discoverPeerActors(String selfName) {
  try {
    return Directory('.')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .where((n) => n.endsWith('.db') && n != '${selfName}.db' &&
            RegExp(r'^[a-z0-9_]+\.db$').hasMatch(n))
        .map((n) => n.substring(0, n.length - 3))
        .toList();
  } catch (_) {
    return const [];
  }
}

class InboxRow {
  final int id;
  final String targetDevice;
  final String fromName;
  final String? fromDevice;
  final String msgType;
  final String value;
  final int ts;
  InboxRow({
    required this.id,
    required this.targetDevice,
    required this.fromName,
    required this.fromDevice,
    required this.msgType,
    required this.value,
    required this.ts,
  });
}

/// Pull all inbox rows targeted at `deviceId` or broadcast, that haven't been
/// consumed by `deviceId` yet. Marks them consumed for `deviceId`.
List<InboxRow> pollInbox(Store self, String deviceId) {
  final rs = self.db.select(
      'SELECT id, target_device, from_name, from_device, msg_type, value, ts, consumed_by '
      'FROM inbox WHERE target_device = ? OR target_device = "*" ORDER BY id ASC',
      [deviceId]);
  if (rs.isEmpty) return const [];

  final fresh = <InboxRow>[];
  final updateStmt =
      self.db.prepare('UPDATE inbox SET consumed_by = ? WHERE id = ?');
  for (final row in rs) {
    final id = row['id'] as int;
    final consumedJson = row['consumed_by'] as String;
    final consumed = (jsonDecode(consumedJson) as List).cast<String>();
    if (consumed.contains(deviceId)) continue;
    fresh.add(InboxRow(
      id: id,
      targetDevice: row['target_device'] as String,
      fromName: row['from_name'] as String,
      fromDevice: row['from_device'] as String?,
      msgType: row['msg_type'] as String,
      value: row['value'] as String,
      ts: row['ts'] as int,
    ));
    consumed.add(deviceId);
    updateStmt.execute([jsonEncode(consumed), id]);
  }
  updateStmt.dispose();
  return fresh;
}
