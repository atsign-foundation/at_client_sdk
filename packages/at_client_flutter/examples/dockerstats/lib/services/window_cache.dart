/// In-memory view of the chart's currently-rendered data.
///
/// The cache holds samples already bucketed to the display window's
/// chart-pixel granularity — one [_Acc] per (host, container,
/// bucket-start). The dashboard fetches `samplesForHost(...)` /
/// `samplesForHostByContainer(...)` (cheaply derived from the
/// accumulators) and feeds them directly into the chart.
///
/// Two write paths:
///
///   - [replaceAll] — bulk-replace from a DB query result. Rows are
///     already aggregated server-side at the right [bucketMs] (or
///     raw with `sampleCount == 1` for narrow windows where every
///     raw sample is its own bucket).
///
///   - [addRaw] — single live notification. Find the right bucket
///     for its `millis` and either merge into the existing
///     accumulator or create a new one. O(log n) on `n` buckets
///     per container thanks to the [SplayTreeMap].
///
/// Identity is `(hostname, containerId)` — the docker container id
/// is the unique key for a running container. Display labels come
/// from each sample's `containerName` field (either an atSign the
/// publisher pulled out of `docker inspect`, or the docker
/// container name).
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/stats_models.dart';
import 'samples_db.dart';

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
  int _bucketMs = 0;

  /// hostKey → containerId → bucket-start → accumulator.
  /// SplayTreeMap so [pruneOlderThan] can drop the oldest in O(log n)
  /// without re-sorting every operation.
  final Map<String, Map<String, SplayTreeMap<int, _Acc>>> _accums = {};

  /// hostKey → raw hostname (preserves the human-readable form).
  final Map<String, String> hostnames = {};

  /// hostKey → containerId → display containerName.
  final Map<String, Map<String, String>> containerNamesByHost = {};

  /// Bucket size in milliseconds. `0` means raw — each notification
  /// becomes its own bucket. `> 0` means aggregate live samples
  /// into bucket-start-aligned accumulators.
  int get bucketMs => _bucketMs;

  /// Update the bucket size and clear the cache. Caller must follow
  /// with [replaceAll] to repopulate from a DB query at the new
  /// granularity. Used by the service on every window-selector
  /// change.
  void setBucketMsAndClear(int bucketMs) {
    _bucketMs = bucketMs;
    _accums.clear();
    hostnames.clear();
    containerNamesByHost.clear();
    notifyListeners();
  }

  /// Iterates known hosts (sanitised id keys).
  Iterable<String> get hostIds => _accums.keys;

  /// True iff no samples are currently cached. Used by the dashboard
  /// to surface a "no data" alert in the status bar.
  bool get isEmpty => _accums.isEmpty;

  /// Bulk-replace the cache from a DB query. Each [AggregatedRow]
  /// represents one bucket (or one raw sample, if the query ran
  /// with `bucketMs == 0`) and carries the underlying sample count
  /// so the running mean stays correct when a live notification
  /// later folds an extra raw sample into the same bucket.
  void replaceAll(Iterable<AggregatedRow> rows) {
    _accums.clear();
    hostnames.clear();
    containerNamesByHost.clear();
    for (final row in rows) {
      _storeAggregated(row);
    }
    notifyListeners();
  }

  /// Merge a single live raw sample into the cache. In raw mode
  /// (`bucketMs == 0`) the sample becomes its own bucket; in
  /// aggregated mode it folds into the existing accumulator for
  /// its bucket-start (creating one if absent).
  void addRaw(StatSample s) {
    final hostKey = _sanitise(s.hostname);
    hostnames.putIfAbsent(hostKey, () => s.hostname);
    containerNamesByHost.putIfAbsent(hostKey, () => {})[s.containerId] =
        s.containerName;
    final perContainer = _accums
        .putIfAbsent(hostKey, () => {})
        .putIfAbsent(s.containerId, () => SplayTreeMap<int, _Acc>());
    final bucket = _bucketMs == 0
        ? s.millis
        : (s.millis ~/ _bucketMs) * _bucketMs;
    final existing = perContainer[bucket];
    if (existing == null) {
      perContainer[bucket] = _Acc.fromRaw(bucketStart: bucket, sample: s);
    } else {
      existing.absorbRaw(s);
    }
    notifyListeners();
  }

  void _storeAggregated(AggregatedRow row) {
    final s = row.sample;
    final hostKey = _sanitise(s.hostname);
    hostnames.putIfAbsent(hostKey, () => s.hostname);
    containerNamesByHost.putIfAbsent(hostKey, () => {})[s.containerId] =
        s.containerName;
    final perContainer = _accums
        .putIfAbsent(hostKey, () => {})
        .putIfAbsent(s.containerId, () => SplayTreeMap<int, _Acc>());
    perContainer[s.millis] = _Acc.fromAggregate(row);
  }

  /// Sample series for [hostId] aggregated across all containers on
  /// that host. The dashboard sums across the returned list per
  /// millis to produce host-level series for each metric.
  List<StatSample> samplesForHost(String hostId) {
    final inner = _accums[hostId];
    if (inner == null) return const [];
    final out = <StatSample>[];
    for (final perBucket in inner.values) {
      for (final acc in perBucket.values) {
        out.add(acc.toSample());
      }
    }
    out.sort((a, b) => a.millis.compareTo(b.millis));
    return out;
  }

  /// Sample series for [hostId] split by container id.
  Map<String, List<StatSample>> samplesForHostByContainer(String hostId) {
    final inner = _accums[hostId];
    if (inner == null) return const {};
    return {
      for (final entry in inner.entries)
        entry.key: [for (final acc in entry.value.values) acc.toSample()],
    };
  }

  /// Drop accumulators whose bucket-start `< cutoffMs`. Called by
  /// the service's periodic prune timer to bound memory while a
  /// long-running session widens / narrows the display window.
  void pruneOlderThan(int cutoffMs) {
    var changed = false;
    for (final hostKey in _accums.keys.toList()) {
      final inner = _accums[hostKey]!;
      for (final containerKey in inner.keys.toList()) {
        final m = inner[containerKey]!;
        while (m.isNotEmpty && m.firstKey()! < cutoffMs) {
          m.remove(m.firstKey()!);
          changed = true;
        }
        if (m.isEmpty) {
          inner.remove(containerKey);
          containerNamesByHost[hostKey]?.remove(containerKey);
        }
      }
      if (inner.isEmpty) {
        _accums.remove(hostKey);
        hostnames.remove(hostKey);
        containerNamesByHost.remove(hostKey);
      }
    }
    if (changed) notifyListeners();
  }
}

