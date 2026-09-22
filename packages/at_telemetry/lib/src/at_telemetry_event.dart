final class AtTelemetryEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, Object?> attributes;

  const AtTelemetryEvent({
    required this.name,
    required this.timestamp,
    this.attributes = const <String, Object?>{},
  });
}
