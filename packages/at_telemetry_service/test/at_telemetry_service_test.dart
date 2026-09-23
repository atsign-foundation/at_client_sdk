import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';
import 'package:at_telemetry_service/at_telemetry_service.dart';
import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as resource;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryService', () {
    const String apiKey = 'server-a-secret';
    late AtTelemetrySqlitePersistence persistence;
    late AtTelemetryService service;
    late HttpClient client;

    setUp(() async {
      persistence = AtTelemetrySqlitePersistence.inMemory();
      service = await AtTelemetryService.bind(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        authenticator: AtTelemetryApiKeyAuthenticator(
          <AtTelemetryApiKeyCredential>[
            AtTelemetryApiKeyCredential(
              apiKey: apiKey,
              producerId: 'server-a',
              tenantId: 'tenant-a',
            ),
          ],
        ),
        ingestor: AtTelemetryIngestor(persistence: persistence),
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await service.close(force: true);
      await persistence.close();
    });

    test('accepts a heartbeat from the OTLP exporter', () async {
      final AtTelemetryExporterOtelHttp exporter =
          await AtTelemetryExporterOtelHttp.create(
        endpoint: Uri.parse(
          'http://${service.address.address}:${service.port}',
        ),
        serviceName: 'atserver',
        apiKey: apiKey,
      );
      try {
        await exporter.export(
          AtTelemetryEvent(
            name: 'atsign.server.heartbeat',
            timestamp: DateTime.utc(2026, 2, 24, 11),
            attributes: const <String, Object?>{
              'atsign.server.id': 'secondary-123',
            },
          ),
        );
        await exporter.flush();
      } finally {
        await exporter.shutdown();
      }

      final List<AtTelemetryRecord> records = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-a'),
      );
      expect(records, hasLength(1));
      expect(records.single.event.name, 'atsign.server.heartbeat');
      expect(
        records.single.event.attributes['atsign.server.id'],
        'secondary-123',
      );
    });

    test('authenticates and persists an OTLP heartbeat', () async {
      final DateTime timestamp = DateTime.utc(2026, 2, 24, 12);
      final List<int> requestBody = _heartbeatRequest(
        timestamp: timestamp,
        claimedTenantId: 'tenant-b',
      );

      final _HttpResult response = await _postLogs(
        client: client,
        service: service,
        requestBody: requestBody,
        apiKey: apiKey,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentType, 'application/x-protobuf');
      expect(
        () => collector.ExportLogsServiceResponse.fromBuffer(response.body),
        returnsNormally,
      );

      final List<AtTelemetryRecord> tenantARecords = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-a'),
      );
      final List<AtTelemetryRecord> tenantBRecords = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-b'),
      );
      expect(tenantARecords, hasLength(1));
      expect(tenantBRecords, isEmpty);
      expect(
        tenantARecords.single.event.name,
        'atsign.server.heartbeat',
      );
      expect(tenantARecords.single.event.timestamp, timestamp);
      expect(
        tenantARecords.single.event.attributes['atsign.server.id'],
        'secondary-123',
      );
      expect(
        tenantARecords.single.event.attributes['tenant.id'],
        'tenant-b',
      );
    });

    test('rejects missing and invalid API keys', () async {
      for (final String? rejectedApiKey in <String?>[null, 'wrong-secret']) {
        final _HttpResult response = await _postLogs(
          client: client,
          service: service,
          requestBody: _heartbeatRequest(
            timestamp: DateTime.utc(2026, 2, 24, 12),
            claimedTenantId: 'tenant-a',
          ),
          apiKey: rejectedApiKey,
        );

        expect(response.statusCode, HttpStatus.unauthorized);
        expect(response.wwwAuthenticate, 'Bearer');
      }
      expect(
        await persistence.query(AtTelemetryQuery(tenantId: 'tenant-a')),
        isEmpty,
      );
    });

    test('rejects malformed Protobuf without persisting it', () async {
      final _HttpResult response = await _postLogs(
        client: client,
        service: service,
        requestBody: <int>[255],
        apiKey: apiKey,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        await persistence.query(AtTelemetryQuery(tenantId: 'tenant-a')),
        isEmpty,
      );
    });
  });

  test('rejects duplicate API keys', () {
    expect(
      () => AtTelemetryApiKeyAuthenticator(
        <AtTelemetryApiKeyCredential>[
          AtTelemetryApiKeyCredential(
            apiKey: 'duplicate',
            producerId: 'server-a',
            tenantId: 'tenant-a',
          ),
          AtTelemetryApiKeyCredential(
            apiKey: 'duplicate',
            producerId: 'server-b',
            tenantId: 'tenant-b',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}

List<int> _heartbeatRequest({
  required DateTime timestamp,
  required String claimedTenantId,
}) {
  return collector.ExportLogsServiceRequest(
    resourceLogs: <logs.ResourceLogs>[
      logs.ResourceLogs(
        resource: resource.Resource(
          attributes: <common.KeyValue>[
            common.KeyValue(
              key: 'service.name',
              value: common.AnyValue(stringValue: 'atserver'),
            ),
            common.KeyValue(
              key: 'tenant.id',
              value: common.AnyValue(stringValue: claimedTenantId),
            ),
          ],
        ),
        scopeLogs: <logs.ScopeLogs>[
          logs.ScopeLogs(
            logRecords: <logs.LogRecord>[
              logs.LogRecord(
                timeUnixNano: Int64(timestamp.microsecondsSinceEpoch * 1000),
                body: common.AnyValue(
                  stringValue: 'atsign.server.heartbeat',
                ),
                attributes: <common.KeyValue>[
                  common.KeyValue(
                    key: 'atsign.server.id',
                    value: common.AnyValue(stringValue: 'secondary-123'),
                  ),
                  common.KeyValue(
                    key: 'atsign.server.healthy',
                    value: common.AnyValue(boolValue: true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ).writeToBuffer();
}

Future<_HttpResult> _postLogs({
  required HttpClient client,
  required AtTelemetryService service,
  required List<int> requestBody,
  required String? apiKey,
}) async {
  final HttpClientRequest request = await client.postUrl(
    Uri.parse('http://${service.address.address}:${service.port}/v1/logs'),
  );
  request.headers.contentType = ContentType('application', 'x-protobuf');
  if (apiKey != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
  }
  request.add(requestBody);

  final HttpClientResponse response = await request.close();
  final List<int> responseBody = await response.fold<List<int>>(
    <int>[],
    (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
  );
  return _HttpResult(
    statusCode: response.statusCode,
    contentType: response.headers.contentType?.mimeType,
    wwwAuthenticate: response.headers.value(HttpHeaders.wwwAuthenticateHeader),
    body: responseBody,
  );
}

final class _HttpResult {
  final int statusCode;
  final String? contentType;
  final String? wwwAuthenticate;
  final List<int> body;

  const _HttpResult({
    required this.statusCode,
    required this.contentType,
    required this.wwwAuthenticate,
    required this.body,
  });
}
