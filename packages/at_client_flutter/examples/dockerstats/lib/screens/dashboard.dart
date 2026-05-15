/// Top dashboard. Two view modes:
///   - **Hosts** (default): one chart series per host, summed across the
///     containers reporting on that host.
///   - **Drill-down** (after selecting a host): one chart series per
///     container on that host, with multi-select chips to keep visible.
library;

import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

import '../models/stats_models.dart';
import '../onboarding.dart' show logout;
import '../services/atsign_colors.dart';
import '../services/dockerstats_service.dart';
import '../widgets/stats_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Selectable display windows. SQLite holds every sample
/// indefinitely under a multi-tier roll-up; the window only
/// controls what the chart renders. Switching the selector
/// triggers a fresh `db.queryWindow(...)` so widening (e.g.
/// 5m → all) immediately reveals every sample in the new range.
///
/// The `all` entry uses [Duration.zero] as a sentinel meaning
/// "fit to the actual data range" — the chart computes `xMin`
/// from the earliest sample in the series rather than `now -
/// window`. Labels follow the user's spec verbatim — `m` is
/// minutes early in the list (`5m`, `15m`) and months later
/// in the list (`1m`, `6m`); positional context disambiguates.
const List<({String label, Duration value})> _windowOptions = [
  (label: '5m', value: Duration(minutes: 5)),
  (label: '15m', value: Duration(minutes: 15)),
  (label: '1h', value: Duration(hours: 1)),
  (label: '5h', value: Duration(hours: 5)),
  (label: '1d', value: Duration(days: 1)),
  (label: '7d', value: Duration(days: 7)),
  (label: '1m', value: Duration(days: 30)),
  (label: '6m', value: Duration(days: 180)),
  (label: '2y', value: Duration(days: 730)),
  (label: 'all', value: Duration.zero),
];

