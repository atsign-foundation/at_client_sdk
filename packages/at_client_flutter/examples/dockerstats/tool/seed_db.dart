// Seeds the Flutter dockerstats app's SQLite store with synthetic
// samples spanning multiple roll-up tiers, so you can open the
// dashboard and step through every window selector (5m → all)
// against realistic cross-tier data without waiting for real
// publisher → roll-up cycles to elapse.
//
// What it does:
//
//   - Generates samples PRE-ALIGNED to each tier's bucket size, so
//     the resulting DB looks like the steady-state output of a
//     long-running publisher + roll-up loop. No need to run
//     `Roller.rollUpAll()` to get a populated DB (you can if you
//     want — pass `--run-rollup` — but it will be a near-no-op).
//
//   - Tier 0 (5s buckets):  6 hours of raw           → 4320 / container
//     Tier 1 (1m buckets):  6h → 72h                 → 3960 / container
//     Tier 2 (15m buckets): 72h → 45d                → 4128 / container
//     Tier 3 (1h buckets):  45d → 6 months           → 3240 / container
//     Tier 4 (8h buckets):  6mo → --span             → variable
//
//   - Per-metric values come from a sine waveform parameterised
//     per container so chart series stay visually distinct.
//     Cumulative counters (net/blk) are monotonically increasing
//     within each container and reflect "value at bucket-end" so
//     neighbouring buckets diff cleanly.
//
// Where to find the DB the Flutter app uses (macOS):
//
//   ~/Library/Containers/com.example.dockerstats/Data/Library/Application Support/com.example.dockerstats/dockerstats/<atSign>.db
//   ~/Library/Application Support/com.example.dockerstats/dockerstats/<atSign>.db
//
// (The first form is the sandboxed bundle path; the second is the
// non-sandboxed one. Use `find ~/Library -name '<atSign>.db' 2>/dev/null`
// to disambiguate. `<atSign>` is sanitised — `@garycasey` → `_garycasey`.)
//
// Usage:
//
//   dart run tool/seed_db.dart \
//     --db-path /path/to/_garycasey.db \
//     --span 1y \
//     --containers 6 \
//     [--clear-first] [--run-rollup]

