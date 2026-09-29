final class AtTelemetrySpanEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, Object?> attributes;

  const AtTelemetrySpanEvent({
    required this.name,
    required this.timestamp,
    this.attributes = const <String, Object?>{},
  });
}
