/// One time-series chart driven by a list of named series.
///
/// Series are expressed as `(label, color, points)` triples; each point
/// is `(millis, value)`. The widget keeps the x-axis right-anchored
/// (`now`) and stretches back by [window].
library;

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

    double yMax = 0;
    for (final s in series) {
      for (final p in s.points) {
        if (p.value > yMax) yMax = p.value;
      }
    }
    if (yMax == 0) yMax = 1;
    yMax *= 1.1;

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
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: xMin,
                  maxX: nowMs,
                  minY: 0,
                  maxY: yMax,
                  lineBarsData: lines,
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
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            yFormatter(v),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: window.inMilliseconds / 5,
                        getTitlesWidget: (v, _) {
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                            v.toInt(),
                          );
                          return Text(
                            '${dt.minute.toString().padLeft(2, '0')}:'
                            '${dt.second.toString().padLeft(2, '0')}',
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
