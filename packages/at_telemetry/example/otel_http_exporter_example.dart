import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';

// Run with: dart run example/otel_http_exporter_example.dart
//
// Starts a local HTTP server that stands in for an OpenTelemetry collector,
// then exports one event to it with AtTelemetryOtelHttpExporter.
Future<void> main() async {
  final HttpServer collector = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  collector.listen(_handle);

  final Uri endpoint = Uri.parse('http://127.0.0.1:${collector.port}');
  final AtTelemetryHttpExporter exporter =
      await AtTelemetryHttpExporter.create(
    endpoint: endpoint,
    serviceName: 'my_app',
  );

  await exporter.export(AtTelemetryLogRecord(
    name: 'atsign.app.started',
    timestamp: DateTime.now().toUtc(),
    attributes: const <String, Object?>{'app.version': '1.2.3'},
  ));

  // Events are batched by OpenTelemetry, so flush to send them now
  await exporter.flush();
  await exporter.shutdown();
  await collector.close(force: true);
}

Future<void> _handle(HttpRequest request) async {
  final List<int> body = await request.fold<List<int>>(
    <int>[],
    (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
  );
  const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();
  final List<AtTelemetryLogRecord> events = codec.decodeExportRequest(body);

  print('Collector received ${request.method} ${request.uri.path}');
  for (final AtTelemetryLogRecord event in events) {
    print('Event: ${event.name} ${event.attributes}');
  }

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType('application', 'x-protobuf')
    ..add(codec.encodeExportResponse());
  await request.response.close();
}
