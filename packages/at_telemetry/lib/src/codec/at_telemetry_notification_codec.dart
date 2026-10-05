import 'dart:convert';

import 'package:at_telemetry/src/models/logs/at_telemetry_log_record.dart';
import 'package:at_telemetry/src/codec/at_telemetry_logs_codec.dart';

final class AtTelemetryNotificationCodec {
  static const String namespace = 'at_telemetry';
  static const String idAndNamespace = 'logs.$namespace';

  final AtTelemetryLogsCodec _logsCodec;

  const AtTelemetryNotificationCodec({
    AtTelemetryLogsCodec logsCodec = const AtTelemetryLogsCodec(),
  }) : _logsCodec = logsCodec;

  String encode(
    Iterable<AtTelemetryLogRecord> events, {
    String? serviceName,
  }) {
    return base64Encode(
      _logsCodec.encodeExportRequest(events, serviceName: serviceName),
    );
  }

  List<AtTelemetryLogRecord> decode(String payload) {
    return _logsCodec.decodeExportRequest(decodePayload(payload));
  }

  List<int> decodePayload(String payload) {
    try {
      return base64Decode(payload);
    } on FormatException catch (error) {
      throw FormatException('Invalid base64 telemetry payload', error);
    }
  }
}
