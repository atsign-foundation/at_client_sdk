import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../at_telemetry_log_record.dart';
import '../codec/at_telemetry_logs_codec.dart';
import '../security/at_telemetry_http_signature.dart';
import '../security/at_telemetry_signer.dart';
import 'at_telemetry_log_record_exporter.dart';

final class AtTelemetrySignedHttpExporter
    implements AtTelemetryLogRecordExporter {
  static const String logsPath = '/v1/logs';
  static const int defaultMaxQueuedExports = 1000;

  final Uri _logsEndpoint;
  final String _serviceName;
  final String _keyId;
  final String _audience;
  final AtTelemetrySigner _signer;
  final http.Client _client;
  final bool _ownsClient;
  final void Function(Object)? _onError;
  final int _maxQueuedExports;
  final ListQueue<(Uri, List<int>, Completer<void>)> _queue =
      ListQueue<(Uri, List<int>, Completer<void>)>();
  Future<void> _last = Future<void>.value();
  bool _sending = false;
  bool _closed = false;

  AtTelemetrySignedHttpExporter({
    required Uri endpoint,
    required String serviceName,
    required String keyId,
    required String audience,
    required AtTelemetrySigner signer,
    http.Client? client,
    void Function(Object)? onError,
    int maxQueuedExports = defaultMaxQueuedExports,
  })  : _logsEndpoint = _logsEndpointFor(endpoint),
        _serviceName = serviceName,
        _keyId = keyId,
        _audience = audience,
        _signer = signer,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _onError = onError,
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
  Future<void> export(AtTelemetryLogRecord event) {
    final (Future<void> _, Future<void> handled) = _enqueueLogRecord(event);
    return handled;
  }

  Future<void> sendConfirmed(AtTelemetryLogRecord event) {
    final (Future<void> sent, Future<void> _) = _enqueueLogRecord(event);
    return sent;
  }

  Future<void> sendEncodedLogs(List<int> body) {
    if (_closed) {
      throw StateError('Exporter is closed');
    }
    final List<int> payload = List<int>.unmodifiable(body);
    final (Future<void> sent, Future<void> _) =
        _enqueue(_logsEndpoint, () => payload);
    return sent;
  }

  @override
  Future<void> flush() => _last;

  @override
  Future<void> shutdown() async {
    _closed = true;
    await _last;
    if (_ownsClient) _client.close();
  }

  (Future<void>, Future<void>) _enqueueLogRecord(AtTelemetryLogRecord event) {
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

  (Future<void>, Future<void>) _enqueue(
    Uri endpoint,
    List<int> Function() encode,
  ) {
    final Completer<void> done = Completer<void>();
    final Future<void> handled = done.future.catchError((Object error) {
      _onError?.call(error);
    });
    final List<int> body;
    try {
      body = encode();
    } on Object catch (error, stackTrace) {
      done.completeError(error, stackTrace);
      return (done.future, handled);
    }

    _queue.add((endpoint, body, done));
    _last = handled;
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
    return (done.future, handled);
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
