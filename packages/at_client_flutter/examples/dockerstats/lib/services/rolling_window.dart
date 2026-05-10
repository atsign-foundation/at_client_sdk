/// In-memory rolling window of [StatSample]s indexed by (host, atSign).
/// Two separate eviction triggers, neither time-coupled to the other:
///   - **Display-window cutoff** (`_trim`): drops samples older than
///     `now - window`, controlling how much of the recent past the
///     dashboard renders. Driven by the dashboard's redraw timer.
///   - **TTL expiry** (`removeById`): driven externally by
///     [CSubItemDeleted] events arriving on the parent collection's
///     `subDeletes` stream. The local keystore's expiry sweep fires
///     `DataDeleted(wasExpired: true)` on TTL crossing, which
///     AtCollection dispatches as a `CSubItemDeleted` for sub-items;
///     the service hands `event.id` to [removeById] and we drop the
///     matching sample without polling.
/// Plain ListenableValue-style change broadcaster so the dashboard
/// widget can `setState` whenever the contents change.
library;

import 'package:flutter/foundation.dart';

import '../models/stats_models.dart';

class RollingWindow extends ChangeNotifier {
  Duration _window;

  /// host -> per-atSign list of samples, oldest first.
  final Map<String, Map<String, List<StatSample>>> _byHostAtSign = {};

  /// host -> raw hostname (preserves the human-readable form).
  final Map<String, String> hostnames = {};

  /// host -> Set of raw atSigns seen on it.
  final Map<String, Map<String, String>> atSignsByHost = {};

  RollingWindow({Duration window = const Duration(minutes: 2)})
    : _window = window;

  Duration get window => _window;
  set window(Duration value) {
    if (value == _window) return;
    _window = value;
    _trim();
    notifyListeners();
  }

  /// Iterates known hosts (sanitised id keys).
  Iterable<String> get hostIds => _byHostAtSign.keys;

  /// Sample series for [hostId] aggregated across all atSigns. Each
  /// returned list element is the latest sample for one (host, atSign)
  /// at that timestamp; the dashboard sums per-stat across the inner
  /// list to produce one series per host.
  List<StatSample> samplesForHost(String hostId) {
    final inner = _byHostAtSign[hostId];
    if (inner == null) return const [];
    final out = <StatSample>[];
    for (final list in inner.values) {
      out.addAll(list);
    }
    out.sort((a, b) => a.millis.compareTo(b.millis));
    return out;
  }

  /// Sample series for [hostId] split by atSign.
  Map<String, List<StatSample>> samplesForHostByAtSign(String hostId) {
    final inner = _byHostAtSign[hostId];
    if (inner == null) return const {};
    return Map.unmodifiable(inner);
  }

  /// All hostnames known to the window.
  Iterable<MapEntry<String, String>> get hostEntries => hostnames.entries;

  /// Idempotent on `(host, atSign, millis)`: if a sample with the
  /// same millis already exists in the bucket, replace it; otherwise
  /// append. Lets backfill and live events run concurrently without
  /// double-counting — the chart's per-millis aggregator would
  /// otherwise sum duplicate samples and inflate y-values.
  void add(StatSample s) {
    final hostKey = s.hostname.toLowerCase();
    final atKey = s.atSign.toLowerCase();
    hostnames.putIfAbsent(hostKey, () => s.hostname);
    final perHost = atSignsByHost.putIfAbsent(hostKey, () => {});
    perHost.putIfAbsent(atKey, () => s.atSign);
    final inner = _byHostAtSign.putIfAbsent(hostKey, () => {});
    final list = inner.putIfAbsent(atKey, () => []);
    final existingIdx = list.indexWhere((x) => x.millis == s.millis);
    if (existingIdx >= 0) {
      list[existingIdx] = s;
    } else {
      list.add(s);
      list.sort((a, b) => a.millis.compareTo(b.millis));
    }
    _trim();
    notifyListeners();
  }

  /// Drop the sample whose `millis.toString()` matches [id]. The
  /// publisher writes leaves with `id: s.millis.toString()`, so a
  /// `CSubItemDeleted.id` round-trips back to that. Scans across all
  /// (host, atSign) buckets — O(N total samples), bounded by the
  /// display window.
  void removeById(String id) {
    var changed = false;
    for (final hostKey in _byHostAtSign.keys.toList()) {
      final inner = _byHostAtSign[hostKey]!;
      for (final atKey in inner.keys.toList()) {
        final list = inner[atKey]!;
        final before = list.length;
        list.removeWhere((s) => s.millis.toString() == id);
        if (list.length != before) changed = true;
        if (list.isEmpty) {
          inner.remove(atKey);
          atSignsByHost[hostKey]?.remove(atKey);
        }
      }
      if (inner.isEmpty) {
        _byHostAtSign.remove(hostKey);
        hostnames.remove(hostKey);
        atSignsByHost.remove(hostKey);
      }
    }
    if (changed) notifyListeners();
  }

  /// Display-window cutoff: drop samples older than `now - window`.
  /// Empty per-atSign and per-host buckets are also removed so
  /// dropdowns don't keep ghosting nodes that have stopped reporting.
  void _trim() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - window.inMilliseconds;
    for (final hostKey in _byHostAtSign.keys.toList()) {
      final inner = _byHostAtSign[hostKey]!;
      for (final atKey in inner.keys.toList()) {
        final list = inner[atKey]!;
        list.removeWhere((s) => s.millis < cutoff);
        if (list.isEmpty) {
          inner.remove(atKey);
          atSignsByHost[hostKey]?.remove(atKey);
        }
      }
      if (inner.isEmpty) {
        _byHostAtSign.remove(hostKey);
        hostnames.remove(hostKey);
        atSignsByHost.remove(hostKey);
      }
    }
  }

  /// Force a [_trim] pass; used by the dashboard's redraw timer so
  /// chart x-axes don't drift past the display window between ingests.
  void evictExpired() {
    _trim();
    notifyListeners();
  }
}
