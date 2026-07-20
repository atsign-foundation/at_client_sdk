/// Owns the receive-side state for the dockerstats dashboard:
///   - [SamplesDb] — per-atSign SQLite store. Tier 0 (raw) is kept
///     for [tier0Retention]; aggregated tiers 1..4 are kept forever
///     and updated incrementally on every notification.
///   - [WindowCache] — in-memory view of the current [VisibleRange]
///     at the chart's pixel-budget granularity. Live notifications
///     fold into bucket accumulators directly.
///   - A notification subscription that decodes each arriving
///     sample into both stores.
///
/// Wire shape (matches `dockerstats_publish.dart`):
///
///     key  = @recipient:sample.<sanitised-container>.<sanitised-host>.dockerstats.demos@sender
///     body = jsonEncode(StatSample.toJson())
library;

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

import '../models/stats_models.dart';
import '../models/visible_range.dart';
import 'samples_db.dart';
import 'window_cache.dart';

const String applicationNamespace = 'dockerstats.demos';

/// Number of buckets we aim to render per chart series. The chart
/// is a few hundred pixels wide in a 2x2 grid; rendering more than
/// a couple of thousand points per series is wasted work.
const int _targetBucketsPerSeries = 1000;

/// Below this size the publisher's natural cadence is finer than
/// the chart needs anyway — skip bucket aggregation and read raw.
const int _minAggregationBucketMs = 5000;

class DockerstatsService {
  final AtClient atClient;
  final SamplesDb db;
  final WindowCache cache;
  final _log = AtSignLogger('dockerstats');

  StreamSubscription<AtNotification>? _notifSub;
  Timer? _pruneTimer;
  Timer? _retentionTimer;
  VisibleRange _range;
  DataExtent _dataExtent = const DataExtent(earliestMs: null, latestMs: null);
  bool _backfilling = false;
  bool get backfilling => _backfilling;

  DockerstatsService._(this.atClient, this.db, this.cache, this._range);

  /// Visible time range. Setting a new value triggers a fresh DB
  /// query at a recomputed tier + bucket size and replaces the
  /// cache contents.
  VisibleRange get range => _range;
  Future<void> setRange(VisibleRange r) async {
    if (r == _range) return;
    _range = r;
    await _loadRange();
  }

  /// Most recent observed data extent (earliest / latest `millis`
  /// across all tiers). Refreshed every time the cache is
  /// repopulated and on each live notification. The dashboard
  /// reads this to clamp pan / zoom and to drive the "Fit" button.
  DataExtent get dataExtent => _dataExtent;

  static Future<DockerstatsService> create({
    required AtClient atClient,
    required VisibleRange range,
  }) async {
    final db = await SamplesDb.open(atClient.atSign.toString());
    final cache = WindowCache();
    final svc = DockerstatsService._(atClient, db, cache, range);
    await svc._init();
    return svc;
  }

