import 'dart:async';
import 'package:meta/meta.dart';

import '../exception/at_exceptions.dart';

@experimental

/// Simple software telemetry service. See https://en.wikipedia.org/wiki/Telemetry#Software
abstract class AtTelemetryService {
  final StreamController<AtTelemetryEvent> _controller;
  StreamController<AtTelemetryEvent> get controller => _controller;

  /// Allow injection of stream controller
  AtTelemetryService({StreamController<AtTelemetryEvent>? controller})
      : _controller =
            controller ?? StreamController<AtTelemetryEvent>.broadcast() {
    if (!_controller.stream.isBroadcast) {
      throw IllegalArgumentException(
          'AtTelemetryService: controller must be a broadcast StreamController');
    }
  }

  /// A broadcast stream of [AtTelemetryEvent]
  Stream<AtTelemetryEvent> get stream => controller.stream;

  /// The [AtTelemetrySample]s which this telemetry service has taken
  Iterator<AtTelemetrySample> get samples;

  /// Request that sample(s) be taken. If [sampleName] is not supplied, samples will be taken for all known sample names.
  Future<void> takeSample({String? sampleName});

  /// Add a sample which has been taken
  void addSample(AtTelemetrySample sample);
}

@experimental

/// Generic telemetry datum
abstract class AtTelemetryItem {
  /// The name of this item - for example, 'SyncStarted'
  final String name;

  /// A value, which can be null - e.g. for telemetry events which don't have any
  /// associated data other than when the event happened
  final dynamic value;

  /// The [DateTime] of this telemetry event, or at which this telemetry sample was taken
  final DateTime _time;
  DateTime get time => _time;

  AtTelemetryItem(this.name, this.value, {DateTime? time})
      : _time = time ?? DateTime.now().toUtc();

  @override
  String toString() {
    return '$runtimeType{name: $name, value: $value, _time: $_time}';
  }
}

@experimental

/// Concrete [AtTelemetryItem] subclass for Events - e.g. SyncStarted, NetworkUnavailable, MonitorUnavailable
class AtTelemetryEvent extends AtTelemetryItem {
  AtTelemetryEvent(super.name, super.value, {super.time});
}

@experimental

/// Concrete [AtTelemetryItem] subclass for Samples - e.g. KeyStoreSize, DataReceived, DataTransmitted
class AtTelemetrySample extends AtTelemetryItem {
  AtTelemetrySample(super.name, super.value, {super.time});
}
