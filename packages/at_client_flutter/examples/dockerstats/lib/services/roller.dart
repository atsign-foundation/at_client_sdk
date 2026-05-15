/// Five-tier roll-up policy for dockerstats samples.
///
/// Tier sizing is designed so every tier holds ~4320 samples per
/// container per (host, container) in steady state — equal-count
/// across tiers (within ±1.4% at default 5s publishing). Each tier
/// defines a wall-clock bucket size and a retention duration
/// before its rows roll up into the next coarser tier:
///
/// | tier | bucket | retention before roll-up |
/// |------|--------|--------------------------|
/// | 0    | 5s     | 6 hours                  |
/// | 1    | 1 min  | 72 hours                 |
/// | 2    | 15 min | 45 days                  |
/// | 3    | 1 hour | 6 months (~180 days)     |
/// | 4    | 8 hours| 4 years, then indefinite |
///
/// Aggregation per field, per the design discussion:
///   - **mean** (weighted by `sample_count`): `cpu_pct`, `mem_pct`,
///     `mem_usage`, `pids_count`.
///   - **last** (value of the highest-`millis` row in the bucket —
///     lets consumers diff neighbouring buckets to recover a rate
///     for cumulative counters): `net_rx`, `net_tx`, `blk_read`,
///     `blk_write`, `mem_limit`, `container_name`, `image`,
///     `sender_at_sign`.
///   - **max**: `restart_count`.
///   - **sum**: `sample_count` (so a tier-N row records how many
///     underlying tier-0 raw samples it represents).
///
/// Bucket millis = bucket start, i.e.
/// `floor(sourceMillis / bucketMs) × bucketMs`. So a 15-min bucket
/// for samples taken between 14:00 and 14:14:59 has millis
/// corresponding to 14:00:00 wall-clock.
library;

