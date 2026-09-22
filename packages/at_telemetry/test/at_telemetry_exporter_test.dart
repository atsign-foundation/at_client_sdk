import 'package:test/test.dart';
import 'package:at_telemetry/at_telemetry.dart';

void main() {
  test('exports a telemetry event', () async {
    final _RecordingExporter exporter = _RecordingExporter();
    final AtTelemetryEvent event = AtTelemetryEvent(
      name: 'at_server.request',
      timestamp: DateTime.utc(2026, 2, 23, 12),
    );
    await exporter.export(event);
    final List<AtTelemetryEvent> expected = <AtTelemetryEvent>[event];
    expect(exporter.events, expected);
  });
}

final class _RecordingExporter implements AtTelemetryExporter {
  final List<AtTelemetryEvent> events = [];

  @override
  Future<void> export(AtTelemetryEvent event) async {
    events.add(event);
  }
}
