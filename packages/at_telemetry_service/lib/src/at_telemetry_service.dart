import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';

import 'at_telemetry_ingestor.dart';
import 'at_telemetry_producer_authenticator.dart';
import 'at_telemetry_producer_identity.dart';
import 'at_telemetry_reader_authenticator.dart';

final class AtTelemetryService {
  static const int defaultMaxRequestBytes = 1024 * 1024;
  static const String logsPath = '/v1/logs';
  static const String eventsPath = '/v1/events';

  final HttpServer _server;
  final AtTelemetryProducerAuthenticator _authenticator;
  final AtTelemetryIngestor _ingestor;
  final AtTelemetryOtelLogsCodec _codec;
  final int _maxRequestBytes;
  final AtTelemetryReaderAuthenticator? _readerAuthenticator;
  final AtTelemetryPersistence? _persistence;

  AtTelemetryService._({
    required HttpServer server,
    required AtTelemetryProducerAuthenticator authenticator,
    required AtTelemetryIngestor ingestor,
    required AtTelemetryOtelLogsCodec codec,
    required int maxRequestBytes,
    required AtTelemetryReaderAuthenticator? readerAuthenticator,
    required AtTelemetryPersistence? persistence,
  })  : _server = server,
        _authenticator = authenticator,
        _ingestor = ingestor,
        _codec = codec,
        _maxRequestBytes = maxRequestBytes,
        _readerAuthenticator = readerAuthenticator,
        _persistence = persistence;

  static Future<AtTelemetryService> bind({
    required Object address,
    required int port,
    required AtTelemetryProducerAuthenticator authenticator,
    required AtTelemetryIngestor ingestor,
    AtTelemetryOtelLogsCodec codec = const AtTelemetryOtelLogsCodec(),
    int maxRequestBytes = defaultMaxRequestBytes,
    AtTelemetryReaderAuthenticator? readerAuthenticator,
    AtTelemetryPersistence? persistence,
    SecurityContext? securityContext,
  }) async {
    if ((readerAuthenticator == null) != (persistence == null)) {
      throw ArgumentError(
        'readerAuthenticator and persistence must be provided together',
      );
    }
    if (port < 0 || port > 65535) {
      throw RangeError.range(port, 0, 65535, 'port');
    }
    if (maxRequestBytes <= 0) {
      throw RangeError.value(
        maxRequestBytes,
        'maxRequestBytes',
        'must be greater than zero',
      );
    }

    final HttpServer server = securityContext == null
        ? await HttpServer.bind(address, port)
        : await HttpServer.bindSecure(address, port, securityContext);
    final AtTelemetryService service = AtTelemetryService._(
      server: server,
      authenticator: authenticator,
      ingestor: ingestor,
      codec: codec,
      maxRequestBytes: maxRequestBytes,
      readerAuthenticator: readerAuthenticator,
      persistence: persistence,
    );
    server.listen((HttpRequest request) {
      unawaited(service._handleRequest(request));
    });
    return service;
  }

  InternetAddress get address => _server.address;

  int get port => _server.port;

