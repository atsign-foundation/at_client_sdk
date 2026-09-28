<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_telemetry)](https://pub.dev/packages/at_telemetry)
[![pub points](https://img.shields.io/pub/points/at_telemetry?logo=dart)](https://pub.dev/packages/at_telemetry/score)
[![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_telemetry

## Introduction

at_telemetry defines the telemetry models, contracts and exporters shared by
Atsign applications and atServers. Producers describe what happened as an
`AtTelemetryEvent` and hand it to an `AtTelemetryExporter`, which delivers it
to a collector as [OpenTelemetry](https://opentelemetry.io/) log records.

The package has two libraries:

| Library | Contents |
| --- | --- |
| `package:at_telemetry/at_telemetry.dart` | `AtTelemetryEvent` and the `AtTelemetryExporter` interface. No networking. |
| `package:at_telemetry/at_telemetry_otel.dart` | OTLP/HTTP exporters, the Atsign request signature, and OTLP codecs. |

## Getting started

```sh
dart pub add at_telemetry
```

## Usage

### Events

An event has a name, a timestamp and optional attributes. Attribute values
must be `String`, `bool`, `int`, finite `double`, `List` or `Map` (nested
values follow the same rules). Attributes with a `null` value are dropped when
the event is exported.

```dart
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetryEvent event = AtTelemetryEvent(
  name: 'atsign.app.started',
  timestamp: DateTime.now().toUtc(),
  attributes: const <String, Object?>{
    'app.version': '1.2.3',
    'app.debug': false,
  },
);

final Map<String, Object?> json = event.toJson();
final AtTelemetryEvent copy = AtTelemetryEvent.fromJson(json);
```

### Exporters

Every exporter implements the same interface, so code that produces telemetry
does not need to know where it goes:

```dart
abstract interface class AtTelemetryExporter {
  Future<void> export(AtTelemetryEvent event);
  Future<void> flush();
  Future<void> shutdown();
}
```

Call `flush()` to wait for pending events to be sent, and `shutdown()` once
you are finished with the exporter.

### Plain OTLP/HTTP exporter

`AtTelemetryOtelHttpExporter` sends events to any OTLP/HTTP collector using
Protobuf, with an optional Bearer token. Events are batched by OpenTelemetry,
so call `flush()` when you need them sent straight away.

```dart
import 'package:at_telemetry/at_telemetry_otel.dart';

final AtTelemetryOtelHttpExporter exporter =
    await AtTelemetryOtelHttpExporter.create(
  endpoint: Uri.parse('https://collector.example.com'),
  serviceName: 'my_app',
  apiKey: 'my-api-key',
);

await exporter.export(event);
await exporter.flush();
await exporter.shutdown();
```

By default, OpenTelemetry adds details about the machine to every event, such
as `host.name`, `host.arch`, `os.name`, `os.version`, `process.runtime.version`
and `process.command_line`. Pass `detectPlatformResources: false` to leave
them out:

```dart
final AtTelemetryOtelHttpExporter exporter =
    await AtTelemetryOtelHttpExporter.create(
  endpoint: Uri.parse('https://collector.example.com'),
  serviceName: 'my_app',
  detectPlatformResources: false,
);
```

### Signed OTLP/HTTP exporter

`AtTelemetryOtelSignedHttpExporter` signs every request with the producer's RSA
private key, so the collector can check which atSign sent the events and
that nobody changed them on the way.

```dart
import 'package:at_telemetry/at_telemetry_otel.dart';

final AtTelemetryOtelSignedHttpExporter exporter = AtTelemetryOtelSignedHttpExporter(
  endpoint: Uri.parse('https://collector.example.com'),
  serviceName: 'my_app',
  keyId: '@producer',
  audience: '@collector',
  signer: AtTelemetryOtelRsaSigner.fromBase64(privateKey),
  onError: (Object error) => print('Telemetry failed: $error'),
);

await exporter.export(event);
await exporter.shutdown();
```

How it behaves:

- Each event is sent as its own request to `/v1/logs` on the endpoint's host.
  Requests are sent one at a time, in the order they were exported.
- A request is retried up to 3 times when the collector returns HTTP 429 or
  5xx, when the connection fails, or when it takes longer than 10 seconds.
  Other non-200 responses are not retried.
- Failed sends are reported to `onError`. `export()` does not throw them, so
  pass `onError` if you want to know when telemetry is not getting through.

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
final AtTelemetryOtelHttpSignature signature = AtTelemetryOtelHttpSignature.parse(
  input: headers['signature-input']!,
  signature: headers['signature']!,
  digest: headers['content-digest']!,
  audience: headers['at-telemetry-audience']!,
);

final bool accepted =
    signature.audience == AtTelemetryOtelHttpSignature.encodeAtsign('@collector') &&
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

Once the request is accepted, decode the body with
`AtTelemetryOtelLogsCodec().decodeExportRequest(body)` and reply with
`encodeExportResponse()`.

### Codecs

- `AtTelemetryOtelLogsCodec` converts events to and from an OTLP
  `ExportLogsServiceRequest` in Protobuf bytes.
- `AtTelemetryOtelNotificationCodec` wraps the same bytes in base64 so events can
  travel as the value of an Atsign notification. Its
  `AtTelemetryOtelNotificationCodec.idAndNamespace` is `logs.at_telemetry`.

```dart
const AtTelemetryOtelNotificationCodec codec = AtTelemetryOtelNotificationCodec();
final String payload = codec.encode(<AtTelemetryEvent>[event]);
final List<AtTelemetryEvent> events = codec.decode(payload);
```

When decoding, resource and scope attributes (such as `service.name`) are
merged into each event's attributes.

## Examples

Every example runs on its own, using a local server in place of a real
collector:

| Example | Shows |
| --- | --- |
| [at_telemetry_example.dart](example/at_telemetry_example.dart) | Events, a custom exporter, JSON and the notification codec |
| [otel_http_exporter_example.dart](example/otel_http_exporter_example.dart) | Exporting to an OTLP/HTTP collector with a Bearer token |
| [otel_signed_http_exporter_example.dart](example/otel_signed_http_exporter_example.dart) | Signing requests as a producer and verifying them as a collector |

```sh
dart run example/at_telemetry_example.dart
```

## Things to know

- `AtTelemetryOtelHttpExporter` sends machine details with every event unless
  it is created with `detectPlatformResources: false`. `process.command_line`
  can contain file paths and arguments, so check that this is acceptable
  before sending telemetry to a collector you do not control.
- The signed exporter only supports RSA 2048 keys.

## Known issues

These are known bugs in the current release:

- **The endpoint path prefix is dropped.** `AtTelemetryOtelSignedHttpExporter`
  accepts an endpoint such as `https://host/otel/v1/logs` but sends requests
  to `https://host/v1/logs`.
- **Send failures are silent without `onError`.** `export()` completes
  normally even when the collector rejects the request.
- **Only one `AtTelemetryOtelHttpExporter` per process.** Creating a second
  one throws a `StateError`, because OpenTelemetry can only be initialized
  once. Calling `shutdown()` also shuts down OpenTelemetry for the whole
  process.
- **`AtTelemetryOtelHttpSignature.parse` can throw `ArgumentError`.** A header
  with an invalid percent encoding, such as `keyid="%zz"`, throws
  `ArgumentError` instead of `FormatException`. Catch both.
- **Inconsistent error types.** `AtTelemetryOtelSignedHttpExporter.export` throws
  a `StateError` synchronously after `shutdown()` instead of returning a
  failed `Future`. `AtTelemetryOtelLogsCodec` throws `FormatException` rather
  than `ArgumentError` when asked to encode a `NaN` or infinite `double`.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest
changes or enhancements or create your own version.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidance on how to
set up tools, tests and make a pull request.
