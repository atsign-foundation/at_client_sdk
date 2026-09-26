final class AtTelemetryEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, Object?> attributes;

  const AtTelemetryEvent({
    required this.name,
    required this.timestamp,
    this.attributes = const <String, Object?>{},
  });

  factory AtTelemetryEvent.fromJson(Map<String, Object?> json) {
    final Object? name = json['name'];
    final Object? timestamp = json['timestamp'];
    final Object attributes = json['attributes'] ?? const <String, Object?>{};
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Event name must be a non-empty string');
    }
    if (timestamp is! String) {
      throw const FormatException('Event timestamp must be an ISO-8601 string');
    }
    if (attributes is! Map<String, Object?>) {
      throw const FormatException('Event attributes must be a JSON object');
    }

    return AtTelemetryEvent(
      name: name,
      timestamp: DateTime.parse(timestamp).toUtc(),
      attributes: Map<String, Object?>.unmodifiable(attributes),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'attributes': attributes,
    };
  }
}
