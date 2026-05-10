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
  SyncProgress? _lastSyncProgress;
  SyncProgressListener? _progressListener;
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
    if (_progressListener != null) {
      AtClientManager.getInstance().atClient.syncService.removeProgressListener(
        _progressListener!,
      );
    }
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      // Subscribe to all SyncProgress events for the lifetime of the
      // dashboard so the status bar always reflects current sync state.
      _progressListener = _ProgressForwarder((p) {
        if (!mounted) return;
        setState(() => _lastSyncProgress = p);
      });
      atClient.syncService.addProgressListener(_progressListener!);
      final s = DockerstatsService(
        atClient: atClient,
        window: RollingWindow(window: _windowDuration),
      );
      await s.init();
      s.window.addListener(_onChange);
      // Frequent setState so the x-axis scrolls smoothly between
      // sample arrivals. Storage eviction is event-driven (via
      // `nodes.subDeletes` in DockerstatsService), so no separate
      // periodic trim is needed.
      _redrawTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        setState(() {});
      });
      if (!mounted) return;
      setState(() => _service = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
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
      bottomNavigationBar: _SyncStatusBar(
        progress: _lastSyncProgress,
        noData: s != null && s.window.hostIds.isEmpty,
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
    final hostIds = s.window.hostIds.toList()..sort();
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
                label: Text(s.window.hostnames[hostId] ?? hostId),
                onPressed: () => setState(() {
                  _drillHostId = hostId;
                  _hiddenAtSigns.clear();
                }),
              ),
          ],
        ),
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
      child: SizedBox(
        width: double.infinity,
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

/// Trivial adapter so we can register a closure as a SyncProgressListener
/// without having to define a full subclass at every call site.
class _ProgressForwarder implements SyncProgressListener {
  final void Function(SyncProgress) _onEvent;
  _ProgressForwarder(this._onEvent);
  @override
  void onSyncProgressEvent(SyncProgress progress) => _onEvent(progress);
}

/// Persistent footer that reflects sync state and any "no data"
/// alert. Top row: amber spinner + commit-ids when local is behind
/// server; green tick + "in sync" otherwise. Optional bottom row:
/// warning triangle + "no data in this time window" hint, only when
/// the rolling window is empty.
class _SyncStatusBar extends StatelessWidget {
  final SyncProgress? progress;
  final bool noData;
  const _SyncStatusBar({required this.progress, required this.noData});

  bool get _isBehind {
    final p = progress;
    if (p == null) return false;
    final local = p.localCommitId;
    final server = p.serverCommitId;
    if (local == null || server == null) return false;
    return local < server;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final local = p?.localCommitId?.toString() ?? '–';
    final server = p?.serverCommitId?.toString() ?? '–';
    final pending = p?.pendingPushCount;

    final Widget icon;
    final String label;
    final Color color;
    if (_isBehind) {
      color = Colors.amber.shade700;
      icon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
      label = 'syncing';
    } else {
      color = Colors.green.shade700;
      icon = Icon(Icons.check_circle, size: 16, color: color);
      label = 'in sync';
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  'local $local · server $server'
                  '${pending != null && pending > 0 ? ' · pending push $pending' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (noData) ...[
              const SizedBox(height: 4),
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
