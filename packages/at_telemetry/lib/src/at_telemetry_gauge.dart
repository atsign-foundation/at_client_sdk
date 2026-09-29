final class AtTelemetryGauge {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final Map<String, Object?> attributes;

  const AtTelemetryGauge({
    required this.name,
    required this.value,
    required this.timestamp,
    this.unit = '',
    this.attributes = const <String, Object?>{},
  });
}