/// Running aggregate for one bucket. Sums-of-each-field plus a
/// count let us emit a `StatSample` whose values represent the
/// mean of the underlying raw samples — including new live
/// arrivals that fold in after the initial DB query.
class _Acc {
  final int bucketStart;
  // Identity columns from one arbitrary sample in the bucket.
  // Assumed invariant per `(hostname, containerId)` so picking any
  // is fine; the publisher doesn't rename containers mid-run.
  final String atSign;
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;

  int n;
  double cpuSum;
  int memSum;
  int memLimitSum;
  double memPctSum;
  int pidsSum;
  int maxRestart;
  // Cumulative counters take the latest value within the bucket
  // (== max for monotonic counters); diffing neighbouring buckets
  // then recovers a rate.
  int lastMillis;
  int lastNetRx;
  int lastNetTx;
  int lastBlkRead;
  int lastBlkWrite;

  _Acc({
    required this.bucketStart,
    required this.atSign,
    required this.hostname,
    required this.containerId,
    required this.containerName,
    required this.image,
    required this.n,
    required this.cpuSum,
    required this.memSum,
    required this.memLimitSum,
    required this.memPctSum,
    required this.pidsSum,
    required this.maxRestart,
    required this.lastMillis,
    required this.lastNetRx,
    required this.lastNetTx,
    required this.lastBlkRead,
    required this.lastBlkWrite,
  });

  /// Construct from a single raw [StatSample] — `n == 1`, all sums
  /// equal the sample's values.
  factory _Acc.fromRaw({required int bucketStart, required StatSample sample}) {
    return _Acc(
      bucketStart: bucketStart,
      atSign: sample.atSign,
      hostname: sample.hostname,
      containerId: sample.containerId,
      containerName: sample.containerName,
      image: sample.image,
      n: 1,
      cpuSum: sample.cpuPct,
      memSum: sample.memUsage,
      memLimitSum: sample.memLimit,
      memPctSum: sample.memPct,
      pidsSum: sample.pidsCount,
      maxRestart: sample.restartCount,
      lastMillis: sample.millis,
      lastNetRx: sample.netRx,
      lastNetTx: sample.netTx,
      lastBlkRead: sample.blkRead,
      lastBlkWrite: sample.blkWrite,
    );
  }

  /// Reconstruct from a pre-aggregated row coming back from the
  /// DB. The sample's per-field values are AVGs of `sampleCount`
  /// underlying raw rows, so the running sums are reconstructed as
  /// `mean × count` — within float precision identical to the
  /// original sum.
  factory _Acc.fromAggregate(AggregatedRow row) {
    final s = row.sample;
    final n = row.sampleCount > 0 ? row.sampleCount : 1;
    return _Acc(
      bucketStart: s.millis,
      atSign: s.atSign,
      hostname: s.hostname,
      containerId: s.containerId,
      containerName: s.containerName,
      image: s.image,
      n: n,
      cpuSum: s.cpuPct * n,
      memSum: s.memUsage * n,
      memLimitSum: s.memLimit * n,
      memPctSum: s.memPct * n,
      pidsSum: s.pidsCount * n,
      maxRestart: s.restartCount,
      lastMillis: s.millis,
      lastNetRx: s.netRx,
      lastNetTx: s.netTx,
      lastBlkRead: s.blkRead,
      lastBlkWrite: s.blkWrite,
    );
  }

  void absorbRaw(StatSample s) {
    n += 1;
    cpuSum += s.cpuPct;
    memSum += s.memUsage;
    memLimitSum += s.memLimit;
    memPctSum += s.memPct;
    pidsSum += s.pidsCount;
    if (s.restartCount > maxRestart) maxRestart = s.restartCount;
    if (s.millis > lastMillis) {
      lastMillis = s.millis;
      lastNetRx = s.netRx;
      lastNetTx = s.netTx;
      lastBlkRead = s.blkRead;
      lastBlkWrite = s.blkWrite;
    }
  }

  StatSample toSample() {
    final count = n == 0 ? 1 : n;
    return StatSample(
      atSign: atSign,
      hostname: hostname,
      containerId: containerId,
      containerName: containerName,
      image: image,
      restartCount: maxRestart,
      pidsCount: pidsSum ~/ count,
      cpuPct: cpuSum / count,
      memUsage: memSum ~/ count,
      memLimit: memLimitSum ~/ count,
      memPct: memPctSum / count,
      netRx: lastNetRx,
      netTx: lastNetTx,
      blkRead: lastBlkRead,
      blkWrite: lastBlkWrite,
      millis: bucketStart,
    );
  }
}
