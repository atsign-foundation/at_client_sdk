import 'package:at_telemetry/src/at_telemetry_gauge.dart';
import 'package:at_telemetry/src/otel/at_telemetry_otel_attributes_codec.dart';
import 'package:dartastic_opentelemetry/proto/collector/metrics/v1/metrics_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/metrics/v1/metrics.pb.dart'
    as metrics;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as resource;
import 'package:fixnum/fixnum.dart';

final class AtTelemetryOtelMetricsCodec {
  static const String scopeName = 'at_telemetry';
  static const AtTelemetryOtelAttributesCodec _attributes =
      AtTelemetryOtelAttributesCodec();

  const AtTelemetryOtelMetricsCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetryGauge> gauges, {
    String? serviceName,
  }) {
    final List<metrics.Metric> encoded = <metrics.Metric>[
      for (final AtTelemetryGauge gauge in gauges) _encodeGauge(gauge),
    ];
    if (encoded.isEmpty) {
      throw ArgumentError.value(gauges, 'gauges', 'must not be empty');
    }

    return collector.ExportMetricsServiceRequest(
      resourceMetrics: <metrics.ResourceMetrics>[
        metrics.ResourceMetrics(
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
          scopeMetrics: <metrics.ScopeMetrics>[
            metrics.ScopeMetrics(
              scope: common.InstrumentationScope(name: scopeName),
              metrics: encoded,
            ),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  List<AtTelemetryGauge> decodeExportRequest(List<int> payload) {
    final collector.ExportMetricsServiceRequest request;
    try {
      request = collector.ExportMetricsServiceRequest.fromBuffer(payload);
    } on Object catch (error) {
      throw FormatException('Invalid OTLP metrics Protobuf payload', error);
    }

    final List<AtTelemetryGauge> gauges = <AtTelemetryGauge>[];
    for (final metrics.ResourceMetrics resourceMetrics
        in request.resourceMetrics) {
      final Map<String, Object?> resourceAttributes =
          resourceMetrics.hasResource()
              ? _attributes.decode(resourceMetrics.resource.attributes)
              : const <String, Object?>{};

      for (final metrics.ScopeMetrics scopeMetrics
          in resourceMetrics.scopeMetrics) {
        final Map<String, Object?> scopeAttributes = scopeMetrics.hasScope()
            ? _attributes.decode(scopeMetrics.scope.attributes)
            : const <String, Object?>{};

        for (final metrics.Metric metric in scopeMetrics.metrics) {
          if (metric.name.trim().isEmpty) {
            throw const FormatException('OTLP metric name must not be empty');
          }
          if (metric.whichData() != metrics.Metric_Data.gauge) {
            throw const FormatException(
                'Only OTLP gauge metrics are supported');
          }
          for (final metrics.NumberDataPoint point in metric.gauge.dataPoints) {
            gauges.add(
              _decodePoint(
                metric,
                point,
                resourceAttributes: resourceAttributes,
                scopeAttributes: scopeAttributes,
              ),
            );
          }
        }
      }
    }

    if (gauges.isEmpty) {
      throw const FormatException(
        'OTLP metrics request must contain at least one gauge data point',
      );
    }
    return List<AtTelemetryGauge>.unmodifiable(gauges);
  }

  List<int> encodeExportResponse() {
    return collector.ExportMetricsServiceResponse().writeToBuffer();
  }

  metrics.Metric _encodeGauge(AtTelemetryGauge gauge) {
    if (gauge.name.trim().isEmpty) {
      throw ArgumentError.value(gauge.name, 'gauge.name', 'must not be empty');
    }
    if (!gauge.value.isFinite) {
      throw ArgumentError.value(gauge.value, 'gauge.value', 'must be finite');
    }

    return metrics.Metric(
      name: gauge.name,
      unit: gauge.unit,
      gauge: metrics.Gauge(
        dataPoints: <metrics.NumberDataPoint>[
          metrics.NumberDataPoint(
            timeUnixNano: Int64(gauge.timestamp.microsecondsSinceEpoch) * 1000,
            asDouble: gauge.value,
            attributes: _attributes.encode(gauge.attributes),
          ),
        ],
      ),
    );
  }

  AtTelemetryGauge _decodePoint(
    metrics.Metric metric,
    metrics.NumberDataPoint point, {
    required Map<String, Object?> resourceAttributes,
    required Map<String, Object?> scopeAttributes,
  }) {
    final double value = switch (point.whichValue()) {
      metrics.NumberDataPoint_Value.asDouble => point.asDouble,
      metrics.NumberDataPoint_Value.asInt => point.asInt.toDouble(),
      metrics.NumberDataPoint_Value.notSet => throw const FormatException(
          'OTLP gauge data point must have a value',
        ),
    };
    if (!value.isFinite) {
      throw const FormatException('OTLP gauge values must be finite');
    }

    final int timestampNanoseconds = point.timeUnixNano.toInt();
    if (timestampNanoseconds <= 0) {
      throw const FormatException(
        'OTLP gauge data point must contain a timestamp',
      );
    }
    final DateTime timestamp;
    try {
      timestamp = DateTime.fromMicrosecondsSinceEpoch(
        timestampNanoseconds ~/ 1000,
        isUtc: true,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP gauge data point timestamp', error);
    }

    return AtTelemetryGauge(
      name: metric.name,
      value: value,
      timestamp: timestamp,
      unit: metric.unit,
      attributes: Map<String, Object?>.unmodifiable(<String, Object?>{
        ...resourceAttributes,
        ...scopeAttributes,
        ..._attributes.decode(point.attributes),
      }),
    );
  }
}
