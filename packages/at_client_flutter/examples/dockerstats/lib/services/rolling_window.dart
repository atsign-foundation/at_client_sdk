/// In-memory rolling window of [StatSample]s indexed by (host, atSign).
/// Discards points older than [window] on every insert + on every read.
/// Plain ListenableValue-style change broadcaster so the dashboard widget
/// can `setState` whenever new data arrives.
library;

import 'package:flutter/foundation.dart';

import '../models/stats_models.dart';

class RollingWindow extends ChangeNotifier {
  final Duration window;

  /// host -> ordered list of (host, atSign, samples), oldest first.
  /// Per (host, atSign) pair we keep a list ordered by `millis`.
  final Map<String, Map<String, List<StatSample>>> _byHostAtSign = {};

  /// host -> raw hostname (preserves the human-readable form).
  final Map<String, String> hostnames = {};

  /// host -> Set of raw atSigns seen on it.
  final Map<String, Map<String, String>> atSignsByHost = {};

  RollingWindow({this.window = const Duration(minutes: 5)});

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

  void add(StatSample s) {
    final hostKey = s.hostname.toLowerCase();
    final atKey = s.atSign.toLowerCase();
    hostnames.putIfAbsent(hostKey, () => s.hostname);
    final perHost = atSignsByHost.putIfAbsent(hostKey, () => {});
    perHost.putIfAbsent(atKey, () => s.atSign);
    final inner = _byHostAtSign.putIfAbsent(hostKey, () => {});
    final list = inner.putIfAbsent(atKey, () => []);
    list.add(s);
    list.sort((a, b) => a.millis.compareTo(b.millis));
    _trim();
    notifyListeners();
  }

  void addAll(Iterable<StatSample> samples) {
    var changed = false;
    for (final s in samples) {
      final hostKey = s.hostname.toLowerCase();
      final atKey = s.atSign.toLowerCase();
      hostnames.putIfAbsent(hostKey, () => s.hostname);
      final perHost = atSignsByHost.putIfAbsent(hostKey, () => {});
      perHost.putIfAbsent(atKey, () => s.atSign);
      final inner = _byHostAtSign.putIfAbsent(hostKey, () => {});
      final list = inner.putIfAbsent(atKey, () => []);
      list.add(s);
      list.sort((a, b) => a.millis.compareTo(b.millis));
      changed = true;
    }
    if (changed) {
      _trim();
      notifyListeners();
    }
  }

  /// Remove samples whose timestamp is older than `now - window`. Also
  /// drops empty per-atSign and per-host buckets so dropdowns don't
  /// keep ghosting nodes that have stopped reporting.
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
  /// chart x-axes don't drift past the window.
  void evictExpired() {
    _trim();
    notifyListeners();
  }
}
