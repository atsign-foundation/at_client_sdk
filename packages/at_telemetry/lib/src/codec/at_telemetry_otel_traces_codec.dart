import 'package:at_telemetry/src/at_telemetry_span.dart';
import 'package:at_telemetry/src/at_telemetry_span_event.dart';
import 'package:at_telemetry/src/at_telemetry_span_kind.dart';
import 'package:at_telemetry/src/at_telemetry_span_link.dart';
import 'package:at_telemetry/src/at_telemetry_span_status.dart';
import 'package:at_telemetry/src/codec/at_telemetry_otel_attributes_codec.dart';
import 'package:dartastic_opentelemetry/proto/collector/trace/v1/trace_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart' as common;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as resource;
import 'package:dartastic_opentelemetry/proto/trace/v1/trace.pb.dart' as traces;
import 'package:fixnum/fixnum.dart';

final class AtTelemetryOtelTracesCodec {
  static const String scopeName = 'at_telemetry';
  static const AtTelemetryOtelAttributesCodec _attributes =
      AtTelemetryOtelAttributesCodec();
  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  const AtTelemetryOtelTracesCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetrySpan> spans, {
    String? serviceName,
  }) {
    final List<traces.Span> encoded = <traces.Span>[
      for (final AtTelemetrySpan span in spans) _encodeSpan(span),
    ];
    if (encoded.isEmpty) {
      throw ArgumentError.value(spans, 'spans', 'must not be empty');
    }
    return collector.ExportTraceServiceRequest(
      resourceSpans: <traces.ResourceSpans>[
        traces.ResourceSpans(
          resource: resource.Resource(
            attributes: serviceName == null
                ? const <common.KeyValue>[]
                : <common.KeyValue>[
                    common.KeyValue(
                      key: 'service.name',
                      value: common.AnyValue(stringValue: serviceName),
                    ),
                  ],
          ),
          scopeSpans: <traces.ScopeSpans>[
            traces.ScopeSpans(
              scope: common.InstrumentationScope(name: scopeName),
              spans: encoded,
            ),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  List<AtTelemetrySpan> decodeExportRequest(List<int> payload) {
    final collector.ExportTraceServiceRequest request;
    try {
      request = collector.ExportTraceServiceRequest.fromBuffer(payload);
    } on Object catch (error) {
      throw FormatException('Invalid OTLP traces Protobuf payload', error);
    }
    final List<AtTelemetrySpan> decoded = <AtTelemetrySpan>[];
    for (final traces.ResourceSpans resourceSpans in request.resourceSpans) {
      final Map<String, Object?> resourceAttributes = resourceSpans.hasResource()
          ? _attributes.decode(resourceSpans.resource.attributes)
          : const <String, Object?>{};
      for (final traces.ScopeSpans scopeSpans in resourceSpans.scopeSpans) {
        final Map<String, Object?> scopeAttributes = scopeSpans.hasScope()
            ? _attributes.decode(scopeSpans.scope.attributes)
            : const <String, Object?>{};
        for (final traces.Span span in scopeSpans.spans) {
          final AtTelemetrySpan decodedSpan = AtTelemetrySpan(
            name: span.name,
            traceId: _decodeId(span.traceId),
            spanId: _decodeId(span.spanId),
            parentSpanId: span.parentSpanId.isEmpty
                ? null
                : _decodeId(span.parentSpanId),
            traceState: span.traceState,
            flags: span.flags,
            startTimestamp: _decodeTimestamp(span.startTimeUnixNano),
            endTimestamp: _decodeTimestamp(span.endTimeUnixNano),
            kind: _decodeKind(span.kind),
            status: _decodeStatus(span.status.code),
            statusMessage: span.status.message,
            attributes: Map<String, Object?>.unmodifiable(<String, Object?>{
              ...resourceAttributes,
              ...scopeAttributes,
              ..._attributes.decode(span.attributes),
            }),
            events: List<AtTelemetrySpanEvent>.unmodifiable(<AtTelemetrySpanEvent>[
              for (final traces.Span_Event event in span.events)
                AtTelemetrySpanEvent(
                  name: event.name,
                  timestamp: _decodeTimestamp(event.timeUnixNano),
                  attributes: Map<String, Object?>.unmodifiable(
                    _attributes.decode(event.attributes),
                  ),
                ),
            ]),
            links: List<AtTelemetrySpanLink>.unmodifiable(<AtTelemetrySpanLink>[
              for (final traces.Span_Link link in span.links)
                AtTelemetrySpanLink(
                  traceId: _decodeId(link.traceId),
                  spanId: _decodeId(link.spanId),
                  traceState: link.traceState,
                  flags: link.flags,
                  attributes: Map<String, Object?>.unmodifiable(
                    _attributes.decode(link.attributes),
                  ),
                ),
            ]),
          );
          try {
            _validate(decodedSpan);
          } on ArgumentError catch (error) {
            throw FormatException('Invalid OTLP span', error);
          }
          decoded.add(decodedSpan);
        }
      }
    }
    if (decoded.isEmpty) {
      throw const FormatException('OTLP traces request must contain a span');
    }
    return List<AtTelemetrySpan>.unmodifiable(decoded);
  }

  List<int> encodeExportResponse() {
    return collector.ExportTraceServiceResponse().writeToBuffer();
  }

  traces.Span _encodeSpan(AtTelemetrySpan span) {
    _validate(span);
    return traces.Span(
      name: span.name,
      traceId: _encodeId(span.traceId, 16),
      spanId: _encodeId(span.spanId, 8),
      parentSpanId: span.parentSpanId == null
          ? null
          : _encodeId(span.parentSpanId!, 8),
      traceState: span.traceState,
      flags: span.flags,
      startTimeUnixNano: _encodeTimestamp(span.startTimestamp),
      endTimeUnixNano: _encodeTimestamp(span.endTimestamp),
      kind: traces.Span_SpanKind.valueOf(span.kind.index + 1)!,
      status: traces.Status(
        code: traces.Status_StatusCode.valueOf(span.status.index)!,
        message: span.statusMessage,
      ),
      attributes: _attributes.encode(span.attributes),
      events: <traces.Span_Event>[
        for (final AtTelemetrySpanEvent event in span.events)
          traces.Span_Event(
            name: event.name,
            timeUnixNano: _encodeTimestamp(event.timestamp),
            attributes: _attributes.encode(event.attributes),
          ),
      ],
      links: <traces.Span_Link>[
        for (final AtTelemetrySpanLink link in span.links)
          traces.Span_Link(
            traceId: _encodeId(link.traceId, 16),
            spanId: _encodeId(link.spanId, 8),
            traceState: link.traceState,
            flags: link.flags,
            attributes: _attributes.encode(link.attributes),
          ),
      ],
    );
  }

  AtTelemetrySpanKind _decodeKind(traces.Span_SpanKind kind) {
    if (kind.value == 0) return AtTelemetrySpanKind.internal;
    if (kind.value < 1 || kind.value > AtTelemetrySpanKind.values.length) {
      throw const FormatException('Invalid OTLP span kind');
    }
    return AtTelemetrySpanKind.values[kind.value - 1];
  }

  AtTelemetrySpanStatus _decodeStatus(traces.Status_StatusCode status) {
    if (status.value < 0 || status.value >= AtTelemetrySpanStatus.values.length) {
      throw const FormatException('Invalid OTLP span status');
    }
    return AtTelemetrySpanStatus.values[status.value];
  }

  List<int> _encodeId(String id, int length) {
    if (id.length != length * 2 || !_hex.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must contain ${length * 2} hexadecimal characters');
    }
    final List<int> bytes = <int>[
      for (int offset = 0; offset < id.length; offset += 2)
        int.parse(id.substring(offset, offset + 2), radix: 16),
    ];
    if (bytes.every((int byte) => byte == 0)) {
      throw ArgumentError.value(id, 'id', 'must not be all zeros');
    }
    return bytes;
  }

  String _decodeId(List<int> bytes) {
    return bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Int64 _encodeTimestamp(DateTime timestamp) {
    return Int64(timestamp.microsecondsSinceEpoch) * 1000;
  }

  DateTime _decodeTimestamp(Int64 timestamp) {
    if (timestamp <= Int64.ZERO) {
      throw const FormatException('OTLP span must contain a timestamp');
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      (timestamp ~/ 1000).toInt(),
      isUtc: true,
    );
  }

  void _validate(AtTelemetrySpan span) {
    if (span.name.trim().isEmpty) {
      throw ArgumentError.value(span.name, 'name', 'must not be empty');
    }
    _encodeId(span.traceId, 16);
    _encodeId(span.spanId, 8);
    if (span.parentSpanId != null) _encodeId(span.parentSpanId!, 8);
    if (span.startTimestamp.microsecondsSinceEpoch <= 0 ||
        span.endTimestamp.isBefore(span.startTimestamp)) {
      throw ArgumentError('Span timestamps must be positive and ordered');
    }
    _validateFlags(span.flags);
    for (final AtTelemetrySpanEvent event in span.events) {
      if (event.name.trim().isEmpty || event.timestamp.microsecondsSinceEpoch <= 0) {
        throw ArgumentError('Span events must have a name and a positive timestamp');
      }
    }
    for (final AtTelemetrySpanLink link in span.links) {
      _encodeId(link.traceId, 16);
      _encodeId(link.spanId, 8);
      _validateFlags(link.flags);
    }
  }

  void _validateFlags(int flags) {
    if (flags < 0 || flags > 0xffffffff) {
      throw ArgumentError.value(flags, 'flags', 'must be an unsigned 32-bit value');
    }
  }
}
