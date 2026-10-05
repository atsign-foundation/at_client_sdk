import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../at_telemetry_log_record.dart';
import '../at_telemetry_resource.dart';
import '../codec/at_telemetry_logs_codec.dart';
import '../security/at_telemetry_http_signature.dart';
import '../security/at_telemetry_signer.dart';
import 'at_telemetry_log_record_exporter.dart';

final class AtTelemetrySignedHttpExporter
    implements AtTelemetryLogRecordExporter {
  static const String logsPath = '/v1/logs';
  static const int defaultMaxQueuedExports = 1000;

  final Uri _logsEndpoint;
  final String _keyId;
  final String _audience;
  final AtTelemetrySigner _signer;
  final http.Client _client;
  final bool _ownsClient;
  final int _maxQueuedExports;
  final ListQueue<(Uri, List<int>, Completer<void>)> _queue =
      ListQueue<(Uri, List<int>, Completer<void>)>();
  Future<void> _last = Future<void>.value();
  bool _sending = false;
  bool _closed = false;

  AtTelemetrySignedHttpExporter({
    required Uri endpoint,
    required String keyId,
    required String audience,
    required AtTelemetrySigner signer,
    http.Client? client,
    int maxQueuedExports = defaultMaxQueuedExports,
  })  : _logsEndpoint = _logsEndpointFor(endpoint),
        _keyId = keyId,
        _audience = audience,
        _signer = signer,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _maxQueuedExports = maxQueuedExports {
    if (maxQueuedExports < 1) {
      throw RangeError.value(maxQueuedExports, 'maxQueuedExports');
    }
  }

  static Uri _logsEndpointFor(Uri endpoint) {
    if (!endpoint.hasAuthority ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty &&
            endpoint.path != '/' &&
            !endpoint.path.endsWith(logsPath))) {
      throw ArgumentError.value(endpoint, 'endpoint', 'invalid OTLP endpoint');
    }
    return endpoint.replace(path: logsPath);
  }

  @override
  Future<void> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) {
    return _enqueue(
      () => const AtTelemetryLogsCodec().encodeExportRequest(
        <AtTelemetryLogRecord>[logRecord],
        resource: resource,
      ),
    );
  }

  Future<void> sendEncodedLogs(List<int> body) {
    final List<int> payload = List<int>.unmodifiable(body);
    return _enqueue(() => payload);
  }

  @override
  Future<void> flush() => _last;

  @override
  Future<void> shutdown() async {
    _closed = true;
    await _last;
    if (_ownsClient) _client.close();
  }

  Future<void> _enqueue(List<int> Function() encode) {
    if (_closed) {
      return Future<void>.error(StateError('Exporter is closed'));
    }

    final List<int> body;
    try {
      body = encode();
    } on Object catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }

    final Completer<void> done = Completer<void>();
    // flush only waits; the failure is reported through the returned Future
    _last = done.future.then<void>((void _) {}, onError: (Object _) {});
    _queue.add((_logsEndpoint, body, done));
    if (_queue.length > _maxQueuedExports) {
      final (Uri _, List<int> _, Completer<void> dropped) =
          _queue.removeFirst();
      dropped.completeError(
        StateError('Telemetry backlog is full, dropped the oldest export'),
      );
    }
    if (!_sending) {
      unawaited(_drain());
    }
    return done.future;
  }

  Future<void> _drain() async {
    _sending = true;
    while (_queue.isNotEmpty) {
      final (Uri endpoint, List<int> body, Completer<void> done) =
          _queue.removeFirst();
      try {
        await _send(endpoint, body);
        done.complete();
      } on Object catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }
    _sending = false;
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
