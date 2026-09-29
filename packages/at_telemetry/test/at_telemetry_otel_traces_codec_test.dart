import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:dartastic_opentelemetry/proto/collector/trace/v1/trace_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/trace/v1/trace.pb.dart' as traces;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

void main() {
  const AtTelemetryOtelTracesCodec codec = AtTelemetryOtelTracesCodec();
  const String traceId = '0123456789abcdef0123456789abcdef';
  const String spanId = '0123456789abcdef';
  final DateTime start = DateTime.utc(2026, 9, 29, 12, 0, 0, 0, 123);
  final DateTime end = start.add(const Duration(milliseconds: 42));

  AtTelemetrySpan span({
    String name = 'lookup',
    String id = traceId,
    String sid = spanId,
    String? parentSpanId,
    DateTime? startTimestamp,
    DateTime? endTimestamp,
    int flags = 1,
    AtTelemetrySpanKind kind = AtTelemetrySpanKind.client,
    AtTelemetrySpanStatus status = AtTelemetrySpanStatus.error,
    List<AtTelemetrySpanEvent> events = const <AtTelemetrySpanEvent>[],
    List<AtTelemetrySpanLink> links = const <AtTelemetrySpanLink>[],
  }) {
    return AtTelemetrySpan(
      name: name,
      traceId: id,
      spanId: sid,
      parentSpanId: parentSpanId,
      startTimestamp: startTimestamp ?? start,
      endTimestamp: endTimestamp ?? end,
      kind: kind,
      status: status,
      statusMessage: 'lookup failed',
      traceState: 'vendor=value',
      flags: flags,
      attributes: const <String, Object?>{
        'atsign.atserver.id': '@producer1',
        'success': false
      },
      events: events,
      links: links,
    );
  }

  test(
      'round trips span context, events, links, status and resource attributes',
      () {
    final AtTelemetrySpan original = span(
      parentSpanId: 'fedcba9876543210',
      events: <AtTelemetrySpanEvent>[
        AtTelemetrySpanEvent(
            name: 'exception',
            timestamp: end,
            attributes: const <String, Object?>{
              'exception.type': 'TimeoutException'
            }),
      ],
      links: const <AtTelemetrySpanLink>[
        AtTelemetrySpanLink(
            traceId: 'fedcba9876543210fedcba9876543210',
            spanId: 'fedcba9876543210',
            traceState: 'remote=state',
            flags: 1,
            attributes: <String, Object?>{'reason': 'retry'}),
      ],
    );
    final List<int> payload = codec.encodeExportRequest(
        <AtTelemetrySpan>[original],
        serviceName: 'at_secondary_server');
    final collector.ExportTraceServiceRequest wire =
        collector.ExportTraceServiceRequest.fromBuffer(payload);
    final traces.ScopeSpans scope = wire.resourceSpans.single.scopeSpans.single;
    final traces.Span encoded = scope.spans.single;
    final AtTelemetrySpan actual = codec.decodeExportRequest(payload).single;

    expect(scope.scope.name, 'at_telemetry');
    expect(encoded.traceId, hasLength(16));
    expect(encoded.spanId, hasLength(8));
    expect(encoded.kind, traces.Span_SpanKind.SPAN_KIND_CLIENT);
    expect(
        encoded.startTimeUnixNano.toInt(), start.microsecondsSinceEpoch * 1000);
    expect(encoded.status.code, traces.Status_StatusCode.STATUS_CODE_ERROR);
    expect(actual.name, original.name);
    expect(actual.traceId, traceId);
    expect(actual.spanId, spanId);
    expect(actual.parentSpanId, original.parentSpanId);
    expect(actual.traceState, original.traceState);
    expect(actual.flags, original.flags);
    expect(actual.startTimestamp, start);
    expect(actual.endTimestamp, end);
    expect(actual.kind, original.kind);
    expect(actual.status, original.status);
    expect(actual.statusMessage, original.statusMessage);
    expect(actual.attributes, <String, Object?>{
      ...original.attributes,
      'service.name': 'at_secondary_server'
    });
    expect(actual.events.single.name, 'exception');
    expect(actual.events.single.timestamp, end);
    expect(
        actual.events.single.attributes['exception.type'], 'TimeoutException');
    expect(actual.links.single.traceId, original.links.single.traceId);
    expect(actual.links.single.spanId, original.links.single.spanId);
    expect(actual.links.single.traceState, 'remote=state');
    expect(actual.links.single.flags, 1);
    expect(actual.links.single.attributes['reason'], 'retry');
    expect(() => actual.events.clear(), throwsUnsupportedError);
    expect(() => actual.links.clear(), throwsUnsupportedError);
    expect(() => actual.attributes.clear(), throwsUnsupportedError);
  });

  for (final AtTelemetrySpanKind kind in AtTelemetrySpanKind.values) {
    for (final AtTelemetrySpanStatus status in AtTelemetrySpanStatus.values) {
      test('round trips $kind and $status', () {
        final AtTelemetrySpan actual = codec
            .decodeExportRequest(
              codec.encodeExportRequest(
                  <AtTelemetrySpan>[span(kind: kind, status: status)]),
            )
            .single;
        expect(actual.kind, kind);
        expect(actual.status, status);
        expect(actual.parentSpanId, isNull);
      });
    }
  }

  test('supports span batches and response protobufs', () {
    final List<AtTelemetrySpan> decoded = codec.decodeExportRequest(
      codec.encodeExportRequest(
          <AtTelemetrySpan>[span(), span(sid: 'fedcba9876543210')]),
    );
    expect(decoded, hasLength(2));
    expect(() => decoded.clear(), throwsUnsupportedError);
    expect(
        collector.ExportTraceServiceResponse.fromBuffer(
                codec.encodeExportResponse())
            .hasPartialSuccess(),
        isFalse);
  });

  test('span attributes take precedence over resource and scope attributes',
      () {
    final collector.ExportTraceServiceRequest request =
        collector.ExportTraceServiceRequest.fromBuffer(
      codec.encodeExportRequest(<AtTelemetrySpan>[span()],
          serviceName: 'service'),
    );
    final traces.ResourceSpans resource = request.resourceSpans.single;
    resource.resource.attributes.add(common.KeyValue(
        key: 'success', value: common.AnyValue(boolValue: true)));
    resource.scopeSpans.single.scope.attributes.add(common.KeyValue(
        key: 'success', value: common.AnyValue(boolValue: true)));
    final AtTelemetrySpan actual =
        codec.decodeExportRequest(request.writeToBuffer()).single;
    expect(actual.attributes['success'], isFalse);
    expect(actual.attributes['service.name'], 'service');
  });

  test('rejects malformed, empty and incomplete trace requests', () {
    expect(() => codec.encodeExportRequest(<AtTelemetrySpan>[]),
        throwsArgumentError);
    expect(() => codec.decodeExportRequest(<int>[255]), throwsFormatException);
    expect(
        () => codec.decodeExportRequest(
            collector.ExportTraceServiceRequest().writeToBuffer()),
        throwsFormatException);
    for (final void Function(traces.Span) invalidate
        in <void Function(traces.Span)>[
      (traces.Span span) => span.traceId = <int>[1],
      (traces.Span span) => span.spanId = List<int>.filled(8, 0),
      (traces.Span span) => span.parentSpanId = <int>[1],
      (traces.Span span) => span.name = '',
      (traces.Span span) => span.startTimeUnixNano = Int64.ZERO,
      (traces.Span span) =>
          span.endTimeUnixNano = Int64(start.microsecondsSinceEpoch - 1) * 1000,
    ]) {
      final collector.ExportTraceServiceRequest request =
          collector.ExportTraceServiceRequest.fromBuffer(
        codec.encodeExportRequest(<AtTelemetrySpan>[span()]),
      );
      invalidate(request.resourceSpans.single.scopeSpans.single.spans.single);
      expect(() => codec.decodeExportRequest(request.writeToBuffer()),
          throwsFormatException);
    }
  });

  test('rejects invalid IDs, times, events, links and flags before export', () {
    for (final AtTelemetrySpan invalid in <AtTelemetrySpan>[
      span(name: ''),
      span(id: 'short'),
      span(id: 'z' * 32),
      span(id: '0' * 32),
      span(sid: '0' * 16),
      span(parentSpanId: '0' * 16),
      span(endTimestamp: start.subtract(const Duration(microseconds: 1))),
      span(startTimestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      span(
          startTimestamp: DateTime.utc(2263),
          endTimestamp: DateTime.utc(2263, 1, 2)),
      span(flags: -1),
      span(flags: 0x100000000),
      span(events: <AtTelemetrySpanEvent>[
        AtTelemetrySpanEvent(name: '', timestamp: end)
      ]),
      span(links: const <AtTelemetrySpanLink>[
        AtTelemetrySpanLink(traceId: traceId, spanId: 'invalid')
      ]),
      span(links: const <AtTelemetrySpanLink>[
        AtTelemetrySpanLink(traceId: traceId, spanId: spanId, flags: -1)
      ]),
    ]) {
      expect(() => codec.encodeExportRequest(<AtTelemetrySpan>[invalid]),
          throwsArgumentError);
    }
  });
}
