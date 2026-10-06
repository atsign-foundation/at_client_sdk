import 'dart:async';
import 'dart:collection';

import 'package:at_utils/at_logger.dart';

import '../at_telemetry_attributes.dart';
import '../at_telemetry_log_record.dart';
import '../at_telemetry_resource.dart';
import '../codec/at_telemetry_logs_codec.dart';
import 'at_telemetry_log_record_exporter.dart';
import 'at_telemetry_notification_batch.dart';

// Sends one notification. The app supplies it, usually wrapping its
// AtClient's notification service, so at_telemetry needs no at_client.
typedef AtTelemetryNotify = Future<void> Function(
  String idAndNamespace,
  String value,
);

// Reads an id from the app's AtClient, such as its enrollment id
typedef AtTelemetryIdSource = String? Function();

// Batches records into OTLP/JSON notifications for the tenant's collector
// atSign. A batch the app's atServer will not take stays in memory and goes
// again with the next flush, up to maxUnsentBatches, beyond which the oldest
// is dropped with a warning. Once the app's atServer accepts a notification,
// that atServer retries delivery to the collector atSign itself.
final class AtTelemetryNotificationExporter
    implements AtTelemetryLogRecordExporter {
  static const String key = 'otlp-json.logs';
  static const String namespace = 'at_telemetry';
  static const String idAndNamespace = '$key.$namespace';
  static const int defaultMaxBatchRecords = 50;
  static const Duration defaultFlushInterval = Duration(seconds: 2);
  static const int defaultMaxUnsentBatches = 100;
  static const Duration defaultNotifyTimeout = Duration(seconds: 30);
  static const Duration defaultShutdownTimeout = Duration(seconds: 10);
  static const int defaultMaxPayloadCharacters = 4 * ((1024 * 1024 + 2) ~/ 3);

  final AtSignLogger _logger = AtSignLogger('AtTelemetryNotificationExporter');
  final AtTelemetryNotify _notify;
  final AtTelemetryIdSource? _enrollmentId;
  final AtTelemetryIdSource? _clientId;
  final int _maxBatchRecords;
  final Duration _flushInterval;
  final int _maxUnsentBatches;
  final Duration _notifyTimeout;
  final Duration _shutdownTimeout;
  final int _maxPayloadCharacters;
  final List<AtTelemetryLogRecord> _records = <AtTelemetryLogRecord>[];
  final List<Completer<bool>> _deliveries = <Completer<bool>>[];
  final ListQueue<AtTelemetryNotificationBatch> _unsent =
      ListQueue<AtTelemetryNotificationBatch>();
  AtTelemetryResource? _resource;
  Timer? _timer;
  Future<void>? _sending;
  Future<void>? _shutdown;
  bool _closed = false;

  AtTelemetryNotificationExporter({
    required AtTelemetryNotify notify,
    AtTelemetryIdSource? enrollmentId,
    AtTelemetryIdSource? clientId,
    int maxBatchRecords = defaultMaxBatchRecords,
    Duration flushInterval = defaultFlushInterval,
    int maxUnsentBatches = defaultMaxUnsentBatches,
    Duration notifyTimeout = defaultNotifyTimeout,
    Duration shutdownTimeout = defaultShutdownTimeout,
    int maxPayloadCharacters = defaultMaxPayloadCharacters,
  })  : _notify = notify,
        _enrollmentId = enrollmentId,
        _clientId = clientId,
        _maxBatchRecords = maxBatchRecords,
        _flushInterval = flushInterval,
        _maxUnsentBatches = maxUnsentBatches,
        _notifyTimeout = notifyTimeout,
        _shutdownTimeout = shutdownTimeout,
        _maxPayloadCharacters = maxPayloadCharacters {
    if (maxBatchRecords < 1) {
      throw RangeError.value(maxBatchRecords, 'maxBatchRecords');
    }
    if (maxUnsentBatches < 1) {
      throw RangeError.value(maxUnsentBatches, 'maxUnsentBatches');
    }
    if (maxPayloadCharacters < 1) {
      throw RangeError.value(maxPayloadCharacters, 'maxPayloadCharacters');
    }
    if (flushInterval <= Duration.zero ||
        notifyTimeout <= Duration.zero ||
        shutdownTimeout <= Duration.zero) {
      throw ArgumentError('Intervals and timeouts must be positive');
    }
  }

  int get unsentBatches => _unsent.length;

  @override
  Future<bool> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) {
    if (_closed) {
      return Future<bool>.value(false);
    }
    // A batch carries one resource
    if (_resource != null && !identical(_resource, resource)) {
      _closeBatch();
    }
    _resource = resource;

    final Completer<bool> delivery = Completer<bool>();
    _records.add(_stamp(logRecord));
    _deliveries.add(delivery);
    if (_records.length >= _maxBatchRecords) {
      _closeBatch();
      unawaited(_send());
    } else {
      _timer ??= Timer(_flushInterval, () {
        _closeBatch();
        unawaited(_send());
      });
    }
    return delivery.future;
  }

  @override
  Future<void> flush() {
    _closeBatch();
    return _send();
  }

  @override
  Future<void> shutdown() => _shutdown ??= _shutdownOnce();

  Future<void> _shutdownOnce() async {
    _closed = true;
    try {
      await flush().timeout(_shutdownTimeout);
    } on TimeoutException {
      _logger.warning('Telemetry shutdown timed out after $_shutdownTimeout');
    }
    int dropped = 0;
    while (_unsent.isNotEmpty) {
      final AtTelemetryNotificationBatch batch = _unsent.removeFirst();
      dropped += batch.recordCount;
      batch.complete(false);
    }
    if (dropped > 0) {
      _logger.warning('Dropped $dropped telemetry records still unsent at '
          'shutdown');
    }
  }

  AtTelemetryLogRecord _stamp(AtTelemetryLogRecord record) {
    final String? enrollmentId = _read(_enrollmentId);
    final String? clientId = _read(_clientId);
    if (enrollmentId == null && clientId == null) {
      return record;
    }
    return record.withDefaultAttributes(<String, Object?>{
      if (enrollmentId != null)
        AtTelemetryAttributes.enrollmentId: enrollmentId,
      if (clientId != null) AtTelemetryAttributes.clientId: clientId,
    });
  }

  String? _read(AtTelemetryIdSource? source) {
    if (source == null) {
      return null;
    }
    try {
      final String? id = source();
      return id == null || id.isEmpty ? null : id;
    } on Object catch (error) {
      _logger.finer('Could not read a telemetry correlation id: $error');
      return null;
    }
  }

  void _closeBatch() {
    _timer?.cancel();
    _timer = null;
    final AtTelemetryResource? resource = _resource;
    if (_records.isEmpty || resource == null) {
      return;
    }
    final List<AtTelemetryLogRecord> records =
        List<AtTelemetryLogRecord>.of(_records);
    final List<Completer<bool>> deliveries =
        List<Completer<bool>>.of(_deliveries);
    _records.clear();
    _deliveries.clear();
    _enqueue(records, deliveries, resource);
  }

  void _enqueue(
    List<AtTelemetryLogRecord> records,
    List<Completer<bool>> deliveries,
    AtTelemetryResource resource,
  ) {
    final String payload;
    try {
      payload = const AtTelemetryLogsCodec()
          .encodeExportRequest(records, resource: resource);
    } on Object catch (error) {
      _logger.warning('Dropped ${records.length} telemetry records that '
          'could not be encoded: $error');
      AtTelemetryNotificationBatch('', deliveries).complete(false);
      return;
    }

    if (payload.length > _maxPayloadCharacters) {
      if (records.length == 1) {
        _logger.warning('Dropped a telemetry record too large for one '
            'notification');
        AtTelemetryNotificationBatch('', deliveries).complete(false);
        return;
      }
      final int half = records.length ~/ 2;
      _enqueue(records.sublist(0, half), deliveries.sublist(0, half), resource);
      _enqueue(records.sublist(half), deliveries.sublist(half), resource);
      return;
    }

    _unsent.add(AtTelemetryNotificationBatch(payload, deliveries));
    while (_unsent.length > _maxUnsentBatches) {
      final AtTelemetryNotificationBatch dropped = _unsent.removeFirst();
      dropped.complete(false);
      _logger.warning('Dropped the oldest unsent telemetry batch '
          '(${dropped.recordCount} records): more than $_maxUnsentBatches '
          'batches are waiting');
    }
  }

  // One drain at a time, so batches go out oldest first
  Future<void> _send() {
    return _sending ??= _drain().whenComplete(() => _sending = null);
  }

  // Stops at the first failure and keeps that batch for the next flush. A
  // timed-out notify may still land later, so the collector can see a batch
  // twice.
  Future<void> _drain() async {
    while (_unsent.isNotEmpty) {
      final AtTelemetryNotificationBatch batch = _unsent.first;
      try {
        await _notify(idAndNamespace, batch.payload).timeout(_notifyTimeout);
      } on Object catch (error) {
        _logger.warning('Could not send a telemetry batch of '
            '${batch.recordCount} records, keeping it for the next flush: '
            '$error');
        return;
      }
      _unsent.remove(batch);
      batch.complete(true);
    }
  }
}
