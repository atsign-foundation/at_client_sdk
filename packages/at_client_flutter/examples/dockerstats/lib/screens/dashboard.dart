/// Top dashboard. Two view modes:
///   - **Hosts** (default): one chart series per host, summed across the
///     atSigns reporting on that host.
///   - **Drill-down** (after selecting a host): one chart series per
///     atSign on that host, with multi-select chips to keep visible.
library;

import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

import '../models/stats_models.dart';
import '../onboarding.dart' show logout;
import '../services/atsign_colors.dart';
import '../services/dockerstats_service.dart';
import '../services/rolling_window.dart';
import '../widgets/stats_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Selectable rolling-window sizes for the dashboard. The publisher's
/// per-sample TTL bounds how much history actually exists in the
/// network — selecting a window larger than that is harmless, the
/// chart just shows whatever data is present (clustered to the right).
const List<({String label, Duration value})> _windowOptions = [
  (label: '2m', value: Duration(minutes: 2)),
  (label: '10m', value: Duration(minutes: 10)),
  (label: '1h', value: Duration(hours: 1)),
  (label: '24h', value: Duration(hours: 24)),
];

class _DashboardScreenState extends State<DashboardScreen> {
  DockerstatsService? _service;
  String? _error;
  Timer? _redrawTimer;
  Timer? _evictTimer;
  bool _catchingUp = true;
  SyncProgress? _lastSyncProgress;
  Duration _windowDuration = _windowOptions.first.value;
  final StableColors _colors = StableColors();
  String? _drillHostId;
  final Set<String> _hiddenAtSigns = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _redrawTimer?.cancel();
    _evictTimer?.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      // Drain the local sync queue first so the dashboard only renders
      // once we're caught up to whatever the atServer had at app start.
      try {
        await atClient.syncService.waitUntilCaughtUp(
          timeout: const Duration(seconds: 60),
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _lastSyncProgress = p);
          },
        );
      } catch (_) {
        // Tolerate a slow / failed sync — keep going so the user sees
        // whatever does arrive over the live subscription.
      }
      if (!mounted) return;
      final s = DockerstatsService(
        atClient: atClient,
        window: RollingWindow(window: _windowDuration),
      );
      await s.init();
      s.window.addListener(_onChange);
      // Frequent setState so the x-axis scrolls smoothly between
      // sample arrivals; eviction runs more rarely since it's O(N).
      _redrawTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        setState(() {});
      });
      _evictTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        s.window.evictExpired();
      });
      if (!mounted) return;
      setState(() {
        _service = s;
        _catchingUp = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _catchingUp = false;
      });
    }
  }

  void _setWindow(Duration d) {
    setState(() => _windowDuration = d);
    _service?.window.window = d;
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
              : 'Docker stats – ${s?.window.hostnames[_drillHostId] ?? _drillHostId}',
        ),
        leading: _drillHostId == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _drillHostId = null;
                  _hiddenAtSigns.clear();
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
    if (_catchingUp) {
      final p = _lastSyncProgress;
      String commitsLine;
      if (p == null) {
        commitsLine = 'waiting for first sync event…';
      } else {
        final local = p.localCommitId?.toString() ?? '–';
        final server = p.serverCommitId?.toString() ?? '–';
        commitsLine = 'localCommitId: $local   serverCommitId: $server';
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('… catching up'),
            const SizedBox(height: 8),
            Text(commitsLine, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hostIds = s.window.hostIds.toList()..sort();
    if (hostIds.isEmpty) {
      return Column(
        children: [
          _windowSelector(),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Waiting for stats…\n\nRun the publisher CLI:\n'
                  '  dart run bin/dockerstats_publish.dart \\\n'
                  '      -a <your-atsign> --other-at-signs <this-app-atsign> --simulate',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

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
          SegmentedButton<Duration>(
            showSelectedIcon: false,
            segments: [
              for (final opt in _windowOptions)
                ButtonSegment(value: opt.value, label: Text(opt.label)),
            ],
            selected: {_windowDuration},
            onSelectionChanged: (s) => _setWindow(s.first),
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
    for (final hostId in hostIds) {
      final hostname = s.window.hostnames[hostId] ?? hostId;
      final color = _colors.colorFor('host:$hostId');
      final samples = s.window.samplesForHost(hostId);
      final agg = _aggregateByMillis(samples);
      cpu.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: [for (final e in agg) (millis: e.millis, value: e.cpuPct)],
        ),
      );
      mem.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: [
            for (final e in agg)
              (millis: e.millis, value: e.memUsage / (1024 * 1024)),
          ],
        ),
      );
      net.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: [
            for (final e in agg)
              (millis: e.millis, value: (e.netRx + e.netTx) / (1024 * 1024)),
          ],
        ),
      );
      blk.add(
        ChartSeries(
          label: hostname,
          color: color,
          points: [
            for (final e in agg)
              (
                millis: e.millis,
                value: (e.blkRead + e.blkWrite) / (1024 * 1024),
              ),
          ],
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
            yLabel: 'sum CPU% across atSigns',
            window: s.window.window,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'sum memUsage (MiB)',
            window: s.window.window,
            series: mem,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB',
            window: s.window.window,
            series: net,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB',
            window: s.window.window,
            series: blk,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
        ]),
      ],
    );
  }

  Widget _hostChips(DockerstatsService s, List<String> hostIds) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              label: Text(s.window.hostnames[hostId] ?? hostId),
              onPressed: () => setState(() {
                _drillHostId = hostId;
                _hiddenAtSigns.clear();
              }),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Drill view — one series per atSign on the selected host

  Widget _buildDrillView(DockerstatsService s, String hostId) {
    final perAtSign = s.window.samplesForHostByAtSign(hostId);
    final atSignKeys = perAtSign.keys.toList()..sort();
    final visibleAtSignKeys = atSignKeys
        .where((k) => !_hiddenAtSigns.contains(k))
        .toList();

    ChartSeries seriesFor(String atKey, double Function(StatSample) extract) {
      final raw = perAtSign[atKey] ?? const <StatSample>[];
      return ChartSeries(
        label: s.window.atSignsByHost[hostId]?[atKey] ?? atKey,
        color: _colors.colorFor('atsign:$atKey'),
        points: [for (final p in raw) (millis: p.millis, value: extract(p))],
      );
    }

    final cpu = [
      for (final k in visibleAtSignKeys) seriesFor(k, (s) => s.cpuPct),
    ];
    final mem = [
      for (final k in visibleAtSignKeys)
        seriesFor(k, (s) => s.memUsage / (1024 * 1024)),
    ];
    final net = [
      for (final k in visibleAtSignKeys)
        seriesFor(k, (s) => (s.netRx + s.netTx) / (1024 * 1024)),
    ];
    final blk = [
      for (final k in visibleAtSignKeys)
        seriesFor(k, (s) => (s.blkRead + s.blkWrite) / (1024 * 1024)),
    ];

    return Column(
      children: [
        _windowSelector(),
        _atSignFilter(s, hostId, atSignKeys),
        _chartGrid([
          StatsChart(
            title: 'CPU',
            yLabel: 'CPU% per atSign',
            window: s.window.window,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'memUsage (MiB) per atSign',
            window: s.window.window,
            series: mem,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB per atSign',
            window: s.window.window,
            series: net,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB per atSign',
            window: s.window.window,
            series: blk,
            yFormatter: (v) => v.toStringAsFixed(0),
          ),
        ]),
      ],
    );
  }

  Widget _atSignFilter(
    DockerstatsService s,
    String hostId,
    List<String> atSignKeys,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('atSigns: '),
          ),
          for (final atKey in atSignKeys)
            FilterChip(
              avatar: CircleAvatar(
                radius: 6,
                backgroundColor: _colors.colorFor('atsign:$atKey'),
              ),
              label: Text(s.window.atSignsByHost[hostId]?[atKey] ?? atKey),
              selected: !_hiddenAtSigns.contains(atKey),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _hiddenAtSigns.remove(atKey);
                } else {
                  _hiddenAtSigns.add(atKey);
                }
              }),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Aggregation helper — bucket samples on identical timestamps and sum
  // the relevant fields. Within a single publishing cycle the publisher
  // writes the same `millis` for every atSign on a host, so a flat
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
