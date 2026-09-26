import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  test('exports, flushes, and shuts down', () async {
    final _TestExporter exporter = _TestExporter();
    final AtTelemetryEvent event = AtTelemetryEvent(
      name: 'at_server.request',
      timestamp: DateTime.utc(2026, 2, 23, 12),
    );

    await exporter.export(event);
    await exporter.flush();
    await exporter.shutdown();

    expect(exporter.events, <AtTelemetryEvent>[event]);
    expect(exporter.isFlushed, isTrue);
    expect(exporter.isShutdown, isTrue);
  });
}

final class _TestExporter implements AtTelemetryExporter {
  final List<AtTelemetryEvent> events = <AtTelemetryEvent>[];
  bool isFlushed = false;
  bool isShutdown = false;

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
