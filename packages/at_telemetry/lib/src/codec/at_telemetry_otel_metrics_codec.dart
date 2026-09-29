import 'package:at_telemetry/src/at_telemetry_aggregation_temporality.dart';
import 'package:at_telemetry/src/at_telemetry_gauge.dart';
import 'package:at_telemetry/src/at_telemetry_histogram.dart';
import 'package:at_telemetry/src/at_telemetry_metric.dart';
import 'package:at_telemetry/src/at_telemetry_sum.dart';
import 'package:at_telemetry/src/codec/at_telemetry_otel_attributes_codec.dart';
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
    Iterable<AtTelemetryMetric> measurements, {
    String? serviceName,
  }) {
    final Map<String, metrics.Metric> encoded = <String, metrics.Metric>{};
    for (final AtTelemetryMetric measurement in measurements) {
      final metrics.Metric metric = _encodeMetric(measurement);
      final metrics.Metric? existing = encoded[metric.name];
      if (existing == null) {
        encoded[metric.name] = metric;
      } else {
        _appendMetric(existing, metric);
      }
    }
    if (encoded.isEmpty) {
      throw ArgumentError.value(
          measurements, 'measurements', 'must not be empty');
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
              metrics: encoded.values,
            ),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  List<AtTelemetryMetric> decodeExportRequest(List<int> payload) {
    final collector.ExportMetricsServiceRequest request;
    try {
      request = collector.ExportMetricsServiceRequest.fromBuffer(payload);
    } on Object catch (error) {
      throw FormatException('Invalid OTLP metrics Protobuf payload', error);
    }
    final List<AtTelemetryMetric> decoded = <AtTelemetryMetric>[];
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
          final Map<String, Object?> shared = <String, Object?>{
            ...resourceAttributes,
            ...scopeAttributes,
          };
          switch (metric.whichData()) {
            case metrics.Metric_Data.gauge:
              for (final metrics.NumberDataPoint point
                  in metric.gauge.dataPoints) {
                decoded.add(AtTelemetryGauge(
                  name: metric.name,
                  unit: metric.unit,
                  value: _decodeNumber(point),
                  timestamp: _decodeTimestamp(point.timeUnixNano),
                  attributes: _decodeAttributes(shared, point.attributes),
                ));
              }
            case metrics.Metric_Data.sum:
              final AtTelemetryAggregationTemporality temporality =
                  _decodeTemporality(metric.sum.aggregationTemporality);
              for (final metrics.NumberDataPoint point
                  in metric.sum.dataPoints) {
                decoded.add(AtTelemetrySum(
                  name: metric.name,
                  unit: metric.unit,
                  value: _decodeNumber(point),
                  timestamp: _decodeTimestamp(point.timeUnixNano),
                  startTimestamp:
                      _decodeStartTimestamp(point.startTimeUnixNano),
                  temporality: temporality,
                  isMonotonic: metric.sum.isMonotonic,
                  attributes: _decodeAttributes(shared, point.attributes),
                ));
              }
            case metrics.Metric_Data.histogram:
              final AtTelemetryAggregationTemporality temporality =
                  _decodeTemporality(metric.histogram.aggregationTemporality);
              for (final metrics.HistogramDataPoint point
                  in metric.histogram.dataPoints) {
                decoded.add(AtTelemetryHistogram(
                  name: metric.name,
                  unit: metric.unit,
                  count: point.count.toInt(),
                  sum: point.hasSum() ? point.sum : null,
                  min: point.hasMin() ? point.min : null,
                  max: point.hasMax() ? point.max : null,
                  bucketCounts: List<int>.unmodifiable(
                    point.bucketCounts.map((Int64 count) => count.toInt()),
                  ),
                  explicitBounds:
                      List<double>.unmodifiable(point.explicitBounds),
                  timestamp: _decodeTimestamp(point.timeUnixNano),
                  startTimestamp:
                      _decodeStartTimestamp(point.startTimeUnixNano),
                  temporality: temporality,
                  attributes: _decodeAttributes(shared, point.attributes),
                ));
              }
            default:
              throw const FormatException('Unsupported OTLP metric data type');
          }
          if (metric.name.trim().isEmpty) {
            throw const FormatException('OTLP metric name must not be empty');
          }
        }
      }
    }
    if (decoded.isEmpty) {
      throw const FormatException(
          'OTLP metrics request must contain a data point');
    }
    try {
      for (final AtTelemetryMetric measurement in decoded) {
        _validate(measurement);
      }
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP metric data point', error);
    }
    return List<AtTelemetryMetric>.unmodifiable(decoded);
  }

  List<int> encodeExportResponse() {
    return collector.ExportMetricsServiceResponse().writeToBuffer();
  }

  void _appendMetric(metrics.Metric existing, metrics.Metric metric) {
    if (existing.whichData() != metric.whichData() ||
        existing.unit != metric.unit) {
      throw ArgumentError(
          'Metrics with the same name must have consistent metadata');
    }
    switch (metric.whichData()) {
      case metrics.Metric_Data.gauge:
        existing.gauge.dataPoints.addAll(metric.gauge.dataPoints);
      case metrics.Metric_Data.sum:
        if (existing.sum.isMonotonic != metric.sum.isMonotonic ||
            existing.sum.aggregationTemporality !=
                metric.sum.aggregationTemporality) {
          throw ArgumentError(
              'Sums with the same name must have consistent metadata');
        }
        existing.sum.dataPoints.addAll(metric.sum.dataPoints);
      case metrics.Metric_Data.histogram:
        if (existing.histogram.aggregationTemporality !=
            metric.histogram.aggregationTemporality) {
          throw ArgumentError(
              'Histograms with the same name must have consistent temporality');
        }
        existing.histogram.dataPoints.addAll(metric.histogram.dataPoints);
      default:
        throw ArgumentError('Unsupported metric data type');
    }
  }

  metrics.Metric _encodeMetric(AtTelemetryMetric measurement) {
    _validate(measurement);
    final metrics.Metric metric = metrics.Metric(
      name: measurement.name,
      unit: measurement.unit,
    );
    switch (measurement) {
      case final AtTelemetryGauge gauge:
        metric.gauge = metrics.Gauge(dataPoints: <metrics.NumberDataPoint>[
          _encodeNumber(gauge, gauge.value),
        ]);
      case final AtTelemetrySum sum:
        metric.sum = metrics.Sum(
          dataPoints: <metrics.NumberDataPoint>[
            _encodeNumber(sum, sum.value, startTimestamp: sum.startTimestamp),
          ],
          aggregationTemporality: _encodeTemporality(sum.temporality),
          isMonotonic: sum.isMonotonic,
        );
      case final AtTelemetryHistogram histogram:
        metric.histogram = metrics.Histogram(
          dataPoints: <metrics.HistogramDataPoint>[
            metrics.HistogramDataPoint(
              timeUnixNano: _encodeTimestamp(histogram.timestamp),
              startTimeUnixNano: histogram.startTimestamp == null
                  ? null
                  : _encodeTimestamp(histogram.startTimestamp!),
              count: Int64(histogram.count),
              sum: histogram.sum,
              min: histogram.min,
              max: histogram.max,
              bucketCounts: histogram.bucketCounts.map(Int64.new),
              explicitBounds: histogram.explicitBounds,
              attributes: _attributes.encode(histogram.attributes),
            ),
          ],
          aggregationTemporality: _encodeTemporality(histogram.temporality),
        );
      default:
        throw ArgumentError.value(
            measurement, 'measurement', 'unsupported type');
    }
    return metric;
  }

  metrics.NumberDataPoint _encodeNumber(
    AtTelemetryMetric measurement,
    double value, {
    DateTime? startTimestamp,
  }) {
    return metrics.NumberDataPoint(
      timeUnixNano: _encodeTimestamp(measurement.timestamp),
      startTimeUnixNano:
          startTimestamp == null ? null : _encodeTimestamp(startTimestamp),
      asDouble: value,
      attributes: _attributes.encode(measurement.attributes),
    );
  }

  double _decodeNumber(metrics.NumberDataPoint point) {
    return switch (point.whichValue()) {
      metrics.NumberDataPoint_Value.asDouble => point.asDouble,
      metrics.NumberDataPoint_Value.asInt => point.asInt.toDouble(),
      metrics.NumberDataPoint_Value.notSet => throw const FormatException(
          'OTLP number data point must have a value',
        ),
    };
  }

  Map<String, Object?> _decodeAttributes(
    Map<String, Object?> shared,
    Iterable<common.KeyValue> attributes,
  ) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      ...shared,
      ..._attributes.decode(attributes),
    });
  }

  metrics.AggregationTemporality _encodeTemporality(
    AtTelemetryAggregationTemporality temporality,
  ) {
    return switch (temporality) {
      AtTelemetryAggregationTemporality.delta =>
        metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_DELTA,
      AtTelemetryAggregationTemporality.cumulative =>
        metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_CUMULATIVE,
    };
  }

  AtTelemetryAggregationTemporality _decodeTemporality(
    metrics.AggregationTemporality temporality,
  ) {
    if (temporality ==
        metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_DELTA) {
      return AtTelemetryAggregationTemporality.delta;
    }
    if (temporality ==
        metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_CUMULATIVE) {
      return AtTelemetryAggregationTemporality.cumulative;
    }
    throw const FormatException(
        'OTLP aggregation temporality must be specified');
  }

  Int64 _encodeTimestamp(DateTime timestamp) {
    final int microseconds = timestamp.microsecondsSinceEpoch;
    if (microseconds <= 0 || microseconds > 9223372036854775) {
      throw ArgumentError.value(
          timestamp, 'timestamp', 'outside the supported nanosecond range');
    }
    return Int64(microseconds) * 1000;
  }

  DateTime _decodeTimestamp(Int64 timestamp) {
    if (timestamp <= Int64.ZERO) {
      throw const FormatException('OTLP data point must contain a timestamp');
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      (timestamp ~/ 1000).toInt(),
      isUtc: true,
    );
  }

  DateTime? _decodeStartTimestamp(Int64 timestamp) {
    return timestamp == Int64.ZERO ? null : _decodeTimestamp(timestamp);
  }

  void _validate(AtTelemetryMetric measurement) {
    if (measurement.name.trim().isEmpty) {
      throw ArgumentError.value(measurement.name, 'name', 'must not be empty');
    }
    _encodeTimestamp(measurement.timestamp);
    switch (measurement) {
      case final AtTelemetryGauge gauge:
        _finite(gauge.value);
      case final AtTelemetrySum sum:
        _finite(sum.value);
        _validateStartTimestamp(sum.startTimestamp, sum.timestamp);
        if (sum.isMonotonic && sum.value < 0) {
          throw ArgumentError.value(
              sum.value, 'value', 'monotonic sums must be non-negative');
        }
      case final AtTelemetryHistogram histogram:
        _validateStartTimestamp(histogram.startTimestamp, histogram.timestamp);
        if (histogram.count < 0 ||
            histogram.bucketCounts.any((int count) => count < 0)) {
          throw ArgumentError('Histogram counts must be non-negative');
        }
        for (final double? value in <double?>[
          histogram.sum,
          histogram.min,
          histogram.max
        ]) {
          if (value != null) _finite(value);
        }
        if (histogram.min != null &&
            histogram.max != null &&
            histogram.min! > histogram.max!) {
          throw ArgumentError('Histogram min must not exceed max');
        }
        if (histogram.count == 0 &&
            (histogram.min != null || histogram.max != null)) {
          throw ArgumentError('Empty histograms must not have min or max');
        }
        if (histogram.bucketCounts.isEmpty &&
            histogram.explicitBounds.isEmpty) {
          return;
        }
        if (histogram.bucketCounts.length !=
                histogram.explicitBounds.length + 1 ||
            histogram.bucketCounts.fold<BigInt>(BigInt.zero,
                    (BigInt total, int count) => total + BigInt.from(count)) !=
                BigInt.from(histogram.count)) {
          throw ArgumentError(
              'Histogram buckets must match bounds and total count');
        }
        double? previous;
        for (final double bound in histogram.explicitBounds) {
          _finite(bound);
          if (previous != null && bound <= previous) {
            throw ArgumentError('Histogram bounds must be strictly increasing');
          }
          previous = bound;
        }
      default:
        throw ArgumentError.value(
            measurement, 'measurement', 'unsupported type');
    }
  }

  void _validateStartTimestamp(DateTime? startTimestamp, DateTime timestamp) {
    if (startTimestamp != null) _encodeTimestamp(startTimestamp);
    if (startTimestamp != null && startTimestamp.isAfter(timestamp)) {
      throw ArgumentError(
          'Start timestamp must not follow the data point timestamp');
    }
  }

  void _finite(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
  }
}
