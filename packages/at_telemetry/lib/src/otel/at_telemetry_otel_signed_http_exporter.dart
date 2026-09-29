import 'dart:async';

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:at_telemetry/src/at_telemetry_exporter.dart';
import 'package:at_telemetry/src/at_telemetry_signer.dart';
import 'package:at_telemetry/src/otel/at_telemetry_otel_http_signature.dart';
import 'package:at_telemetry/src/otel/at_telemetry_otel_logs_codec.dart';
import 'package:http/http.dart' as http;

final class AtTelemetryOtelSignedHttpExporter implements AtTelemetryExporter {
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

  AtTelemetryOtelSignedHttpExporter({
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
    sendConfirmed(event);
    return _pending;
  }

  Future<void> sendConfirmed(AtTelemetryEvent event) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    return _enqueue(() => const AtTelemetryOtelLogsCodec().encodeExportRequest(
          <AtTelemetryEvent>[event],
          serviceName: _serviceName,
        ));
  }

  Future<void> sendEncodedLogs(List<int> body) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final List<int> payload = List<int>.unmodifiable(body);
    return _enqueue(() => payload);
  }

  @override
  Future<void> flush() => _pending;

  @override
  Future<void> shutdown() async {
    _closed = true;
    await _pending;
    if (_ownsClient) _client.close();
  }

  Future<void> _enqueue(List<int> Function() encode) {
    final Future<void> sent = _pending.then((_) => _send(encode()));
    _pending = sent.catchError((Object error) {
      _onError?.call(error);
    });
    return sent;
  }

  Future<void> _send(List<int> body) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final AtTelemetryOtelHttpSignature signed =
          await AtTelemetryOtelHttpSignature.sign(
        body: body,
        path: _endpoint.path,
        keyId: _keyId,
        audience: _audience,
        signer: _signer,
      );
      final http.Request request = http.Request('POST', _endpoint)
        ..followRedirects = false
        ..headers.addAll(<String, String>{
          'content-type': AtTelemetryOtelHttpSignature.contentType,
          AtTelemetryOtelHttpSignature.digestHeader: signed.digest,
          AtTelemetryOtelHttpSignature.audienceHeader: signed.audience,
          AtTelemetryOtelHttpSignature.inputHeader: signed.input,
          AtTelemetryOtelHttpSignature.signatureHeader: signed.signature,
          if (_apiKey != null) 'authorization': 'Bearer $_apiKey',
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
