// Benchmark the dashboard's per-window SQL queries against a seeded
// DB. Mirrors the bucket-size + tier-picking logic in
// DockerstatsService so the timings match what the live app pays.
//
// Usage:
//   dart run tool/bench_queries.dart --db-path /tmp/bench.db [--repeats 3]

import 'dart:io';

import 'package:args/args.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const List<int> _tierBucketsMs = [
  5 * 1000,
  60 * 1000,
  15 * 60 * 1000,
  60 * 60 * 1000,
  8 * 60 * 60 * 1000,
];

const int _targetBucketsPerSeries = 1000;
const int _minAggregationBucketMs = 5000;

const List<({String label, Duration value})> _windows = [
  (label: '5m', value: Duration(minutes: 5)),
  (label: '15m', value: Duration(minutes: 15)),
  (label: '1h', value: Duration(hours: 1)),
  (label: '5h', value: Duration(hours: 5)),
  (label: '1d', value: Duration(days: 1)),
  (label: '7d', value: Duration(days: 7)),
  (label: '1mo', value: Duration(days: 30)),
  (label: '6mo', value: Duration(days: 180)),
  (label: '2y', value: Duration(days: 730)),
  (label: 'all', value: Duration.zero),
];

void main(List<String> args) async {
  final ap = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('db-path', mandatory: true)
    ..addOption('repeats', defaultsTo: '3');

  final parsed = ap.parse(args);
  if (parsed['help'] == true) {
    stdout.writeln(ap.usage);
    return;
  }

  final dbPath = parsed['db-path'] as String;
  final repeats = int.parse(parsed['repeats'] as String);

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true, version: 3),
  );

  final rowCount = await _scalarInt(db, 'SELECT COUNT(*) FROM tiered_samples');
  final t0Count = await _scalarInt(
    db,
    'SELECT COUNT(*) FROM tiered_samples WHERE granularity = 0',
  );
  final t1Count = await _scalarInt(
    db,
    'SELECT COUNT(*) FROM tiered_samples WHERE granularity = 1',
  );
  final t2Count = await _scalarInt(
    db,
    'SELECT COUNT(*) FROM tiered_samples WHERE granularity = 2',
  );
  final t3Count = await _scalarInt(
    db,
    'SELECT COUNT(*) FROM tiered_samples WHERE granularity = 3',
  );
  final t4Count = await _scalarInt(
    db,
    'SELECT COUNT(*) FROM tiered_samples WHERE granularity = 4',
  );
  final earliestMs = await _scalarInt(
    db,
    'SELECT MIN(millis) FROM tiered_samples',
  );
  final latestMs = await _scalarInt(
    db,
    'SELECT MAX(millis) FROM tiered_samples',
  );
  final dbBytes = File(dbPath).statSync().size;
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  stdout.writeln('DB:        $dbPath');
  stdout.writeln('size:      ${_humanBytes(dbBytes)}');
  stdout.writeln(
    'rows:      ${_fmtNum(rowCount)} total — '
    't0=${_fmtNum(t0Count)} '
    't1=${_fmtNum(t1Count)} '
    't2=${_fmtNum(t2Count)} '
    't3=${_fmtNum(t3Count)} '
    't4=${_fmtNum(t4Count)}',
  );
  stdout.writeln(
    'time span: ${_fmtMs(earliestMs)}  →  ${_fmtMs(latestMs)}  '
    '(${_fmtDuration(latestMs - earliestMs)})',
  );
  stdout.writeln('now:       ${_fmtMs(nowMs)}');
  stdout.writeln('repeats:   $repeats per window (reporting median ms)');
  stdout.writeln('');

  stdout.writeln(
    '${_pad("window", 6)}  '
    '${_pad("tier", 4)}  '
    '${_padR("bucket", 10)}  '
    '${_padR("source rows", 11)}  '
    '${_padR("returned rows", 13)}  '
    '${_padR("median ms", 9)}  '
    '${_padR("min", 7)}  '
    '${_padR("max", 7)}',
  );
  stdout.writeln(
    '${'-' * 6}  ${'-' * 4}  ${'-' * 10}  ${'-' * 11}  ${'-' * 13}  '
    '${'-' * 9}  ${'-' * 7}  ${'-' * 7}',
  );

  for (final w in _windows) {
    final int sinceMs;
    final int spanMs;
    if (w.value == Duration.zero) {
      sinceMs = 0;
      spanMs = nowMs - earliestMs;
    } else {
      sinceMs = nowMs - w.value.inMilliseconds;
      spanMs = w.value.inMilliseconds;
    }
    final shape = _computeReadShape(spanMs);
    final tier = shape.tier;
    final regroupMs = shape.bucketMs;
    final tierBucket = _tierBucketsMs[tier];
    final effectiveBucketMs = regroupMs == 0 ? tierBucket : regroupMs;

    final sourceWhere = sinceMs > 0
        ? 'granularity = $tier AND millis >= $sinceMs'
        : 'granularity = $tier';
    final sourceRows = await _scalarInt(
      db,
      'SELECT COUNT(*) FROM tiered_samples WHERE $sourceWhere',
    );

    final timings = <int>[];
    int returnedRows = 0;
    for (var i = 0; i < repeats; i++) {
      final sw = Stopwatch()..start();
      final rows = await _runQuery(
        db,
        tier: tier,
        sinceMs: sinceMs,
        bucketMs: effectiveBucketMs,
      );
      sw.stop();
      timings.add(sw.elapsedMilliseconds);
      returnedRows = rows;
    }
    timings.sort();
    final median = timings[timings.length ~/ 2];
    final minMs = timings.first;
    final maxMs = timings.last;

    stdout.writeln(
      '${_pad(w.label, 6)}  '
      '${_pad("t$tier", 4)}  '
      '${_padR(_fmtBucket(effectiveBucketMs), 10)}  '
      '${_padR(_fmtNum(sourceRows), 11)}  '
      '${_padR(_fmtNum(returnedRows), 13)}  '
      '${_padR(median.toString(), 9)}  '
      '${_padR(minMs.toString(), 7)}  '
      '${_padR(maxMs.toString(), 7)}',
    );
  }

  await db.close();
}

