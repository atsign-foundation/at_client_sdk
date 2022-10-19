import 'dart:async';
import 'dart:collection';

import 'package:at_client/src/telemetry/at_telemetry.dart';

import '../../at_client.dart';

/// Telemetry Service for an AtProtocol client (i.e. emitter of atProtocol verb commands)
///
/// We'll set ourselves as the telemetry service in the supplied AtClient, SyncService,
/// NotificationService, LocalSecondary, RemoteSecondary, SecondaryKeyStore,
/// CommitLog, etc etc etc
///
/// Those classes will be instrumented to add [AtTelemetryEvent]s to this service's stream.
///
/// Additionally, this class will 'know' how to ask various classes for point-in-time values
/// such as the current size of the key store, how much data has been sent over the network,
/// how much data has been received over the network, the number of keystore operations, the
/// number of sync operations, the number of entries synced to the server, the number synced
/// from the server, etc etc etc
class AtClientTelemetryService extends AtTelemetryService {
  final AtClient atClient;
  AtClientTelemetryService(this.atClient, {StreamController<AtTelemetryEvent>? controller}) :
        super(controller: controller) {
    atClient.telemetry = this;
  }

  final List<AtTelemetrySample> _samples = <AtTelemetrySample>[];
  @override
  Iterator<AtTelemetrySample> get samples => _samples.iterator;

  @override
  Future<void> sample({String? name}) async {
    // TODO
  }
}

class AtClientTelemetryConsumer {
  final AtClientTelemetryService telemetry;

  final int bufferSize;
  Queue<AtTelemetryEvent> buffer = Queue();

  AtClientTelemetryConsumer(this.telemetry, {this.bufferSize = 10000});

  StreamSubscription? _subscription;
  void start() {
    _subscription ??= telemetry.stream.listen(eventHandler);
  }
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
  void eventHandler(event) {
    buffer.addLast(event);
    if (buffer.length > bufferSize) {
      buffer.removeFirst();
    }
  }
  void dumpToConsole() {
    while (buffer.isNotEmpty) {
      print(buffer.removeFirst());
    }
  }
}