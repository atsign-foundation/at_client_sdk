/// Per-atSign SQLite store for incoming dockerstats samples.
///
/// One table, `tiered_samples`, holds **every tier** (raw and
/// rolled-up) keyed by `(granularity, at_sign, hostname,
/// container_id, millis)`. The table name is intentionally different
/// from the older schemas — `samples` (v1 with granularity + tier
/// scheme, v2 raw-only) — so the on-open migration can simply DROP
/// any pre-existing `samples` table without disturbing this one.
///
///   granularity  bucket    retention            written
///   -----------  --------  -------------------  -----------------------
///   0 (raw)      n/a       last 90 days only    per notification
///   1            1 min     forever              incremental UPSERT
///   2            15 min    forever              incremental UPSERT
///   3            1 hour    forever              incremental UPSERT
///   4            8 hours   forever              incremental UPSERT
///
/// Aggregated tiers store **running sums and a count** rather than
/// pre-computed averages. That lets the read query both:
///
///   - emit the right average per row (`cpu_sum / sample_count`); and
///   - aggregate FURTHER across multiple tier rows when the dashboard's
///     pixel-budget bucket is larger than the source tier's bucket
///     (`SUM(cpu_sum) / SUM(sample_count)` — a correct weighted mean,
///     unlike `AVG(cpu_avg)` which would be an unweighted mean of means).
///
/// Cumulative monotonic counters (`net_rx`, `net_tx`, `blk_read`,
/// `blk_write`) are kept as **last-in-bucket**: the value of the most
/// recent raw sample in the bucket. Diffing neighbouring buckets
/// recovers the rate. Monotonic event counters (`restart_count`) keep
/// the max.
///
/// Writes are **synchronous on insert**: each notification triggers
/// one transaction containing one tier-0 `INSERT OR IGNORE` plus four
/// tier-1..4 UPSERTs. `INSERT OR IGNORE` makes the whole transaction
/// idempotent — a re-delivered notification doesn't double-count any
/// tier.
///
/// Concurrency: sqflite serialises writes through its own queue, so
/// concurrent [insertSample] calls from the notification listener are
/// safe. Reads are non-blocking against writes.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/stats_models.dart';

/// Tier bucket sizes in milliseconds, indexed by granularity (0..4).
/// Tier 0 is raw — its "bucket" is the publisher's natural cadence
/// but the schema doesn't enforce or assume it.
const List<int> tierBucketsMs = [
  5 * 1000, // tier 0: 5s nominal (raw)
  60 * 1000, // tier 1: 1 min
  15 * 60 * 1000, // tier 2: 15 min
  60 * 60 * 1000, // tier 3: 1 h
  8 * 60 * 60 * 1000, // tier 4: 8 h
];

/// Retention for tier-0 raw rows. Tiers 1+ are derived from tier 0
/// during the bucket's lifetime and then kept indefinitely, so
/// dropping older raw rows doesn't lose any chart fidelity (the
/// aggregated tiers carry every metric the dashboard reads).
const Duration tier0Retention = Duration(days: 90);

/// One bucket's worth of data — what [SamplesDb.queryWindow] returns.
/// Carries the row's underlying sample count so the in-memory cache
/// can fold incoming live samples into the right bucket while keeping
/// the running mean correct.
class AggregatedRow {
  final StatSample sample;
  final String senderAtSign;
  final int sampleCount;

  const AggregatedRow({
    required this.sample,
    required this.senderAtSign,
    required this.sampleCount,
  });
}

/// Result shape from [SamplesDb.dataExtent].
class DataExtent {
  /// Earliest stored `millis` across all tiers, or `null` if empty.
  final int? earliestMs;

  /// Latest stored `millis` across all tiers, or `null` if empty.
  final int? latestMs;

  const DataExtent({required this.earliestMs, required this.latestMs});

  bool get isEmpty => earliestMs == null || latestMs == null;
}

class SamplesDb {
  final Database _db;

  SamplesDb._(this._db);

