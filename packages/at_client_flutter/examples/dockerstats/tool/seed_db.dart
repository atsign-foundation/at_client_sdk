// Seeds the Flutter dockerstats app's SQLite store with synthetic
// samples across all five tiers (raw + four aggregated rollups), so
// the dashboard's zoom / pan controls have realistic data at every
// resolution without waiting hours / days / months for a live
// publisher.
//
// Strategy:
//
//   1. Write raw tier-0 rows at `--rate` spacing across `--span`.
//   2. Compute tier 1 by SQL-GROUPing tier 0 into 1-minute buckets.
//   3. Compute tier 2 from tier 1 (15-min buckets).
//   4. Compute tier 3 from tier 2 (1-hour buckets).
//   5. Compute tier 4 from tier 3 (8-hour buckets).
//
// Sums + count + last-in-bucket aggregation matches what the runtime
// service computes incrementally on each notification, so a seeded
// DB is indistinguishable from one populated by a live publisher.
//
// Row counts at common settings (raw + ~9% for aggregated tiers):
//
//   --rate 5s   --span 1d      :  ~108 k rows total (6 containers)
//   --rate 30s  --span 90d     :  ~1.7 M rows total
//   --rate 5s   --span 90d     :  ~10 M rows total
//   --rate 5s   --span 1y      :  ~41 M rows total (slow!)
//
// Where to find the DB the Flutter app uses (macOS):
//
//   ~/Library/Containers/com.example.dockerstats/Data/Library/Application Support/com.example.dockerstats/dockerstats/<atSign>.db
//   ~/Library/Application Support/com.example.dockerstats/dockerstats/<atSign>.db
//
// Usage:
//
//   dart run tool/seed_db.dart \
//     --db-path /path/to/_garycasey.db \
//     --span 90d \
//     --rate 30s \
//     --containers 6 \
//     [--clear-first]

import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mirror of `samples_db.dart`'s `tierBucketsMs` constant — kept in
/// sync because this tool can't depend on `package:dockerstats` (it
/// would pull in path_provider / Flutter).
const List<int> _tierBucketsMs = [
  5 * 1000,
  60 * 1000,
  15 * 60 * 1000,
  60 * 60 * 1000,
  8 * 60 * 60 * 1000,
];

const String _createTieredSamplesTable = '''
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
''';

const String _createMillisIndex =
    'CREATE INDEX IF NOT EXISTS idx_tiered_samples_gran_millis '
    'ON tiered_samples (granularity, millis)';

