<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_telemetry)](https://pub.dev/packages/at_telemetry)
[![pub points](https://img.shields.io/pub/points/at_telemetry?logo=dart)](https://pub.dev/packages/at_telemetry/score)
[![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_telemetry

## Introduction

at_telemetry defines the telemetry model, contracts and exporters shared by
Atsign applications and Atsign Servers. Producers describe what happened as an
`AtTelemetryLogRecord` and hand it to an exporter, which delivers it as an
[OpenTelemetry](https://opentelemetry.io/) OTLP logs request.

at_telemetry supports OpenTelemetry **logs only**. There are no metric or
trace (span) models. To report a measurement, put it in a log record
attribute, for example an uptime heartbeat:

```dart
AtTelemetryLogRecord(
  name: 'atsign.atserver.heartbeat',
  timestamp: DateTime.now().toUtc(),
  attributes: const <String, Object?>{'atsign.atserver.uptime_seconds': 60.0},
);
```

The public API is a single library, `package:at_telemetry/at_telemetry.dart`.
The [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
dependency used to build OTLP payloads stays internal to the package.

## Getting started

```sh
dart pub add at_telemetry
```

## Usage

### Log records

An `AtTelemetryLogRecord` has a name, a timestamp and optional attributes, and
round-trips through JSON with `toJson()`/`fromJson()`. When exported, the name
becomes the OTLP log body and the severity is always `INFO`.

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

Code that produces telemetry depends only on the
`AtTelemetryLogRecordExporter` interface, so it does not need to know where
the telemetry goes:

```dart
abstract interface class AtTelemetryLogRecordExporter {
  Future<void> export(AtTelemetryLogRecord logRecord);
  Future<void> flush();
  Future<void> shutdown();
}
```

Call `flush()` to wait for pending sends, and `shutdown()` once you are
finished with the exporter. The package ships two implementations.

| Exporter | Delivers telemetry as | Use it from |
| --- | --- | --- |
| `AtTelemetrySignedHttpExporter` | A signed OTLP/HTTP request to `/v1/logs` | Atsign Servers |
| `AtTelemetryNotificationExporter` | The value of an Atsign Protocol notification | Applications with an `AtClient` |

Both exporters send one record at a time, in the order they were exported.
Each keeps at most 1000 queued exports by default (`maxQueuedExports`). When
the queue is full, the oldest queued export is dropped and fails with a
`StateError`.

### Signed HTTP exporter

`AtTelemetrySignedHttpExporter` signs every request with the producer's RSA
private key, so the receiving service can check which Atsign sent the
telemetry and that nobody changed it on the way.

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
await exporter.shutdown();
```

`AtTelemetryRsaSigner` is one implementation of the `AtTelemetrySigner`
interface. Both `AtTelemetrySignedHttpExporter` and
`AtTelemetryHttpSignature.sign()` accept any `AtTelemetrySigner`, so you can
swap in a different key source or signing algorithm by implementing
`AtTelemetrySigner` yourself, without changing the exporter.

How it behaves:

- Every request goes to `/v1/logs` on the endpoint's host. The endpoint may be
  a bare origin or end in `/v1/logs`. Any other path, including `/v1/metrics`
  and `/v1/traces`, throws an `ArgumentError`.
- Each send makes up to 3 attempts. It tries again when the server returns
  HTTP 429 or 5xx, when the connection fails, or when a request takes longer
  than 10 seconds. Other non-200 responses, including redirects, fail
  immediately.
- `export()` is best effort. Its `Future` completes normally even when the
  send fails, and the failure is only reported to `onError`.
- `sendConfirmed()` sends a record and fails its `Future` when delivery
  fails. `sendEncodedLogs()` does the same for bytes that are already an
  encoded OTLP logs request, which is useful for retrying stored telemetry.

### Notification exporter

`AtTelemetryNotificationExporter` delivers telemetry as the value of an
Atsign Protocol notification, using the `notify` callback you provide (for
example one that calls `AtClient.notificationService.send`):

```dart
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetryNotificationExporter exporter = AtTelemetryNotificationExporter(
  serviceName: 'my_app',
  notify: (String idAndNamespace, String payload) async {
    // Send payload to the collector Atsign as the value of a notification
    // keyed by idAndNamespace, which is always 'logs.at_telemetry'
  },
);

await exporter.export(event);
await exporter.shutdown();
```

How it behaves:

- Unlike the signed HTTP exporter, the `Future` returned by `export()` fails
  when delivery fails. `flush()` also rethrows the first failure since the
  previous `flush()`.
- A payload longer than `maxPayloadCharacters` (base64 of 1 MiB by default)
  fails with an `ArgumentError` before anything is sent.
- After `shutdown()`, `export()` returns a failed `Future` with a
  `StateError`.

### Verifying signed requests on the receiving service

Each signed request carries these headers:

| Header | Value |
| --- | --- |
| `content-digest` | SHA-256 digest of the request body |
| `at-telemetry-audience` | The Atsign the request is meant for |
| `signature-input` | Signed components, `created` and `expires` times, a random `nonce`, the producer Atsign as `keyid`, and the algorithm |
| `signature` | RSA PKCS#1 v1.5 SHA-256 signature over the method, path, content type, digest and audience |

A signature is valid for at most 5 minutes. Accept a request only when all of
these checks pass:

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
- `signature.keyId` is the producer Atsign. Use it to look up the producer's
  public key.
- Remember nonces for at least as long as a signature stays fresh, so a
  captured request cannot be replayed.

Once the request is accepted, decode the body with
`AtTelemetryLogsCodec().decodeExportRequest(body)` and reply with
`encodeExportResponse()`.

### Codecs

- `AtTelemetryLogsCodec` converts log records to and from an OTLP
  `ExportLogsServiceRequest` in Protobuf bytes.
- `AtTelemetryNotificationCodec` wraps the same bytes in base64 so telemetry
  can travel as the value of a notification. Its `idAndNamespace` is
  `logs.at_telemetry`.

```dart
const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
final String payload = codec.encode(<AtTelemetryLogRecord>[event]);
final List<AtTelemetryLogRecord> events = codec.decode(payload);
```

When decoding, resource and scope attributes (such as `service.name`) are
merged into each record's attributes.

## Package layout

```
lib/
  at_telemetry.dart                      The only public entry point
  src/
    at_telemetry_log_record.dart         The log record model
    codec/                               OTLP and notification codecs
    exporters/                           The exporter interface and both exporters
    internal/                            dartastic_opentelemetry adapters, not exported
    security/                            Request signing and verification
```

`test/at_telemetry_boundary_test.dart` checks that nothing outside
`src/internal/` imports dartastic_opentelemetry or fixnum, and that the public
entry point exports nothing from `src/internal/`.

## Examples

Every example runs on its own, using a local server or callback in place of a
real collector:

| Example | Shows |
| --- | --- |
| [at_telemetry_example.dart](example/at_telemetry_example.dart) | A custom log exporter, JSON round trip and the notification codec |
| [notification_exporter_example.dart](example/notification_exporter_example.dart) | Delivering logs through `AtTelemetryNotificationExporter` |
| [otel_signed_http_exporter_example.dart](example/otel_signed_http_exporter_example.dart) | Signing requests as a producer and verifying them as a collector |

```sh
dart run example/at_telemetry_example.dart
```

## Things to know

- The signed exporter only supports RSA 2048 keys.
- `AtTelemetrySignedHttpExporter` always replaces the endpoint path with
  `/v1/logs`, so a custom path prefix such as `https://host/otel/v1/logs` is
  not preserved.

## Known issues

These are known bugs in the current release:

- **Best-effort sends are silent without `onError`.**
  `AtTelemetrySignedHttpExporter.export()` completes normally even when the
  receiving service rejects the request. Only `sendConfirmed()` reports the
  failure back to the caller.
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
