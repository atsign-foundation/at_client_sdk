import 'dart:convert';
import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';
import 'package:at_telemetry_service/at_telemetry_service.dart';
import 'package:test/test.dart';

void main() {
  const String producerApiKey = 'producer-secret';
  const String readerApiKey = 'reader-a-secret';

  group('GET /v1/events', () {
    late AtTelemetrySqlitePersistence persistence;
    late AtTelemetryService service;
    late HttpClient client;

    setUp(() async {
      persistence = AtTelemetrySqlitePersistence.inMemory();
      service = await AtTelemetryService.bind(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        authenticator: _producerAuthenticator(producerApiKey),
        ingestor: AtTelemetryIngestor(persistence: persistence),
        readerAuthenticator: AtTelemetryReaderApiKeyAuthenticator(
          <AtTelemetryReaderApiKeyCredential>[
            AtTelemetryReaderApiKeyCredential(
              apiKey: readerApiKey,
              readerId: 'control-center',
              tenantId: 'tenant-a',
            ),
          ],
        ),
        persistence: persistence,
      );
      client = HttpClient();

      for (final (String tenantId, String name, int hour)
          in <(String, String, int)>[
        ('tenant-a', 'atsign.server.heartbeat', 10),
        ('tenant-a', 'atsign.server.heartbeat', 11),
        ('tenant-a', 'atsign.server.error', 12),
        ('tenant-b', 'atsign.server.heartbeat', 13),
      ]) {
        await persistence.store(
          tenantId: tenantId,
          event: AtTelemetryEvent(
            name: name,
            timestamp: DateTime.utc(2026, 2, 24, hour),
          ),
        );
      }
    });

    tearDown(() async {
      client.close(force: true);
      await service.close(force: true);
      await persistence.close();
    });

    test('returns only the reader tenant records, typed', () async {
      final _JsonResult result = await _getEvents(
        client: client,
        service: service,
        apiKey: readerApiKey,
        query: AtTelemetryQuery(
          tenantId: 'ignored-by-server',
          name: 'atsign.server.heartbeat',
          order: AtTelemetryOrder.oldestFirst,
        ),
      );

      expect(result.statusCode, HttpStatus.ok);
      expect(result.contentType, 'application/json');
      final List<AtTelemetryRecord> records = result.records();
      expect(records, hasLength(2));
      expect(
        records.map((AtTelemetryRecord record) => record.tenantId),
        everyElement('tenant-a'),
      );
      expect(
        records.map((AtTelemetryRecord record) => record.event.timestamp),
        <DateTime>[
          DateTime.utc(2026, 2, 24, 10),
          DateTime.utc(2026, 2, 24, 11)
        ],
      );
    });

    test('rejects missing, invalid, and producer API keys', () async {
      for (final String? apiKey in <String?>[
        null,
        'wrong-secret',
        producerApiKey,
      ]) {
        final _JsonResult result = await _getEvents(
          client: client,
          service: service,
          apiKey: apiKey,
        );
        expect(result.statusCode, HttpStatus.unauthorized, reason: apiKey);
      }
    });

    test('rejects a tenantId query parameter', () async {
      final _JsonResult result = await _getEvents(
        client: client,
        service: service,
        apiKey: readerApiKey,
        rawParameters: <String, String>{'tenantId': 'tenant-b'},
      );
      expect(result.statusCode, HttpStatus.badRequest);
    });

    test('rejects an out-of-range limit', () async {
      final _JsonResult result = await _getEvents(
        client: client,
        service: service,
        apiKey: readerApiKey,
        rawParameters: <String, String>{'limit': '5000'},
      );
      expect(result.statusCode, HttpStatus.badRequest);
    });

    test('rejects other methods', () async {
      final HttpClientRequest request = await client.postUrl(
        _eventsUri(service, const <String, String>{}),
      );
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.headers.value(HttpHeaders.allowHeader), 'GET');
    });
  });

  test('hides /v1/events when no reader keys are configured', () async {
    final AtTelemetrySqlitePersistence persistence =
        AtTelemetrySqlitePersistence.inMemory();
    final AtTelemetryService service = await AtTelemetryService.bind(
      address: InternetAddress.loopbackIPv4,
      port: 0,
      authenticator: _producerAuthenticator(producerApiKey),
      ingestor: AtTelemetryIngestor(persistence: persistence),
    );
    final HttpClient client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await service.close(force: true);
      await persistence.close();
    });

    final _JsonResult result = await _getEvents(
      client: client,
      service: service,
      apiKey: readerApiKey,
    );
    expect(result.statusCode, HttpStatus.notFound);
  });

  test('requires reader keys and persistence together', () {
    expect(
      () => AtTelemetryService.bind(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        authenticator: _producerAuthenticator(producerApiKey),
        ingestor: AtTelemetryIngestor(
          persistence: AtTelemetrySqlitePersistence.inMemory(),
        ),
        readerAuthenticator: AtTelemetryReaderApiKeyAuthenticator(
          <AtTelemetryReaderApiKeyCredential>[
            AtTelemetryReaderApiKeyCredential(
              apiKey: readerApiKey,
              readerId: 'control-center',
              tenantId: 'tenant-a',
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });
}

AtTelemetryApiKeyAuthenticator _producerAuthenticator(String apiKey) {
  return AtTelemetryApiKeyAuthenticator(
    <AtTelemetryApiKeyCredential>[
      AtTelemetryApiKeyCredential(
        apiKey: apiKey,
        producerId: 'server-a',
        tenantId: 'tenant-a',
      ),
    ],
  );
}

Uri _eventsUri(AtTelemetryService service, Map<String, String> parameters) {
  return Uri(
    scheme: 'http',
    host: service.address.address,
    port: service.port,
    path: AtTelemetryService.eventsPath,
    queryParameters: parameters.isEmpty ? null : parameters,
  );
}

Future<_JsonResult> _getEvents({
  required HttpClient client,
  required AtTelemetryService service,
  required String? apiKey,
  AtTelemetryQuery? query,
  Map<String, String>? rawParameters,
}) async {
  final HttpClientRequest request = await client.getUrl(
    _eventsUri(
      service,
      rawParameters ?? query?.toQueryParameters() ?? const <String, String>{},
    ),
  );
  if (apiKey != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
  }
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  return _JsonResult(
    statusCode: response.statusCode,
    contentType: response.headers.contentType?.mimeType,
    body: body,
  );
}

final class _JsonResult {
  final int statusCode;
  final String? contentType;
  final String body;

  const _JsonResult({
    required this.statusCode,
    required this.contentType,
    required this.body,
  });

  List<AtTelemetryRecord> records() {
    final Map<String, Object?> json = jsonDecode(body) as Map<String, Object?>;
    return <AtTelemetryRecord>[
      for (final Object? record in json['records']! as List<Object?>)
        AtTelemetryRecord.fromJson(record! as Map<String, Object?>),
    ];
  }
}
