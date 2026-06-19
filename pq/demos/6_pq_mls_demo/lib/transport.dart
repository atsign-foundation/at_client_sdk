// Transport API — SQL ops on top of Store.
//
//   put / get              — write/read records (own store)
//   peekPeer               — read another name's records
//   notifyDevice / Broadcast — write into someone's inbox
//   pollInbox              — pull unconsumed rows targeting our device

import 'dart:convert';
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

String? peekPeer(Database peerDb, String key) {
  final rs = peerDb.select('SELECT value FROM records WHERE key = ?', [key]);
  if (rs.isEmpty) return null;
  return rs.first['value'] as String;
}

/// Notify a specific device on a peer's store.
void notifyDevice(
  Database peerDb,
  String targetDevice,
  String fromName,
  String? fromDevice,
  String msgType,
  String value,
) {
  final stmt = peerDb.prepare(
      'INSERT INTO inbox (target_device, from_name, from_device, msg_type, value, ts) VALUES (?, ?, ?, ?, ?, ?)');
  stmt.execute([
    targetDevice,
    fromName,
    fromDevice,
    msgType,
    value,
    DateTime.now().millisecondsSinceEpoch
  ]);
  stmt.dispose();
}

/// Notify all devices on a peer's store (target_device = "*").
void notifyBroadcast(
  Database peerDb,
  String fromName,
  String? fromDevice,
  String msgType,
  String value,
) {
  notifyDevice(peerDb, '*', fromName, fromDevice, msgType, value);
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