import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:dockerstats/services/roller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _createSamplesTable = '''
  CREATE TABLE IF NOT EXISTS samples (
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

// Per-tier bucket sizes and age ranges. Tier 0 lives in `[now-6h, now]`;
// tier 1 in `[now-72h, now-6h]`; etc.
const int _tier0BucketMs = 5 * 1000;
const int _tier1BucketMs = 60 * 1000;
const int _tier2BucketMs = 15 * 60 * 1000;
const int _tier3BucketMs = 60 * 60 * 1000;
const int _tier4BucketMs = 8 * 60 * 60 * 1000;

const Duration _tier0Retention = Duration(hours: 6);
const Duration _tier1Retention = Duration(hours: 72);
const Duration _tier2Retention = Duration(days: 45);
const Duration _tier3Retention = Duration(days: 180);

void main(List<String> args) async {
  final ap = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'db-path',
      mandatory: true,
      help:
          'Path to the SQLite file the Flutter app uses. See the '
          'file header for where to find it.',
    )
    ..addOption(
      'span',
      defaultsTo: '1y',
      help:
          'How far back to seed data, going back from `now`. '
          'Accepts h / d / mo / y units (e.g. 7d, 6mo, 1y, 2y).',
    )
    ..addOption(
      'containers',
      defaultsTo: '6',
      help:
          'Number of (host, container) series to generate. The '
          'first N are split across two hosts, alternating.',
    )
    ..addFlag(
      'clear-first',
      negatable: false,
      help: 'DELETE FROM samples before seeding. Schema preserved.',
    )
    ..addFlag(
      'run-rollup',
      negatable: false,
      help:
          'After seeding, run Roller.rollUpAll() once. With seeded '
          'data already tier-aligned this is a near-no-op, but it '
          'exercises the code path end-to-end.',
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
  final nContainers = int.tryParse(parsed['containers'] as String) ?? 6;
  if (nContainers <= 0) {
    stderr.writeln('--containers must be a positive integer');
    exit(64);
  }
  final clearFirst = parsed['clear-first'] as bool;
  final runRollup = parsed['run-rollup'] as bool;

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async => db.execute(_createSamplesTable),
    ),
  );
  // Re-run the schema in case we opened an existing DB that
  // pre-dates the table being added.
  await db.execute(_createSamplesTable);

  final containers = _buildContainerSet(nContainers);
  stdout.writeln(
    'Seeding ${containers.length} container(s) at $dbPath '
    'for span=${parsed['span']}',
  );

  if (clearFirst) {
    final removed = await db.delete('samples');
    stdout.writeln('  cleared $removed existing row(s)');
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final spanCutoff = now - span.inMilliseconds;

  // Tier age ranges (newer-end → older-end).
  final tier0Start = now - _tier0Retention.inMilliseconds;
  final tier1Start = now - _tier1Retention.inMilliseconds;
  final tier2Start = now - _tier2Retention.inMilliseconds;
  final tier3Start = now - _tier3Retention.inMilliseconds;

  // Tier 0: [tier0Start, now)
  final t0 = await _seedTier(
    db: db,
    granularity: 0,
    bucketMs: _tier0BucketMs,
    rangeStart: math.max(tier0Start, spanCutoff),
    rangeEnd: now,
    containers: containers,
  );
  stdout.writeln('  tier 0 (raw, 5s):    $t0 row(s)');

  // Tier 1: [tier1Start, tier0Start)
  final t1 = await _seedTier(
    db: db,
    granularity: 1,
    bucketMs: _tier1BucketMs,
    rangeStart: math.max(tier1Start, spanCutoff),
    rangeEnd: math.min(tier0Start, now),
    containers: containers,
  );
  stdout.writeln('  tier 1 (1m avg):     $t1 row(s)');

  // Tier 2: [tier2Start, tier1Start)
  final t2 = await _seedTier(
    db: db,
    granularity: 2,
    bucketMs: _tier2BucketMs,
    rangeStart: math.max(tier2Start, spanCutoff),
    rangeEnd: math.min(tier1Start, now),
    containers: containers,
  );
  stdout.writeln('  tier 2 (15m avg):    $t2 row(s)');

  // Tier 3: [tier3Start, tier2Start)
  final t3 = await _seedTier(
    db: db,
    granularity: 3,
    bucketMs: _tier3BucketMs,
    rangeStart: math.max(tier3Start, spanCutoff),
    rangeEnd: math.min(tier2Start, now),
    containers: containers,
  );
  stdout.writeln('  tier 3 (1h avg):     $t3 row(s)');

  // Tier 4: [spanCutoff, tier3Start) — indefinite-retention tier
  // gets everything beyond 6 months.
  final t4 = await _seedTier(
    db: db,
    granularity: 4,
    bucketMs: _tier4BucketMs,
    rangeStart: spanCutoff,
    rangeEnd: math.min(tier3Start, now),
    containers: containers,
  );
  stdout.writeln('  tier 4 (8h avg):     $t4 row(s)');

  stdout.writeln('  total:               ${t0 + t1 + t2 + t3 + t4} row(s)');

  if (runRollup) {
    stdout.writeln('Running Roller.rollUpAll()...');
    final report = await Roller(db).rollUpAll();
    stdout.writeln('  $report');
  }

  await db.close();
  stdout.writeln('Done.');
}

class _Container {
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;
  // Sinusoid parameters used to generate the per-time values.
  final double cpuBaseline; // 5..30
  final double cpuAmplitude; // 5..25
  final double memBaselineMib; // 100..1500
  final double memAmplitudeMib; // 20..400
  final double
  cpuPeriodSeconds; // 600..6000 — distinct so series visibly diverge
  final double memPeriodSeconds;
  final int memLimitBytes;
  final double netRxRateMbps; // ~0.5..3 MB/s avg cumulative gain
  final double netTxRateMbps;
  final double blkReadRateMbps; // ~0.1..1
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
        // Half the containers display as an @atSign label (the docker
        // inspect path), the other half as a plain container name —
        // matches the "container name is either an atSign or a docker
        // name" semantics from the publisher.
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

Future<int> _seedTier({
  required Database db,
  required int granularity,
  required int bucketMs,
  required int rangeStart,
  required int rangeEnd,
  required List<_Container> containers,
}) async {
  if (rangeEnd <= rangeStart) return 0;
  // Align both ends to bucket boundaries.
  final firstBucket = ((rangeStart + bucketMs - 1) ~/ bucketMs) * bucketMs;
  final lastBucket = (rangeEnd ~/ bucketMs) * bucketMs - bucketMs;
  if (lastBucket < firstBucket) return 0;

  // sample_count = how many raw 5s samples would have rolled up
  // into this bucket. For tier 0 that's 1; for tier N>0 it's
  // bucketMs / 5000.
  final sampleCount = granularity == 0 ? 1 : bucketMs ~/ _tier0BucketMs;

  var total = 0;
  const int batchSize = 1000;
  final rows = <Map<String, Object?>>[];

  for (final c in containers) {
    for (var b = firstBucket; b <= lastBucket; b += bucketMs) {
      rows.add(
        _makeRow(
          c,
          granularity: granularity,
          bucketStartMs: b,
          bucketSizeMs: bucketMs,
          sampleCount: sampleCount,
        ),
      );
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
      batch.insert('samples', r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  });
  return rows.length;
}

Map<String, Object?> _makeRow(
  _Container c, {
  required int granularity,
  required int bucketStartMs,
  required int bucketSizeMs,
  required int sampleCount,
}) {
  // Closed-form integral mean over the bucket interval — what a real
  // roll-up chain would converge to after cascading averaging at
  // each tier. Sampling at the midpoint (the previous approach) made
  // tier-4 rows visibly noisier than tier-3 because tier-4's 8 h
  // bucket only got one sine sample at a random phase. The chart
  // showed that as a step at the tier-4/3 boundary even after
  // dashboard-side re-bucketing. Integral mean makes every tier's
  // values converge toward baseline whenever the bucket is wider
  // than the waveform's period, so adjacent tiers line up cleanly.
  final t0Sec = bucketStartMs / 1000.0;
  final t1Sec = (bucketStartMs + bucketSizeMs) / 1000.0;

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

  // Cumulative counters: value at bucket-END. Linear in tBucketEnd
  // with a small sine modulation in the rate so the chart line has
  // some texture. Pick the bucket-end so neighbouring buckets diff
  // cleanly into rate, as a real publisher's cumulative counters
  // would.
  final tEnd = bucketStartMs + bucketSizeMs;
  final tEndSec = tEnd / 1000.0;
  int cumul(double rateMbps) {
    final modulator =
        1.0 + 0.3 * math.sin(2 * math.pi * tEndSec / c.cpuPeriodSeconds);
    return (rateMbps * 1024 * 1024 * tEndSec * modulator).round();
  }

  return {
    'granularity': granularity,
    'millis': bucketStartMs,
    'sender_at_sign': '@seed_pub',
    'at_sign': '@seed_pub',
    'hostname': c.hostname,
    'container_id': c.containerId,
    'container_name': c.containerName,
    'image': c.image,
    'cpu_pct': cpu,
    'mem_usage': memUsage,
    'mem_limit': c.memLimitBytes,
    'mem_pct': memPct,
    'net_rx': cumul(c.netRxRateMbps),
    'net_tx': cumul(c.netTxRateMbps),
    'blk_read': cumul(c.blkReadRateMbps),
    'blk_write': cumul(c.blkWriteRateMbps),
    'pids_count': 5 + (bucketStartMs ~/ bucketSizeMs) % 25,
    'restart_count': 0,
    'sample_count': sampleCount,
  };
}

/// Closed-form mean of `sin(2π·t / period)` over `[t0Sec, t1Sec]`.
/// Falls back to the midpoint sample when the interval is zero-length
/// or the period is non-positive — the same single-point behaviour
/// the previous implementation used everywhere.
double _sineIntegralMean(double periodSec, double t0Sec, double t1Sec) {
  if (periodSec <= 0 || t1Sec <= t0Sec) {
    final tMid = (t0Sec + t1Sec) / 2.0;
    return math.sin(2 * math.pi * tMid / (periodSec <= 0 ? 1 : periodSec));
  }
  final omega = 2 * math.pi / periodSec;
  // ∫ sin(ωt) dt = -cos(ωt)/ω, so the mean over [t0, t1] is
  //   -(cos(ωt1) - cos(ωt0)) / (ω · (t1 - t0)).
  return -(math.cos(omega * t1Sec) - math.cos(omega * t0Sec)) /
      (omega * (t1Sec - t0Sec));
}

Duration _parseDuration(String raw) {
  final s = raw.trim().toLowerCase();
  final m = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m|h|d|mo|y)?$',
  ).firstMatch(s);
  if (m == null) {
    throw FormatException('Bad duration "$raw" — try 1y / 6mo / 7d / 2h');
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
