import 'package:at_telemetry/at_telemetry.dart';

final class FakeExporter implements AtTelemetryLogRecordExporter {
  final List<(AtTelemetryLogRecord, AtTelemetryResource)> exports =
      <(AtTelemetryLogRecord, AtTelemetryResource)>[];
  Future<void> Function(AtTelemetryLogRecord logRecord)? onExport;
  Object? flushError;
  Object? shutdownError;
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  Future<void> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) {
    exports.add((logRecord, resource));
    final Future<void> Function(AtTelemetryLogRecord logRecord)? handler =
        onExport;
    return handler == null ? Future<void>.value() : handler(logRecord);
  }

  @override
  Future<void> flush() async {
    flushCount++;
    final Object? error = flushError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    final Object? error = shutdownError;
    if (error != null) {
      throw error;
    }
  }
}
