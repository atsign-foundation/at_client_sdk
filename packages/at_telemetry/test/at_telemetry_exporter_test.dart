import 'dart:io';

import 'package:test/test.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';

void main() {
  test('exports a telemetry event', () async {
    final _RecordingExporter exporter = _RecordingExporter();
    final AtTelemetryEvent event = AtTelemetryEvent(
      name: 'at_server.request',
      timestamp: DateTime.utc(2026, 2, 23, 12),
    );
    await exporter.export(event);
    await exporter.shutdown();
    await exporter.flush();
    final List<AtTelemetryEvent> expected = <AtTelemetryEvent>[event];
    expect(exporter.events, expected);
    expect(exporter.isShutdown, isTrue);
    expect(exporter.isFlushed, isTrue);
  });

  test('export an atServer event and receive it', () async {
    // 1. Start an HTTP server that mimics the at_telemetry_service
    final HttpServer server =
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final String serverUriString = 'http://${server.address.address}:${server.port}';

    // 2. Instantiate telemetry exporter
    final AtTelemetryExporterOtelHttp exporter = await AtTelemetryExporterOtelHttp.create(
      endpoint: Uri.parse(serverUriString),
      serviceName: 'atserver',
    );

    // 3. Store future of the first request to hit the HTTP server
    final Future<HttpRequest> requestFuture = server.first;

    // 4. Send the AtTelemetryEvent via HTTP (exporter.export)
    // 4a. Create the event
    final AtTelemetryEvent heartbeat = AtTelemetryEvent(
      name: 'atsign.server.heartbeat',
      timestamp: DateTime.now().toUtc(),
      attributes: <String, Object?>{
        'atsign.server.id': 'secondary-123',
      },
    );

    // 4b. Export the event
    await exporter.export(heartbeat); // emit the event
    final Future<void> flushFuture = exporter.flush(); // immediately export

    // 5. Expect the request to come in
    final HttpRequest request = await requestFuture.timeout(
      const Duration(seconds: 5),
    );

    // 5a. decode payload
    final List<int> payload = await request.fold<List<int>>(
      <int>[],
      (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
    );

    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    await flushFuture;

    expect(request.uri.path, '/v1/logs');
    expect(
      request.headers.contentType?.mimeType,
      'application/x-protobuf',
    );
    expect(payload, isNotEmpty);
    expect(flushFuture, completes);
  });
}

final class _RecordingExporter implements AtTelemetryExporter {
  final List<AtTelemetryEvent> events = [];
  bool isShutdown = false;
  bool isFlushed = false;

  @override
  Future<void> export(AtTelemetryEvent event) async {
    events.add(event);
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  Future<void> shutdown() async {
    isShutdown = true;
  }

}
