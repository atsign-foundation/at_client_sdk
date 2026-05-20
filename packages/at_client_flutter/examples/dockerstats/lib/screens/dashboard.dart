/// Top dashboard. Two view modes:
///   - **Hosts** (default): one chart series per host, summed across the
///     containers reporting on that host.
///   - **Drill-down** (after selecting a host): one chart series per
///     container on that host, with multi-select chips to keep visible.
library;

import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/stats_models.dart';
import '../models/visible_range.dart';
import '../onboarding.dart' show logout;
import '../services/atsign_colors.dart';
import '../services/dockerstats_service.dart';
import '../widgets/stats_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Quick-jump span presets shown in the range control bar.
/// `'all'` is a sentinel — selecting it computes the span as
/// `now - dataExtent.earliestMs`.
const List<({String label, Duration? value})> _spanPresets = [
  (label: '1h', value: Duration(hours: 1)),
  (label: '1d', value: Duration(days: 1)),
  (label: '1m', value: Duration(days: 30)),
  (label: '1y', value: Duration(days: 365)),
  (label: 'all', value: null),
];

/// Default initial range: the past hour, pinned to live.
final VisibleRange _defaultRange = VisibleRange.livePreset(
  const Duration(hours: 1).inMilliseconds,
);

class _DashboardScreenState extends State<DashboardScreen> {
  DockerstatsService? _service;
  String? _error;
  Timer? _redrawTimer;
  VisibleRange _range = _defaultRange;
  final StableColors _colors = StableColors();
  String? _drillHostId;
  final Set<String> _hiddenContainers = {};

  // Pan-drag state: chart-local pixels / time conversion baseline.
  // Captured on PointerDown and consumed on PointerMove / PointerUp.
  int? _dragStartEndMs;
  Offset? _dragStartLocal;
  double? _dragChartWidthPx;

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
        range: _range,
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

