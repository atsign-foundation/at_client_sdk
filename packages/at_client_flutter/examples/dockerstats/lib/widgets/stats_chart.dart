/// One time-series chart driven by a list of named series.
///
/// Series are expressed as `(label, color, points)` triples; each point
/// is `(millis, value)`. The widget keeps the x-axis right-anchored
/// (`now`) and stretches back by [window].
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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
    final xMin = nowMs - window.inMilliseconds;

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
    final yInterval = yMax / 5;

    final lines = [
      for (final s in series)
        LineChartBarData(
          isCurved: false,
          color: s.color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          spots: [
            for (final p in s.points)
              if (p.millis >= xMin) FlSpot(p.millis.toDouble(), p.value),
          ],
        ),
    ];

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const Spacer(),
                _Legend(series: series),
              ],
            ),
            const SizedBox(height: 4),
            Text(yLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
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
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        interval: yInterval,
                        getTitlesWidget: (v, _) {
                          // Suppress the very top tick so it can't
                          // overlap the next-lower one as yMax shifts
                          // between snapped buckets.
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
                        interval: _bottomTickInterval(window),
                        getTitlesWidget: (v, meta) {
                          // Suppress ticks within ~⅓ interval of the
                          // chart edges so the leftmost label can't
                          // overlap the next one entering view as the
                          // x-axis scrolls.
                          final guard = _bottomTickInterval(window) / 3;
                          if (v < xMin + guard || v > nowMs - guard) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _formatTimeLabel(v.toInt(), window),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tick interval (ms) tuned to the visible window so we get ~5 labels.
double _bottomTickInterval(Duration window) {
  return window.inMilliseconds / 5;
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

/// Time label, formatted to the resolution that's useful at the
/// selected window. Short windows want second resolution; long windows
/// want clock time.
String _formatTimeLabel(int ms, Duration window) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  if (window <= const Duration(minutes: 10)) {
    return '${two(dt.minute)}:${two(dt.second)}';
  }
  return '${two(dt.hour)}:${two(dt.minute)}';
}

class _Legend extends StatelessWidget {
  final List<ChartSeries> series;
  const _Legend({required this.series});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 4,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(s.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
