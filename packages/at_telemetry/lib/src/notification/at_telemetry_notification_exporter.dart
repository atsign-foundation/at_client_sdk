import '../codec/at_telemetry_notification_codec.dart';
import '../exporters/at_telemetry_log_record_exporter.dart';
import '../exporters/at_telemetry_metric_exporter.dart';
import '../exporters/at_telemetry_span_exporter.dart';
import '../models/logs/at_telemetry_log_record.dart';
import '../models/metrics/at_telemetry_metric.dart';
import '../models/traces/at_telemetry_span.dart';

typedef AtTelemetryNotify = Future<void> Function(
  String idAndNamespace,
  String payload,
);

final class AtTelemetryNotificationExporter
    implements
        AtTelemetryLogRecordExporter,
        AtTelemetryMetricExporter,
        AtTelemetrySpanExporter {
  static const int defaultMaxPendingExports = 1000;
  static const int defaultMaxPayloadCharacters = 4 * ((1024 * 1024 + 2) ~/ 3);

  final AtTelemetryNotify _notify;
  final String _serviceName;
  final AtTelemetryNotificationCodec _codec;
  final int _maxPendingExports;
  final int _maxPayloadCharacters;
  Future<void> _pending = Future<void>.value();
  int _pendingCount = 0;
  bool _closed = false;
  (Object, StackTrace)? _failure;

  AtTelemetryNotificationExporter({
    required AtTelemetryNotify notify,
    required String serviceName,
    AtTelemetryNotificationCodec codec = const AtTelemetryNotificationCodec(),
    int maxPendingExports = defaultMaxPendingExports,
    int maxPayloadCharacters = defaultMaxPayloadCharacters,
  })  : _notify = notify,
        _serviceName = serviceName,
        _codec = codec,
        _maxPendingExports = maxPendingExports,
        _maxPayloadCharacters = maxPayloadCharacters {
    if (serviceName.trim().isEmpty) {
      throw ArgumentError.value(
          serviceName, 'serviceName', 'must not be empty');
    }
    if (maxPendingExports < 1) {
      throw RangeError.value(maxPendingExports, 'maxPendingExports');
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
  Future<void> exportMetrics(Iterable<AtTelemetryMetric> measurements) {
    return _enqueue(
      AtTelemetryNotificationCodec.metricsIdAndNamespace,
      () => _codec.encodeMetrics(measurements, serviceName: _serviceName),
    );
  }

  @override
  Future<void> exportSpans(Iterable<AtTelemetrySpan> spans) {
    return _enqueue(
      AtTelemetryNotificationCodec.tracesIdAndNamespace,
      () => _codec.encodeSpans(spans, serviceName: _serviceName),
    );
  }

  @override
  Future<void> flush() async {
    await _pending;
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
    if (_pendingCount >= _maxPendingExports) {
      return Future<void>.error(StateError('Telemetry backlog is full'));
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

    _pendingCount++;
    final Future<void> sent = _pending.then(
      (_) => _notify(idAndNamespace, payload),
    );
    _pending = sent.then<void>(
      (_) => _pendingCount--,
      onError: (Object error, StackTrace stackTrace) {
        _pendingCount--;
        _failure ??= (error, stackTrace);
      },
    );
    return sent;
  }
}
