// Exercises the five-tier roll-up policy end-to-end against an
// in-memory SQLite database. Each test fast-forwards a synthetic
// `now` past one tier boundary at a time, verifies row counts in
// the source and target tiers, and spot-checks the aggregation
// math (weighted mean + last-in-bucket + max + sum-of-sample-
// counts).
//
// Uses `sqflite_common_ffi`'s `inMemoryDatabasePath` so each test
// gets its own isolated DB without touching disk.

import 'package:dockerstats/services/roller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Schema mirrored from samples_db.dart's onCreate so the test can
// stand up a fresh DB without going through `SamplesDb.open` (which
// requires path_provider / a writable on-disk directory).
const String _createSamplesTable = '''
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
    PRIMARY KEY (granularity, at_sign, hostname, container_id, millis)
  )
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;
  late Roller roller;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async => db.execute(_createSamplesTable),
      ),
    );
    roller = Roller(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------
  // Fixture helpers.

  /// Insert one raw row at [ms] with [cpu]% CPU, [memUsage] bytes
  /// memory, and the given cumulative counters / restart count.
  Future<void> insertRaw({
    required int ms,
    double cpu = 10,
    int memUsage = 100 * 1024 * 1024,
    int netRx = 0,
    int netTx = 0,
    int blkRead = 0,
    int blkWrite = 0,
    int restart = 0,
    String containerId = 'c1',
    String containerName = 'web',
  }) async {
    await db.insert('samples', {
      'granularity': 0,
      'millis': ms,
      'sender_at_sign': '@pub',
      'at_sign': '@pub',
      'hostname': 'host-a',
      'container_id': containerId,
      'container_name': containerName,
      'image': 'nginx',
      'cpu_pct': cpu,
      'mem_usage': memUsage,
      'mem_limit': 1024 * 1024 * 1024,
      'mem_pct': cpu / 10,
      'net_rx': netRx,
      'net_tx': netTx,
      'blk_read': blkRead,
      'blk_write': blkWrite,
      'pids_count': 5,
      'restart_count': restart,
      'sample_count': 1,
    });
  }

  Future<int> countTier(int g) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM samples WHERE granularity = ?',
      [g],
    );
    return (r.first['c'] as num).toInt();
  }

  Future<Map<String, Object?>> singleRow(int g) async {
    final rows = await db.query(
      'samples',
      where: 'granularity = ?',
      whereArgs: [g],
    );
    expect(rows, hasLength(1));
    return rows.first;
  }

  // ---------------------------------------------------------------
  // Tier 0 → 1: raw rows older than 6h get bucketed into 1-min
  // averages. Verifies that the boundary fires, that recent rows
  // are untouched, and that the source tier is purged after the
  // roll-up.

  test('tier 0 → 1: rows older than 6h roll into 1-min buckets', () async {
    final now = DateTime(2026, 5, 14, 12);
    // Twelve raw samples spanning t-7h00 to t-7h00+55s, all in the
    // same 1-min bucket. They're > 6h old so they roll. Plus three
    // recent rows that should stay in tier 0.
    final bucketStart = now
        .subtract(const Duration(hours: 7))
        .millisecondsSinceEpoch;
    for (var i = 0; i < 12; i++) {
      await insertRaw(ms: bucketStart + i * 5000, cpu: 10 + i * 1.0);
    }
    for (var i = 0; i < 3; i++) {
      await insertRaw(ms: now.millisecondsSinceEpoch - 60 * 1000 * (i + 1));
    }

    expect(await countTier(0), 15);
    expect(await countTier(1), 0);

    await roller.rollUpAll(now: now);

    expect(await countTier(0), 3, reason: 'recent rows stay raw');
    expect(await countTier(1), 1, reason: 'old rows collapse to one bucket');

    final row = await singleRow(1);
    expect(row['millis'], (bucketStart ~/ 60000) * 60000);
    expect(row['sample_count'], 12);
    // Mean CPU of 10,11,12,...,21 = 15.5
    expect(row['cpu_pct'] as double, closeTo(15.5, 1e-9));
    // Last container_name in the bucket (all the same here)
    expect(row['container_name'], 'web');
  });

  // ---------------------------------------------------------------
  // last-in-bucket semantics for cumulative counters.

  test('cumulative counters take the last value in the bucket', () async {
    final now = DateTime(2026, 5, 14, 12);
    final bucketStart = now
        .subtract(const Duration(hours: 7))
        .millisecondsSinceEpoch;
    // Three samples 30s apart, all in the same 1-min bucket. Last
    // sample has highest counters.
    await insertRaw(
      ms: bucketStart,
      netRx: 100,
      netTx: 200,
      blkRead: 10,
      blkWrite: 20,
      restart: 0,
    );
    await insertRaw(
      ms: bucketStart + 30000,
      netRx: 200,
      netTx: 400,
      blkRead: 20,
      blkWrite: 40,
      restart: 2,
    );
    await insertRaw(
      ms: bucketStart + 55000,
      netRx: 300,
      netTx: 600,
      blkRead: 30,
      blkWrite: 60,
      restart: 1,
    );

    await roller.rollUpAll(now: now);

    final row = await singleRow(1);
    expect(row['net_rx'], 300, reason: 'last value in bucket');
    expect(row['net_tx'], 600);
    expect(row['blk_read'], 30);
    expect(row['blk_write'], 60);
    // restart_count is MAX across the bucket, not LAST.
    expect(row['restart_count'], 2);
    expect(row['sample_count'], 3);
  });

  // ---------------------------------------------------------------
  // Weighted means when rolling tier-N into tier-N+1: each input
  // row already has a sample_count from its own roll-up. Verify
  // the higher-weight rows dominate the average.

  test('weighted mean honours sample_count', () async {
    final now = DateTime(2026, 5, 14, 12);
    // Tier 1 rows (>72h old roll to tier 2 in 15-min buckets).
    // Two tier-1 rows in the same 15-min bucket:
    //   - one with sample_count=10 and cpu_pct=20
    //   - one with sample_count=2  and cpu_pct=50
    // Naive mean would give 35; weighted mean gives
    //   (10*20 + 2*50) / 12 = 300/12 = 25.
    final bucketStart = now
        .subtract(const Duration(days: 4))
        .millisecondsSinceEpoch;
    final aligned = (bucketStart ~/ (15 * 60 * 1000)) * 15 * 60 * 1000;
    await db.insert('samples', {
      'granularity': 1,
      'millis': aligned + 1 * 60 * 1000,
      'sender_at_sign': '@pub',
      'at_sign': '@pub',
      'hostname': 'host-a',
      'container_id': 'c1',
      'container_name': 'web',
      'image': 'nginx',
      'cpu_pct': 20.0,
      'mem_usage': 100,
      'mem_limit': 1000,
      'mem_pct': 10.0,
      'net_rx': 0,
      'net_tx': 0,
      'blk_read': 0,
      'blk_write': 0,
      'pids_count': 5,
      'restart_count': 0,
      'sample_count': 10,
    });
    await db.insert('samples', {
      'granularity': 1,
      'millis': aligned + 2 * 60 * 1000,
      'sender_at_sign': '@pub',
      'at_sign': '@pub',
      'hostname': 'host-a',
      'container_id': 'c1',
      'container_name': 'web',
      'image': 'nginx',
      'cpu_pct': 50.0,
      'mem_usage': 100,
      'mem_limit': 1000,
      'mem_pct': 25.0,
      'net_rx': 0,
      'net_tx': 0,
      'blk_read': 0,
      'blk_write': 0,
      'pids_count': 5,
      'restart_count': 0,
      'sample_count': 2,
    });

    await roller.rollUpAll(now: now);

    final row = await singleRow(2);
    expect(row['cpu_pct'] as double, closeTo(25.0, 1e-9));
    expect(row['sample_count'], 12, reason: 'sum of input weights');
  });

  // ---------------------------------------------------------------
  // Fast-forward four years: every old row should cascade through
  // tiers 1 → 2 → 3 → 4 in a single rollUpAll. Verifies the chain
  // works without manual intervention between passes.

  test('cascade: 4y fast-forward lands raw samples in tier 4', () async {
    final now = DateTime(2030, 5, 14, 12);
    // One raw sample 4 years and 1 day ago. Should land in tier 4
    // (8-hour buckets, indefinite retention).
    final ageStart = now
        .subtract(const Duration(days: 4 * 365 + 1))
        .millisecondsSinceEpoch;
    await insertRaw(ms: ageStart, cpu: 7.5);

    expect(await countTier(0), 1);

    await roller.rollUpAll(now: now);

    expect(await countTier(0), 0);
    expect(await countTier(1), 0);
    expect(await countTier(2), 0);
    expect(await countTier(3), 0);
    expect(await countTier(4), 1);

    final row = await singleRow(4);
    final bucketMs = 8 * 60 * 60 * 1000;
    expect(row['millis'], (ageStart ~/ bucketMs) * bucketMs);
    expect(row['cpu_pct'] as double, closeTo(7.5, 1e-9));
    expect(row['sample_count'], 1);
  });

  // ---------------------------------------------------------------
  // Distinct (host, container) keys don't merge — even if their
  // millis values land in the same bucket.

  test('different containers in the same bucket stay distinct', () async {
    final now = DateTime(2026, 5, 14, 12);
    final base = now.subtract(const Duration(hours: 7)).millisecondsSinceEpoch;
    await insertRaw(ms: base, cpu: 10, containerId: 'c1', containerName: 'web');
    await insertRaw(ms: base, cpu: 50, containerId: 'c2', containerName: 'db');

    await roller.rollUpAll(now: now);

    expect(await countTier(1), 2);
    final rows = await db.query(
      'samples',
      where: 'granularity = 1',
      orderBy: 'container_id',
    );
    expect(rows[0]['container_id'], 'c1');
    expect(rows[0]['cpu_pct'] as double, closeTo(10, 1e-9));
    expect(rows[1]['container_id'], 'c2');
    expect(rows[1]['cpu_pct'] as double, closeTo(50, 1e-9));
  });

  // ---------------------------------------------------------------
  // No-op safety: calling rollUpAll on an empty / all-recent DB is
  // a no-op and doesn't raise.

  test('no-op when nothing has aged out', () async {
    final now = DateTime(2026, 5, 14, 12);
    await insertRaw(ms: now.millisecondsSinceEpoch - 60 * 1000);

    final report = await roller.rollUpAll(now: now);

    expect(await countTier(0), 1);
    expect(await countTier(1), 0);
    expect(report.passes.every((p) => p.sourceRowsConsumed == 0), isTrue);
  });
}
