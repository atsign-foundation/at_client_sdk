import 'at_telemetry_gauge.dart';

abstract interface class AtTelemetryGaugeExporter {
  Future<void> exportGauges(Iterable<AtTelemetryGauge> gauges);
}
