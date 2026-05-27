// Transport: thin operations on top of Store.
//
//   put(self, k, v)              → INSERT/UPDATE own records
//   get(self, k)                 → SELECT from own records
//   peekPeer(peerDb, k)          → SELECT from peer's records (read-only)
//   notifyPeer(peerDb, from, v)  → INSERT into peer's inbox
//   pollInbox(self)              → SELECT consumed=0 rows; mark consumed=1

import 'package:sqlite3/sqlite3.dart';
import 'store.dart';

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

void notifyPeer(Database peerDb, String fromName, String value) {
  final stmt = peerDb.prepare(
      'INSERT INTO inbox (from_name, value, ts) VALUES (?, ?, ?)');
  stmt.execute([fromName, value, DateTime.now().millisecondsSinceEpoch]);
  stmt.dispose();
}

class InboxRow {
  final int id;
  final String fromName;
  final String value;
  final int ts;
  InboxRow(this.id, this.fromName, this.value, this.ts);
}

/// Returns all unconsumed inbox rows and marks them consumed.
List<InboxRow> pollInbox(Store self) {
  final rs = self.db.select(
      'SELECT id, from_name, value, ts FROM inbox WHERE consumed = 0 ORDER BY id ASC');
  if (rs.isEmpty) return const [];
  final rows = <InboxRow>[];
  for (final row in rs) {
    rows.add(InboxRow(
      row['id'] as int,
      row['from_name'] as String,
      row['value'] as String,
      row['ts'] as int,
    ));
  }
  final markStmt =
      self.db.prepare('UPDATE inbox SET consumed = 1 WHERE id = ?');
  for (final r in rows) {
    markStmt.execute([r.id]);
  }
  markStmt.dispose();
  return rows;
}