  /// Opens (creating if needed) the per-atSign database file at
  /// `<applicationSupportDir>/dockerstats/<atSign>.db`.
  static Future<SamplesDb> open(String atSign) async {
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
        version: 3,
        onCreate: (db, _) async {
          await _dropLegacySamplesTable(db);
          await _createSchema(db);
        },
        // Pre-v3 stored a different schema in `samples` (v1 with
        // granularity + roll-up policy; v2 raw-only). Drop the old
        // `samples` table and create the new `tiered_samples`
        // schema; the latter never existed in v1/v2 so an
        // upgrade-time DROP of `tiered_samples` would be a bug
        // — it'd silently destroy any data a future v3+ migration
        // had already written.
        onUpgrade: (db, _, _) async {
          await _dropLegacySamplesTable(db);
          await _createSchema(db);
        },
        // Defensive: catches the edge case where someone opens a DB
        // already at version 3 but still carrying a stray `samples`
        // table from an interrupted migration. Cheap when the table
        // doesn't exist.
        onOpen: (db) async => _dropLegacySamplesTable(db),
      ),
    );
    return SamplesDb._(db);
  }

  /// Removes any legacy `samples` table left behind by older
  /// schemas. Idempotent; cheap when the table doesn't exist.
  static Future<void> _dropLegacySamplesTable(Database db) async {
    await db.execute('DROP TABLE IF EXISTS samples');
  }

  static Future<void> _createSchema(Database db) async {
    // `IF NOT EXISTS` makes this re-entrant — onCreate runs once
    // for a fresh DB, but onUpgrade also calls into here for the
    // v1/v2 → v3 path, and onOpen calls _dropLegacySamplesTable
    // before this is reached. If we ever bump beyond v3 with a
    // genuine schema change, a future onUpgrade should `DROP
    // TABLE tiered_samples` explicitly before calling this.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tiered_samples (
        granularity       INTEGER NOT NULL,
        millis            INTEGER NOT NULL,
        sender_at_sign    TEXT    NOT NULL,
        at_sign           TEXT    NOT NULL,
        hostname          TEXT    NOT NULL,
        container_id      TEXT    NOT NULL,
        container_name    TEXT    NOT NULL,
        image             TEXT    NOT NULL DEFAULT '',
        cpu_sum           REAL    NOT NULL,
        mem_sum           INTEGER NOT NULL,
        mem_limit_sum     INTEGER NOT NULL,
        mem_pct_sum       REAL    NOT NULL,
        pids_sum          INTEGER NOT NULL,
        last_net_rx       INTEGER NOT NULL,
        last_net_tx       INTEGER NOT NULL,
        last_blk_read     INTEGER NOT NULL,
        last_blk_write    INTEGER NOT NULL,
        last_millis       INTEGER NOT NULL,
        max_restart_count INTEGER NOT NULL,
        sample_count      INTEGER NOT NULL,
        PRIMARY KEY (granularity, at_sign, hostname, container_id, millis)
      )
    ''');
    // Read path is always WHERE granularity = ? AND millis >= ?
    // (optionally AND millis < ?). This composite index lets every
    // tier-specific query stream sorted by millis off the index.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tiered_samples_gran_millis '
      'ON tiered_samples (granularity, millis)',
    );
  }

  Future<void> close() => _db.close();

  /// Raw access to the underlying [Database]. Exposed mainly for
  /// pure-Dart tools (e.g. `tool/seed_db.dart`) that need direct
  /// schema access without going through this class.
  Database get database => _db;

  /// Insert one raw sample and synchronously roll it up into tiers
  /// 1..4. The whole operation is one transaction:
  ///
  ///   1. `INSERT OR IGNORE` the raw row at tier 0. If a row with the
  ///      same PK already exists (duplicate notification) we return
  ///      early and the tier UPSERTs are skipped — keeping the whole
  ///      thing idempotent on `(at_sign, hostname, container_id,
  ///      millis)`.
  ///   2. For tiers 1..4 in order, UPSERT into the bucket containing
  ///      this sample's millis: insert if absent (sums = raw values,
  ///      count = 1) or accumulate (sums += raw values, count += 1)
  ///      with last-in-bucket semantics for the cumulative counters
  ///      and max for the restart counter.
  Future<void> insertSample(
    StatSample s, {
    required String senderAtSign,
  }) async {
    await _db.transaction((txn) async {
      final inserted = await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO tiered_samples (
          granularity, millis, sender_at_sign, at_sign, hostname,
          container_id, container_name, image,
          cpu_sum, mem_sum, mem_limit_sum, mem_pct_sum, pids_sum,
          last_net_rx, last_net_tx, last_blk_read, last_blk_write,
          last_millis, max_restart_count, sample_count
        ) VALUES (
          0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1
        )
        ''',
        [
          s.millis,
          senderAtSign,
          s.atSign,
          s.hostname,
          s.containerId,
          s.containerName,
          s.image,
          s.cpuPct,
          s.memUsage,
          s.memLimit,
          s.memPct,
          s.pidsCount,
          s.netRx,
          s.netTx,
          s.blkRead,
          s.blkWrite,
          s.millis,
          s.restartCount,
        ],
      );
      if (inserted == 0) return; // duplicate, tier rows already in sync
      for (var tier = 1; tier <= 4; tier++) {
        final bucketMs = tierBucketsMs[tier];
        final bucketStart = (s.millis ~/ bucketMs) * bucketMs;
        await txn.rawInsert(_tierUpsertSql, [
          tier,
          bucketStart,
          senderAtSign,
          s.atSign,
          s.hostname,
          s.containerId,
          s.containerName,
          s.image,
          s.cpuPct,
          s.memUsage,
          s.memLimit,
          s.memPct,
          s.pidsCount,
          s.netRx,
          s.netTx,
          s.blkRead,
          s.blkWrite,
          s.millis,
          s.restartCount,
        ]);
      }
    });
  }

  static const String _tierUpsertSql = '''
    INSERT INTO tiered_samples (
      granularity, millis, sender_at_sign, at_sign, hostname,
      container_id, container_name, image,
      cpu_sum, mem_sum, mem_limit_sum, mem_pct_sum, pids_sum,
      last_net_rx, last_net_tx, last_blk_read, last_blk_write,
      last_millis, max_restart_count, sample_count
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1
    )
    ON CONFLICT(granularity, at_sign, hostname, container_id, millis)
    DO UPDATE SET
      cpu_sum        = cpu_sum + excluded.cpu_sum,
      mem_sum        = mem_sum + excluded.mem_sum,
      mem_limit_sum  = mem_limit_sum + excluded.mem_limit_sum,
      mem_pct_sum    = mem_pct_sum + excluded.mem_pct_sum,
      pids_sum       = pids_sum + excluded.pids_sum,
      sample_count   = sample_count + 1,
      last_net_rx    = CASE WHEN excluded.last_millis > last_millis
                            THEN excluded.last_net_rx ELSE last_net_rx END,
      last_net_tx    = CASE WHEN excluded.last_millis > last_millis
                            THEN excluded.last_net_tx ELSE last_net_tx END,
      last_blk_read  = CASE WHEN excluded.last_millis > last_millis
                            THEN excluded.last_blk_read ELSE last_blk_read END,
      last_blk_write = CASE WHEN excluded.last_millis > last_millis
                            THEN excluded.last_blk_write ELSE last_blk_write END,
      max_restart_count = MAX(max_restart_count, excluded.max_restart_count),
      last_millis    = MAX(last_millis, excluded.last_millis)
  ''';

  /// Delete tier-0 rows older than [cutoffMs]. Aggregated tiers
  /// remain untouched. Called periodically by [DockerstatsService]
  /// to enforce the [tier0Retention] policy.
  Future<int> pruneTier0OlderThan(int cutoffMs) {
    return _db.delete(
      'tiered_samples',
      where: 'granularity = 0 AND millis < ?',
      whereArgs: [cutoffMs],
    );
  }

  /// Earliest and latest `millis` across all tiers. Tier 4 (or 3)
  /// will typically carry the oldest row since tier 0 is pruned.
  /// Used by the dashboard's "Fit all" button and pan/zoom clamps.
  Future<DataExtent> dataExtent() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(millis) AS lo, MAX(millis) AS hi FROM tiered_samples',
    );
    final lo = rows.first['lo'];
    final hi = rows.first['hi'];
    return DataExtent(
      earliestMs: lo == null ? null : (lo as num).toInt(),
      latestMs: hi == null ? null : (hi as num).toInt(),
    );
  }

  /// Read a slice of one tier into chart-pixel-budget rows.
  ///
  /// - [tier] selects the source granularity (0..4). The caller picks
  ///   the coarsest tier whose natural bucket ≤ the chart's pixel
  ///   budget.
  /// - [sinceMs] / [untilMs] bound the time range. `untilMs == null`
  ///   means "no upper bound" (the dashboard's live mode).
  /// - [bucketMs] is the chart's pixel-budget bucket. When it equals
  ///   the source tier's natural bucket the query is a plain
  ///   `SELECT` — one row per tier row. When it's larger, the query
  ///   runs a `GROUP BY` to merge multiple tier rows into one chart
  ///   row (using `SUM`/`SUM` for rates and `MAX` for cumulative
  ///   counters).
  ///
  /// Returns rows already shaped as the dashboard renders them.
  Future<List<AggregatedRow>> queryWindow({
    required int tier,
    required int sinceMs,
    required int? untilMs,
    required int bucketMs,
  }) async {
    final tierBucket = tierBucketsMs[tier];
    final regroup = bucketMs > tierBucket;

    final whereParts = <String>['granularity = ?'];
    final args = <Object?>[tier];
    if (sinceMs > 0) {
      whereParts.add('millis >= ?');
      args.add(sinceMs);
    }
    if (untilMs != null) {
      whereParts.add('millis < ?');
      args.add(untilMs);
    }
    final whereClause = whereParts.join(' AND ');

    if (!regroup) {
      final rows = await _db.rawQuery('''
        SELECT
          millis AS bucket_start,
          at_sign, sender_at_sign, hostname, container_id,
          container_name, image,
          cpu_sum / CAST(sample_count AS REAL)         AS cpu_pct,
          CAST(mem_sum / sample_count AS INTEGER)      AS mem_usage,
          CAST(mem_limit_sum / sample_count AS INTEGER) AS mem_limit,
          mem_pct_sum / CAST(sample_count AS REAL)     AS mem_pct,
          CAST(pids_sum / sample_count AS INTEGER)     AS pids_count,
          last_net_rx                                  AS net_rx,
          last_net_tx                                  AS net_tx,
          last_blk_read                                AS blk_read,
          last_blk_write                               AS blk_write,
          max_restart_count                            AS restart_count,
          sample_count
        FROM tiered_samples
        WHERE $whereClause
      ''', args);
      return [for (final r in rows) _toAggregatedRow(r)];
    }
    final bucketExpr = '((millis / $bucketMs) * $bucketMs)';
    final rows = await _db.rawQuery('''
      SELECT
        $bucketExpr AS bucket_start,
        MAX(at_sign)         AS at_sign,
        MAX(sender_at_sign)  AS sender_at_sign,
        hostname, container_id,
        MAX(container_name)  AS container_name,
        MAX(image)           AS image,
        SUM(cpu_sum)       / CAST(SUM(sample_count) AS REAL) AS cpu_pct,
        CAST(SUM(mem_sum)       / SUM(sample_count) AS INTEGER) AS mem_usage,
        CAST(SUM(mem_limit_sum) / SUM(sample_count) AS INTEGER) AS mem_limit,
        SUM(mem_pct_sum)   / CAST(SUM(sample_count) AS REAL) AS mem_pct,
        CAST(SUM(pids_sum)      / SUM(sample_count) AS INTEGER) AS pids_count,
        MAX(last_net_rx)     AS net_rx,
        MAX(last_net_tx)     AS net_tx,
        MAX(last_blk_read)   AS blk_read,
        MAX(last_blk_write)  AS blk_write,
        MAX(max_restart_count) AS restart_count,
        SUM(sample_count)    AS sample_count
      FROM tiered_samples
      WHERE $whereClause
      GROUP BY hostname, container_id, bucket_start
    ''', args);
    return [for (final r in rows) _toAggregatedRow(r)];
  }

  /// Pick the coarsest tier whose source bucket size is ≤
  /// [targetBucketMs]. Returns 0 (raw) when [targetBucketMs] is
  /// finer than tier 0.
  static int pickTier(int targetBucketMs) {
    var t = 0;
    for (var i = 0; i < tierBucketsMs.length; i++) {
      if (tierBucketsMs[i] <= targetBucketMs) t = i;
    }
    return t;
  }

  AggregatedRow _toAggregatedRow(Map<String, Object?> r) {
    return AggregatedRow(
      sample: StatSample(
        atSign: r['at_sign'] as String,
        hostname: r['hostname'] as String,
        containerId: r['container_id'] as String,
        containerName: r['container_name'] as String,
        image: r['image'] as String? ?? '',
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
        millis: (r['bucket_start'] as num).toInt(),
      ),
      senderAtSign: r['sender_at_sign'] as String,
      sampleCount: (r['sample_count'] as num).toInt(),
    );
  }
}