void main(List<String> args) async {
  final ap = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'db-path',
      mandatory: true,
      help: 'Path to the SQLite file the Flutter app uses.',
    )
    ..addOption('span', defaultsTo: '90d')
    ..addOption('rate', defaultsTo: '30s')
    ..addOption('containers', defaultsTo: '6')
    ..addFlag(
      'clear-first',
      negatable: false,
      help: 'DELETE FROM tiered_samples before seeding. Schema preserved.',
    );

  ArgResults parsed;
  try {
    parsed = ap.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(ap.usage);
    exit(64);
  }
  if (parsed['help'] == true) {
    stdout.writeln(ap.usage);
    return;
  }

  final dbPath = parsed['db-path'] as String;
  final span = _parseDuration(parsed['span'] as String);
  final rate = _parseDuration(parsed['rate'] as String);
  if (rate.inMilliseconds <= 0) {
    stderr.writeln('--rate must be positive');
    exit(64);
  }
  final nContainers = int.tryParse(parsed['containers'] as String) ?? 6;
  if (nContainers <= 0) {
    stderr.writeln('--containers must be a positive integer');
    exit(64);
  }
  final clearFirst = parsed['clear-first'] as bool;

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        // Drop any legacy `samples` table the app's older versions
        // may have written. Matches the runtime migration so a
        // bench DB and an app-created DB share an identical shape.
        await db.execute('DROP TABLE IF EXISTS samples');
        await db.execute(_createTieredSamplesTable);
        await db.execute(_createMillisIndex);
      },
      onUpgrade: (db, _, _) async {
        // Drop the legacy v1/v2 `samples` table; the new
        // `tiered_samples` never existed in those versions so
        // dropping it here would be a data-loss bug if a future
        // v3+ migration had already written to it.
        await db.execute('DROP TABLE IF EXISTS samples');
        await db.execute(_createTieredSamplesTable);
        await db.execute(_createMillisIndex);
      },
    ),
  );
  // Belt-and-braces in case we opened a pre-existing v3 DB.
  await db.execute('DROP TABLE IF EXISTS samples');
  await db.execute(_createTieredSamplesTable);
  await db.execute(_createMillisIndex);

  final containers = _buildContainerSet(nContainers);
  stdout.writeln(
    'Seeding ${containers.length} container(s) at $dbPath '
    'for span=${parsed['span']} rate=${parsed['rate']}',
  );

  if (clearFirst) {
    final removed = await db.delete('tiered_samples');
    stdout.writeln('  cleared $removed existing row(s)');
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final start = now - span.inMilliseconds;
  final step = rate.inMilliseconds;

  final swT0 = Stopwatch()..start();
  final rawInserted = await _seedTier0(
    db: db,
    rangeStart: start,
    rangeEnd: now,
    stepMs: step,
    containers: containers,
  );
  swT0.stop();
  stdout.writeln(
    '  tier 0 (raw):  $rawInserted row(s)  '
    '(${_fmtElapsed(swT0.elapsed)})',
  );

  // Cascade tier 1 ← 0, tier 2 ← 1, tier 3 ← 2, tier 4 ← 3.
  // Roll-up math is associative (sum-of-sums, count-of-counts,
  // max-of-maxes, last-of-lasts) so each tier can be built from the
  // tier immediately below without rescanning the raw rows.
  for (var tier = 1; tier <= 4; tier++) {
    final sw = Stopwatch()..start();
    final rolled = await _cascadeTier(db, tier);
    sw.stop();
    stdout.writeln(
      '  tier $tier (${_fmtBucket(_tierBucketsMs[tier])}):  $rolled row(s)  '
      '(${_fmtElapsed(sw.elapsed)})',
    );
  }

  await db.close();
  stdout.writeln('Done.');
}

class _Container {
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;
  final double cpuBaseline;
  final double cpuAmplitude;
  final double memBaselineMib;
  final double memAmplitudeMib;
  final double cpuPeriodSeconds;
  final double memPeriodSeconds;
  final int memLimitBytes;
  final double netRxRateMbps;
  final double netTxRateMbps;
  final double blkReadRateMbps;
  final double blkWriteRateMbps;

  _Container({
    required this.hostname,
    required this.containerId,
    required this.containerName,
    required this.image,
    required this.cpuBaseline,
    required this.cpuAmplitude,
    required this.memBaselineMib,
    required this.memAmplitudeMib,
    required this.cpuPeriodSeconds,
    required this.memPeriodSeconds,
    required this.memLimitBytes,
    required this.netRxRateMbps,
    required this.netTxRateMbps,
    required this.blkReadRateMbps,
    required this.blkWriteRateMbps,
  });
}

List<_Container> _buildContainerSet(int n) {
  final rng = math.Random(42);
  final images = const [
    'nginx:1.27',
    'redis:7.4',
    'postgres:16',
    'busybox:1.37',
    'caddy:2.8',
    'node:22-alpine',
  ];
  final out = <_Container>[];
  for (var i = 0; i < n; i++) {
    final host = i.isEven ? 'sim-host-01' : 'sim-host-02';
    final atSign = '@sim_${host.replaceAll('-', '_')}_${(i ~/ 2) + 1}';
    out.add(
      _Container(
        hostname: host,
        containerId: '${host}_c${(i + 1).toString().padLeft(2, '0')}'.padRight(
          64,
          '0',
        ),
        containerName: i.isEven ? atSign : 'sim_${atSign.replaceAll('@', '')}',
        image: images[i % images.length],
        cpuBaseline: 5 + rng.nextDouble() * 25,
        cpuAmplitude: 5 + rng.nextDouble() * 20,
        memBaselineMib: 100 + rng.nextDouble() * 1400,
        memAmplitudeMib: 20 + rng.nextDouble() * 380,
        cpuPeriodSeconds: 600 + rng.nextDouble() * 5400,
        memPeriodSeconds: 1200 + rng.nextDouble() * 6000,
        memLimitBytes: (1024 + rng.nextInt(7) * 1024) * 1024 * 1024,
        netRxRateMbps: 0.5 + rng.nextDouble() * 2.5,
        netTxRateMbps: 0.5 + rng.nextDouble() * 2.5,
        blkReadRateMbps: 0.1 + rng.nextDouble() * 0.9,
        blkWriteRateMbps: 0.1 + rng.nextDouble() * 0.9,
      ),
    );
  }
  return out;
}

