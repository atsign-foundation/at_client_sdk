import 'dart:async';

import 'package:at_utils/at_logger.dart';

import 'at_telemetry_log_record.dart';
import 'at_telemetry_resource.dart';
import 'at_telemetry_severity.dart';
import 'exporters/at_telemetry_log_record_exporter.dart';

typedef AtTelemetryErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

// The entry point for sending telemetry. Each method is a kind of signal.
// Delivery problems never throw. They go to the onError passed to that call,
// otherwise the onError passed to AtTelemetry, otherwise defaultOnError.
// Invalid values, such as an attribute that is not an AnyValue, throw
// ArgumentError.
final class AtTelemetry {
  static final AtSignLogger _logger = AtSignLogger('AtTelemetry');

  final AtTelemetryResource resource;
  final AtTelemetryLogRecordExporter _exporter;
  final AtTelemetryErrorHandler _onError;
  final Set<Future<void>> _pending = <Future<void>>{};
  bool _closed = false;

  AtTelemetry({
    required String serviceName,
    Map<String, Object?> resourceAttributes = const <String, Object?>{},
    required AtTelemetryLogRecordExporter exporter,
    AtTelemetryErrorHandler onError = defaultOnError,
  })  : resource = AtTelemetryResource(
          serviceName: serviceName,
          attributes: resourceAttributes,
        ),
        _exporter = exporter,
        _onError = onError;

  // Logs the failure as a warning
  static void defaultOnError(Object error, StackTrace stackTrace) {
    _logger.warning('Telemetry failed: $error');
  }

  void event(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
    Object? body,
    AtTelemetrySeverity? severity,
    DateTime? timestamp,
    AtTelemetryErrorHandler? onError,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    _emit(
      AtTelemetryLogRecord(
        eventName: name,
        body: body,
        timestamp: timestamp ?? DateTime.now(),
        severityNumber: severity,
        attributes: attributes,
      ),
      onError ?? _onError,
    );
  }

  void log(
    Object? body, {
    AtTelemetrySeverity? severity,
    String? severityText,
    Map<String, Object?> attributes = const <String, Object?>{},
    DateTime? timestamp,
    AtTelemetryErrorHandler? onError,
  }) {
    _emit(
      AtTelemetryLogRecord(
        body: body,
        timestamp: timestamp ?? DateTime.now(),
        severityNumber: severity,
        severityText: severityText,
        attributes: attributes,
      ),
      onError ?? _onError,
    );
  }

  // Returns once every record so far is delivered or reported to its onError
  Future<void> flush() async {
    try {
      await _exporter.flush();
    } on Object catch (error, stackTrace) {
      _report(_onError, error, stackTrace);
    }
    await Future.wait(_pending.toList());
  }

  Future<void> shutdown() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _exporter.shutdown();
    } on Object catch (error, stackTrace) {
      _report(_onError, error, stackTrace);
    }
    await Future.wait(_pending.toList());
  }

  void _emit(AtTelemetryLogRecord logRecord, AtTelemetryErrorHandler onError) {
    if (_closed) {
      _report(
        onError,
        StateError('AtTelemetry is shut down'),
        StackTrace.current,
      );
      return;
    }
    final Future<void> delivery;
    try {
      delivery = _exporter.export(logRecord, resource);
    } on Object catch (error, stackTrace) {
      _report(onError, error, stackTrace);
      return;
    }
    // reported never fails, so flush can wait on it safely
    final Future<void> reported = delivery.then<void>(
      (void _) {},
      onError: (Object error, StackTrace stackTrace) =>
          _report(onError, error, stackTrace),
    );
    _pending.add(reported);
    unawaited(reported.whenComplete(() => _pending.remove(reported)));
  }

  void _report(
    AtTelemetryErrorHandler onError,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      onError(error, stackTrace);
    } on Object {
      // A failing error handler must not break the app
    }
  }
}