  Future<void> close({bool force = false}) async {
    await _server.close(force: force);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case logsPath:
          await _handleLogs(request);
        case eventsPath when _readerAuthenticator != null:
          await _handleEvents(request);
        default:
          await _sendError(request.response, HttpStatus.notFound, 'Not found');
      }
    } on Object {
      try {
        await _sendError(
          request.response,
          HttpStatus.internalServerError,
          'Internal server error',
        );
      } on Object {
        return;
      }
    }
  }

  Future<void> _handleEvents(HttpRequest request) async {
    if (request.method != 'GET') {
      await _sendMethodNotAllowed(request.response, 'GET');
      return;
    }

    final String? apiKey = _bearerCredential(request.headers);
    if (apiKey == null) {
      await _sendUnauthorized(request.response);
      return;
    }

    final AtTelemetryReaderIdentity? reader;
    try {
      reader = await _readerAuthenticator!.authenticate(apiKey);
    } on Object {
      await _sendError(
        request.response,
        HttpStatus.serviceUnavailable,
        'Authentication unavailable',
      );
      return;
    }
    if (reader == null) {
      await _sendUnauthorized(request.response);
      return;
    }

    final AtTelemetryQuery query;
    try {
      query = AtTelemetryQuery.fromQueryParameters(
        tenantId: reader.tenantId,
        parameters: request.uri.queryParameters,
      );
    } on FormatException catch (error) {
      await _sendError(request.response, HttpStatus.badRequest, error.message);
      return;
    } on ArgumentError catch (error) {
      await _sendError(
        request.response,
        HttpStatus.badRequest,
        '${error.name ?? 'query'}: ${error.message}',
      );
      return;
    }

    final List<AtTelemetryRecord> records;
    try {
      records = await _persistence!.query(query);
    } on Object {
      await _sendError(
        request.response,
        HttpStatus.serviceUnavailable,
        'Telemetry persistence unavailable',
      );
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'records': <Map<String, Object?>>[
          for (final AtTelemetryRecord record in records) record.toJson(),
        ],
      }),
    );
    await request.response.close();
  }

  Future<void> _handleLogs(HttpRequest request) async {
    if (request.method != 'POST') {
      await _sendMethodNotAllowed(request.response, 'POST');
      return;
    }

    final String? apiKey = _bearerCredential(request.headers);
    if (apiKey == null) {
      await _sendUnauthorized(request.response);
      return;
    }

    final AtTelemetryProducerIdentity? producer;
    try {
      producer = await _authenticator.authenticate(apiKey);
    } on Object {
      await _sendError(
        request.response,
        HttpStatus.serviceUnavailable,
        'Authentication unavailable',
      );
      return;
    }
    if (producer == null) {
      await _sendUnauthorized(request.response);
      return;
    }

    if (request.headers.contentType?.mimeType != 'application/x-protobuf') {
      await _sendError(
        request.response,
        HttpStatus.unsupportedMediaType,
        'Content-Type must be application/x-protobuf',
      );
      return;
    }
    final String? contentEncoding =
        request.headers.value(HttpHeaders.contentEncodingHeader);
    if (contentEncoding != null &&
        contentEncoding.toLowerCase() != 'identity') {
      await _sendError(
        request.response,
        HttpStatus.unsupportedMediaType,
        'Content encoding is not supported',
      );
      return;
    }

    try {
      final List<int> payload = await _readPayload(request);
      final List<AtTelemetryEvent> events = _codec.decodeExportRequest(payload);
      await _ingestor.ingest(producer: producer, events: events);
      await _sendSuccess(request.response);
    } on _RequestTooLargeException {
      await _sendError(
        request.response,
        HttpStatus.requestEntityTooLarge,
        'Request body is too large',
      );
    } on FormatException {
      await _sendError(
        request.response,
        HttpStatus.badRequest,
        'Invalid OTLP logs request',
      );
    } on Object {
      await _sendError(
        request.response,
        HttpStatus.serviceUnavailable,
        'Telemetry persistence unavailable',
      );
    }
  }

  String? _bearerCredential(HttpHeaders headers) {
    final List<String>? values = headers[HttpHeaders.authorizationHeader];
    if (values == null || values.length != 1) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'^Bearer ([^\s]+)$',
      caseSensitive: false,
    ).firstMatch(values.single.trim());
    return match?.group(1);
  }

  Future<List<int>> _readPayload(HttpRequest request) async {
    if (request.contentLength > _maxRequestBytes) {
      throw const _RequestTooLargeException();
    }

    final List<int> payload = <int>[];
    await for (final List<int> chunk in request) {
      if (payload.length + chunk.length > _maxRequestBytes) {
        throw const _RequestTooLargeException();
      }
      payload.addAll(chunk);
    }
    return payload;
  }

  Future<void> _sendMethodNotAllowed(
    HttpResponse response,
    String allowedMethod,
  ) async {
    response.headers.set(HttpHeaders.allowHeader, allowedMethod);
    await _sendError(
      response,
      HttpStatus.methodNotAllowed,
      'Method not allowed',
    );
  }

  Future<void> _sendUnauthorized(HttpResponse response) async {
    response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
    await _sendError(response, HttpStatus.unauthorized, 'Unauthorized');
  }

  Future<void> _sendSuccess(HttpResponse response) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'application',
      'x-protobuf',
    );
    response.add(_codec.encodeExportResponse());
    await response.close();
  }

  Future<void> _sendError(
    HttpResponse response,
    int statusCode,
    String message,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.text;
    response.write(message);
    await response.close();
  }
}

final class _RequestTooLargeException implements Exception {
  const _RequestTooLargeException();
}