class _DashboardScreenState extends State<DashboardScreen> {
  DockerstatsService? _service;
  String? _error;
  Timer? _redrawTimer;
  Duration _windowDuration = _windowOptions.first.value;
  final StableColors _colors = StableColors();
  String? _drillHostId;
  final Set<String> _hiddenContainers = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _redrawTimer?.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      final s = await DockerstatsService.create(
        atClient: atClient,
        window: _windowDuration,
      );
      s.cache.addListener(_onChange);
      _startRedrawTimer();
      if (!mounted) return;
      setState(() => _service = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Pick a redraw cadence matching the visible window. Short
  /// windows want 50 ms (smooth axis scroll for live tier-0 5s
  /// data); wide windows (hours / days / months) move <1 px per
  /// real second so a 1 Hz tick is plenty and saves us from
  /// rebuilding 4 charts × 1000 spots 20 times a second for no
  /// visual gain.
  void _startRedrawTimer() {
    _redrawTimer?.cancel();
    final intervalMs = _windowDuration == Duration.zero
        ? 1000
        : (_windowDuration.inMilliseconds ~/ 14400).clamp(50, 1000);
    _redrawTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _setWindow(Duration d) async {
    setState(() => _windowDuration = d);
    _startRedrawTimer();
    await _service?.setWindow(d);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _logout() async {
    await logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _drillHostId == null
              ? 'Docker stats'
              : 'Docker stats – ${s?.cache.hostnames[_drillHostId] ?? _drillHostId}',
        ),
        leading: _drillHostId == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _drillHostId = null;
                  _hiddenContainers.clear();
                }),
              ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(s)),
      bottomNavigationBar: _StatusBar(
        backfilling: s?.backfilling ?? false,
        noData: s != null && !s.backfilling && s.cache.isEmpty,
      ),
    );
  }

  Widget _buildBody(DockerstatsService? s) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to start: $_error'),
        ),
      );
    }
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hostIds = s.cache.hostIds.toList()..sort();
    // Always render the chart layout — when there's no data the
    // status bar surfaces a "no data in this time window" alert.
    return _drillHostId == null
        ? _buildHostsView(s, hostIds)
        : _buildDrillView(s, _drillHostId!);
  }

  Widget _windowSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Text('Window:'),
          ),
          // Horizontal scroll defensively bounds the SegmentedButton
          // on narrow windows — 10 segments × ~36 px ≈ 360 px is
          // comfortable on desktop but tight on a side panel.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<Duration>(
                showSelectedIcon: false,
                segments: [
                  for (final opt in _windowOptions)
                    ButtonSegment(value: opt.value, label: Text(opt.label)),
                ],
                selected: {_windowDuration},
                onSelectionChanged: (s) => _setWindow(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartGrid(List<StatsChart> charts) {
    assert(charts.length == 4);
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: charts[0]),
                Expanded(child: charts[1]),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: charts[2]),
                Expanded(child: charts[3]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top view — one series per host

  Widget _buildHostsView(DockerstatsService s, List<String> hostIds) {
    final cpu = <ChartSeries>[];
    final mem = <ChartSeries>[];
    final net = <ChartSeries>[];
    final blk = <ChartSeries>[];
    // Render-time re-bucketing: snap every sample to a bucket whose
    // size matches the coarsest tier currently visible. That hides
    // the per-tier density change at tier boundaries — at 7d view
    // tier-0 5s samples get averaged into 15-min buckets just like
    // the tier-1 / tier-2 rows already are, so the entire trace is
    // uniform-density.
    final bucketMs = _chartBucketMs(s.window);
    final smoothWin = _smoothingWindow(bucketMs);
    for (final hostId in hostIds) {
      final hostname = s.cache.hostnames[hostId] ?? hostId;
      final color = _colors.colorFor('host:$hostId');
      final perContainer = s.cache.samplesForHostByContainer(hostId);
      final bucketed = <StatSample>[];
      for (final list in perContainer.values) {
        bucketed.addAll(_rebucketSeries(list, bucketMs));
      }
      bucketed.sort((a, b) => a.millis.compareTo(b.millis));
      final agg = _aggregateByMillis(bucketed);
      cpu.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: _smoothPoints([
            for (final e in agg) (millis: e.millis, value: e.cpuPct),
          ], smoothWin),
        ),
      );
      mem.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: _smoothPoints([
            for (final e in agg)
              (millis: e.millis, value: e.memUsage / (1024 * 1024)),
          ], smoothWin),
        ),
      );
      net.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: _smoothPoints([
            for (final e in agg)
              (millis: e.millis, value: (e.netRx + e.netTx) / (1024 * 1024)),
          ], smoothWin),
        ),
      );
      blk.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: _smoothPoints([
            for (final e in agg)
              (
                millis: e.millis,
                value: (e.blkRead + e.blkWrite) / (1024 * 1024),
              ),
          ], smoothWin),
        ),
      );
    }
    return Column(
      children: [
        _windowSelector(),
        _hostChips(s, hostIds),
        _chartGrid([
          StatsChart(
            title: 'CPU',
            yLabel: 'sum CPU% across containers',
            window: s.window,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'sum memUsage (MiB)',
            window: s.window,
            series: mem,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB',
            window: s.window,
            series: net,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB',
            window: s.window,
            series: blk,
            yFormatter: _compactNumber,
          ),
        ]),
      ],
    );
  }

  Widget _hostChips(DockerstatsService s, List<String> hostIds) {
    // SizedBox(width: double.infinity) gives Wrap an explicit
    // bounded width so it word-wraps onto a new run instead of
    // overflowing past the right edge when there are many hosts.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Tap a host to drill down: '),
            ),
            for (final hostId in hostIds)
              ActionChip(
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: _colors.colorFor('host:$hostId'),
                ),
                label: Text(s.cache.hostnames[hostId] ?? hostId),
                onPressed: () => setState(() {
                  _drillHostId = hostId;
                  _hiddenContainers.clear();
                }),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Drill view — one series per container on the selected host

  Widget _buildDrillView(DockerstatsService s, String hostId) {
    final perContainer = s.cache.samplesForHostByContainer(hostId);
    final containerIds = perContainer.keys.toList()..sort();
    final visibleContainerIds = containerIds
        .where((k) => !_hiddenContainers.contains(k))
        .toList();
    // Same render-time re-bucketing as the hosts view — keeps the
    // trace uniform-density across tier boundaries.
    final bucketMs = _chartBucketMs(s.window);
    final bucketedByCid = <String, List<StatSample>>{
      for (final cid in visibleContainerIds)
        cid: _rebucketSeries(
          perContainer[cid] ?? const <StatSample>[],
          bucketMs,
        ),
    };

    final smoothWin = _smoothingWindow(bucketMs);
    ChartSeries seriesFor(String cid, double Function(StatSample) extract) {
      final raw = bucketedByCid[cid] ?? const <StatSample>[];
      return ChartSeries(
        label: s.cache.containerNamesByHost[hostId]?[cid] ?? cid,
        color: _colors.colorFor('container:$cid'),
        points: _smoothPoints([
          for (final p in raw) (millis: p.millis, value: extract(p)),
        ], smoothWin),
      );
    }

    final cpu = [
      for (final cid in visibleContainerIds) seriesFor(cid, (s) => s.cpuPct),
    ];
    final mem = [
      for (final cid in visibleContainerIds)
        seriesFor(cid, (s) => s.memUsage / (1024 * 1024)),
    ];
    final net = [
      for (final cid in visibleContainerIds)
        seriesFor(cid, (s) => (s.netRx + s.netTx) / (1024 * 1024)),
    ];
    final blk = [
      for (final cid in visibleContainerIds)
        seriesFor(cid, (s) => (s.blkRead + s.blkWrite) / (1024 * 1024)),
    ];

    return Column(
      children: [
        _windowSelector(),
        _containerFilter(s, hostId, containerIds),
        _chartGrid([
          StatsChart(
            title: 'CPU',
            yLabel: 'CPU% per container',
            window: s.window,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'memUsage (MiB) per container',
            window: s.window,
            series: mem,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB per container',
            window: s.window,
            series: net,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB per container',
            window: s.window,
            series: blk,
            yFormatter: _compactNumber,
          ),
        ]),
      ],
    );
  }

  Widget _containerFilter(
    DockerstatsService s,
    String hostId,
    List<String> containerIds,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('containers: '),
            ),
            for (final cid in containerIds)
              FilterChip(
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: _colors.colorFor('container:$cid'),
                ),
                label: Text(s.cache.containerNamesByHost[hostId]?[cid] ?? cid),
                selected: !_hiddenContainers.contains(cid),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _hiddenContainers.remove(cid);
                  } else {
                    _hiddenContainers.add(cid);
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Aggregation helper — bucket samples on identical timestamps and sum
  // the relevant fields. Within a single publishing cycle the publisher
  // writes the same `millis` for every container on a host, so a flat
  // millis-equality bucketing is enough.

  List<_HostAgg> _aggregateByMillis(List<StatSample> samples) {
    final byMs = <int, _HostAgg>{};
    for (final s in samples) {
      final cur = byMs.putIfAbsent(s.millis, () => _HostAgg(millis: s.millis));
      cur.cpuPct += s.cpuPct;
      cur.memUsage += s.memUsage;
      cur.netRx += s.netRx;
      cur.netTx += s.netTx;
      cur.blkRead += s.blkRead;
      cur.blkWrite += s.blkWrite;
    }
    final out = byMs.values.toList()
      ..sort((a, b) => a.millis.compareTo(b.millis));
    return out;
  }
}

