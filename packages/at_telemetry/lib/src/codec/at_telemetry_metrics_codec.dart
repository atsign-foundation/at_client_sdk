import '../internal/opentelemetry/dartastic_metrics_codec.dart';
import '../models/metrics/at_telemetry_metric.dart';

final class AtTelemetryMetricsCodec {
  static const String scopeName = DartasticMetricsCodec.scopeName;
  static const DartasticMetricsCodec _codec = DartasticMetricsCodec();

  const AtTelemetryMetricsCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetryMetric> measurements, {
    String? serviceName,
  }) {
    return _codec.encodeExportRequest(measurements, serviceName: serviceName);
  }

  List<AtTelemetryMetric> decodeExportRequest(List<int> payload) {
    return _codec.decodeExportRequest(payload);
  }

  List<int> encodeExportResponse() {
    return _codec.encodeExportResponse();
  }
}
