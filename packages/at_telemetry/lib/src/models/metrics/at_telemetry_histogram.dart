import 'at_telemetry_aggregation_temporality.dart';
import 'at_telemetry_metric.dart';

final class AtTelemetryHistogram extends AtTelemetryMetric {
  final int count;
  final double? sum;
  final double? min;
  final double? max;
  final List<int> bucketCounts;
  final List<double> explicitBounds;
  final DateTime? startTimestamp;
  final AtTelemetryAggregationTemporality temporality;

  const AtTelemetryHistogram({
    required super.name,
    required this.count,
    required super.timestamp,
    this.sum,
    this.min,
    this.max,
    this.bucketCounts = const <int>[],
    this.explicitBounds = const <double>[],
    this.startTimestamp,
    this.temporality = AtTelemetryAggregationTemporality.cumulative,
    super.unit,
    super.attributes,
  });
}
