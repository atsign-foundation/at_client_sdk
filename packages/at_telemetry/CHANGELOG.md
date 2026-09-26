## 0.1.0

- Initial release with `AtTelemetryEvent` and the `AtTelemetryExporter` interface.
- Added an OTLP/HTTP exporter that sends events as OpenTelemetry log records, with optional Bearer token authentication.
- Added a signed HTTP exporter for OTLP logs using RSA signatures, with retry handling for transient failures.
- Added codecs for telemetry notifications and OTLP log requests.
