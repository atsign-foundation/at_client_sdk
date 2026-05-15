/// Per-atSign SQLite store for incoming dockerstats samples.
///
/// Schema is single-table with a `granularity` column reserved for
/// the future roll-up tiers (15-min averages, 1-hour averages, daily
/// averages). v1 only writes `granularity = 0` (raw) rows; the
/// reserved column lets us add roll-up later as a purely additive
/// change with no migration.
///
/// Concurrency: sqflite serialises writes through its own queue, so
/// concurrent [insertRaw] calls from the notification listener are
/// safe. Reads via [queryWindow] are non-blocking against writes.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/stats_models.dart';

/// One row from the `samples` table — a [StatSample] plus the
/// metadata the schema tracks (sender atSign, granularity, sample
/// count for rolled-up rows). v1 only writes raw rows so
/// `granularity == 0` and `sampleCount == 1` for everything inserted
/// here; the fields are exposed so future roll-up code can read them
/// back.
class StatSampleRow {
  final StatSample sample;
  final String senderAtSign;
  final int granularity;
  final int sampleCount;

  const StatSampleRow({
    required this.sample,
    required this.senderAtSign,
    this.granularity = 0,
    this.sampleCount = 1,
  });
}

class SamplesDb {
  final Database _db;

  SamplesDb._(this._db);

  /// Opens (creating if needed) the per-atSign database file at
  /// `<applicationSupportDir>/dockerstats/<atSign>.db`. Each atSign
  /// gets its own DB so logging in as a different atSign opens a
  /// different store — no cross-account leakage.
  static Future<SamplesDb> open(String atSign) async {
    // sqflite_common_ffi needs explicit init on desktop and CLI. On
    // Flutter mobile, sqflite (not _common_ffi) is the standard
    // backend, but dockerstats is desktop-only so the FFI path is
    // the right one here.
    sqfliteFfiInit();
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'dockerstats'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = atSign.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = p.join(dir.path, '$safe.db');
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE samples (
              granularity     INTEGER NOT NULL,
              millis          INTEGER NOT NULL,
              sender_at_sign  TEXT NOT NULL,
              at_sign         TEXT NOT NULL,
              hostname        TEXT NOT NULL,
              container_id    TEXT NOT NULL,
              container_name  TEXT NOT NULL,
              image           TEXT NOT NULL DEFAULT '',
              cpu_pct         REAL NOT NULL,
              mem_usage       INTEGER NOT NULL,
              mem_limit       INTEGER NOT NULL,
              mem_pct         REAL NOT NULL,
              net_rx          INTEGER NOT NULL,
              net_tx          INTEGER NOT NULL,
              blk_read        INTEGER NOT NULL,
              blk_write       INTEGER NOT NULL,
              pids_count      INTEGER NOT NULL,
              restart_count   INTEGER NOT NULL,
              sample_count    INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY
                (granularity, at_sign, hostname, container_id, millis)
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_samples_millis ON samples (millis)',
          );
          await db.execute(
            'CREATE INDEX idx_samples_gran_millis '
            'ON samples (granularity, millis)',
          );
        },
      ),
    );
    return SamplesDb._(db);
  }

  Future<void> close() => _db.close();

  /// Raw access to the underlying sqflite [Database]. Exposed so the
  /// [Roller] (in `roller.dart`) can run its grouped-INSERT +
  /// bulk-DELETE under a single transaction without re-implementing
  /// every storage primitive on this class. Production consumers
  /// should prefer the typed methods on this class.
  Database get database => _db;

  /// Insert one raw sample. Idempotent on
  /// `(granularity, at_sign, hostname, container_id, millis)` —
  /// re-inserting the same sample (e.g. on a notification retry)
  /// replaces the existing row rather than throwing.
  Future<void> insertRaw(StatSample s, {required String senderAtSign}) {
    return _db.insert('samples', {
      'granularity': 0,
      'millis': s.millis,
      'sender_at_sign': senderAtSign,
      'at_sign': s.atSign,
      'hostname': s.hostname,
      'container_id': s.containerId,
      'container_name': s.containerName,
      'image': s.image,
      'cpu_pct': s.cpuPct,
      'mem_usage': s.memUsage,
      'mem_limit': s.memLimit,
      'mem_pct': s.memPct,
      'net_rx': s.netRx,
      'net_tx': s.netTx,
      'blk_read': s.blkRead,
      'blk_write': s.blkWrite,
      'pids_count': s.pidsCount,
      'restart_count': s.restartCount,
      'sample_count': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// All rows with `millis >= sinceMs`, oldest first. Returns rows
  /// across every granularity tier; v1 only writes tier 0 so this
  /// degenerates to "all raw samples in the window".
  Future<List<StatSampleRow>> queryWindow(int sinceMs) async {
    final rows = await _db.query(
      'samples',
      where: 'millis >= ?',
      whereArgs: [sinceMs],
      orderBy: 'millis ASC',
    );
    return [for (final r in rows) _rowToSample(r)];
  }

  /// Convenience for dashboards that want "the newest single row
  /// per (host, container)" without scanning everything — e.g.
  /// populating the host-chips row on a fresh launch. Not used in
  /// v1 but cheap to expose now.
  Future<List<StatSampleRow>> latestPerHostContainer() async {
    final rows = await _db.rawQuery('''
      SELECT s.* FROM samples s
      JOIN (
        SELECT at_sign, hostname, container_id, MAX(millis) AS m
        FROM samples WHERE granularity = 0
        GROUP BY at_sign, hostname, container_id
      ) j
        ON  s.at_sign      = j.at_sign
        AND s.hostname     = j.hostname
        AND s.container_id = j.container_id
        AND s.millis       = j.m
      WHERE s.granularity = 0
    ''');
    return [for (final r in rows) _rowToSample(r)];
  }

  StatSampleRow _rowToSample(Map<String, Object?> r) {
    final sample = StatSample(
      atSign: r['at_sign'] as String,
      hostname: r['hostname'] as String,
      containerId: r['container_id'] as String,
      containerName: r['container_name'] as String,
      image: r['image'] as String,
      restartCount: (r['restart_count'] as num).toInt(),
      pidsCount: (r['pids_count'] as num).toInt(),
      cpuPct: (r['cpu_pct'] as num).toDouble(),
      memUsage: (r['mem_usage'] as num).toInt(),
      memLimit: (r['mem_limit'] as num).toInt(),
      memPct: (r['mem_pct'] as num).toDouble(),
      netRx: (r['net_rx'] as num).toInt(),
      netTx: (r['net_tx'] as num).toInt(),
      blkRead: (r['blk_read'] as num).toInt(),
      blkWrite: (r['blk_write'] as num).toInt(),
      millis: (r['millis'] as num).toInt(),
    );
    return StatSampleRow(
      sample: sample,
      senderAtSign: r['sender_at_sign'] as String,
      granularity: (r['granularity'] as num).toInt(),
      sampleCount: (r['sample_count'] as num).toInt(),
    );
  }
}
