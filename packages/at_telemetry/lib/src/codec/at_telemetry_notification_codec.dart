import 'dart:convert';

import 'package:at_telemetry/src/models/logs/at_telemetry_log_record.dart';
import 'package:at_telemetry/src/codec/at_telemetry_logs_codec.dart';
import 'package:at_telemetry/src/codec/at_telemetry_metrics_codec.dart';
import 'package:at_telemetry/src/codec/at_telemetry_traces_codec.dart';
import 'package:at_telemetry/src/models/metrics/at_telemetry_metric.dart';
import 'package:at_telemetry/src/models/traces/at_telemetry_span.dart';

final class AtTelemetryNotificationCodec {
  static const String namespace = 'at_telemetry';
  static const String idAndNamespace = 'logs.$namespace';
  static const String metricsIdAndNamespace = 'metrics.$namespace';
  static const String tracesIdAndNamespace = 'traces.$namespace';

  final AtTelemetryLogsCodec _logsCodec;
  final AtTelemetryMetricsCodec _metricsCodec;
  final AtTelemetryTracesCodec _tracesCodec;

  const AtTelemetryNotificationCodec({
    AtTelemetryLogsCodec logsCodec = const AtTelemetryLogsCodec(),
    AtTelemetryMetricsCodec metricsCodec = const AtTelemetryMetricsCodec(),
    AtTelemetryTracesCodec tracesCodec = const AtTelemetryTracesCodec(),
  })  : _logsCodec = logsCodec,
        _metricsCodec = metricsCodec,
        _tracesCodec = tracesCodec;

  String encode(
    Iterable<AtTelemetryLogRecord> events, {
    String? serviceName,
  }) {
    return base64Encode(
      _logsCodec.encodeExportRequest(events, serviceName: serviceName),
    );
  }

  String encodeMetrics(
    Iterable<AtTelemetryMetric> measurements, {
    String? serviceName,
  }) {
    return base64Encode(
      _metricsCodec.encodeExportRequest(measurements, serviceName: serviceName),
    );
  }

  String encodeSpans(
    Iterable<AtTelemetrySpan> spans, {
    String? serviceName,
  }) {
    return base64Encode(
      _tracesCodec.encodeExportRequest(spans, serviceName: serviceName),
    );
  }

  List<AtTelemetryLogRecord> decode(String payload) {
    return _logsCodec.decodeExportRequest(decodePayload(payload));
  }

  List<AtTelemetryMetric> decodeMetrics(String payload) {
    return _metricsCodec.decodeExportRequest(decodePayload(payload));
  }

  List<AtTelemetrySpan> decodeSpans(String payload) {
    return _tracesCodec.decodeExportRequest(decodePayload(payload));
  }

  List<int> decodePayload(String payload) {
    try {
      return base64Decode(payload);
    } on FormatException catch (error) {
      throw FormatException('Invalid base64 telemetry payload', error);
    }
  }
}
