import 'at_telemetry_aggregation_temporality.dart';
import 'at_telemetry_metric.dart';

final class AtTelemetrySum extends AtTelemetryMetric {
  final double value;
  final DateTime? startTimestamp;
  final AtTelemetryAggregationTemporality temporality;
  final bool isMonotonic;

  const AtTelemetrySum({
    required super.name,
    required this.value,
    required super.timestamp,
    this.startTimestamp,
    this.temporality = AtTelemetryAggregationTemporality.cumulative,
    this.isMonotonic = true,
    super.unit,
    super.attributes,
  });
}