import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Roller {
  final Database db;
  final _log = AtSignLogger('dockerstats.roller');

  Roller(this.db);

  // Tier retention boundaries. A source-tier row whose `millis` is
  // older than the boundary gets rolled up into the next tier.
  static const Duration _tier0Retention = Duration(hours: 6);
  static const Duration _tier1Retention = Duration(hours: 72);
  static const Duration _tier2Retention = Duration(days: 45);
  static const Duration _tier3Retention = Duration(days: 180);

  // Target-tier bucket sizes, in milliseconds.
  static const int _tier1BucketMs = 60 * 1000;
  static const int _tier2BucketMs = 15 * 60 * 1000;
  static const int _tier3BucketMs = 60 * 60 * 1000;
  static const int _tier4BucketMs = 8 * 60 * 60 * 1000;

  /// Run all four roll-up passes in sequence. Returns a summary
  /// suitable for logging. Safe to call concurrently with live
  /// inserts — sqflite serialises the transactions.
  ///
  /// [now], when supplied, overrides the wall-clock reference the
  /// retention cutoffs are computed against. Tests use this to
  /// fast-forward through the tier boundaries without waiting 6h /
  /// 72h / 45d for the real clock to catch up. Production callers
  /// leave it null and the real `DateTime.now()` is used.
  Future<RollupReport> rollUpAll({DateTime? now}) async {
    final report = RollupReport();
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    report.passes.add(
      await _rollOneTier(
        sourceGranularity: 0,
        targetGranularity: 1,
        targetBucketMs: _tier1BucketMs,
        olderThanMs: nowMs - _tier0Retention.inMilliseconds,
      ),
    );
    report.passes.add(
      await _rollOneTier(
        sourceGranularity: 1,
        targetGranularity: 2,
        targetBucketMs: _tier2BucketMs,
        olderThanMs: nowMs - _tier1Retention.inMilliseconds,
      ),
    );
    report.passes.add(
      await _rollOneTier(
        sourceGranularity: 2,
        targetGranularity: 3,
        targetBucketMs: _tier3BucketMs,
        olderThanMs: nowMs - _tier2Retention.inMilliseconds,
      ),
    );
    report.passes.add(
      await _rollOneTier(
        sourceGranularity: 3,
        targetGranularity: 4,
        targetBucketMs: _tier4BucketMs,
        olderThanMs: nowMs - _tier3Retention.inMilliseconds,
      ),
    );
    _log.info('rollup complete: $report');
    return report;
  }

  Future<TierRollupReport> _rollOneTier({
    required int sourceGranularity,
    required int targetGranularity,
    required int targetBucketMs,
    required int olderThanMs,
  }) async {
    final rows = await db.query(
      'samples',
      where: 'granularity = ? AND millis < ?',
      whereArgs: [sourceGranularity, olderThanMs],
      orderBy: 'at_sign, hostname, container_id, millis ASC',
    );
    if (rows.isEmpty) {
      return TierRollupReport(
        sourceGranularity: sourceGranularity,
        targetGranularity: targetGranularity,
        sourceRowsConsumed: 0,
        targetBucketsWritten: 0,
      );
    }

    // Group in memory by (at_sign, hostname, container_id,
    // bucket_start). Approach (a) per the design discussion:
    // simpler and clearer than equivalent SQL with window
    // functions, fast enough for retention-bounded volumes.
    final buckets = <String, _BucketAccum>{};
    for (final row in rows) {
      final ms = row['millis'] as int;
      final bucketStart = (ms ~/ targetBucketMs) * targetBucketMs;
      final atSign = row['at_sign'] as String;
      final hostname = row['hostname'] as String;
      final containerId = row['container_id'] as String;
      final key = '$atSign|$hostname|$containerId|$bucketStart';
      final accum = buckets.putIfAbsent(
        key,
        () => _BucketAccum(
          bucketStartMs: bucketStart,
          atSign: atSign,
          hostname: hostname,
          containerId: containerId,
        ),
      );
      accum.absorb(row);
    }

    // Atomic INSERT + DELETE so we never lose data on a crash mid
    // roll-up. INSERT OR REPLACE handles the case where an
    // earlier partial run already wrote into the target bucket.
    await db.transaction((txn) async {
      for (final accum in buckets.values) {
        await txn.insert(
          'samples',
          accum.toRow(targetGranularity),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.delete(
        'samples',
        where: 'granularity = ? AND millis < ?',
        whereArgs: [sourceGranularity, olderThanMs],
      );
    });

    return TierRollupReport(
      sourceGranularity: sourceGranularity,
      targetGranularity: targetGranularity,
      sourceRowsConsumed: rows.length,
      targetBucketsWritten: buckets.length,
    );
  }
}

class _BucketAccum {
  final int bucketStartMs;
  final String atSign;
  final String hostname;
  final String containerId;

  // Weighted-mean accumulators. `weightSum` is the sum of input
  // `sample_count`s, so rolling tier-1 (which already has
  // sample_count = 60-ish) into tier-2 weights correctly even
  // though each tier-1 row counts as multiple raw samples.
  double cpuPctSum = 0;
  double memPctSum = 0;
  num memUsageSum = 0;
  num pidsCountSum = 0;
  int weightSum = 0;

  // "Last" fields — value of the row with the highest `millis`
  // within the bucket. Tracks `_lastMillis` to decide which row
  // wins.
  int _lastMillis = -1;
  String senderAtSign = '';
  String containerName = '';
  String image = '';
  int memLimit = 0;
  int netRx = 0;
  int netTx = 0;
  int blkRead = 0;
  int blkWrite = 0;

  // Max.
  int restartCount = 0;

  _BucketAccum({
    required this.bucketStartMs,
    required this.atSign,
    required this.hostname,
    required this.containerId,
  });

  void absorb(Map<String, Object?> row) {
    final weight = (row['sample_count'] as int);
    final cpuPct = (row['cpu_pct'] as num).toDouble();
    final memPct = (row['mem_pct'] as num).toDouble();
    final memUsage = (row['mem_usage'] as num);
    final pidsCount = (row['pids_count'] as num);

    cpuPctSum += cpuPct * weight;
    memPctSum += memPct * weight;
    memUsageSum += memUsage * weight;
    pidsCountSum += pidsCount * weight;
    weightSum += weight;

    final ms = row['millis'] as int;
    if (ms > _lastMillis) {
      _lastMillis = ms;
      senderAtSign = row['sender_at_sign'] as String;
      containerName = row['container_name'] as String;
      image = row['image'] as String;
      memLimit = (row['mem_limit'] as num).toInt();
      netRx = (row['net_rx'] as num).toInt();
      netTx = (row['net_tx'] as num).toInt();
      blkRead = (row['blk_read'] as num).toInt();
      blkWrite = (row['blk_write'] as num).toInt();
    }

    final rc = (row['restart_count'] as num).toInt();
    if (rc > restartCount) restartCount = rc;
  }

  Map<String, Object?> toRow(int granularity) => {
    'granularity': granularity,
    'millis': bucketStartMs,
    'sender_at_sign': senderAtSign,
    'at_sign': atSign,
    'hostname': hostname,
    'container_id': containerId,
    'container_name': containerName,
    'image': image,
    'cpu_pct': cpuPctSum / weightSum,
    'mem_usage': (memUsageSum / weightSum).round(),
    'mem_limit': memLimit,
    'mem_pct': memPctSum / weightSum,
    'net_rx': netRx,
    'net_tx': netTx,
    'blk_read': blkRead,
    'blk_write': blkWrite,
    'pids_count': (pidsCountSum / weightSum).round(),
    'restart_count': restartCount,
    'sample_count': weightSum,
  };
}

/// Per-roll-up-pass summary, suitable for an info log line.
class TierRollupReport {
  final int sourceGranularity;
  final int targetGranularity;
  final int sourceRowsConsumed;
  final int targetBucketsWritten;

  const TierRollupReport({
    required this.sourceGranularity,
    required this.targetGranularity,
    required this.sourceRowsConsumed,
    required this.targetBucketsWritten,
  });

  @override
  String toString() =>
      'tier $sourceGranularity → $targetGranularity: '
      '$sourceRowsConsumed src rows → $targetBucketsWritten buckets';
}

class RollupReport {
  final List<TierRollupReport> passes = [];

  @override
  String toString() => passes.map((p) => p.toString()).join('; ');
}