class _HostAgg {
  final int millis;
  double cpuPct = 0;
  int memUsage = 0;
  int netRx = 0;
  int netTx = 0;
  int blkRead = 0;
  int blkWrite = 0;
  _HostAgg({required this.millis});
}

/// Compact y-axis formatter for byte-quantity-derived numbers. The
/// chart pre-scales raw bytes to MiB before display, but cumulative
/// counters (`netRx`/`netTx`/`blkRead`/`blkWrite`) accumulate without
/// bound — across a year a single container can produce values in
/// the millions or billions of MiB — and a 9-digit literal will not
/// fit in a y-tick slot at any reasonable chart width. Use SI-style
/// suffixes (k/M/G/T) so every tick fits in ~5 characters.
String _compactNumber(double v) {
  final abs = v.abs();
  if (abs >= 1e12) return '${(v / 1e12).toStringAsFixed(1)}T';
  if (abs >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}G';
  if (abs >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (abs >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

/// Pick the render-time bucket size for a given display window so
/// the chart shows uniform-density data across all visible tiers.
/// Returns the bucket size of the coarsest tier whose retention
/// boundary falls within the window (so eg the 7d window includes
/// up-to-tier-2 data and we re-bucket finer rows to 15-min).
int _chartBucketMs(Duration window) {
  const tier0 = Duration(seconds: 5);
  const tier1 = Duration(minutes: 1);
  const tier2 = Duration(minutes: 15);
  const tier3 = Duration(hours: 1);
  const tier4 = Duration(hours: 8);
  if (window == Duration.zero) return tier4.inMilliseconds;
  final ms = window.inMilliseconds;
  if (ms <= const Duration(hours: 6).inMilliseconds) {
    return tier0.inMilliseconds;
  }
  if (ms <= const Duration(hours: 72).inMilliseconds) {
    return tier1.inMilliseconds;
  }
  if (ms <= const Duration(days: 45).inMilliseconds) {
    return tier2.inMilliseconds;
  }
  if (ms <= const Duration(days: 180).inMilliseconds) {
    return tier3.inMilliseconds;
  }
  return tier4.inMilliseconds;
}

/// Pick a moving-average smoothing window for chart series, sized
/// against the render bucket. Re-bucketing alone matches the
/// coarsest visible tier's bucket SIZE but doesn't change how many
/// underlying samples each visible bucket aggregates: a tier-4 row
/// holds the integrated mean of 8 h of source samples, but if the
/// upstream source only contributed one sample per tier-4 bucket
/// (e.g. legacy seed data), no averaging happens at render. A small
/// moving average over neighbouring buckets masks the residual.
/// For tier-0-only windows (5 m – 5 h) we leave it at 1 so live
/// updates aren't temporally smeared.
int _smoothingWindow(int bucketMs) {
  if (bucketMs <= Duration(seconds: 5).inMilliseconds) return 1;
  return 9;
}

/// Centred moving average over a series of `(millis, value)` points.
/// Output preserves the input length and `millis` values; only
/// `value` is smoothed. Window is automatically truncated at the
/// series edges so the first and last points still get emitted with
/// an asymmetric mean of their neighbours rather than dropped.
List<({int millis, double value})> _smoothPoints(
  List<({int millis, double value})> points,
  int windowSize,
) {
  if (points.length < 2 || windowSize <= 1) return points;
  final half = windowSize ~/ 2;
  final out = <({int millis, double value})>[];
  for (var i = 0; i < points.length; i++) {
    final lo = (i - half) < 0 ? 0 : (i - half);
    final hi = (i + half + 1) > points.length ? points.length : (i + half + 1);
    var sum = 0.0;
    for (var j = lo; j < hi; j++) {
      sum += points[j].value;
    }
    out.add((millis: points[i].millis, value: sum / (hi - lo)));
  }
  return out;
}

/// Group [samples] into uniform [bucketMs] buckets per container.
/// Aggregation mirrors the SQLite roller's semantics: weighted-mean
/// for rates (cpu/mem), last-in-bucket for cumulative counters
/// (net/blk), max for monotonic event counts (restartCount). The
/// returned samples carry the bucket-start millis so the resulting
/// trace lines up neighbour-to-neighbour without phase ripples at
/// tier boundaries.
///
/// Caller passes a single container's samples — bucketing across
/// containers would lose per-container identity and would conflict
/// with the chart's downstream cross-container summation.
List<StatSample> _rebucketSeries(List<StatSample> samples, int bucketMs) {
  if (samples.isEmpty || bucketMs <= 0) return samples;
  final byBucket = <int, _BucketAcc>{};
  for (final s in samples) {
    final b = (s.millis ~/ bucketMs) * bucketMs;
    final cur = byBucket.putIfAbsent(b, () => _BucketAcc(b, s));
    cur.absorb(s);
  }
  final out = byBucket.values.map((a) => a.toSample()).toList()
    ..sort((a, b) => a.millis.compareTo(b.millis));
  return out;
}

class _BucketAcc {
  final int bucketStart;
  final StatSample template;
  int n = 0;
  double cpuSum = 0;
  int memSum = 0;
  double memPctSum = 0;
  int pidsSum = 0;
  int maxRestart = 0;
  int lastMillis = -1;
  int lastNetRx = 0;
  int lastNetTx = 0;
  int lastBlkRead = 0;
  int lastBlkWrite = 0;

  _BucketAcc(this.bucketStart, this.template);

  void absorb(StatSample s) {
    n += 1;
    cpuSum += s.cpuPct;
    memSum += s.memUsage;
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

  StatSample toSample() => StatSample(
    atSign: template.atSign,
    hostname: template.hostname,
    containerId: template.containerId,
    containerName: template.containerName,
    image: template.image,
    restartCount: maxRestart,
    pidsCount: n == 0 ? template.pidsCount : pidsSum ~/ n,
    cpuPct: n == 0 ? 0 : cpuSum / n,
    memUsage: n == 0 ? 0 : memSum ~/ n,
    memLimit: template.memLimit,
    memPct: n == 0 ? 0 : memPctSum / n,
    netRx: lastNetRx,
    netTx: lastNetTx,
    blkRead: lastBlkRead,
    blkWrite: lastBlkWrite,
    millis: bucketStart,
  );
}

/// Persistent footer. Two optional rows:
///   - spinner + "loading historical samples from local store…"
///     while the SQLite query is running on startup or after a
///     window-selector change;
///   - warning triangle + "no data in this time window…" hint
///     when the cache is empty post-load.
/// Sync state is no longer surfaced — the dockerstats receiver
/// doesn't use AtCollection (and hence the sync queue) any more;
/// every sample arrives as a single notification.
class _StatusBar extends StatelessWidget {
  final bool backfilling;
  final bool noData;
  const _StatusBar({required this.backfilling, required this.noData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!backfilling && !noData) {
      // Reserve a single thin row so the bottom-nav slot has a
      // stable height; otherwise toggling the alerts on/off jumps
      // the chart grid vertically.
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text('ready', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (backfilling)
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'loading historical samples from local store…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            if (noData) ...[
              if (backfilling) const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'no data in this time window — run the publisher CLI: '
                      'dart run bin/dockerstats_publish.dart '
                      '-a <your-atsign> --other-at-signs <this-app-atsign> --simulate',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
