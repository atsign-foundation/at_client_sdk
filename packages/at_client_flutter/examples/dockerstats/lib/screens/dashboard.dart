/// Top dashboard. Two view modes:
///   - **Hosts** (default): one chart series per host, summed across the
///     atSigns reporting on that host.
///   - **Drill-down** (after selecting a host): one chart series per
///     atSign on that host, with multi-select chips to keep visible.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stats_models.dart';
import '../onboarding.dart' show logout;
import '../services/atsign_colors.dart';
import '../services/dockerstats_service.dart';
import '../widgets/stats_chart.dart';
import 'package:at_client_flutter/at_client_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DockerstatsService? _service;
  String? _error;
  Timer? _redraw;
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
    _redraw?.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      final s = DockerstatsService(atClient: atClient);
      await s.init();
      // Tick once per second to age out points past the rolling window.
      _redraw = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        s.window.evictExpired();
      });
      s.window.addListener(_onChange);
      if (!mounted) return;
      setState(() => _service = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
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
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hostIds = s.window.hostIds.toList()..sort();
    if (hostIds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Waiting for stats…\n\nRun the publisher CLI:\n'
            '  dart run bin/dockerstats_publish.dart \\\n'
            '      -a <your-atsign> --other-at-signs <this-app-atsign> --simulate',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return _drillHostId == null
        ? _buildHostsView(s, hostIds)
        : _buildDrillView(s, _drillHostId!);
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
    return ListView(
      children: [
        _hostChips(s, hostIds),
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

    return ListView(
      children: [
        _atSignFilter(s, hostId, atSignKeys),
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
