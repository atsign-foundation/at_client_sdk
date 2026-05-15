/// In-memory view of the samples currently within the display
/// window, keyed by (sanitised hostname, container id). Populated
/// from `SamplesDb.queryWindow(...)` at startup and on every
/// window-selector change; appended to live as notifications
/// arrive.
///
/// Identity is `(host, containerId)` — the docker container ID is
/// the unique key for a running container. Some containers carry
/// an atSign (the publisher pulls it out of `docker inspect` args
/// starting with `@`); others don't. The display label is the
/// sample's `containerName` field, which is either an atSign or
/// the docker container name depending on what the publisher
/// chose.
///
/// Storage retention is independent of this cache — SQLite holds
/// everything indefinitely under the multi-tier roll-up policy.
/// The cache only ever carries the current display window's worth;
/// a periodic [pruneOlderThan] sweep run by the service keeps it
/// bounded so a long-running session doesn't accumulate hours of
/// unused samples in RAM.
library;

import 'package:flutter/foundation.dart';

import '../models/stats_models.dart';

const int _maxSegmentLen = 55;

/// Mirror of the publisher's `sanitiseSegment` so the host bucket
/// keys match the sanitised hostnames the publisher embeds in
/// notification namespaces. Lowercase + replace non-`[a-z0-9_-]`
/// with `_`; trim leading and trailing `_`.
String _sanitise(String input) {
  if (input.isEmpty) return 'empty';
  final cleaned = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  final base = trimmed.isEmpty ? 'x' : trimmed;
  if (base.length <= _maxSegmentLen) return base;
  return base.substring(0, _maxSegmentLen);
}

class WindowCache extends ChangeNotifier {
  /// hostKey → containerId → list of samples, oldest first.
  final Map<String, Map<String, List<StatSample>>> _byHostContainer = {};

  /// hostKey → raw hostname (preserves the human-readable form).
  final Map<String, String> hostnames = {};

  /// hostKey → containerId → display containerName (`@atSign` or a
  /// docker container name, depending on what the publisher chose).
  final Map<String, Map<String, String>> containerNamesByHost = {};

  /// Iterates known hosts (sanitised id keys).
  Iterable<String> get hostIds => _byHostContainer.keys;

  /// True iff no samples are currently cached. Used by the dashboard
  /// to surface a "no data" alert in the status bar.
  bool get isEmpty => _byHostContainer.isEmpty;

  /// Sample series for [hostId] aggregated across all containers on
  /// that host. The dashboard's per-millis aggregator sums across
  /// the returned list to produce one host-level series for each
  /// metric.
  List<StatSample> samplesForHost(String hostId) {
    final inner = _byHostContainer[hostId];
    if (inner == null) return const [];
    final out = <StatSample>[];
    for (final list in inner.values) {
      out.addAll(list);
    }
    out.sort((a, b) => a.millis.compareTo(b.millis));
    return out;
  }

  /// Sample series for [hostId] split by container id.
  Map<String, List<StatSample>> samplesForHostByContainer(String hostId) {
    final inner = _byHostContainer[hostId];
    if (inner == null) return const {};
    return Map.unmodifiable(inner);
  }

  /// Idempotent on `(host, containerId, millis)`: if a sample with
  /// the same millis already exists in the bucket, replace it;
  /// otherwise append. Lets the initial DB load and live arrivals
  /// run concurrently without double-counting.
  void add(StatSample s) {
    final hostKey = _sanitise(s.hostname);
    final containerKey = s.containerId;
    hostnames.putIfAbsent(hostKey, () => s.hostname);
    final perHost = containerNamesByHost.putIfAbsent(hostKey, () => {});
    perHost[containerKey] = s.containerName;
    final inner = _byHostContainer.putIfAbsent(hostKey, () => {});
    final list = inner.putIfAbsent(containerKey, () => []);
    final existingIdx = list.indexWhere((x) => x.millis == s.millis);
    if (existingIdx >= 0) {
      list[existingIdx] = s;
    } else {
      list.add(s);
      list.sort((a, b) => a.millis.compareTo(b.millis));
    }
    notifyListeners();
  }

  /// Replace the entire cache contents with [samples] in one pass —
  /// no per-row notify. Used by `loadWindow` after a DB query so the
  /// dashboard sees a single rebuild rather than one rebuild per
  /// inserted row.
  void replaceAll(Iterable<StatSample> samples) {
    _byHostContainer.clear();
    hostnames.clear();
    containerNamesByHost.clear();
    for (final s in samples) {
      final hostKey = _sanitise(s.hostname);
      final containerKey = s.containerId;
      hostnames.putIfAbsent(hostKey, () => s.hostname);
      final perHost = containerNamesByHost.putIfAbsent(hostKey, () => {});
      perHost[containerKey] = s.containerName;
      final inner = _byHostContainer.putIfAbsent(hostKey, () => {});
      final list = inner.putIfAbsent(containerKey, () => []);
      list.add(s);
    }
    for (final inner in _byHostContainer.values) {
      for (final list in inner.values) {
        list.sort((a, b) => a.millis.compareTo(b.millis));
      }
    }
    notifyListeners();
  }

  /// Drop cached samples whose `millis < cutoffMs`. Called by the
  /// service's periodic prune timer to bound memory: SQLite retains
  /// everything (under the multi-tier roll-up), this cache only
  /// carries the current display window. Empty per-container and
  /// per-host buckets are also removed so chips don't ghost
  /// containers that have stopped reporting.
  void pruneOlderThan(int cutoffMs) {
    var changed = false;
    for (final hostKey in _byHostContainer.keys.toList()) {
      final inner = _byHostContainer[hostKey]!;
      for (final containerKey in inner.keys.toList()) {
        final list = inner[containerKey]!;
        final before = list.length;
        list.removeWhere((s) => s.millis < cutoffMs);
        if (list.length != before) changed = true;
        if (list.isEmpty) {
          inner.remove(containerKey);
          containerNamesByHost[hostKey]?.remove(containerKey);
        }
      }
      if (inner.isEmpty) {
        _byHostContainer.remove(hostKey);
        hostnames.remove(hostKey);
        containerNamesByHost.remove(hostKey);
      }
    }
    if (changed) notifyListeners();
  }
}
