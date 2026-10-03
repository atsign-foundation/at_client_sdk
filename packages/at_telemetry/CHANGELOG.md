## 0.1.0

- Initial release with log, metric, and span models: `AtTelemetryLogRecord`, `AtTelemetryGauge`, `AtTelemetryHistogram`, `AtTelemetrySum`, and `AtTelemetrySpan` with its supporting event/kind/link/status types.
- Added `AtTelemetryLogRecordExporter`, `AtTelemetryMetricExporter`, and `AtTelemetrySpanExporter` interfaces.
- Added an OTLP/HTTP exporter that sends logs, metrics, and spans as OpenTelemetry requests, with optional Bearer token authentication.
- Added a signed HTTP exporter for OTLP requests using RSA signatures, with retry handling for transient failures.
- Added an atServer notification exporter that delivers logs, metrics, and spans via atProtocol notifications.
- Added codecs for telemetry notifications and OTLP log, metric, and trace requests.
- Added `AtTelemetryHttpSignature` and `AtTelemetryRsaSigner` for signing and verifying telemetry payloads.