({int tier, int bucketMs}) _computeReadShape(int spanMs) {
  if (spanMs <= 0) return (tier: 0, bucketMs: 0);
  final raw = spanMs ~/ _targetBucketsPerSeries;
  final target = raw < _minAggregationBucketMs ? 0 : raw;
  var t = 0;
  for (var i = 0; i < _tierBucketsMs.length; i++) {
    if (_tierBucketsMs[i] <= (target == 0 ? _tierBucketsMs[0] : target)) t = i;
  }
  return (tier: t, bucketMs: target);
}

Future<int> _runQuery(
  Database db, {
  required int tier,
  required int sinceMs,
  required int bucketMs,
}) async {
  final tierBucket = _tierBucketsMs[tier];
  final regroup = bucketMs > tierBucket;
  final whereParts = <String>['granularity = ?'];
  final args = <Object?>[tier];
  if (sinceMs > 0) {
    whereParts.add('millis >= ?');
    args.add(sinceMs);
  }
  final whereClause = whereParts.join(' AND ');
  if (!regroup) {
    final rows = await db.rawQuery('''
      SELECT
        millis AS bucket_start, hostname, container_id,
        cpu_sum / CAST(sample_count AS REAL) AS cpu_pct,
        last_net_rx AS net_rx
      FROM tiered_samples
      WHERE $whereClause
      ''', args);
    return rows.length;
  }
  final bucketExpr = '((millis / $bucketMs) * $bucketMs)';
  final rows = await db.rawQuery('''
    SELECT
      $bucketExpr AS bucket_start,
      hostname, container_id,
      SUM(cpu_sum) / CAST(SUM(sample_count) AS REAL) AS cpu_pct,
      MAX(last_net_rx) AS net_rx
    FROM tiered_samples
    WHERE $whereClause
    GROUP BY hostname, container_id, bucket_start
    ''', args);
  return rows.length;
}

Future<int> _scalarInt(Database db, String sql, [List<Object?>? args]) async {
  final r = await db.rawQuery(sql, args);
  final v = r.first.values.first;
  return v == null ? 0 : (v as num).toInt();
}

String _pad(String s, int n) => s.length >= n ? s : s + ' ' * (n - s.length);
String _padR(String s, int n) => s.length >= n ? s : ' ' * (n - s.length) + s;

String _fmtNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _humanBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KiB';
  if (n < 1024 * 1024 * 1024) {
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}

String _fmtMs(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String _fmtBucket(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60 * 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
  if (ms < 60 * 60 * 1000) return '${(ms / 60000).toStringAsFixed(1)}m';
  if (ms < 24 * 60 * 60 * 1000) return '${(ms / 3600000).toStringAsFixed(1)}h';
  return '${(ms / (24 * 3600000)).toStringAsFixed(1)}d';
}

String _fmtDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60 * 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
  if (ms < 60 * 60 * 1000) return '${(ms / 60000).toStringAsFixed(1)}m';
  if (ms < 24 * 60 * 60 * 1000) return '${(ms / 3600000).toStringAsFixed(1)}h';
  return '${(ms / (24 * 3600000)).toStringAsFixed(1)}d';
}
