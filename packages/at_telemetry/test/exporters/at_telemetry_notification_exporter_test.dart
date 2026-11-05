import 'dart:async';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryNotificationExporter', () {
    const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();
    final AtTelemetryResource resource = AtTelemetryResource(
      serviceName: 'acme_photos',
    );
    late List<(String, String)> sent;
    late Future<void> Function(String key, String value) notify;

    AtTelemetryNotificationExporter exporter({
      int maxBatchRecords = 50,
      Duration flushInterval = const Duration(hours: 1),
      int maxUnsentBatches = 100,
      Duration notifyTimeout = const Duration(seconds: 30),
      Duration shutdownTimeout = const Duration(seconds: 10),
      int maxPayloadCharacters =
          AtTelemetryNotificationExporter.defaultMaxPayloadCharacters,
      AtTelemetryIdSource? enrollmentId,
      AtTelemetryIdSource? clientId,
    }) {
      return AtTelemetryNotificationExporter(
        notify: (String key, String value) => notify(key, value),
        enrollmentId: enrollmentId,
        clientId: clientId,
        maxBatchRecords: maxBatchRecords,
        flushInterval: flushInterval,
        maxUnsentBatches: maxUnsentBatches,
        notifyTimeout: notifyTimeout,
        shutdownTimeout: shutdownTimeout,
        maxPayloadCharacters: maxPayloadCharacters,
      );
    }

    AtTelemetryLogRecord event(String name) =>
        AtTelemetryLogRecord(eventName: name, timestamp: DateTime.utc(2024));

    List<String> eventNames(String value) => <String>[
          for (final AtTelemetryResourceLogs logs in codec.decode(value))
            for (final AtTelemetryLogRecord record in logs.records)
              record.eventName!,
        ];

    setUp(() {
      sent = <(String, String)>[];
      notify = (String key, String value) async => sent.add((key, value));
    });

    test('sends under the logs.at_telemetry key', () {
      expect(
        AtTelemetryNotificationExporter.idAndNamespace,
        'logs.at_telemetry',
      );
    });

    test('sends a full batch as one OTLP/JSON notification', () async {
      final AtTelemetryNotificationExporter subject =
          exporter(maxBatchRecords: 3);
      final List<Future<bool>> deliveries = <Future<bool>>[
        for (final String name in <String>['a', 'b', 'c'])
          subject.export(event(name), resource),
      ];

      expect(await Future.wait(deliveries), <bool>[true, true, true]);
      expect(sent, hasLength(1));
      final (String key, String value) = sent.single;
      expect(key, AtTelemetryNotificationExporter.idAndNamespace);
      expect(eventNames(value), <String>['a', 'b', 'c']);
      expect(
        codec.decode(value).single.resourceAttributes,
        <String, Object?>{'service.name': 'acme_photos'},
      );
    });

    test('closes a batch after the flush interval', () async {
      final AtTelemetryNotificationExporter subject =
          exporter(flushInterval: const Duration(milliseconds: 20));

      final Future<bool> delivery = subject.export(event('a'), resource);
      expect(sent, isEmpty);

      expect(await delivery, isTrue);
      expect(eventNames(sent.single.$2), <String>['a']);
    });

    test('flush sends whatever is batched', () async {
      final AtTelemetryNotificationExporter subject = exporter();
      final Future<bool> delivery = subject.export(event('a'), resource);

      await subject.flush();

      expect(await delivery, isTrue);
      expect(sent, hasLength(1));
    });

    test('a new resource closes the open batch', () async {
      final AtTelemetryNotificationExporter subject = exporter();
      unawaited(subject.export(event('a'), resource));
      unawaited(subject.export(
        event('b'),
        AtTelemetryResource(serviceName: 'other'),
      ));

      await subject.flush();

      expect(sent, hasLength(2));
    });

    test('keeps records with the same resource in one batch', () async {
      final AtTelemetryNotificationExporter subject = exporter();
      unawaited(subject.export(event('a'), resource));
      unawaited(subject.export(event('b'), resource));

      await subject.flush();

      expect(sent, hasLength(1));
      expect(eventNames(sent.single.$2), <String>['a', 'b']);
    });

    test('flush with nothing batched sends nothing', () async {
      final AtTelemetryNotificationExporter subject = exporter();

      await subject.flush();

      expect(sent, isEmpty);
      expect(subject.unsentBatches, 0);
    });

    test('a full batch cancels the flush timer', () async {
      final AtTelemetryNotificationExporter subject = exporter(
        maxBatchRecords: 2,
        flushInterval: const Duration(milliseconds: 20),
      );
      unawaited(subject.export(event('a'), resource));
      await subject.export(event('b'), resource);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sent, hasLength(1));
    });

    test('starts a new flush timer for the next batch', () async {
      final AtTelemetryNotificationExporter subject =
          exporter(flushInterval: const Duration(milliseconds: 20));

      expect(await subject.export(event('a'), resource), isTrue);
      expect(await subject.export(event('b'), resource), isTrue);

      expect(
        sent.map(((String, String) item) => eventNames(item.$2).single),
        <String>['a', 'b'],
      );
    });

    test('sends a batch closed during a send in the same order', () async {
      final Completer<void> firstSend = Completer<void>();
      int calls = 0;
      notify = (String key, String value) async {
        calls++;
        if (calls == 1) {
          await firstSend.future;
        }
        sent.add((key, value));
      };
      final AtTelemetryNotificationExporter subject = exporter();
      unawaited(subject.export(event('a'), resource));
      final Future<void> firstFlush = subject.flush();
      await pumpEventQueue();

      unawaited(subject.export(event('b'), resource));
      final Future<void> secondFlush = subject.flush();
      await pumpEventQueue();
      expect(calls, 1);

      firstSend.complete();
      await Future.wait(<Future<void>>[firstFlush, secondFlush]);

      expect(calls, 2);
      expect(
        sent.map(((String, String) item) => eventNames(item.$2).single),
        <String>['a', 'b'],
      );
    });

    group('correlation ids', () {
      test('stamps the enrollment and client ids on every record', () async {
        final AtTelemetryNotificationExporter subject = exporter(
          enrollmentId: () => 'e1',
          clientId: () => 'c1',
        );
        unawaited(subject.export(event('a'), resource));
        await subject.flush();

        expect(
          codec.decode(sent.single.$2).single.records.single.attributes,
          <String, Object?>{
            AtTelemetryAttributes.enrollmentId: 'e1',
            AtTelemetryAttributes.clientId: 'c1',
          },
        );
      });

      test('leaves an id the record already carries', () async {
        final AtTelemetryNotificationExporter subject =
            exporter(enrollmentId: () => 'e1');
        unawaited(subject.export(
          AtTelemetryLogRecord(
            eventName: 'a',
            attributes: const <String, Object?>{
              AtTelemetryAttributes.enrollmentId: 'mine',
            },
          ),
          resource,
        ));
        await subject.flush();

        expect(
          codec.decode(sent.single.$2).single.records.single.attributes,
          <String, Object?>{AtTelemetryAttributes.enrollmentId: 'mine'},
        );
      });

      test('skips an id source that is empty, null or throws', () async {
        final AtTelemetryNotificationExporter subject = exporter(
          enrollmentId: () => throw StateError('no AtClient yet'),
          clientId: () => '',
        );
        unawaited(subject.export(event('a'), resource));
        await subject.flush();

        expect(
          codec.decode(sent.single.$2).single.records.single.attributes,
          isEmpty,
        );
      });
    });

    group('when the app\'s atServer does not take a batch', () {
      test('keeps it and sends it again with the next flush', () async {
        notify = (String key, String value) async => throw StateError('down');
        final AtTelemetryNotificationExporter subject = exporter();
        bool? delivered;
        unawaited(subject
            .export(event('a'), resource)
            .then((bool value) => delivered = value));

        await subject.flush();
        await pumpEventQueue();
        expect(delivered, isNull);
        expect(subject.unsentBatches, 1);

        notify = (String key, String value) async => sent.add((key, value));
        await subject.flush();
        await pumpEventQueue();

        expect(delivered, isTrue);
        expect(subject.unsentBatches, 0);
        expect(eventNames(sent.single.$2), <String>['a']);
      });

      test('sends batches one at a time, oldest first', () async {
        notify = (String key, String value) async => throw StateError('down');
        final AtTelemetryNotificationExporter subject =
            exporter(maxBatchRecords: 1);
        for (final String name in <String>['a', 'b', 'c']) {
          unawaited(subject.export(event(name), resource));
        }
        await subject.flush();
        expect(subject.unsentBatches, 3);

        int inFlight = 0;
        int mostInFlight = 0;
        notify = (String key, String value) async {
          inFlight++;
          mostInFlight = inFlight > mostInFlight ? inFlight : mostInFlight;
          await Future<void>.delayed(Duration.zero);
          sent.add((key, value));
          inFlight--;
        };
        await subject.flush();

        expect(mostInFlight, 1);
        expect(
          sent.map(((String, String) item) => eventNames(item.$2).single),
          <String>['a', 'b', 'c'],
        );
      });

      test('drops the oldest batch past the cap, with false', () async {
        notify = (String key, String value) async => throw StateError('down');
        final AtTelemetryNotificationExporter subject =
            exporter(maxBatchRecords: 1, maxUnsentBatches: 2);
        final List<Future<bool>> deliveries = <Future<bool>>[
          for (final String name in <String>['a', 'b', 'c'])
            subject.export(event(name), resource),
        ];
        await subject.flush();

        expect(await deliveries.first, isFalse);
        expect(subject.unsentBatches, 2);

        notify = (String key, String value) async => sent.add((key, value));
        await subject.flush();
        expect(await Future.wait(deliveries.skip(1)), <bool>[true, true]);
        expect(
          sent.map(((String, String) item) => eventNames(item.$2).single),
          <String>['b', 'c'],
        );
      });

      test('stops at the first failure and tries nothing after it', () async {
        int calls = 0;
        notify = (String key, String value) async {
          calls++;
          throw StateError('down');
        };
        final AtTelemetryNotificationExporter subject =
            exporter(maxBatchRecords: 1);
        for (final String name in <String>['a', 'b', 'c']) {
          unawaited(subject.export(event(name), resource));
        }
        await pumpEventQueue();
        calls = 0;

        await subject.flush();

        expect(calls, 1);
        expect(subject.unsentBatches, 3);
      });

      test('handles a notify that throws synchronously', () async {
        notify = (String key, String value) => throw StateError('sync');
        final AtTelemetryNotificationExporter subject = exporter();
        bool? delivered;
        unawaited(subject
            .export(event('a'), resource)
            .then((bool value) => delivered = value));

        await expectLater(subject.flush(), completes);
        await pumpEventQueue();

        expect(delivered, isNull);
        expect(subject.unsentBatches, 1);
      });

      test('times out a notify that hangs, and keeps the batch', () async {
        notify = (String key, String value) => Completer<void>().future;
        final AtTelemetryNotificationExporter subject =
            exporter(notifyTimeout: const Duration(milliseconds: 20));
        unawaited(subject.export(event('a'), resource));

        await subject.flush();

        expect(subject.unsentBatches, 1);
      });
    });

    group('payload size', () {
      test('splits a batch too large for one notification', () async {
        final AtTelemetryNotificationExporter subject =
            exporter(maxPayloadCharacters: 400);
        final List<Future<bool>> deliveries = <Future<bool>>[
          for (final String name in <String>['a', 'b', 'c', 'd'])
            subject.export(event(name), resource),
        ];
        await subject.flush();

        expect(await Future.wait(deliveries), everyElement(isTrue));
        expect(sent.length, greaterThan(1));
        expect(
          sent.expand(((String, String) item) => eventNames(item.$2)),
          <String>['a', 'b', 'c', 'd'],
        );
        for (final (String _, String value) in sent) {
          expect(value.length, lessThanOrEqualTo(400));
        }
      });

      test('drops a single record too large for one notification', () async {
        final AtTelemetryNotificationExporter subject =
            exporter(maxPayloadCharacters: 100);

        final Future<bool> delivery = subject.export(event('a'), resource);
        await subject.flush();

        expect(await delivery, isFalse);
        expect(sent, isEmpty);
      });
    });

    group('shutdown', () {
      test('sends what is batched, then refuses new records', () async {
        final AtTelemetryNotificationExporter subject = exporter();
        final Future<bool> delivery = subject.export(event('a'), resource);

        await subject.shutdown();

        expect(await delivery, isTrue);
        expect(await subject.export(event('b'), resource), isFalse);
        expect(sent, hasLength(1));
      });

      test('returns at its deadline and drops what is unsent', () async {
        notify = (String key, String value) => Completer<void>().future;
        final AtTelemetryNotificationExporter subject = exporter(
          shutdownTimeout: const Duration(milliseconds: 50),
        );
        final Future<bool> delivery = subject.export(event('a'), resource);

        final Stopwatch stopwatch = Stopwatch()..start();
        await subject.shutdown();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(await delivery, isFalse);
        expect(subject.unsentBatches, 0);
      });

      test('is safe to call twice', () async {
        final AtTelemetryNotificationExporter subject = exporter();
        await subject.shutdown();
        await subject.shutdown();
      });

      test('returns the same future when called twice', () {
        final AtTelemetryNotificationExporter subject = exporter();

        expect(subject.shutdown(), same(subject.shutdown()));
      });

      test('drops every unsent batch with false', () async {
        notify = (String key, String value) async => throw StateError('down');
        final AtTelemetryNotificationExporter subject =
            exporter(maxBatchRecords: 2);
        final List<Future<bool>> deliveries = <Future<bool>>[
          for (final String name in <String>['a', 'b', 'c', 'd', 'e'])
            subject.export(event(name), resource),
        ];

        await subject.shutdown();

        expect(
          await Future.wait(deliveries),
          <bool>[false, false, false, false, false],
        );
        expect(subject.unsentBatches, 0);
      });

      test('does not start a flush timer for a refused record', () async {
        final AtTelemetryNotificationExporter subject =
            exporter(flushInterval: const Duration(milliseconds: 10));
        await subject.shutdown();

        expect(await subject.export(event('a'), resource), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(sent, isEmpty);
        expect(subject.unsentBatches, 0);
      });
    });

    test('rejects nonsensical limits', () {
      expect(() => exporter(maxBatchRecords: 0), throwsRangeError);
      expect(() => exporter(maxUnsentBatches: 0), throwsRangeError);
      expect(() => exporter(maxPayloadCharacters: 0), throwsRangeError);
      expect(
        () => exporter(notifyTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => exporter(flushInterval: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => exporter(shutdownTimeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('the default payload limit fits a 1 MiB notification as base64', () {
      expect(
        AtTelemetryNotificationExporter.defaultMaxPayloadCharacters,
        1398104,
      );
    });
  });
}
