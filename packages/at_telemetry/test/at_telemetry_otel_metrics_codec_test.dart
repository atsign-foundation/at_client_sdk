import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:dartastic_opentelemetry/proto/collector/metrics/v1/metrics_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart' as common;
import 'package:dartastic_opentelemetry/proto/metrics/v1/metrics.pb.dart' as metrics;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

void main() {
  const AtTelemetryOtelMetricsCodec codec = AtTelemetryOtelMetricsCodec();
  final DateTime start = DateTime.utc(2026, 9, 29, 12);
  final DateTime timestamp = start.add(const Duration(seconds: 10));

  List<int> request(metrics.Metric metric) {
    return collector.ExportMetricsServiceRequest(
      resourceMetrics: <metrics.ResourceMetrics>[
        metrics.ResourceMetrics(
          scopeMetrics: <metrics.ScopeMetrics>[
            metrics.ScopeMetrics(metrics: <metrics.Metric>[metric]),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  test('round trips a gauge with resource and point attributes', () {
    final AtTelemetryGauge gauge = AtTelemetryGauge(
      name: 'atsign.atserver.uptime',
      value: 42.5,
      unit: 's',
      timestamp: timestamp,
      attributes: const <String, Object?>{
        'atsign.atserver.id': '@producer1',
        'healthy': true,
      },
    );
    final List<AtTelemetryMetric> decoded = codec.decodeExportRequest(
      codec.encodeExportRequest(<AtTelemetryMetric>[gauge],
          serviceName: 'at_secondary_server'),
    );
    final AtTelemetryGauge actual = decoded.single as AtTelemetryGauge;

    expect(actual.name, gauge.name);
    expect(actual.value, gauge.value);
    expect(actual.unit, 's');
    expect(actual.timestamp, timestamp);
    expect(actual.attributes, <String, Object?>{
      ...gauge.attributes,
      'service.name': 'at_secondary_server',
    });
  });

  for (final AtTelemetryAggregationTemporality temporality
      in AtTelemetryAggregationTemporality.values) {
    for (final bool monotonic in <bool>[true, false]) {
      test('round trips $temporality sums with monotonic=$monotonic', () {
        final AtTelemetrySum sum = AtTelemetrySum(
          name: monotonic ? 'requests' : 'connections',
          value: monotonic ? 42 : -2,
          timestamp: timestamp,
          startTimestamp: start,
          unit: '{request}',
          isMonotonic: monotonic,
          temporality: temporality,
          attributes: const <String, Object?>{'route': '/status'},
        );
        final List<int> payload = codec.encodeExportRequest(<AtTelemetryMetric>[sum]);
        final metrics.Metric wire = collector.ExportMetricsServiceRequest
            .fromBuffer(payload).resourceMetrics.single.scopeMetrics.single.metrics.single;
        final AtTelemetrySum actual = codec.decodeExportRequest(payload).single as AtTelemetrySum;

        expect(wire.whichData(), metrics.Metric_Data.sum);
        expect(wire.sum.isMonotonic, monotonic);
        expect(wire.sum.aggregationTemporality.value, temporality == AtTelemetryAggregationTemporality.delta ? 1 : 2);
        expect(actual.name, sum.name);
        expect(actual.value, sum.value);
        expect(actual.unit, sum.unit);
        expect(actual.timestamp, timestamp);
        expect(actual.startTimestamp, start);
        expect(actual.isMonotonic, monotonic);
        expect(actual.temporality, temporality);
        expect(actual.attributes, sum.attributes);
      });
    }

    test('round trips $temporality histograms with buckets and optional statistics', () {
      final AtTelemetryHistogram histogram = AtTelemetryHistogram(
        name: 'request.duration',
        unit: 's',
        timestamp: timestamp,
        startTimestamp: start,
        temporality: temporality,
        count: 6,
        sum: 18,
        min: 0.5,
        max: 10,
        explicitBounds: const <double>[1, 5],
        bucketCounts: const <int>[2, 3, 1],
        attributes: const <String, Object?>{'route': '/status'},
      );
      final List<int> payload = codec.encodeExportRequest(<AtTelemetryMetric>[histogram]);
      final metrics.Histogram wire = collector.ExportMetricsServiceRequest
          .fromBuffer(payload).resourceMetrics.single.scopeMetrics.single.metrics.single.histogram;
      final AtTelemetryHistogram actual = codec.decodeExportRequest(payload).single as AtTelemetryHistogram;

      expect(wire.dataPoints.single.bucketCounts.map((Int64 value) => value.toInt()), <int>[2, 3, 1]);
      expect(actual.name, histogram.name);
      expect(actual.unit, 's');
      expect(actual.timestamp, timestamp);
      expect(actual.startTimestamp, start);
      expect(actual.temporality, temporality);
      expect(actual.count, 6);
      expect(actual.sum, 18);
      expect(actual.min, 0.5);
      expect(actual.max, 10);
      expect(actual.explicitBounds, <double>[1, 5]);
      expect(actual.bucketCounts, <int>[2, 3, 1]);
      expect(actual.attributes, histogram.attributes);
      expect(() => actual.bucketCounts.add(1), throwsUnsupportedError);
    });
  }

  test('supports mixed metric batches and absent optional statistics', () {
    final List<AtTelemetryMetric> decoded = codec.decodeExportRequest(
      codec.encodeExportRequest(<AtTelemetryMetric>[
        AtTelemetryGauge(name: 'temperature', value: 20, timestamp: timestamp),
        AtTelemetrySum(name: 'requests', value: 1, timestamp: timestamp),
        AtTelemetryHistogram(name: 'duration', count: 0, timestamp: timestamp),
      ]),
    );
    expect(decoded, hasLength(3));
    final AtTelemetrySum sum = decoded[1] as AtTelemetrySum;
    final AtTelemetryHistogram histogram = decoded[2] as AtTelemetryHistogram;
    expect(sum.startTimestamp, isNull);
    expect(histogram.startTimestamp, isNull);
    expect(histogram.sum, isNull);
    expect(histogram.min, isNull);
    expect(histogram.max, isNull);
    expect(() => decoded.clear(), throwsUnsupportedError);
  });

  test('decodes integer number points and point attributes take precedence', () {
    final AtTelemetryGauge gauge = codec.decodeExportRequest(request(
      metrics.Metric(name: 'temperature', gauge: metrics.Gauge(
        dataPoints: <metrics.NumberDataPoint>[
          metrics.NumberDataPoint(
            timeUnixNano: Int64(timestamp.microsecondsSinceEpoch) * 1000,
            asInt: Int64(42),
            attributes: <common.KeyValue>[
              common.KeyValue(key: 'room', value: common.AnyValue(stringValue: 'lab')),
            ],
          ),
        ],
      )),
    )).single as AtTelemetryGauge;
    expect(gauge.value, 42);
    expect(gauge.attributes['room'], 'lab');
  });

  test('rejects empty, malformed, unsupported and incomplete requests', () {
    expect(() => codec.encodeExportRequest(<AtTelemetryMetric>[]), throwsArgumentError);
    for (final List<int> payload in <List<int>>[
      <int>[255],
      collector.ExportMetricsServiceRequest().writeToBuffer(),
      request(metrics.Metric(name: 'requests', sum: metrics.Sum())),
      request(metrics.Metric(name: 'duration', exponentialHistogram: metrics.ExponentialHistogram())),
      request(metrics.Metric(name: 'duration', summary: metrics.Summary())),
      request(metrics.Metric(name: 'gauge', gauge: metrics.Gauge(dataPoints: <metrics.NumberDataPoint>[
        metrics.NumberDataPoint(timeUnixNano: Int64(timestamp.microsecondsSinceEpoch) * 1000),
      ]))),
      request(metrics.Metric(name: 'gauge', gauge: metrics.Gauge(dataPoints: <metrics.NumberDataPoint>[
        metrics.NumberDataPoint(asDouble: 1),
      ]))),
    ]) {
      expect(() => codec.decodeExportRequest(payload), throwsFormatException);
    }
  });

  test('rejects invalid number and histogram measurements', () {
    final List<AtTelemetryMetric> invalid = <AtTelemetryMetric>[
      AtTelemetryGauge(name: '', value: 1, timestamp: timestamp),
      AtTelemetryGauge(name: 'gauge', value: double.nan, timestamp: timestamp),
      AtTelemetrySum(name: 'sum', value: double.infinity, timestamp: timestamp),
      AtTelemetrySum(name: 'sum', value: -1, timestamp: timestamp),
      AtTelemetrySum(name: 'sum', value: 1, timestamp: start, startTimestamp: timestamp),
      AtTelemetryHistogram(name: 'histogram', count: -1, timestamp: timestamp),
      AtTelemetryHistogram(name: 'histogram', count: 1, timestamp: timestamp, bucketCounts: <int>[-1, 2], explicitBounds: <double>[1]),
      AtTelemetryHistogram(name: 'histogram', count: 1, timestamp: timestamp, bucketCounts: <int>[1], explicitBounds: <double>[1]),
      AtTelemetryHistogram(name: 'histogram', count: 2, timestamp: timestamp, bucketCounts: <int>[1]),
      AtTelemetryHistogram(name: 'histogram', count: 3, timestamp: timestamp, bucketCounts: <int>[1, 1, 1], explicitBounds: <double>[2, 1]),
      AtTelemetryHistogram(name: 'histogram', count: 3, timestamp: timestamp, bucketCounts: <int>[1, 1, 1], explicitBounds: <double>[1, 1]),
      AtTelemetryHistogram(name: 'histogram', count: 2, timestamp: timestamp, bucketCounts: <int>[1, 1], explicitBounds: <double>[double.infinity]),
      AtTelemetryHistogram(name: 'histogram', count: 1, timestamp: timestamp, min: 2, max: 1),
      AtTelemetryHistogram(name: 'histogram', count: 0, timestamp: timestamp, min: 1),
      AtTelemetryHistogram(name: 'histogram', count: 1, timestamp: timestamp, sum: double.nan),
    ];
    for (final AtTelemetryMetric measurement in invalid) {
      expect(() => codec.encodeExportRequest(<AtTelemetryMetric>[measurement]), throwsArgumentError);
    }
  });

  test('rejects invalid histogram and monotonic sum wire data', () {
    expect(() => codec.decodeExportRequest(request(metrics.Metric(
      name: 'histogram',
      histogram: metrics.Histogram(
        aggregationTemporality: metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_DELTA,
        dataPoints: <metrics.HistogramDataPoint>[
          metrics.HistogramDataPoint(timeUnixNano: Int64(timestamp.microsecondsSinceEpoch) * 1000,
            count: Int64(2), bucketCounts: <Int64>[Int64(1)]),
        ],
      ),
    ))), throwsFormatException);
    expect(() => codec.decodeExportRequest(request(metrics.Metric(
      name: 'sum',
      sum: metrics.Sum(
        isMonotonic: true,
        aggregationTemporality: metrics.AggregationTemporality.AGGREGATION_TEMPORALITY_CUMULATIVE,
        dataPoints: <metrics.NumberDataPoint>[
          metrics.NumberDataPoint(timeUnixNano: Int64(timestamp.microsecondsSinceEpoch) * 1000, asDouble: -1),
        ],
      ),
    ))), throwsFormatException);
  });
}
