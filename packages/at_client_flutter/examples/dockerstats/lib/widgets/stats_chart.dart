/// One time-series chart driven by a list of named series.
///
/// Series are expressed as `(label, color, points)` triples; each
/// point is `(millis, value)`. The widget keeps the x-axis
/// right-anchored (`now`) and stretches back by [window].
///
/// [window] = [Duration.zero] is the "fit to data" sentinel — the
/// chart sets `xMin` to the earliest sample across all series
/// instead of `now - window`, and the time-axis tick spacing /
/// label format are derived from the data range.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Floor for the gap-break threshold — the smallest pause that
/// can ever trigger a chart break. At narrow windows the actual
/// threshold equals this; at wider windows it scales up via
/// [_gapThresholdFor] so coarser-tier data (1-min, 15-min, 1-hour,
/// 8-hour buckets) doesn't show every adjacent pair as a break.
const int _gapThresholdFloorMs = 30 * 1000;

/// Hard cap on the number of points rendered per series. fl_chart
/// happily renders thousands but redraw cost scales linearly, and
/// the human eye can't distinguish thousands of points on a
/// finite-pixel chart. Stride-downsample anything above this so
/// long-window views (7d, 1m, 6m, 2y, all) render at the same fps
/// as short ones.
const int _maxSpotsPerSeries = 1000;

/// Compute the gap-break threshold for a given visible window.
/// Scales as `window / 240` (so a 1-day window yields a 6-min
/// threshold, a 7-day window yields ~42 min) but never drops below
/// [_gapThresholdFloorMs] so finely-sampled views still surface
/// short pauses.
int _gapThresholdFor(num effectiveWindowMs) {
  final scaled = (effectiveWindowMs / 240).round();
  return scaled > _gapThresholdFloorMs ? scaled : _gapThresholdFloorMs;
}

/// Stride-downsample [points] to at most [_maxSpotsPerSeries]
/// entries, preserving the first and last point and keeping the
/// in-between spacing uniform. Cheap and order-preserving;
/// adequate for time-series chart rendering where the visual
/// shape is what matters and the exact density of points is not
/// meaningful below a few hundred per series.
List<P> _downsample<P>(List<P> points) {
  if (points.length <= _maxSpotsPerSeries) return points;
  final stride = points.length / _maxSpotsPerSeries;
  final out = <P>[];
  for (var i = 0; i < _maxSpotsPerSeries - 1; i++) {
    out.add(points[(i * stride).floor()]);
  }
  out.add(points.last); // pin the right-most point
  return out;
}

class ChartSeries {
  final String label;
  final Color color;
  final List<({int millis, double value})> points;

  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });
}

class StatsChart extends StatelessWidget {
  final String title;
  final String yLabel;
  final Duration window;
  final List<ChartSeries> series;
  final String Function(double) yFormatter;

