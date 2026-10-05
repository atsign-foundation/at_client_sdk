import 'dart:async';
import 'dart:collection';

import '../codec/at_telemetry_notification_codec.dart';
import '../exporters/at_telemetry_log_record_exporter.dart';
import '../models/logs/at_telemetry_log_record.dart';

typedef AtTelemetryNotify = Future<void> Function(
  String idAndNamespace,
  String payload,
);

final class AtTelemetryNotificationExporter
    implements AtTelemetryLogRecordExporter {
  static const int defaultMaxQueuedExports = 1000;
  static const int defaultMaxPayloadCharacters = 4 * ((1024 * 1024 + 2) ~/ 3);

  final AtTelemetryNotify _notify;
  final String _serviceName;
  final AtTelemetryNotificationCodec _codec;
  final int _maxQueuedExports;
  final int _maxPayloadCharacters;
  final ListQueue<(String, String, Completer<void>)> _queue =
      ListQueue<(String, String, Completer<void>)>();
  Future<void> _last = Future<void>.value();
  bool _sending = false;
  bool _closed = false;
  (Object, StackTrace)? _failure;

  AtTelemetryNotificationExporter({
    required AtTelemetryNotify notify,
    required String serviceName,
    AtTelemetryNotificationCodec codec = const AtTelemetryNotificationCodec(),
    int maxQueuedExports = defaultMaxQueuedExports,
    int maxPayloadCharacters = defaultMaxPayloadCharacters,
  })  : _notify = notify,
        _serviceName = serviceName,
        _codec = codec,
        _maxQueuedExports = maxQueuedExports,
        _maxPayloadCharacters = maxPayloadCharacters {
    if (serviceName.trim().isEmpty) {
      throw ArgumentError.value(
          serviceName, 'serviceName', 'must not be empty');
    }
    if (maxQueuedExports < 1) {
      throw RangeError.value(maxQueuedExports, 'maxQueuedExports');
    }
    if (maxPayloadCharacters < 1) {
      throw RangeError.value(maxPayloadCharacters, 'maxPayloadCharacters');
    }
  }

  @override
  Future<void> export(AtTelemetryLogRecord logRecord) {
    return _enqueue(
      AtTelemetryNotificationCodec.idAndNamespace,
      () => _codec
          .encode(<AtTelemetryLogRecord>[logRecord], serviceName: _serviceName),
    );
  }

  @override
  Future<void> flush() async {
    await _last;
    final (Object, StackTrace)? failure = _failure;
    _failure = null;
    if (failure != null) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  @override
  Future<void> shutdown() {
    _closed = true;
    return flush();
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
    _last = done.future.catchError((Object error, StackTrace stackTrace) {
      _failure ??= (error, stackTrace);
    });
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
