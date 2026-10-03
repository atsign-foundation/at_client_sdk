import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  test('exports, flushes, and shuts down', () async {
    final _TestExporter exporter = _TestExporter();
    final AtTelemetryLogRecord event = AtTelemetryLogRecord(
      name: 'at_server.request',
      timestamp: DateTime.utc(2026, 2, 23, 12),
    );

    await exporter.export(event);
    await exporter.flush();
    await exporter.shutdown();

    expect(exporter.events, <AtTelemetryLogRecord>[event]);
    expect(exporter.isFlushed, isTrue);
    expect(exporter.isShutdown, isTrue);
  });
}

final class _TestExporter implements AtTelemetryLogRecordExporter {
  final List<AtTelemetryLogRecord> events = <AtTelemetryLogRecord>[];
  bool isFlushed = false;
  bool isShutdown = false;

  @override
  Future<void> export(AtTelemetryLogRecord event) async {
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
