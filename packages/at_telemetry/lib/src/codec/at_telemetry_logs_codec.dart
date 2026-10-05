import '../at_telemetry_log_record.dart';
import '../internal/dartastic_logs_codec.dart';

final class AtTelemetryLogsCodec {
  static const String scopeName = DartasticLogsCodec.scopeName;
  static const DartasticLogsCodec _codec = DartasticLogsCodec();

  const AtTelemetryLogsCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetryLogRecord> events, {
    String? serviceName,
  }) {
    return _codec.encodeExportRequest(events, serviceName: serviceName);
  }

  List<AtTelemetryLogRecord> decodeExportRequest(List<int> payload) {
    return _codec.decodeExportRequest(payload);
  }

  List<int> encodeExportResponse() {
    return _codec.encodeExportResponse();
  }
}
