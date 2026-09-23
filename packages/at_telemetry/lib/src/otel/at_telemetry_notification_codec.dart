import 'dart:convert';

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:at_telemetry/src/otel/at_telemetry_otel_logs_codec.dart';

final class AtTelemetryNotificationCodec {
  static const String namespace = 'at_telemetry';
  static const String idAndNamespace = 'logs.$namespace';

  final AtTelemetryOtelLogsCodec _logsCodec;

  const AtTelemetryNotificationCodec({
    AtTelemetryOtelLogsCodec logsCodec = const AtTelemetryOtelLogsCodec(),
  }) : _logsCodec = logsCodec;

  String encode(
    Iterable<AtTelemetryEvent> events, {
    String? serviceName,
  }) {
    return base64Encode(
      _logsCodec.encodeExportRequest(events, serviceName: serviceName),
    );
  }

  List<AtTelemetryEvent> decode(String payload) {
    final List<int> bytes;
    try {
      bytes = base64Decode(payload);
    } on FormatException catch (error) {
      throw FormatException('Invalid base64 telemetry payload', error);
    }
    return _logsCodec.decodeExportRequest(bytes);
  }
}
