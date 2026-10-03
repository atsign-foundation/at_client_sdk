import 'at_telemetry_metric.dart';

final class AtTelemetryGauge extends AtTelemetryMetric {
  final double value;

  const AtTelemetryGauge({
    required super.name,
    required this.value,
    required super.timestamp,
    super.unit,
    super.attributes,
  });
}