  Future<void> _init() async {
    atClient.notificationService.startListening();

    final selfFragment = RegExp.escape(atClient.atSign.toString());
    final nsTail = RegExp.escape('.$applicationNamespace');
    final regex = '^$selfFragment:sample\\.[^.]+\\.[^.]+$nsTail@';
    _log.info('subscribing with regex $regex');

    _notifSub = atClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen(
          _onNotification,
          onError: (Object e, StackTrace st) {
            _log.warning('subscribe error: $e\n$st');
          },
        );

    // Periodic prune: when the range is live, the left edge moves
    // forward over time. Drop cache accumulators that have slipped
    // outside the visible window. Historical ranges are fixed in
    // time so pruning is a no-op.
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_range.isLive) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      cache.pruneOlderThan(_range.resolveStartMs(nowMs));
    });

    // Tier-0 retention. Once at startup (catches up after any
    // long-offline gap), then daily.
    unawaited(_pruneTier0());
    _retentionTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => unawaited(_pruneTier0()),
    );

    await _refreshDataExtent();
    await _loadRange();
  }

  Future<void> _pruneTier0() async {
    try {
      final cutoff =
          DateTime.now().millisecondsSinceEpoch - tier0Retention.inMilliseconds;
      final removed = await db.pruneTier0OlderThan(cutoff);
      if (removed > 0) {
        _log.info(
          'pruned $removed tier-0 row(s) older than ${tier0Retention.inDays}d',
        );
      }
    } catch (e, st) {
      _log.warning('pruneTier0 failed: $e\n$st');
    }
  }

  Future<void> _refreshDataExtent() async {
    try {
      _dataExtent = await db.dataExtent();
    } catch (e, st) {
      _log.warning('dataExtent failed: $e\n$st');
    }
  }

  /// Pick the source tier and chart bucket size for the current
  /// `_range`. Target bucket = span / target-bucket-count; coarsest
  /// tier whose source bucket ≤ target.
  ({int tier, int bucketMs}) _computeReadShape() {
    final spanMs = _range.spanMs;
    if (spanMs <= 0) return (tier: 0, bucketMs: 0);
    final raw = spanMs ~/ _targetBucketsPerSeries;
    final targetBucketMs = raw < _minAggregationBucketMs ? 0 : raw;
    final tier = SamplesDb.pickTier(
      targetBucketMs == 0 ? tierBucketsMs[0] : targetBucketMs,
    );
    return (tier: tier, bucketMs: targetBucketMs);
  }

  Future<void> _loadRange() async {
    _backfilling = true;
    try {
      final shape = _computeReadShape();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final sinceMs = _range.resolveStartMs(nowMs);
      final untilMs = _range.isLive ? null : _range.resolveEndMs(nowMs);
      final effectiveBucketMs = shape.bucketMs == 0
          ? tierBucketsMs[shape.tier]
          : shape.bucketMs;
      cache.setBucketMsAndClear(shape.bucketMs);
      final rows = await db.queryWindow(
        tier: shape.tier,
        sinceMs: sinceMs,
        untilMs: untilMs,
        bucketMs: effectiveBucketMs,
      );
      cache.replaceAll(rows);
      _log.info(
        'loaded ${rows.length} bucket(s) from tier ${shape.tier} '
        'for span=${_range.spanMs}ms '
        '${_range.isLive ? "(live)" : "(historical end=${_range.endMs})"} '
        'at bucket=${shape.bucketMs == 0 ? "raw" : "${shape.bucketMs}ms"}',
      );
    } catch (e, st) {
      _log.warning('loadRange failed: $e\n$st');
    } finally {
      _backfilling = false;
    }
  }

  Future<void> _onNotification(AtNotification n) async {
    final value = n.value;
    if (value == null || value.isEmpty) return;
    StatSample s;
    try {
      s = StatSample.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (e) {
      _log.warning('decode failed for ${n.key} from ${n.from}: $e');
      return;
    }
    try {
      await db.insertSample(s, senderAtSign: n.from);
    } catch (e, st) {
      _log.warning('db.insertSample failed for ${s.millis}: $e\n$st');
    }
    // Keep the data extent fresh — the dashboard's pan / zoom
    // clamps reference it.
    if (_dataExtent.latestMs == null || s.millis > _dataExtent.latestMs!) {
      _dataExtent = DataExtent(
        earliestMs: _dataExtent.earliestMs ?? s.millis,
        latestMs: s.millis,
      );
    }
    // Fold into the cache only when the sample falls inside the
    // current visible range. Historical ranges are frozen — they
    // don't pick up new samples until the user moves the range
    // (which triggers a fresh DB query).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = _range.resolveStartMs(nowMs);
    final endMs = _range.resolveEndMs(nowMs);
    if (s.millis >= startMs && s.millis < endMs) {
      cache.addRaw(s);
    }
  }

  Future<void> dispose() async {
    _pruneTimer?.cancel();
    _retentionTimer?.cancel();
    await _notifSub?.cancel();
    await db.close();
  }
}
