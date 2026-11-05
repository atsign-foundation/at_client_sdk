import 'dart:async';

// One encoded notification value and the records it carries
final class AtTelemetryNotificationBatch {
  final String payload;
  final List<Completer<bool>> _deliveries;

  AtTelemetryNotificationBatch(this.payload, List<Completer<bool>> deliveries)
      : _deliveries = List<Completer<bool>>.of(deliveries);

  int get recordCount => _deliveries.length;

  // Safe to call more than once; only the first outcome counts
  void complete(bool delivered) {
    for (final Completer<bool> delivery in _deliveries) {
      if (!delivery.isCompleted) {
        delivery.complete(delivered);
      }
    }
  }
}
