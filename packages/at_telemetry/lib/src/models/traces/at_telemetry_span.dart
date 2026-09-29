import 'at_telemetry_span_event.dart';
import 'at_telemetry_span_kind.dart';
import 'at_telemetry_span_link.dart';
import 'at_telemetry_span_status.dart';

final class AtTelemetrySpan {
  final String name;
  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final String traceState;
  final int flags;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final AtTelemetrySpanKind kind;
  final AtTelemetrySpanStatus status;
  final String statusMessage;
  final Map<String, Object?> attributes;
  final List<AtTelemetrySpanEvent> events;
  final List<AtTelemetrySpanLink> links;

  const AtTelemetrySpan({
    required this.name,
    required this.traceId,
    required this.spanId,
    required this.startTimestamp,
    required this.endTimestamp,
    this.parentSpanId,
    this.traceState = '',
    this.flags = 0,
    this.kind = AtTelemetrySpanKind.internal,
    this.status = AtTelemetrySpanStatus.unset,
    this.statusMessage = '',
    this.attributes = const <String, Object?>{},
    this.events = const <AtTelemetrySpanEvent>[],
    this.links = const <AtTelemetrySpanLink>[],
  });
}
