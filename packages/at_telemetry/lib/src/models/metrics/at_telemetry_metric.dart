abstract class AtTelemetryMetric {
  final String name;
  final DateTime timestamp;
  final String unit;
  final Map<String, Object?> attributes;

  const AtTelemetryMetric({
    required this.name,
    required this.timestamp,
    this.unit = '',
    this.attributes = const <String, Object?>{},
  });
}
