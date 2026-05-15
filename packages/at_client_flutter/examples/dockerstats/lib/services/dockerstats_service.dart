/// Owns the receive-side state for the dockerstats dashboard:
///   - [SamplesDb] — per-atSign SQLite store, holds every sample
///     indefinitely under the multi-tier roll-up policy.
///   - [WindowCache] — in-memory view of just the current display
///     window, what the chart actually renders.
///   - [Roller] — periodic background job that rolls older raw
///     samples into 1-min / 15-min / 1-hour / 8-hour buckets per
///     the five-tier policy documented on the class.
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
import 'roller.dart';
import 'samples_db.dart';
import 'window_cache.dart';

const String applicationNamespace = 'dockerstats.demos';

class DockerstatsService {
  final AtClient atClient;
  final SamplesDb db;
  final WindowCache cache;
  final Roller roller;
  final _log = AtSignLogger('dockerstats');

  StreamSubscription<AtNotification>? _notifSub;
  Timer? _pruneTimer;
  Timer? _rollupTimer;
  Duration _window;
  bool _backfilling = false;
  bool get backfilling => _backfilling;

  DockerstatsService._(
    this.atClient,
    this.db,
    this.cache,
    this.roller,
    this._window,
  );

  /// Display window. Setting a new value triggers a fresh DB query
  /// for the new range and replaces the cache contents — widening
  /// from 2m → 24h instantly reveals samples that were in the DB
  /// but had been pruned from the cache.
  Duration get window => _window;
  Future<void> setWindow(Duration value) async {
    if (value == _window) return;
    _window = value;
    await _loadWindow();
  }

  static Future<DockerstatsService> create({
    required AtClient atClient,
    required Duration window,
  }) async {
    final db = await SamplesDb.open(atClient.atSign.toString());
    final cache = WindowCache();
    final roller = Roller(db.database);
    final svc = DockerstatsService._(atClient, db, cache, roller, window);
    await svc._init();
    return svc;
  }

  Future<void> _init() async {
    // Force the notification listener up front so the first arrival
    // doesn't race the lazy startup inside subscribe().
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

    // Periodic prune: drop cached samples that have fallen outside
    // the current display window. SQLite retains them; only the
    // in-memory cache is bounded. The "all" window (Duration.zero)
    // disables pruning — we want everything queryable in memory.
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_window == Duration.zero) return;
      final cutoff =
          DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
      cache.pruneOlderThan(cutoff);
    });

    // Initial load — populate the cache from whatever the DB
    // already holds (any tier).
    await _loadWindow();

    // Roll-up: catch-up pass at startup so any samples that aged
    // past their tier boundary while the app was closed get
    // compacted right away. Then every hour thereafter.
    // Background-unawaited so a slow first pass doesn't delay
    // dashboard render.
    unawaited(_rollUp());
    _rollupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_rollUp());
    });
  }

  Future<void> _rollUp() async {
    try {
      await roller.rollUpAll();
      // The roll-up may have removed raw rows that the cache still
      // holds, replacing them with aggregated tier-1 rows. Re-load
      // the window so the cache reflects the new DB shape.
      await _loadWindow();
    } catch (e, st) {
      _log.warning('rollUp failed: $e\n$st');
    }
  }

  Future<void> _loadWindow() async {
    _backfilling = true;
    try {
      // [Duration.zero] is the dashboard's "all" sentinel — pass 0
      // as `sinceMs` so the DB query returns every row in every
      // tier.
      final sinceMs = _window == Duration.zero
          ? 0
          : DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
      final rows = await db.queryWindow(sinceMs);
      cache.replaceAll(rows.map((r) => r.sample));
      _log.info(
        'loaded ${rows.length} sample(s) from db for window '
        '${_window == Duration.zero ? "all" : "${_window.inSeconds}s"}',
      );
    } catch (e, st) {
      _log.warning('loadWindow failed: $e\n$st');
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
      await db.insertRaw(s, senderAtSign: n.from);
    } catch (e, st) {
      _log.warning('db.insertRaw failed for ${s.millis}: $e\n$st');
    }
    // Only fold into the cache if it's within the current display
    // window; older samples sit in the DB and surface on the next
    // setWindow / re-query. `Duration.zero` means "all" — fold
    // everything in.
    if (_window == Duration.zero) {
      cache.add(s);
      return;
    }
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
    if (s.millis >= cutoff) {
      cache.add(s);
    }
  }

  Future<void> dispose() async {
    _pruneTimer?.cancel();
    _rollupTimer?.cancel();
    await _notifSub?.cancel();
    await db.close();
  }
}
