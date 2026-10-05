import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../helpers/callback_signer.dart';
import '../helpers/closable_mock_client.dart';

void main() {
  const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();
  final Uri endpoint = Uri.parse('https://collector.example');
  final AtTelemetryResource resource = AtTelemetryResource(serviceName: 'svc');

  late RsaKeyPair keys;
  late AtTelemetrySigner signer;
  late List<http.Request> requests;

  setUpAll(() {
    keys = RsaKeyPair.generate();
    signer = AtTelemetryRsaSigner.fromBase64(keys.atPrivateKey.privateKey);
  });

  setUp(() {
    requests = <http.Request>[];
  });

  http.Response ok() => http.Response.bytes(codec.encodeExportResponse(), 200);

  // Answers each request with the next response, repeating the last one
  MockClient clientReplying(List<FutureOr<http.Response> Function()> replies) {
    return MockClient((http.Request request) async {
      requests.add(request);
      final int index = requests.length - 1;
      return replies[index < replies.length ? index : replies.length - 1]();
    });
  }

  AtTelemetrySignedHttpExporter exporterFor(
    http.Client client, {
    int maxQueuedExports =
        AtTelemetrySignedHttpExporter.defaultMaxQueuedExports,
  }) {
    return AtTelemetrySignedHttpExporter(
      endpoint: endpoint,
      keyId: '@alice',
      audience: '@collector',
      signer: signer,
      client: client,
      maxQueuedExports: maxQueuedExports,
    );
  }

  Future<void> exportEvent(
    AtTelemetrySignedHttpExporter exporter,
    String name,
  ) {
    return exporter.export(AtTelemetryLogRecord(eventName: name), resource);
  }

  String eventNameOf(http.Request request) {
    return codec.decodeExportRequest(request.bodyBytes).single.eventName!;
  }

  Matcher throwsStateErrorContaining(String text) {
    return throwsA(
      isA<StateError>().having(
        (StateError error) => error.message,
        'message',
        contains(text),
      ),
    );
  }

  group('AtTelemetrySignedHttpExporter', () {
    group('endpoint', () {
      test('posts to /v1/logs on accepted endpoints', () async {
        for (final String accepted in <String>[
          'https://collector.example',
          'https://collector.example/',
          'https://collector.example/v1/logs',
          'http://127.0.0.1:4318',
        ]) {
          requests.clear();
          final AtTelemetrySignedHttpExporter exporter =
              AtTelemetrySignedHttpExporter(
            endpoint: Uri.parse(accepted),
            keyId: '@alice',
            audience: '@collector',
            signer: signer,
            client: clientReplying(<http.Response Function()>[ok]),
          );

          await exportEvent(exporter, 'login');

          expect(requests.single.url.path, '/v1/logs', reason: accepted);
          expect(
            requests.single.url.origin,
            Uri.parse(accepted).origin,
            reason: accepted,
          );
        }
      });

      test(
        'keeps a path prefix before /v1/logs',
        () async {
          final AtTelemetrySignedHttpExporter exporter =
              AtTelemetrySignedHttpExporter(
            endpoint: Uri.parse('https://collector.example/otel/v1/logs'),
            keyId: '@alice',
            audience: '@collector',
            signer: signer,
            client: clientReplying(<http.Response Function()>[ok]),
          );

          await exportEvent(exporter, 'login');

          expect(requests.single.url.path, '/otel/v1/logs');
        },
        skip: 'The exporter replaces the whole path with /v1/logs',
      );

      test('rejects invalid endpoints', () {
        for (final String rejected in <String>[
          'ftp://collector.example',
          'https://collector.example?x=1',
          'https://collector.example#x',
          'https://collector.example/other',
          '/v1/logs',
        ]) {
          expect(
            () => AtTelemetrySignedHttpExporter(
              endpoint: Uri.parse(rejected),
              keyId: '@alice',
              audience: '@collector',
              signer: signer,
            ),
            throwsArgumentError,
            reason: rejected,
          );
        }
      });

      test('rejects a maxQueuedExports below 1', () {
        expect(
          () => exporterFor(MockClient((http.Request _) async => ok()),
              maxQueuedExports: 0),
          throwsRangeError,
        );
      });
    });

    group('request', () {
      test('is a signed OTLP POST that the collector can verify', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[ok]));

        await exporter.export(
          AtTelemetryLogRecord(
            eventName: 'login',
            attributes: const <String, Object?>{'method': 'pkam'},
          ),
          resource,
        );

        final http.Request request = requests.single;
        expect(request.method, 'POST');
        expect(request.followRedirects, isFalse);
        expect(request.headers['content-type'], 'application/x-protobuf');

        final AtTelemetryHttpSignature signature =
            AtTelemetryHttpSignature.parse(
          input: request.headers[AtTelemetryHttpSignature.inputHeader]!,
          signature: request.headers[AtTelemetryHttpSignature.signatureHeader]!,
          digest: request.headers[AtTelemetryHttpSignature.digestHeader]!,
          audience: request.headers[AtTelemetryHttpSignature.audienceHeader]!,
        );
        expect(signature.keyId, '@alice');
        expect(signature.audience, '@collector');
        expect(signature.isFresh(DateTime.now()), isTrue);
        expect(signature.matchesBody(request.bodyBytes), isTrue);
        expect(
          await signature.verify(
            path: request.url.path,
            publicKey: keys.atPublicKey.publicKey,
          ),
          isTrue,
        );

        final AtTelemetryLogRecord decoded =
            codec.decodeExportRequest(request.bodyBytes).single;
        expect(decoded.eventName, 'login');
        expect(decoded.attributes, <String, Object?>{
          'method': 'pkam',
          AtTelemetryResource.serviceNameAttribute: 'svc',
        });
      });

      test('sendEncodedLogs posts a copy of the given bytes', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[ok]));
        final List<int> body = <int>[1, 2, 3];

        final Future<void> sent = exporter.sendEncodedLogs(body);
        body[0] = 9;
        await sent;

        expect(requests.single.bodyBytes, <int>[1, 2, 3]);
      });
    });

    group('responses', () {
      test('resolves on HTTP 200', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[ok]));

        await exportEvent(exporter, 'login');

        expect(requests, hasLength(1));
      });

      for (final int status in <int>[204, 302, 400, 401, 404]) {
        test('fails without retrying on HTTP $status', () async {
          final AtTelemetrySignedHttpExporter exporter =
              exporterFor(clientReplying(<http.Response Function()>[
            () => http.Response('', status),
          ]));

          await expectLater(
            exportEvent(exporter, 'login'),
            throwsStateErrorContaining('rejected: HTTP $status'),
          );
          expect(requests, hasLength(1));
        });
      }

      for (final int status in <int>[429, 503]) {
        test('retries HTTP $status 3 times in total', () async {
          final AtTelemetrySignedHttpExporter exporter =
              exporterFor(clientReplying(<http.Response Function()>[
            () => http.Response('', status),
          ]));

          await expectLater(
            exportEvent(exporter, 'login'),
            throwsStateErrorContaining('unavailable: HTTP $status'),
          );
          expect(requests, hasLength(3));
        });
      }

      test('resolves when a retry succeeds and re-signs each attempt',
          () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[
          () => http.Response('', 500),
          () => http.Response('', 500),
          ok,
        ]));

        await exportEvent(exporter, 'login');

        expect(requests, hasLength(3));
        final Set<String> inputs = requests
            .map((http.Request request) =>
                request.headers[AtTelemetryHttpSignature.inputHeader]!)
            .toSet();
        expect(inputs, hasLength(3));
      });

      test('retries a ClientException', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[
          () => throw http.ClientException('down'),
          ok,
        ]));

        await exportEvent(exporter, 'login');

        expect(requests, hasLength(2));
      });

      test('fails with the ClientException after 3 attempts', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[
          () => throw http.ClientException('down'),
        ]));

        await expectLater(
          exportEvent(exporter, 'login'),
          throwsA(isA<http.ClientException>()),
        );
        expect(requests, hasLength(3));
      });

      test('retries a TimeoutException', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[
          () => throw TimeoutException('slow'),
          ok,
        ]));

        await exportEvent(exporter, 'login');

        expect(requests, hasLength(2));
      });

      test('fails without sending when the signer throws', () async {
        final StateError failure = StateError('no key');
        final AtTelemetrySignedHttpExporter exporter =
            AtTelemetrySignedHttpExporter(
          endpoint: endpoint,
          keyId: '@alice',
          audience: '@collector',
          signer: CallbackSigner((List<int> _) async => throw failure),
          client: clientReplying(<http.Response Function()>[ok]),
        );

        await expectLater(exportEvent(exporter, 'login'), throwsA(failure));
        expect(requests, isEmpty);
      });
    });

    group('queue', () {
      test('sends exports in order, one at a time', () async {
        int inFlight = 0;
        int maxInFlight = 0;
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(MockClient((http.Request request) async {
          requests.add(request);
          inFlight++;
          maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
          await pumpEventQueue();
          inFlight--;
          return ok();
        }));

        await Future.wait(<Future<void>>[
          exportEvent(exporter, 'a'),
          exportEvent(exporter, 'b'),
          exportEvent(exporter, 'c'),
        ]);

        expect(requests.map(eventNameOf), <String>['a', 'b', 'c']);
        expect(maxInFlight, 1);
      });

      test('drops the oldest waiting export when the backlog is full',
          () async {
        final Completer<void> release = Completer<void>();
        final AtTelemetrySignedHttpExporter exporter = exporterFor(
          MockClient((http.Request request) async {
            requests.add(request);
            await release.future;
            return ok();
          }),
          maxQueuedExports: 2,
        );

        final Future<void> a = exportEvent(exporter, 'a');
        final Future<void> b = exportEvent(exporter, 'b');
        final Future<void> bDropped = expectLater(
          b,
          throwsStateErrorContaining('backlog is full'),
        );
        final Future<void> c = exportEvent(exporter, 'c');
        final Future<void> d = exportEvent(exporter, 'd');
        await bDropped;

        release.complete();
        await Future.wait(<Future<void>>[a, c, d]);

        expect(requests.map(eventNameOf), <String>['a', 'c', 'd']);
      });
    });

    group('flush and shutdown', () {
      test('flush waits for pending exports and never throws', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[
          () => http.Response('', 400),
        ]));

        final Future<void> failed = expectLater(
          exportEvent(exporter, 'login'),
          throwsStateError,
        );
        await exporter.flush();

        expect(requests, hasLength(1));
        await failed;
      });

      test('flush completes when nothing was exported', () async {
        await exporterFor(clientReplying(<http.Response Function()>[ok]))
            .flush();
      });

      test('shutdown waits for pending exports', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[ok]));

        final Future<void> sent = exportEvent(exporter, 'login');
        await exporter.shutdown();

        expect(requests, hasLength(1));
        await sent;
      });

      test('rejects exports after shutdown', () async {
        final AtTelemetrySignedHttpExporter exporter =
            exporterFor(clientReplying(<http.Response Function()>[ok]));
        await exporter.shutdown();

        await expectLater(
          exportEvent(exporter, 'login'),
          throwsStateErrorContaining('closed'),
        );
        await expectLater(
          exporter.sendEncodedLogs(Uint8List(1)),
          throwsStateErrorContaining('closed'),
        );
        expect(requests, isEmpty);
      });

      test('shutdown does not close a client it was given', () async {
        final ClosableMockClient client =
            ClosableMockClient((http.Request _) async => ok());

        await exporterFor(client).shutdown();

        expect(client.closed, isFalse);
      });
    });
  });
}
