/// In-memory rolling window of [StatSample]s indexed by
/// (sanitised host, sanitised atSign). The key sanitisation matches
/// the publisher's [sanitiseSegment] so that
/// `CSubItemDeleted.ancestry` ids (which carry the sanitised forms
/// the publisher used as parent CItem ids) line up directly with
/// the bucket keys here.
///
/// **Storage retention is decoupled from the display window.** The
/// rolling window holds every sample it sees until the publisher's
/// TTL drives a `CSubItemDeleted` event (via the local keystore's
/// expiry sweep), at which point [removeById] drops the matching
/// (host, atSign, millis) entry. The dashboard's [window] property
/// affects only what the chart RENDERS — the chart filters points
/// by `millis >= now - window` at paint time — so flipping the
/// window selector (2m ↔ 24h) instantly reveals or hides existing
/// samples without losing them.
library;

import 'package:flutter/foundation.dart';

import '../models/stats_models.dart';

const int _maxSegmentLen = 55;

/// Receiver-side mirror of the publisher's `sanitiseSegment`
/// (`packages/at_client/example/lib/dockerstats/models.dart`).
/// Lowercase + replace non-`[a-z0-9_-]` with `_`; trim leading and
/// trailing `_`. Tracking the publisher byte-for-byte so the keys
/// here line up with the parent-CItem ids carried in
/// `CSubItemDeleted.ancestry`. We don't need the truncate-and-hash
/// long-segment branch — dockerstats hostnames and atSigns stay
/// well below 55 chars in practice.
String _sanitise(String input) {
  if (input.isEmpty) return 'empty';
  final cleaned = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  final base = trimmed.isEmpty ? 'x' : trimmed;
  if (base.length <= _maxSegmentLen) return base;
  return base.substring(0, _maxSegmentLen);
}

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

  /// Display window — used by the dashboard for the chart's x-axis
  /// range. Storage retention is independent of this; changing the
  /// window is a render-only change.
  Duration get window => _window;
  set window(Duration value) {
    if (value == _window) return;
    _window = value;
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
    final hostKey = _sanitise(s.hostname);
    final atKey = _sanitise(s.atSign);
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
    notifyListeners();
  }

  /// Drop the sample with `(host, atSign, id)`. The publisher writes
  /// leaves with `id: s.millis.toString()`, and within a single
  /// publishing cycle EVERY (host, atSign) pair is written with the
  /// same `millis` — so matching by id alone would over-evict
  /// across all buckets. The (host, atSign) coordinates come from
  /// the `CSubItemDeleted.ancestry` ids (sanitised forms of
  /// hostname/atSign that the publisher used as parent ids).
  void removeById({
    required String hostId,
    required String atSignId,
    required String id,
  }) {
    final hostKey = hostId.toLowerCase();
    final atKey = atSignId.toLowerCase();
    final inner = _byHostAtSign[hostKey];
    if (inner == null) return;
    final list = inner[atKey];
    if (list == null) return;
    final before = list.length;
    list.removeWhere((s) => s.millis.toString() == id);
    if (list.length == before) return;
    if (list.isEmpty) {
      inner.remove(atKey);
      atSignsByHost[hostKey]?.remove(atKey);
    }
    if (inner.isEmpty) {
      _byHostAtSign.remove(hostKey);
      hostnames.remove(hostKey);
      atSignsByHost.remove(hostKey);
    }
    notifyListeners();
  }
}
