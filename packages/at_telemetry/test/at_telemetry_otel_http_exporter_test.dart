import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:test/test.dart';

void main() {
  test('exports an event as an OTLP HTTP Protobuf log record', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Uri endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}',
    );
    final AtTelemetryExporterOtelHttp exporter =
        await AtTelemetryExporterOtelHttp.create(
      endpoint: endpoint,
      serviceName: 'atserver',
    );

    addTearDown(() async {
      await exporter.shutdown();
      await server.close(force: true);
    });

    final Future<HttpRequest> requestFuture = server.first;
    final DateTime timestamp = DateTime.utc(2026, 2, 23, 12);
    final AtTelemetryEvent heartbeat = AtTelemetryEvent(
      name: 'atsign.server.heartbeat',
      timestamp: timestamp,
      attributes: <String, Object?>{
        'atsign.server.id': 'secondary-123',
        'atsign.server.healthy': true,
        'atsign.server.optional': null,
      },
    );

    await exporter.export(heartbeat);
    final Future<void> flushFuture = exporter.flush();
    final HttpRequest request = await requestFuture.timeout(
      const Duration(seconds: 5),
    );
    final List<int> payload = await request.fold<List<int>>(
      <int>[],
      (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
    );

    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    await flushFuture;

    expect(request.method, 'POST');
    expect(request.uri.path, '/v1/logs');
    expect(
      request.headers.contentType?.mimeType,
      'application/x-protobuf',
    );

    final collector.ExportLogsServiceRequest exportRequest =
        collector.ExportLogsServiceRequest.fromBuffer(payload);
    expect(exportRequest.resourceLogs, hasLength(1));

    final logs.ResourceLogs resourceLogs = exportRequest.resourceLogs.single;
    expect(resourceLogs.scopeLogs, hasLength(1));
    final logs.ScopeLogs scopeLogs = resourceLogs.scopeLogs.single;
    expect(scopeLogs.scope.name, 'at_telemetry');
    expect(scopeLogs.logRecords, hasLength(1));

    final logs.LogRecord logRecord = scopeLogs.logRecords.single;
    expect(logRecord.body.stringValue, heartbeat.name);
    expect(
      logRecord.timeUnixNano.toInt(),
      timestamp.microsecondsSinceEpoch * 1000,
    );

    final Map<String, common.AnyValue> attributes = <String, common.AnyValue>{
      for (final common.KeyValue attribute in logRecord.attributes)
        attribute.key: attribute.value,
    };
    expect(attributes['atsign.server.id']?.stringValue, 'secondary-123');
    expect(attributes['atsign.server.healthy']?.boolValue, isTrue);
    expect(attributes, isNot(contains('atsign.server.optional')));

    final common.KeyValue serviceName =
        resourceLogs.resource.attributes.singleWhere(
      (common.KeyValue attribute) => attribute.key == 'service.name',
    );
    expect(serviceName.value.stringValue, 'atserver');
  });
}
