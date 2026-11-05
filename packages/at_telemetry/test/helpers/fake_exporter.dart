import 'package:at_telemetry/at_telemetry.dart';

final class FakeExporter implements AtTelemetryLogRecordExporter {
  final List<(AtTelemetryLogRecord, AtTelemetryResource)> exports =
      <(AtTelemetryLogRecord, AtTelemetryResource)>[];
  Future<bool> Function(AtTelemetryLogRecord logRecord)? onExport;
  Future<void> Function()? onFlush;
  Future<void> Function()? onShutdown;
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  Future<bool> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) {
    exports.add((logRecord, resource));
    final Future<bool> Function(AtTelemetryLogRecord logRecord)? handler =
        onExport;
    return handler == null ? Future<bool>.value(true) : handler(logRecord);
  }

  @override
  Future<void> flush() async {
    flushCount++;
    await onFlush?.call();
  }

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    await onShutdown?.call();
  }
}