Future<int> _seedTier0({
  required Database db,
  required int rangeStart,
  required int rangeEnd,
  required int stepMs,
  required List<_Container> containers,
}) async {
  if (rangeEnd <= rangeStart) return 0;
  final firstSample = ((rangeStart + stepMs - 1) ~/ stepMs) * stepMs;
  final lastSample = (rangeEnd ~/ stepMs) * stepMs - stepMs;
  if (lastSample < firstSample) return 0;

  var total = 0;
  const int batchSize = 5000;
  final rows = <Map<String, Object?>>[];

  for (final c in containers) {
    for (var t = firstSample; t <= lastSample; t += stepMs) {
      rows.add(_makeRow(c, sampleMs: t));
      if (rows.length >= batchSize) {
        total += await _insertBatch(db, rows);
        rows.clear();
      }
    }
  }
  if (rows.isNotEmpty) {
    total += await _insertBatch(db, rows);
  }
  return total;
}

Future<int> _insertBatch(Database db, List<Map<String, Object?>> rows) async {
  await db.transaction((txn) async {
    final batch = txn.batch();
    for (final r in rows) {
      batch.insert(
        'tiered_samples',
        r,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  });
  return rows.length;
}

Map<String, Object?> _makeRow(_Container c, {required int sampleMs}) {
  // Closed-form integral mean of the underlying sine wave centred
  // on `sampleMs`. For tier-0 raw rows the "bucket" is a single
  // millisecond window — effectively a point sample, but using the
  // ±500ms integral keeps the value mathematically consistent with
  // what wider-bucket aggregation would produce.
  final t0Sec = (sampleMs - 500) / 1000.0;
  final t1Sec = (sampleMs + 500) / 1000.0;
  final tEndSec = sampleMs / 1000.0;

  final cpu =
      (c.cpuBaseline +
              c.cpuAmplitude *
                  _sineIntegralMean(c.cpuPeriodSeconds, t0Sec, t1Sec))
          .clamp(0.0, 100.0);

  final memMib =
      (c.memBaselineMib +
              c.memAmplitudeMib *
                  _sineIntegralMean(c.memPeriodSeconds, t0Sec, t1Sec))
          .clamp(0.0, c.memLimitBytes / (1024 * 1024));
  final memUsage = (memMib * 1024 * 1024).round();
  final memPct = (memUsage * 100) / c.memLimitBytes;

  int cumul(double rateMbps) {
    final modulator =
        1.0 + 0.3 * math.sin(2 * math.pi * tEndSec / c.cpuPeriodSeconds);
    return (rateMbps * 1024 * 1024 * tEndSec * modulator).round();
  }

  return {
    'granularity': 0,
    'millis': sampleMs,
    'sender_at_sign': '@seed_pub',
    'at_sign': '@seed_pub',
    'hostname': c.hostname,
    'container_id': c.containerId,
    'container_name': c.containerName,
    'image': c.image,
    'cpu_sum': cpu,
    'mem_sum': memUsage,
    'mem_limit_sum': c.memLimitBytes,
    'mem_pct_sum': memPct,
    'pids_sum': 5 + (sampleMs ~/ math.max(1, c.cpuPeriodSeconds.toInt())) % 25,
    'last_net_rx': cumul(c.netRxRateMbps),
    'last_net_tx': cumul(c.netTxRateMbps),
    'last_blk_read': cumul(c.blkReadRateMbps),
    'last_blk_write': cumul(c.blkWriteRateMbps),
    'last_millis': sampleMs,
    'max_restart_count': 0,
    'sample_count': 1,
  };
}

/// Build tier [tier] by GROUPing tier `tier - 1`'s rows into
/// [tierBucketsMs[tier]]-sized buckets. Sum-of-sums, count-of-
/// counts, max-of-maxes, last-of-lasts — produces the same row
/// values the runtime UPSERT path would land on after the
/// equivalent set of raw notifications.
Future<int> _cascadeTier(Database db, int tier) async {
  assert(tier >= 1 && tier <= 4);
  final bucket = _tierBucketsMs[tier];
  final src = tier - 1;
  final bucketExpr = '((millis / $bucket) * $bucket)';
  // For cumulative counters we need the value of the row in each
  // bucket with the maximum last_millis. The columns are monotonic
  // (raw cumulative counters never decrease), so MAX over the
  // bucket equals the latest value. Same for max_restart_count.
  await db.execute('''
    INSERT INTO tiered_samples (
      granularity, millis, sender_at_sign, at_sign, hostname,
      container_id, container_name, image,
      cpu_sum, mem_sum, mem_limit_sum, mem_pct_sum, pids_sum,
      last_net_rx, last_net_tx, last_blk_read, last_blk_write,
      last_millis, max_restart_count, sample_count
    )
    SELECT
      $tier AS granularity,
      $bucketExpr AS bucket_start,
      MAX(sender_at_sign), at_sign, hostname,
      container_id, MAX(container_name), MAX(image),
      SUM(cpu_sum), SUM(mem_sum), SUM(mem_limit_sum),
      SUM(mem_pct_sum), SUM(pids_sum),
      MAX(last_net_rx), MAX(last_net_tx),
      MAX(last_blk_read), MAX(last_blk_write),
      MAX(last_millis), MAX(max_restart_count),
      SUM(sample_count)
    FROM tiered_samples
    WHERE granularity = $src
    GROUP BY at_sign, hostname, container_id, bucket_start
  ''');
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM tiered_samples WHERE granularity = ?',
    [tier],
  );
  return (r.first['c'] as num).toInt();
}

/// Closed-form mean of `sin(2π·t / period)` over `[t0Sec, t1Sec]`.
double _sineIntegralMean(double periodSec, double t0Sec, double t1Sec) {
  if (periodSec <= 0 || t1Sec <= t0Sec) {
    final tMid = (t0Sec + t1Sec) / 2.0;
    return math.sin(2 * math.pi * tMid / (periodSec <= 0 ? 1 : periodSec));
  }
  final omega = 2 * math.pi / periodSec;
  return -(math.cos(omega * t1Sec) - math.cos(omega * t0Sec)) /
      (omega * (t1Sec - t0Sec));
}

String _fmtBucket(int ms) {
  if (ms < 60 * 1000) return '${ms ~/ 1000}s';
  if (ms < 60 * 60 * 1000) return '${ms ~/ 60000}min';
  return '${ms ~/ 3600000}h';
}

String _fmtElapsed(Duration d) {
  if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  return '${d.inMinutes}m${d.inSeconds % 60}s';
}

Duration _parseDuration(String raw) {
  final s = raw.trim().toLowerCase();
  final m = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m|h|d|mo|y)?$',
  ).firstMatch(s);
  if (m == null) {
    throw FormatException('Bad duration "$raw" — try 1y / 6mo / 7d / 2h / 30s');
  }
  final value = double.parse(m.group(1)!);
  switch (m.group(2) ?? 'd') {
    case 'ms':
      return Duration(milliseconds: value.round());
    case 's':
      return Duration(milliseconds: (value * 1000).round());
    case 'm':
      return Duration(milliseconds: (value * 60 * 1000).round());
    case 'h':
      return Duration(milliseconds: (value * 3600 * 1000).round());
    case 'd':
      return Duration(milliseconds: (value * 86400 * 1000).round());
    case 'mo':
      return Duration(milliseconds: (value * 30 * 86400 * 1000).round());
    case 'y':
      return Duration(milliseconds: (value * 365 * 86400 * 1000).round());
  }
  return Duration(seconds: value.round());
}
