## 0.1.0

- feat: initial, experimental release. The contracts below may change in any
  0.x release.
- feat: `AtTelemetry`, which records events and logs for an app and sends
  every failure to an `onError` handler rather than throwing. `flush()` and
  `shutdown()` return within a bounded time.
- feat: an OpenTelemetry-style log record (`AtTelemetryLogRecord`), with an
  optional event name, a body, severity 1 to 24 (`AtTelemetrySeverity`),
  timestamps range-checked to what OTLP can carry, and attributes limited to
  OpenTelemetry AnyValues.
- feat: `AtTelemetryResource`, which describes the sender, with
  `AtTelemetryResource.app` and `AtTelemetryResource.atServer` to build its
  attributes under the right names. `AtTelemetryAttributes` holds every
  attribute name the package uses.
- feat: `AtTelemetryLogsCodec`, which encodes and decodes OTLP/JSON logs
  requests directly, with no protobuf dependency, and carries the event name
  in OTLP's own `eventName` field.
- feat: `AtTelemetryNotificationExporter`, which batches records into one
  notification per batch for a collector atSign, stamps the enrollment and
  client ids on each record, times out a slow notify, and keeps unsent
  batches for the next flush up to a limit.
- feat: the `at-telemetry` request signature (`AtTelemetryHttpSignature`), an
  RFC 9421 profile signed with Ed25519 (`AtTelemetryEd25519Signer`). It covers
  the body digest, path, audience, producer atSign and a per-boot sequence
  number (`AtTelemetrySequence`). `AtTelemetryPublicKeyRecord` is the
  published form of the public key.
