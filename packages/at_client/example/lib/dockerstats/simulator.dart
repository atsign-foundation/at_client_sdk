/// In-memory dockerstats simulator. Each fake host gets a small set of
/// fake containers, each with its own atSign and a bounded random walk
/// over cpu / mem / net / block. Cumulative counters (net, block) only
/// move forward; cpu and memPct are mean-reverting around a target.
library;

import 'dart:async';
import 'dart:math';

import 'models.dart';
import 'stats_source.dart';

class SimulatedStatsSource implements StatsSource {
  @override
  final String hostname;
  final List<_FakeContainer> _containers;
  final Random _rng;

  SimulatedStatsSource._(this.hostname, this._containers, this._rng);

  /// Builds [hostsCount] fake hosts. If [atSigns] is non-empty, each
  /// host runs one container per atSign in [atSigns]. Otherwise, each
  /// host runs three containers with auto-named atSigns.
  static List<SimulatedStatsSource> buildHosts({
    required int hostsCount,
    required List<String> atSigns,
    int seed = 0,
  }) {
    final rng = Random(seed == 0 ? DateTime.now().microsecond : seed);
    final out = <SimulatedStatsSource>[];
    for (var h = 0; h < hostsCount; h++) {
      final hostname = 'sim-host-${(h + 1).toString().padLeft(2, '0')}';
      final atSignList =
          atSigns.isEmpty
              ? [for (var i = 0; i < 3; i++) '@sim_${hostname}_${i + 1}']
              : atSigns;
      final containers = [
        for (var i = 0; i < atSignList.length; i++)
          _FakeContainer(
            atSign: atSignList[i],
            hostname: hostname,
            containerId: '${hostname}_c${(i + 1).toString().padLeft(2, '0')}'
                .padRight(64, '0'),
            containerName: 'sim_${atSignList[i].replaceAll('@', '')}',
            image: _images[i % _images.length],
            restartCount: rng.nextInt(3),
            // Each container starts at a different baseline so the
            // chart series are visually distinguishable.
            baselineCpu: 5 + rng.nextDouble() * 35,
            baselineMemPct: 10 + rng.nextDouble() * 50,
            memLimit: 1024 * 1024 * 1024 * (1 + rng.nextInt(7)), // 1..8 GiB
            netRx: 0,
            netTx: 0,
            blkRead: 0,
            blkWrite: 0,
            cpuPct: 0,
            memPct: 0,
          ),
      ];
      out.add(SimulatedStatsSource._(hostname, containers, rng));
    }
    return out;
  }

  static const List<String> _images = [
    'nginx:1.27',
    'redis:7.4',
    'postgres:16',
    'busybox:1.37',
    'caddy:2.8',
    'node:22-alpine',
  ];

  @override
  Future<List<StatSample>> sample() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <StatSample>[];
    for (final c in _containers) {
      c.tick(_rng);
      out.add(
        StatSample(
          atSign: c.atSign,
          hostname: c.hostname,
          containerId: c.containerId,
          containerName: c.containerName,
          image: c.image,
          restartCount: c.restartCount,
          pidsCount: 5 + _rng.nextInt(20),
          cpuPct: c.cpuPct,
          memUsage: ((c.memPct / 100.0) * c.memLimit).round(),
          memLimit: c.memLimit,
          memPct: c.memPct,
          netRx: c.netRx,
          netTx: c.netTx,
          blkRead: c.blkRead,
          blkWrite: c.blkWrite,
          millis: now,
        ),
      );
    }
    return out;
  }
}

class _FakeContainer {
  final String atSign;
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;
  final int restartCount;
  final double baselineCpu;
  final double baselineMemPct;
  final int memLimit;

  // Mutable state.
  double cpuPct;
  double memPct;
  int netRx;
  int netTx;
  int blkRead;
  int blkWrite;

  _FakeContainer({
    required this.atSign,
    required this.hostname,
    required this.containerId,
    required this.containerName,
    required this.image,
    required this.restartCount,
    required this.baselineCpu,
    required this.baselineMemPct,
    required this.memLimit,
    required this.cpuPct,
    required this.memPct,
    required this.netRx,
    required this.netTx,
    required this.blkRead,
    required this.blkWrite,
  });

  /// One step of the bounded mean-reverting walk.
  void tick(Random rng) {
    cpuPct = _step(cpuPct, baselineCpu, rng, jitter: 8.0, lo: 0.1, hi: 100);
    memPct = _step(memPct, baselineMemPct, rng, jitter: 4.0, lo: 0.5, hi: 99);
    netRx += 1024 + rng.nextInt(1024 * 50);
    netTx += 1024 + rng.nextInt(1024 * 30);
    blkRead += rng.nextInt(1024 * 20);
    blkWrite += rng.nextInt(1024 * 10);
  }

  static double _step(
    double current,
    double target,
    Random rng, {
    required double jitter,
    required double lo,
    required double hi,
  }) {
    final pull = (target - current) * 0.20;
    final shock = (rng.nextDouble() - 0.5) * jitter;
    final next = current + pull + shock;
    if (next < lo) return lo;
    if (next > hi) return hi;
    return next;
  }
}