  const StatsChart({
    super.key,
    required this.title,
    required this.yLabel,
    required this.window,
    required this.series,
    required this.yFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final double xMin;
    if (window == Duration.zero) {
      // "All" mode: fit to data. Find the earliest sample millis
      // across every series; fall back to `now - 5 min` when the
      // chart has no data so the axes still render sensibly.
      double earliest = double.infinity;
      for (final s in series) {
        for (final p in s.points) {
          if (p.millis < earliest) earliest = p.millis.toDouble();
        }
      }
      xMin = earliest.isFinite
          ? earliest
          : nowMs - const Duration(minutes: 5).inMilliseconds;
    } else {
      xMin = nowMs - window.inMilliseconds;
    }
    // Effective window — what the tick interval and label format
    // should size against. For fixed windows this equals `window`;
    // for `all` it equals the data range.
    final effectiveWindowMs = (nowMs - xMin).clamp(1, double.infinity);

    double rawMax = 0;
    for (final s in series) {
      for (final p in s.points) {
        if (p.value > rawMax) rawMax = p.value;
      }
    }
    // Snap the top-of-chart to a "nice" round value so it doesn't
    // jitter every frame as new samples come in. Without this, fl_chart
    // re-picks tick positions on each redraw and labels at the top
    // edge fight each other for the same row.
    final yMax = _niceCeiling(rawMax == 0 ? 1 : rawMax * 1.1);

    // Per-window gap-break threshold. Scales with the visible
    // window so coarser-tier data (1-min, 15-min, 1-hour, 8-hour
    // buckets) doesn't trip the "publisher paused" break at every
    // consecutive pair. Narrow windows still get the tight
    // 30-second floor so real short pauses surface.
    final gapThresholdMs = _gapThresholdFor(effectiveWindowMs);

    // Per-series pipeline:
    //   filter → gap-break (on RAW spacing) → downsample (per segment) → render.
    // Gap-break MUST run on raw spacing, not after downsampling,
    // because downsampling spreads neighbouring points further apart
    // and would otherwise trip the threshold on every downsampled
    // tier-2 / tier-3 / tier-4 pair, hiding them from the chart.
    //
    // `seriesByBarIndex` maps each emitted LineChartBarData index
    // back to its parent [ChartSeries] so the tooltip can recover
    // the series label.
    final lines = <LineChartBarData>[];
    final seriesByBarIndex = <ChartSeries>[];
    for (final s in series) {
      final visible = [
        for (final p in s.points)
          if (p.millis >= xMin) p,
      ];
      if (visible.isEmpty) continue;
      var segmentStart = 0;
      for (var i = 1; i <= visible.length; i++) {
        final atEnd = i == visible.length;
        final breakHere =
            !atEnd &&
            visible[i].millis - visible[i - 1].millis > gapThresholdMs;
        if (atEnd || breakHere) {
          final segment = visible.sublist(segmentStart, i);
          final sampled = _downsample(segment);
          lines.add(
            LineChartBarData(
              isCurved: false,
              color: s.color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              spots: [
                for (final p in sampled) FlSpot(p.millis.toDouble(), p.value),
              ],
            ),
          );
          seriesByBarIndex.add(s);
          segmentStart = i;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(yLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Adaptive tick counts derived from the actual
                  // chart pixel size. ~80 px per x-axis label gives
                  // a date/time stamp comfortable headroom; ~32 px
                  // per y-axis label leaves a baseline gap between
                  // adjacent ticks. Clamped so the chart never
                  // looks empty (≥2 ticks) and never collides on
                  // narrow grid cells (≤6 ticks).
                  final maxXTicks = (constraints.maxWidth / 80).floor().clamp(
                    2,
                    6,
                  );
                  final maxYTicks = (constraints.maxHeight / 32).floor().clamp(
                    2,
                    6,
                  );
                  final xInterval = effectiveWindowMs / maxXTicks;
                  final yInterval = yMax / maxYTicks;
                  return LineChart(
                    duration: Duration.zero,
                    LineChartData(
                      minX: xMin,
                      maxX: nowMs,
                      minY: 0,
                      maxY: yMax,
                      lineBarsData: lines,
                      clipData: const FlClipData.horizontal(),
                      gridData: const FlGridData(
                        show: true,
                        drawVerticalLine: false,
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          tooltipBorderRadius: BorderRadius.circular(4),
                          maxContentWidth: 280,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (_) => theme
                              .colorScheme
                              .inverseSurface
                              .withValues(alpha: 0.95),
                          getTooltipItems: (spots) => _buildTooltipItems(
                            spots,
                            seriesByBarIndex,
                            theme,
                            yFormatter: yFormatter,
                          ),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 56,
                            interval: yInterval,
                            getTitlesWidget: (v, _) {
                              // Suppress the very top tick so it
                              // can't overlap the next-lower one as
                              // yMax shifts between snapped buckets.
                              if (v > yMax - yInterval / 3) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  yFormatter(v),
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: xInterval,
                            getTitlesWidget: (v, meta) {
                              // Suppress ticks within ~⅓ interval of
                              // the chart edges so the leftmost
                              // label can't overlap the next one
                              // entering view as the x-axis scrolls.
                              final guard = xInterval / 3;
                              if (v < xMin + guard || v > nowMs - guard) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                _formatTimeLabel(v.toInt(), effectiveWindowMs),
                                style: theme.textTheme.bodySmall,
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Snap [v] up to the nearest 1/2/5 × 10ⁿ. Stabilises the y-axis top
/// so it only steps when the data crosses a round threshold rather
/// than recomputing on every redraw.
double _niceCeiling(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 5.0]) {
    if (v <= m * mag) return m * mag;
  }
  return 10 * mag;
}

/// Tooltip-friendly timestamp — always full date + clock so the
/// user never has to guess what year or hour the hovered point is
/// from. Independent of [_formatTimeLabel], which is the
/// space-constrained x-axis tick label.
String _formatTooltipTimestamp(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// Build the tooltip's content for a hover/tap on the chart.
/// First item carries the timestamp as a header (followed by the
/// first series' line); subsequent items are one line per series.
/// Each series line is `label: yFormatter(value)` coloured to
/// match the series' line, on a high-contrast background.
List<LineTooltipItem?> _buildTooltipItems(
  List<LineBarSpot> spots,
  List<ChartSeries> seriesByBarIndex,
  ThemeData theme, {
  required String Function(double) yFormatter,
}) {
  if (spots.isEmpty) return const [];
  final headerColor = theme.colorScheme.onInverseSurface;
  final headerStyle =
      theme.textTheme.bodySmall?.copyWith(
        color: headerColor,
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(color: headerColor, fontWeight: FontWeight.w600, fontSize: 11);
  final lineStyleBase =
      theme.textTheme.bodySmall?.copyWith(color: headerColor) ??
      TextStyle(color: headerColor, fontSize: 11);

  // All hover spots share the same x at fl_chart's vertical sweep,
  // so we read the timestamp from the first one.
  final tsText = _formatTooltipTimestamp(spots.first.x.toInt());

  return [
    for (var i = 0; i < spots.length; i++)
      _itemFor(
        spots[i],
        seriesByBarIndex,
        yFormatter: yFormatter,
        lineStyle: lineStyleBase,
        // Only the first item shows the timestamp header — the
        // rest just contribute their series line.
        headerText: i == 0 ? tsText : null,
        headerStyle: headerStyle,
      ),
  ];
}

LineTooltipItem _itemFor(
  LineBarSpot spot,
  List<ChartSeries> seriesByBarIndex, {
  required String Function(double) yFormatter,
  required TextStyle lineStyle,
  required String? headerText,
  required TextStyle headerStyle,
}) {
  final s = (spot.barIndex >= 0 && spot.barIndex < seriesByBarIndex.length)
      ? seriesByBarIndex[spot.barIndex]
      : null;
  final label = s?.label ?? 'series';
  final color = s?.color ?? lineStyle.color ?? const Color(0xffffffff);
  final lineText = '$label: ${yFormatter(spot.y)}';
  if (headerText != null) {
    return LineTooltipItem(
      headerText,
      headerStyle,
      textAlign: TextAlign.left,
      children: [
        const TextSpan(text: '\n'),
        TextSpan(
          text: lineText,
          style: lineStyle.copyWith(color: color),
        ),
      ],
    );
  }
  return LineTooltipItem(
    lineText,
    lineStyle.copyWith(color: color),
    textAlign: TextAlign.left,
  );
}

/// Time label, formatted to the resolution that's useful for the
/// visible range. Short ranges want second resolution; multi-day
/// ranges want a date+hour stamp; multi-month/year ranges want
/// just a date. Takes `effectiveWindowMs` so the "all" path's
/// data-derived range works without a synthetic Duration.
String _formatTimeLabel(int ms, num effectiveWindowMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  const int minute = 60 * 1000;
  const int hour = 60 * minute;
  const int day = 24 * hour;
  if (effectiveWindowMs <= 10 * minute) {
    return '${two(dt.minute)}:${two(dt.second)}';
  }
  if (effectiveWindowMs <= day) {
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
  if (effectiveWindowMs <= 30 * day) {
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}