  /// Pick a redraw cadence matching the visible span. Short
  /// windows want 50 ms (smooth axis scroll for live tier-0 5s
  /// data); wide windows (hours / days / months) move <1 px per
  /// real second so a 1 Hz tick is plenty and saves us from
  /// rebuilding 4 charts × 1000 spots 20 times a second for no
  /// visual gain.
  void _startRedrawTimer() {
    _redrawTimer?.cancel();
    final intervalMs = (_range.spanMs ~/ 14400).clamp(50, 1000);
    _redrawTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      // Only redraw when live — historical ranges are static between
      // user actions, so no animation is needed.
      if (_range.isLive) setState(() {});
    });
  }

  Future<void> _setRange(VisibleRange r) async {
    if (r == _range) return;
    setState(() => _range = r);
    _startRedrawTimer();
    await _service?.setRange(r);
  }

  /// Span limits for clamping zoom. Max is data extent (or current
  /// span when extent is unknown); min is the model's hard 5-minute
  /// floor.
  ({int minMs, int maxMs}) _spanLimits() {
    final extent = _service?.dataExtent;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final earliest = extent?.earliestMs ?? (nowMs - _range.spanMs);
    final maxMs = (nowMs - earliest).clamp(_range.spanMs, 1 << 53);
    return (minMs: minVisibleSpan.inMilliseconds, maxMs: maxMs);
  }

  void _zoomBy(double factor) {
    final limits = _spanLimits();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _setRange(
      _range.zoomedAroundCenter(
        factor,
        nowMs: nowMs,
        minSpanMs: limits.minMs,
        maxSpanMs: limits.maxMs,
      ),
    );
  }

  void _panBy(int deltaMs) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final extent = _service?.dataExtent;
    final earliest = extent?.earliestMs ?? nowMs;
    _setRange(_range.pannedBy(deltaMs, nowMs: nowMs, earliestMs: earliest));
  }

  void _goLive() => _setRange(_range.goingLive());

  void _fitAll() {
    final extent = _service?.dataExtent;
    if (extent?.earliestMs == null) {
      _setRange(_defaultRange);
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _setRange(_range.fittingAll(earliestMs: extent!.earliestMs!, nowMs: nowMs));
  }

  void _setPreset(Duration? d) {
    if (d != null) {
      _setRange(VisibleRange.livePreset(d.inMilliseconds));
      return;
    }
    _fitAll();
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

  Widget _rangeControlBar() {
    final theme = Theme.of(context);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final liveColor = _range.isLive ? Colors.lightBlueAccent.shade400 : null;
    final liveFg = _range.isLive
        ? Colors.white
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    // Two rows: controls on top (stable layout — every button's
    // screen position is determined only by the button widths to
    // its left, never by the readout), readout below on its own
    // line so its width changes don't ripple back into the
    // controls.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Pan 1×, pan ½, zoom out, zoom in, pan ½, pan 1×.
                IconButton(
                  tooltip: 'Pan left (1 full span)',
                  icon: const Icon(Icons.keyboard_double_arrow_left),
                  onPressed: () => _panBy(-_range.spanMs),
                ),
                IconButton(
                  tooltip: 'Pan left (½ span)',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _panBy(-_range.spanMs ~/ 2),
                ),
                IconButton(
                  tooltip: 'Zoom out (2×)',
                  icon: const Icon(Icons.remove),
                  onPressed: () => _zoomBy(0.5),
                ),
                IconButton(
                  tooltip: 'Zoom in (2×)',
                  icon: const Icon(Icons.add),
                  onPressed: () => _zoomBy(2.0),
                ),
                IconButton(
                  tooltip: 'Pan right (½ span)',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _panBy(_range.spanMs ~/ 2),
                ),
                IconButton(
                  tooltip: 'Pan right (1 full span)',
                  icon: const Icon(Icons.keyboard_double_arrow_right),
                  onPressed: () => _panBy(_range.spanMs),
                ),
                const SizedBox(width: 16),
                // Presets — single-tap jumps to a live span.
                for (final p in _spanPresets)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: TextButton(
                      onPressed: () => _setPreset(p.value),
                      child: Text(p.label),
                    ),
                  ),
                const SizedBox(width: 16),
                // Live indicator + jump-to-live. Bright blue when
                // live; dimmed when historical so the colour itself
                // surfaces "you're scrolled away from now".
                FilledButton.tonalIcon(
                  onPressed: _goLive,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('LIVE'),
                  style: FilledButton.styleFrom(
                    backgroundColor: liveColor,
                    foregroundColor: liveFg,
                    disabledForegroundColor: liveFg,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _fitAll,
                  icon: const Icon(Icons.fit_screen, size: 18),
                  label: const Text('Fit'),
                ),
              ],
            ),
          ),
          // Readout — own row, so its width changes don't move the
          // buttons. Tabular figures keep digit widths stable so the
          // text itself doesn't twitch tick-to-tick under live
          // updates.
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 8),
            child: Text(
              _formatRangeReadout(nowMs),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRangeReadout(int nowMs) {
    if (_range.isLive) {
      return 'Past ${_humanSpan(_range.spanMs)} (live)';
    }
    final startMs = _range.resolveStartMs(nowMs);
    final endMs = _range.resolveEndMs(nowMs);
    final agoMs = nowMs - endMs;
    return '${_fmtAbs(startMs)} → ${_fmtAbs(endMs)} '
        '(${_humanSpan(_range.spanMs)} ending ${_humanSpan(agoMs)} ago)';
  }

  static String _humanSpan(int ms) {
    if (ms < 60 * 1000) return '${ms ~/ 1000}s';
    if (ms < 60 * 60 * 1000) return '${ms ~/ 60000}m';
    if (ms < 24 * 60 * 60 * 1000) return '${ms ~/ 3600000}h';
    if (ms < 30 * 24 * 60 * 60 * 1000) return '${ms ~/ (24 * 3600000)}d';
    if (ms < 365 * 24 * 60 * 60 * 1000) {
      return '${ms ~/ (30 * 24 * 3600000)}mo';
    }
    return '${(ms / (365.0 * 24 * 3600000)).toStringAsFixed(1)}y';
  }

  static String _fmtAbs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _chartGrid(List<StatsChart> charts) {
    assert(charts.length == 4);
    // One gesture-capturing wrapper covers the whole 2x2 grid so a
    // wheel-zoom or click-drag on any chart panel updates the
    // shared range — all four charts share the same x-axis.
    return Expanded(
      child: _RangeGestureWrapper(
        onWheelZoom: _onWheelZoom,
        onDragStart: _onPanDragStart,
        onDragUpdate: _onPanDragUpdate,
        onDragEnd: _onPanDragEnd,
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
      ),
    );
  }

  // -- Gesture handlers (Phase 4) -------------------------------------------

  void _onPanDragStart(Offset local, double widthPx) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _dragStartEndMs = _range.resolveEndMs(nowMs);
    _dragStartLocal = local;
    _dragChartWidthPx = widthPx;
  }

  void _onPanDragUpdate(Offset local) {
    final startEnd = _dragStartEndMs;
    final startLocal = _dragStartLocal;
    final widthPx = _dragChartWidthPx;
    if (startEnd == null || startLocal == null || widthPx == null) return;
    if (widthPx <= 0) return;
    final dxPx = local.dx - startLocal.dx;
    // Pixel → time conversion: dragging the chart to the right
    // (positive dx) should reveal *older* data, so the proposed
    // endMs moves backward.
    final deltaMs = -(dxPx / widthPx) * _range.spanMs;
    final proposedEnd = startEnd + deltaMs.round();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final earliest = _service?.dataExtent.earliestMs ?? nowMs;
    if (proposedEnd >= nowMs) {
      _setRange(_range.goingLive());
      return;
    }
    final minEnd = earliest + _range.spanMs;
    final clampedEnd = proposedEnd < minEnd ? minEnd : proposedEnd;
    _setRange(VisibleRange(spanMs: _range.spanMs, endMs: clampedEnd));
  }

  void _onPanDragEnd() {
    _dragStartEndMs = null;
    _dragStartLocal = null;
    _dragChartWidthPx = null;
  }

  /// Cursor-anchored wheel zoom: the time-position under the
  /// pointer at wheel-start stays fixed under the pointer after the
  /// span changes, so the user is zooming "into" what they're
  /// looking at rather than the abstract midpoint.
  void _onWheelZoom(double factor, double cursorXPx, double widthPx) {
    if (widthPx <= 0 || factor <= 0) return;
    final limits = _spanLimits();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final xMin = _range.resolveStartMs(nowMs);
    final cursorFrac = (cursorXPx / widthPx).clamp(0.0, 1.0);
    final timeUnderCursor = xMin + (cursorFrac * _range.spanMs).round();
    final newSpan = (_range.spanMs / factor).round().clamp(
          limits.minMs,
          limits.maxMs,
        );
    final newXMin = timeUnderCursor - (cursorFrac * newSpan).round();
    final proposedEnd = newXMin + newSpan;
    if (proposedEnd >= nowMs) {
      _setRange(VisibleRange(spanMs: newSpan, endMs: null));
      return;
    }
    final earliest = _service?.dataExtent.earliestMs ?? nowMs;
    final minEnd = earliest + newSpan;
    final clampedEnd = proposedEnd < minEnd ? minEnd : proposedEnd;
    _setRange(VisibleRange(spanMs: newSpan, endMs: clampedEnd));
  }

  // -------------------------------------------------------------------------
  // Top view — one series per host

  ({int xMinMs, int xMaxMs}) _chartAxis() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return (
      xMinMs: _range.resolveStartMs(nowMs),
      xMaxMs: _range.resolveEndMs(nowMs),
    );
  }

  Widget _buildHostsView(DockerstatsService s, List<String> hostIds) {
    final axis = _chartAxis();
    final cpu = <ChartSeries>[];
    final mem = <ChartSeries>[];
    final net = <ChartSeries>[];
    final blk = <ChartSeries>[];
    // The cache already holds samples bucketed to the chart's
    // pixel-budget granularity — server-side via SQL `GROUP BY` on
    // the initial query, then incrementally as live notifications
    // fold into bucket accumulators. We only need to sum per millis
    // across containers to produce the host-level series.
    for (final hostId in hostIds) {
      final hostname = s.cache.hostnames[hostId] ?? hostId;
      final color = _colors.colorFor('host:$hostId');
      final samples = s.cache.samplesForHost(hostId);
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
        _rangeControlBar(),
        _hostChips(s, hostIds),
        _chartGrid([
          StatsChart(
            title: 'CPU',
            yLabel: 'sum CPU% across containers',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'sum memUsage (MiB)',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: mem,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: net,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
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
    final axis = _chartAxis();
    final perContainer = s.cache.samplesForHostByContainer(hostId);
    final containerIds = perContainer.keys.toList()..sort();
    final visibleContainerIds =
        containerIds.where((k) => !_hiddenContainers.contains(k)).toList();

    ChartSeries seriesFor(String cid, double Function(StatSample) extract) {
      final raw = perContainer[cid] ?? const <StatSample>[];
      return ChartSeries(
        label: s.cache.containerNamesByHost[hostId]?[cid] ?? cid,
        color: _colors.colorFor('container:$cid'),
        points: [for (final p in raw) (millis: p.millis, value: extract(p))],
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
        _rangeControlBar(),
        _containerFilter(s, hostId, containerIds),
        _chartGrid([
          StatsChart(
            title: 'CPU',
            yLabel: 'CPU% per container',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: cpu,
            yFormatter: (v) => '${v.toStringAsFixed(0)}%',
          ),
          StatsChart(
            title: 'Memory',
            yLabel: 'memUsage (MiB) per container',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: mem,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Network I/O (cumulative rx + tx)',
            yLabel: 'MiB per container',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
            series: net,
            yFormatter: _compactNumber,
          ),
          StatsChart(
            title: 'Block I/O (cumulative read + write)',
            yLabel: 'MiB per container',
            xMinMs: axis.xMinMs,
            xMaxMs: axis.xMaxMs,
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

/// Wraps the chart grid to translate mouse-wheel and click-drag
/// gestures into range updates. One wrapper covers all four charts
/// so a gesture anywhere in the grid updates the shared time axis.
///
/// Listener handles `PointerSignalEvent`s (wheel scrolls); a sibling
/// GestureDetector picks up horizontal drag. fl_chart's built-in
/// touch handling for tooltips / hover keeps working under both
/// (tap and hover are different gesture types from horizontal drag).
class _RangeGestureWrapper extends StatelessWidget {
  final Widget child;

  /// Called on each wheel tick. `factor > 1` zooms in; `factor < 1`
  /// zooms out. `cursorXPx` is the pointer's x within the wrapper's
  /// local coordinate space; `widthPx` is the wrapper's pixel width.
  final void Function(double factor, double cursorXPx, double widthPx)
      onWheelZoom;

  /// Drag started at [local] (local coordinates) on a wrapper of
  /// [widthPx] pixels wide. The dashboard captures these for the
  /// duration of the gesture.
  final void Function(Offset local, double widthPx) onDragStart;

  /// Pointer moved while the drag is active.
  final void Function(Offset local) onDragUpdate;

  /// Drag finished (released or cancelled).
  final VoidCallback onDragEnd;

  const _RangeGestureWrapper({
    required this.child,
    required this.onWheelZoom,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthPx = constraints.maxWidth;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // Wheel up (scrollDelta.dy < 0) → zoom in;
              // wheel down → zoom out. 1.2× per tick feels smooth on
              // both a discrete mouse wheel and a trackpad's
              // continuous scroll.
              final factor = event.scrollDelta.dy < 0 ? 1.2 : 1.0 / 1.2;
              onWheelZoom(factor, event.localPosition.dx, widthPx);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Horizontal drag pans; the chart's own touch handling
            // (tooltips on hover / tap) sits below this and still
            // fires for non-drag gestures.
            onHorizontalDragStart: (details) {
              onDragStart(details.localPosition, widthPx);
            },
            onHorizontalDragUpdate: (details) {
              onDragUpdate(details.localPosition);
            },
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragEnd,
            child: child,
          ),
        );
      },
    );
  }
}
