import 'dart:async';

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:at_telemetry/src/at_telemetry_exporter.dart';
import 'package:at_telemetry/src/otel/at_telemetry_http_signature.dart';
import 'package:at_telemetry/src/otel/at_telemetry_otel_logs_codec.dart';
import 'package:http/http.dart' as http;

final class AtTelemetrySignedHttpExporter implements AtTelemetryExporter {
  final Uri _endpoint;
  final String _serviceName;
  final String _keyId;
  final String _audience;
  final AtTelemetryRsaSigner _signer;
  final String? _apiKey;
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
    required AtTelemetryRsaSigner signer,
    String? apiKey,
    http.Client? client,
    void Function(Object)? onError,
  })  : _endpoint = _logsEndpoint(endpoint),
        _serviceName = serviceName,
        _keyId = keyId,
        _audience = audience,
        _signer = signer,
        _apiKey = apiKey,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _onError = onError;

  static Uri _logsEndpoint(Uri endpoint) {
    if (!endpoint.hasAuthority ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty &&
            endpoint.path != '/' &&
            !endpoint.path.endsWith('/v1/logs'))) {
      throw ArgumentError.value(endpoint, 'endpoint', 'invalid OTLP endpoint');
    }
    return endpoint.replace(path: '/v1/logs');
  }

  @override
  Future<void> export(AtTelemetryEvent event) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final Future<void> sent = _pending.then((_) => _send(event));
    _pending = sent.catchError((Object error) {
      _onError?.call(error);
    });
    return _pending;
  }

  Future<void> _send(AtTelemetryEvent event) async {
    final List<int> body = const AtTelemetryOtelLogsCodec().encodeExportRequest(
        <AtTelemetryEvent>[event],
        serviceName: _serviceName);
    for (int attempt = 0; attempt < 3; attempt++) {
      final AtTelemetryHttpSignature signed =
          await AtTelemetryHttpSignature.sign(
        body: body,
        path: _endpoint.path,
        keyId: _keyId,
        audience: _audience,
        signer: _signer,
      );
      final Map<String, String> headers = <String, String>{
        'content-type': AtTelemetryHttpSignature.contentType,
        AtTelemetryHttpSignature.digestHeader: signed.digest,
        AtTelemetryHttpSignature.audienceHeader: signed.audience,
        AtTelemetryHttpSignature.inputHeader: signed.input,
        AtTelemetryHttpSignature.signatureHeader: signed.signature,
        if (_apiKey != null) 'authorization': 'Bearer $_apiKey',
      };
      try {
        final http.Response response = await _client
            .post(
              _endpoint,
              headers: headers,
              body: body,
            )
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

  @override
  Future<void> flush() => _pending;

  @override
  Future<void> shutdown() async {
    _closed = true;
    await _pending;
    if (_ownsClient) _client.close();
  }
}
