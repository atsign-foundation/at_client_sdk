final class AtTelemetrySpanLink {
  final String traceId;
  final String spanId;
  final String traceState;
  final int flags;
  final Map<String, Object?> attributes;

  const AtTelemetrySpanLink({
    required this.traceId,
    required this.spanId,
    this.traceState = '',
    this.flags = 0,
    this.attributes = const <String, Object?>{},
  });
}
