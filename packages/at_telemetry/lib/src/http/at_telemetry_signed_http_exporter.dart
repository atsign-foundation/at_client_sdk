import 'dart:async';

import 'package:at_telemetry/src/models/logs/at_telemetry_log_record.dart';
import 'package:at_telemetry/src/exporters/at_telemetry_log_record_exporter.dart';
import 'package:at_telemetry/src/models/metrics/at_telemetry_metric.dart';
import 'package:at_telemetry/src/exporters/at_telemetry_metric_exporter.dart';
import 'package:at_telemetry/src/models/traces/at_telemetry_span.dart';
import 'package:at_telemetry/src/exporters/at_telemetry_span_exporter.dart';
import 'package:at_telemetry/src/security/at_telemetry_signer.dart';
import 'package:at_telemetry/src/security/at_telemetry_http_signature.dart';
import 'package:at_telemetry/src/codec/at_telemetry_logs_codec.dart';
import 'package:at_telemetry/src/codec/at_telemetry_metrics_codec.dart';
import 'package:at_telemetry/src/codec/at_telemetry_traces_codec.dart';
import 'package:http/http.dart' as http;

final class AtTelemetrySignedHttpExporter
    implements
        AtTelemetryLogRecordExporter,
        AtTelemetryMetricExporter,
        AtTelemetrySpanExporter {
  static const String logsPath = '/v1/logs';
  static const String metricsPath = '/v1/metrics';
  static const String tracesPath = '/v1/traces';

  final Uri _logsEndpoint;
  final Uri _metricsEndpoint;
  final Uri _tracesEndpoint;
  final String _serviceName;
  final String _keyId;
  final String _audience;
  final AtTelemetrySigner _signer;
  final http.Client _client;
  final bool _ownsClient;
  final void Function(Object)? _onError;
  Future<void> _pending = Future<void>.value();
  bool _closed = false;

  AtTelemetrySignedHttpExporter({
    required Uri endpoint,
    required String serviceName,
    required String keyId,
    required String audience,
    required AtTelemetrySigner signer,
    http.Client? client,
    void Function(Object)? onError,
  })  : _logsEndpoint = _signalEndpoint(endpoint, logsPath),
        _metricsEndpoint = _signalEndpoint(endpoint, metricsPath),
        _tracesEndpoint = _signalEndpoint(endpoint, tracesPath),
        _serviceName = serviceName,
        _keyId = keyId,
        _audience = audience,
        _signer = signer,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _onError = onError;

  static Uri _signalEndpoint(Uri endpoint, String path) {
    if (!endpoint.hasAuthority ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty &&
            endpoint.path != '/' &&
            !endpoint.path.endsWith(logsPath) &&
            !endpoint.path.endsWith(metricsPath) &&
            !endpoint.path.endsWith(tracesPath))) {
      throw ArgumentError.value(endpoint, 'endpoint', 'invalid OTLP endpoint');
    }
    return endpoint.replace(path: path);
  }

  @override
  Future<void> export(AtTelemetryLogRecord event) {
    sendConfirmed(event);
    return _pending;
  }

  Future<void> sendConfirmed(AtTelemetryLogRecord event) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    return _enqueue(
        _logsEndpoint,
        () => const AtTelemetryLogsCodec().encodeExportRequest(
              <AtTelemetryLogRecord>[event],
              serviceName: _serviceName,
            ));
  }

  @override
  Future<void> exportMetrics(Iterable<AtTelemetryMetric> measurements) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final List<AtTelemetryMetric> snapshot =
        List<AtTelemetryMetric>.of(measurements);
    _enqueue(
        _metricsEndpoint,
        () => const AtTelemetryMetricsCodec().encodeExportRequest(
              snapshot,
              serviceName: _serviceName,
            ));
    return _pending;
  }

  @override
  Future<void> exportSpans(Iterable<AtTelemetrySpan> spans) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final List<AtTelemetrySpan> snapshot = List<AtTelemetrySpan>.of(spans);
    _enqueue(
        _tracesEndpoint,
        () => const AtTelemetryTracesCodec().encodeExportRequest(
              snapshot,
              serviceName: _serviceName,
            ));
    return _pending;
  }

  Future<void> sendEncodedLogs(List<int> body) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final List<int> payload = List<int>.unmodifiable(body);
    return _enqueue(_logsEndpoint, () => payload);
  }

  @override
  Future<void> flush() => _pending;

  @override
  Future<void> shutdown() async {
    _closed = true;
    await _pending;
    if (_ownsClient) _client.close();
  }

  Future<void> _enqueue(Uri endpoint, List<int> Function() encode) {
    final Future<void> sent = _pending.then((_) => _send(endpoint, encode()));
    _pending = sent.catchError((Object error) {
      _onError?.call(error);
    });
    return sent;
  }

  Future<void> _send(Uri endpoint, List<int> body) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final AtTelemetryHttpSignature signed =
          await AtTelemetryHttpSignature.sign(
        body: body,
        path: endpoint.path,
        keyId: _keyId,
        audience: _audience,
        signer: _signer,
      );
      final http.Request request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers.addAll(<String, String>{
          'content-type': AtTelemetryHttpSignature.contentType,
          AtTelemetryHttpSignature.digestHeader: signed.digest,
          AtTelemetryHttpSignature.audienceHeader: signed.audience,
          AtTelemetryHttpSignature.inputHeader: signed.input,
          AtTelemetryHttpSignature.signatureHeader: signed.signature,
        })
        ..bodyBytes = body;
      try {
        final http.StreamedResponse response =
            await _client.send(request).timeout(const Duration(seconds: 10));
        await response.stream
            .drain<void>()
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          return;
        }
        if (response.statusCode != 429 && response.statusCode < 500) {
          throw StateError('Telemetry rejected: HTTP ${response.statusCode}');
        }
        if (attempt == 2) {
          throw StateError(
              'Telemetry unavailable: HTTP ${response.statusCode}');
        }
      } on http.ClientException {
        if (attempt == 2) rethrow;
      } on TimeoutException {
        if (attempt == 2) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 200 * (1 << attempt)));
    }
  }
}
