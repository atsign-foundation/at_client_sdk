import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../at_telemetry_log_record.dart';
import '../at_telemetry_resource.dart';
import 'at_telemetry_log_record_exporter.dart';

typedef AtTelemetryNotify = Future<void> Function(
  String idAndNamespace,
  String payload,
);

final class AtTelemetryNotificationExporter
    implements AtTelemetryLogRecordExporter {
  static const String idAndNamespace = 'logs.at_telemetry';
  static const int defaultMaxQueuedExports = 1000;
  static const int defaultMaxPayloadCharacters = 4 * ((1024 * 1024 + 2) ~/ 3);

  final AtTelemetryNotify _notify;
  final int _maxQueuedExports;
  final int _maxPayloadCharacters;
  final ListQueue<(String, String, Completer<void>)> _queue =
      ListQueue<(String, String, Completer<void>)>();
  Future<void> _last = Future<void>.value();
  bool _sending = false;
  bool _closed = false;

  AtTelemetryNotificationExporter({
    required AtTelemetryNotify notify,
    int maxQueuedExports = defaultMaxQueuedExports,
    int maxPayloadCharacters = defaultMaxPayloadCharacters,
  })  : _notify = notify,
        _maxQueuedExports = maxQueuedExports,
        _maxPayloadCharacters = maxPayloadCharacters {
    if (maxQueuedExports < 1) {
      throw RangeError.value(maxQueuedExports, 'maxQueuedExports');
    }
    if (maxPayloadCharacters < 1) {
      throw RangeError.value(maxPayloadCharacters, 'maxPayloadCharacters');
    }
  }

  @override
  Future<void> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) {
    return _enqueue(idAndNamespace, () => _encode(logRecord, resource));
  }

  @override
  Future<void> flush() => _last;

  @override
  Future<void> shutdown() {
    _closed = true;
    return flush();
  }

  // The JSON payload has no separate resource, so the resource attributes are
  // merged into the record's attributes. The resource wins on a clash.
  String _encode(AtTelemetryLogRecord logRecord, AtTelemetryResource resource) {
    return jsonEncode(AtTelemetryLogRecord(
      eventName: logRecord.eventName,
      body: logRecord.body,
      timestamp: logRecord.timestamp ?? DateTime.now(),
      severityNumber: logRecord.severityNumber,
      severityText: logRecord.severityText,
      attributes: <String, Object?>{
        ...logRecord.attributes,
        ...resource.attributes,
      },
    ).toJson());
  }

  Future<void> _enqueue(String idAndNamespace, String Function() encode) {
    if (_closed) {
      return Future<void>.error(StateError('Exporter is closed'));
    }

    final String payload;
    try {
      payload = encode();
      if (payload.length > _maxPayloadCharacters) {
        throw ArgumentError('Telemetry notification payload is too large');
      }
    } on Object catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }

    final Completer<void> done = Completer<void>();
    // flush only waits; the failure is reported through the returned Future
    _last = done.future.then<void>((void _) {}, onError: (Object _) {});
    _queue.add((idAndNamespace, payload, done));
    if (_queue.length > _maxQueuedExports) {
      final (String _, String _, Completer<void> dropped) =
          _queue.removeFirst();
      dropped.completeError(
        StateError('Telemetry backlog is full, dropped the oldest export'),
      );
    }
    if (!_sending) {
      unawaited(_drain());
    }
    return done.future;
  }

  Future<void> _drain() async {
    _sending = true;
    while (_queue.isNotEmpty) {
      final (String idAndNamespace, String payload, Completer<void> done) =
          _queue.removeFirst();
      try {
        await _notify(idAndNamespace, payload);
        done.complete();
      } on Object catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }
    _sending = false;
  }
}
