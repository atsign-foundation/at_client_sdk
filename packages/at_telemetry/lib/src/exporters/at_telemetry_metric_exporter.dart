import '../models/metrics/at_telemetry_metric.dart';

abstract interface class AtTelemetryMetricExporter {
  Future<void> exportMetrics(Iterable<AtTelemetryMetric> metrics);
  Future<void> flush();
  Future<void> shutdown();
}
