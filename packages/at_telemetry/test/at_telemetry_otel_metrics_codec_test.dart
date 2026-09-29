import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:dartastic_opentelemetry/proto/collector/metrics/v1/metrics_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/metrics/v1/metrics.pb.dart'
    as metrics;
import 'package:test/test.dart';

void main() {
  const AtTelemetryOtelMetricsCodec codec = AtTelemetryOtelMetricsCodec();

  test('round trips a gauge with resource and point attributes', () {
    final AtTelemetryGauge gauge = AtTelemetryGauge(
      name: 'atsign.atserver.uptime',
      value: 42.5,
      unit: 's',
      timestamp: DateTime.utc(2026, 9, 29, 12),
      attributes: const <String, Object?>{
        'atsign.atserver.id': '@producer1',
        'healthy': true,
      },
    );
    final List<int> payload = codec.encodeExportRequest(
      <AtTelemetryGauge>[gauge],
      serviceName: 'at_secondary_server',
    );
    final List<AtTelemetryGauge> decoded = codec.decodeExportRequest(payload);

    expect(decoded, hasLength(1));
    expect(decoded.single.name, gauge.name);
    expect(decoded.single.value, gauge.value);
    expect(decoded.single.unit, 's');
    expect(decoded.single.timestamp, gauge.timestamp);
    expect(decoded.single.attributes, <String, Object?>{
      ...gauge.attributes,
      'service.name': 'at_secondary_server',
    });
  });

  test('rejects empty and non-gauge requests', () {
    expect(() => codec.decodeExportRequest(<int>[255]), throwsFormatException);
    expect(
      () => codec.decodeExportRequest(
        collector.ExportMetricsServiceRequest().writeToBuffer(),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decodeExportRequest(
        collector.ExportMetricsServiceRequest(
          resourceMetrics: <metrics.ResourceMetrics>[
            metrics.ResourceMetrics(
              scopeMetrics: <metrics.ScopeMetrics>[
                metrics.ScopeMetrics(
                  metrics: <metrics.Metric>[
                    metrics.Metric(name: 'requests', sum: metrics.Sum()),
                  ],
                ),
              ],
            ),
          ],
        ).writeToBuffer(),
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid gauge values', () {
    expect(
      () => codec.encodeExportRequest(<AtTelemetryGauge>[
        AtTelemetryGauge(
          name: 'uptime',
          value: double.nan,
          timestamp: DateTime.now().toUtc(),
        ),
      ]),
      throwsArgumentError,
    );
  });
}
