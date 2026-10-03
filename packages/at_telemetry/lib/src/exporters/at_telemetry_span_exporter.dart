import '../models/traces/at_telemetry_span.dart';

abstract interface class AtTelemetrySpanExporter {
  Future<void> exportSpans(Iterable<AtTelemetrySpan> spans);
  Future<void> flush();
  Future<void> shutdown();
}
