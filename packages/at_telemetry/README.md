<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_telemetry)](https://pub.dev/packages/at_telemetry)
[![pub points](https://img.shields.io/pub/points/at_telemetry?logo=dart)](https://pub.dev/packages/at_telemetry/score)
[![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_telemetry

## Introduction

at_telemetry defines the telemetry models, contracts and exporters shared by
Atsign applications and atServers. Producers describe what happened as an
`AtTelemetryLogRecord`, `AtTelemetryGauge`/`AtTelemetrySum`/`AtTelemetryHistogram`,
or `AtTelemetrySpan`, and hand it to an exporter, which delivers it as
[OpenTelemetry](https://opentelemetry.io/) OTLP requests. The public API is a
single library, `package:at_telemetry/at_telemetry.dart`; the
[dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
dependency used to build OTLP payloads stays internal to the package.

## Getting started

```sh
dart pub add at_telemetry
```

## Usage

### Models

- `AtTelemetryLogRecord` has a name, a timestamp and optional attributes, and
  round-trips through JSON with `toJson()`/`fromJson()`.
- `AtTelemetryMetric` (abstract) - name, unit, timestamp, and attributes
  - `AtTelemetryGauge`
  - `AtTelemetrySum`
  - `AtTelemetryHistogram`
- `AtTelemetrySpan` has a name, trace/span ids, start/end timestamps, a
  `AtTelemetrySpanKind`, a `AtTelemetrySpanStatus`, and optional events and
  links.

Attribute values must be `String`, `bool`, `int`, finite `double`, `List` or
`Map` (nested values follow the same rules). Attributes with a `null` value
are dropped when the record is exported.

```dart
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetryLogRecord event = AtTelemetryLogRecord(
  name: 'atsign.app.started',
  timestamp: DateTime.now().toUtc(),
  attributes: const <String, Object?>{
    'app.version': '1.2.3',
    'app.debug': false,
  },
);

final Map<String, Object?> json = event.toJson();
final AtTelemetryLogRecord copy = AtTelemetryLogRecord.fromJson(json);
```

### Exporters

Each telemetry kind has its own exporter interface (all three are
`abstract interface class`, meant to be implemented rather than instantiated
directly), so code that produces telemetry does not need to know where it
goes:

```dart
abstract interface class AtTelemetryLogRecordExporter {
  Future<void> export(AtTelemetryLogRecord logRecord);
  Future<void> flush();
  Future<void> shutdown();
}

abstract interface class AtTelemetryMetricExporter {
  Future<void> exportMetrics(Iterable<AtTelemetryMetric> metrics);
  Future<void> flush();
  Future<void> shutdown();
}

abstract interface class AtTelemetrySpanExporter {
  Future<void> exportSpans(Iterable<AtTelemetrySpan> spans);
  Future<void> flush();
  Future<void> shutdown();
}
```

Call `flush()` to wait for pending sends, and `shutdown()` once you are
finished with the exporter.

### Signed HTTP exporter

`AtTelemetrySignedHttpExporter` implements all three exporter interfaces. It
signs every request with the producer's RSA private key, so the collector can
check which atSign sent the telemetry and that nobody changed it on the way.

```dart
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetrySignedHttpExporter exporter = AtTelemetrySignedHttpExporter(
  endpoint: Uri.parse('https://collector.example.com'),
  serviceName: 'my_app',
  keyId: '@producer',
  audience: '@collector',
  signer: AtTelemetryRsaSigner.fromBase64(privateKey),
  onError: (Object error) => print('Telemetry failed: $error'),
);

await exporter.export(event);
await exporter.exportMetrics(<AtTelemetryMetric>[gauge]);
await exporter.exportSpans(<AtTelemetrySpan>[span]);
await exporter.shutdown();
```

`AtTelemetryRsaSigner` is one implementation of the abstract interface
`AtTelemetrySigner`. Both `AtTelemetrySignedHttpExporter` and
`AtTelemetryHttpSignature.sign()` accept any `AtTelemetrySigner`, so a
different key source or a different signing algorithm can be swapped in by
implementing `AtTelemetrySigner` directly, without changing the exporter.

How it behaves:

- Logs, metrics and spans are each sent to their own path on the endpoint's
  host: `/v1/logs`, `/v1/metrics` and `/v1/traces`. Requests are sent one at a
  time, in the order they were exported.
- A request is retried up to 3 times when the collector returns HTTP 429 or
  5xx, when the connection fails, or when it takes longer than 10 seconds.
  Other non-200 responses are not retried.
- `export()`, `exportMetrics()` and `exportSpans()` are best effort: they do
  not throw when the send ultimately fails, they only report the failure to
  `onError`. Use `sendConfirmed()` to await a `AtTelemetryLogRecord` send and
  have delivery failures thrown back to the caller instead.

### Notification exporter

`AtTelemetryNotificationExporter` implements the same three interfaces but
delivers telemetry as the value of an atProtocol notification instead of an
HTTP request, using whatever `notify` callback (for example
`AtClient.notificationService`) you provide:

```dart
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetryNotificationExporter exporter = AtTelemetryNotificationExporter(
  serviceName: 'my_app',
  notify: (String idAndNamespace, String payload) async {
    // send payload as the value of a notification keyed by idAndNamespace
  },
);

await exporter.export(event);
await exporter.exportMetrics(<AtTelemetryMetric>[gauge]);
await exporter.exportSpans(<AtTelemetrySpan>[span]);
await exporter.shutdown();
```

Each call is queued and delivered in order. `flush()` waits for the queue to
drain and rethrows the first delivery failure it finds; `export()` and
friends do not throw on their own.

### Verifying signed requests on the collector

Each signed request carries these headers:

| Header | Value |
| --- | --- |
| `content-digest` | SHA-256 digest of the request body |
| `at-telemetry-audience` | The atSign the request is meant for |
| `signature-input` | Signed components, `created` and `expires` times, a random `nonce`, the producer atSign as `keyid`, and the algorithm |
| `signature` | RSA PKCS#1 v1.5 SHA-256 signature over the method, path, content type, digest and audience |

A signature is valid for at most 5 minutes. A collector should accept a
request only when all of these checks pass:

```dart
final AtTelemetryHttpSignature signature = AtTelemetryHttpSignature.parse(
  input: headers['signature-input']!,
  signature: headers['signature']!,
  digest: headers['content-digest']!,
  audience: headers['at-telemetry-audience']!,
);

final bool accepted =
    signature.audience == AtTelemetryHttpSignature.encodeAtsign('@collector') &&
        signature.isFresh(DateTime.now()) &&
        signature.matchesBody(body) &&
        await signature.verify(path: path, publicKey: producerPublicKey) &&
        seenNonces.add(signature.nonce);
```

- `parse` throws when a header is malformed. Reject the request with HTTP 400.
- `signature.keyId` is the producer atSign. Use it to look up the producer's
  public key.
- Remember nonces for at least as long as a signature stays fresh, so a
  captured request cannot be replayed.

Once the request is accepted, decode the body with the matching codec, for
example `AtTelemetryLogsCodec().decodeExportRequest(body)`, and reply with
`encodeExportResponse()`.

### Codecs

- `AtTelemetryLogsCodec`, `AtTelemetryMetricsCodec` and `AtTelemetryTracesCodec`
  convert log records, metrics and spans to and from the matching OTLP
  `Export*ServiceRequest` in Protobuf bytes.
- `AtTelemetryNotificationCodec` wraps the same bytes in base64 so telemetry
  can travel as the value of an atProtocol notification. Its
  `idAndNamespace`, `metricsIdAndNamespace` and `tracesIdAndNamespace` are
  `logs.at_telemetry`, `metrics.at_telemetry` and `traces.at_telemetry`.

```dart
const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
final String payload = codec.encode(<AtTelemetryLogRecord>[event]);
final List<AtTelemetryLogRecord> events = codec.decode(payload);
```

When decoding, resource and scope attributes (such as `service.name`) are
merged into each record's attributes.

## Examples

Every example runs on its own, using a local server in place of a real
collector:

| Example | Shows |
| --- | --- |
| [at_telemetry_example.dart](example/at_telemetry_example.dart) | A custom log exporter, JSON round trip and the notification codec |
| [notification_exporter_example.dart](example/notification_exporter_example.dart) | Delivering logs, metrics and spans through `AtTelemetryNotificationExporter` |
| [otel_signed_http_exporter_example.dart](example/otel_signed_http_exporter_example.dart) | Signing requests as a producer and verifying them as a collector |

```sh
dart run example/at_telemetry_example.dart
```

## Things to know

- The signed exporter only supports RSA 2048 keys.
- `AtTelemetrySignedHttpExporter` accepts an endpoint with any OTLP signal
  path (for example `https://host/otel/v1/traces`) but always replaces the
  path with `/v1/logs`, `/v1/metrics` or `/v1/traces` depending on what is
  being sent, so a custom path prefix is not preserved.

## Known issues

These are known bugs in the current release:

- **Best-effort sends are silent without `onError`.** `export()`,
  `exportMetrics()` and `exportSpans()` complete normally even when the
  collector rejects the request; only `sendConfirmed()` reports the failure
  back to the caller.
- **`AtTelemetryHttpSignature.parse` can throw `ArgumentError`.** A header
  with an invalid percent encoding, such as `keyid="%zz"`, throws
  `ArgumentError` instead of `FormatException`. Catch both.
- **Inconsistent error types.** `AtTelemetrySignedHttpExporter` methods throw
  a `StateError` synchronously after `shutdown()` instead of returning a
  failed `Future`. The OTLP codecs throw `FormatException` rather than
  `ArgumentError` when asked to encode a `NaN` or infinite `double`.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest
changes or enhancements or create your own version.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidance on how to
set up tools, tests and make a pull request.
