import '../internal/opentelemetry/dartastic_traces_codec.dart';
import '../models/traces/at_telemetry_span.dart';

final class AtTelemetryTracesCodec {
  static const String scopeName = DartasticTracesCodec.scopeName;
  static const DartasticTracesCodec _codec = DartasticTracesCodec();

  const AtTelemetryTracesCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetrySpan> spans, {
    String? serviceName,
  }) {
    return _codec.encodeExportRequest(spans, serviceName: serviceName);
  }

  List<AtTelemetrySpan> decodeExportRequest(List<int> payload) {
    return _codec.decodeExportRequest(payload);
  }

  List<int> encodeExportResponse() {
    return _codec.encodeExportResponse();
  }
}
