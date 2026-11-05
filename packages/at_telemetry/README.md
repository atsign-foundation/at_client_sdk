# at_telemetry

Telemetry for apps and atServers built on the Atsign Protocol. It holds the
record model, the OTLP/JSON logs encoding, the request signature atServers use
when they send telemetry over HTTPS, and a client that lets an app send its
own telemetry to a collector atSign by notification.

This package is experimental. It stays below 1.0 while the contracts it
defines are still settling, so expect breaking changes between minor
versions.

## Features

- `AtTelemetry`, the entry point an app uses to record events and logs. It
  never throws into the app: every failure goes to an `onError` handler,
  which by default logs a warning.
- A log record and event model that follows the OpenTelemetry logs data
  model: an optional event name, a body, severity 1 to 24, timestamps,
  attributes, and a resource describing the sender.
- `AtTelemetryNotificationExporter`, which batches records and sends each
  batch as one notification to a collector atSign.
- `AtTelemetryLogsCodec`, which encodes and decodes OTLP/JSON
  `ExportLogsServiceRequest` payloads. It is built directly from maps, with no
  protobuf dependency.
- The `at-telemetry` request signature, an RFC 9421 profile signed with
  Ed25519, for atServers sending telemetry over HTTPS and for the collector
  verifying it.

## Getting started

Add the package to your app:

```sh
dart pub add at_telemetry
```

`at_telemetry` does not depend on `at_client`. An app that already uses
`at_client` passes in a small callback that sends the notification, as shown
below.

## Usage

### Sending telemetry from an app

```dart
import 'package:at_client/at_client.dart';
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetry telemetry = AtTelemetry(
  serviceName: 'acme_photos',
  resourceAttributes: AtTelemetryResource.app(serviceVersion: '2.4.1'),
  exporter: AtTelemetryNotificationExporter(
    notify: (String idAndNamespace, String value) async {
      await atClient.notificationService.send(
        to: '@acme_telemetry'.toAtsign(),
        idAndNamespace: idAndNamespace,
        body: value,
        shouldEncrypt: true,
      );
    },
    enrollmentId: () => atClient.enrollmentId,
    clientId: () =>
        atClient.getPreferences()?.atClientParticulars.clientId,
  ),
);

// An event: something the user meant to do
telemetry.event(
  'photos.album.shared',
  attributes: <String, Object?>{'album.photoCount': 12},
  notificationIds: <String>[notificationId],
  keys: <String>[albumKey.toString()],
);

// A plain log line
telemetry.log(
  'Reconnecting to the atServer',
  severity: AtTelemetrySeverity.warn,
);

// Before the app exits, send what is still batched
await telemetry.shutdown();
```

`event` and `log` return straight away. Records are sent in the background.

### Events and logs

A record with an event name is an event, and one without is a plain log.
Use events for application intent, such as `photos.album.shared`, and leave
protocol traffic to the atServer, which already reports it.

`notificationIds` and `keys` name the protocol objects an event produced. The
exporter also stamps every record with the enrollment id and client id it
reads from the callbacks you give it. These are the ids the atServer's own
events carry, so the Control Center can line an app's intent up with what the
atServer did.

Attribute values, and the body, must be OpenTelemetry AnyValues: `null`,
`String`, `bool`, `int`, a finite `double`, `Uint8List`, or a `List` or
`Map<String, Object?>` of those. Anything else throws `ArgumentError`.

### Resource attributes

The resource describes who sent the telemetry, and is the same for every
record a program sends. Build its attributes with `AtTelemetryResource.app`
or `AtTelemetryResource.atServer` rather than typing the keys by hand:

```dart
// An app
AtTelemetryResource.app(
  serviceVersion: '2.4.1',
  attributes: <String, Object?>{'deployment.environment.name': 'prod'},
);

// An atServer. The collector rejects an atServer's batch unless
// atsign.atserver.id names the atServer that sent it.
AtTelemetryResource.atServer(
  atServerId: '@alice',
  serviceVersion: '3.0.0',
  serviceInstanceId: bootId,
);
```

`AtTelemetryAttributes` holds every attribute name the package uses. Names
follow OpenTelemetry where a standard name exists, and use `atsign.*`
otherwise.

### Delivery

