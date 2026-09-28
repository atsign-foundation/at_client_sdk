import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';

// Run with: dart run example/otel_http_exporter_example.dart
//
// Starts a local HTTP server that stands in for an OpenTelemetry collector,
// then exports one event to it with AtTelemetryExporterOtelHttp.
Future<void> main() async {
  final HttpServer collector = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  collector.listen(_handle);

  final Uri endpoint = Uri.parse('http://127.0.0.1:${collector.port}');
  final AtTelemetryExporterOtelHttp exporter =
      await AtTelemetryExporterOtelHttp.create(
    endpoint: endpoint,
    serviceName: 'my_app',
    apiKey: 'example-api-key',
  );

  await exporter.export(AtTelemetryEvent(
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
  const AtTelemetryOtelLogsCodec codec = AtTelemetryOtelLogsCodec();
  final List<AtTelemetryEvent> events = codec.decodeExportRequest(body);

  print('Collector received ${request.method} ${request.uri.path}');
  print('Authorization: ${request.headers.value('authorization')}');
  for (final AtTelemetryEvent event in events) {
    print('Event: ${event.name} ${event.attributes}');
  }

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType('application', 'x-protobuf')
    ..add(codec.encodeExportResponse());
  await request.response.close();
}