`AtTelemetryNotificationExporter` sends a batch when it reaches 50 records,
or 2 seconds after its first record, whichever comes first. Each batch is one
notification under the key `AtTelemetryNotificationExporter.idAndNamespace`,
whose value is an OTLP/JSON logs request. A batch too large for one
notification is split in half until it fits.

If the app's atServer does not take a notification, or `notify` takes longer
than 30 seconds, the batch stays in memory and goes again with the next
flush. Past 100 waiting batches, the oldest is dropped with a warning. Once
the app's atServer accepts a notification, that atServer retries delivery to
the collector atSign itself.

Every limit is a constructor parameter on the exporter.

### Errors, flush and shutdown

`AtTelemetry` sends every failure, including a record the exporter dropped
(`AtTelemetryDroppedException`), to `onError`. Pass your own handler to
report failures elsewhere:

```dart
AtTelemetry(
  serviceName: 'acme_photos',
  exporter: exporter,
  onError: (Object error, StackTrace stackTrace) =>
      stderr.writeln('Telemetry failed: $error'),
);
```

`flush()` sends what is batched now and gives up after 30 seconds.
`shutdown()` makes a last attempt and returns within 10 seconds. Records sent
after `shutdown()` are reported to `onError` and not sent.

### Writing your own exporter

Implement `AtTelemetryLogRecordExporter` to send records somewhere else. Its
Futures must never complete with an error, and `flush` and `shutdown` must
return within a bounded time.

```dart
final class ConsoleExporter implements AtTelemetryLogRecordExporter {
  @override
  Future<bool> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) async {
    print(const AtTelemetryLogsCodec().encodeExportRequest(
      <AtTelemetryLogRecord>[logRecord],
      resource: resource,
    ));
    return true;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}
```

### Decoding a batch on the collector

```dart
for (final AtTelemetryResourceLogs logs
    in const AtTelemetryLogsCodec().decode(payload)) {
  print(logs.resourceAttributes[AtTelemetryAttributes.atServerId]);
  for (final AtTelemetryLogRecord record in logs.records) {
    print('${record.eventName} ${record.attributes}');
  }
}
```

`decode` throws `FormatException` for anything that is not a valid OTLP/JSON
logs request.

### Signing telemetry requests from an atServer

An atServer signs each HTTPS request with an Ed25519 key that only it holds.
The signature covers the method, path, content type, body digest, the
collector it is meant for (the audience), the producer atSign, and a sequence
number.

```dart
final AtTelemetryEd25519Signer signer =
    await AtTelemetryEd25519Signer.fromSeed(seed);
final AtTelemetryPublicKeyRecord publicKey = AtTelemetryPublicKeyRecord(
  algorithm: signer.algorithm,
  publicKey: signer.publicKey,
);

final AtTelemetryHttpSignature signature = await AtTelemetryHttpSignature.sign(
  body: body,
  path: '/v1/logs',
  keyId: publicKey.keyId,
  audience: 'collector.example.com',
  producer: '@alice',
  sequence: AtTelemetrySequence(bootId: bootId, number: 42),
  signer: signer,
);
// Send signature.headers with the request
```

`AtTelemetrySequence.newBootId()` makes a boot id, once per atServer start.
The number counts up from 0 within that boot, so the collector can spot a
batch it has already ingested, and see a gap where batches were dropped.

`AtTelemetryPublicKeyRecord.encode()` is the value the atServer publishes for
its public key. The key id is a hash of the key, so a record cannot name a key
it does not hold.

### Verifying a request on the collector

```dart
final AtTelemetryHttpSignature signature = AtTelemetryHttpSignature.parse(
  input: headers['signature-input']!,
  signature: headers['signature']!,
  digest: headers['content-digest']!,
  audience: headers['at-telemetry-audience']!,
  producer: headers['at-telemetry-producer']!,
  sequence: headers['at-telemetry-sequence']!,
);
final bool valid = signature.audience == 'collector.example.com' &&
    signature.isFresh(DateTime.now()) &&
    signature.matchesBody(body) &&
    await signature.verify(path: '/v1/logs', publicKey: publicKey.publicKey);
```

`parse` only checks the headers' shapes. The caller still checks the
audience, freshness, the body digest and the signature, and tracks sequence
numbers to reject a repeat.

## Examples

```sh
dart run example/at_telemetry_example.dart
dart run example/notification_exporter_example.dart
```
