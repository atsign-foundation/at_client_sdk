import 'dart:async';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

import 'helpers/fake_exporter.dart';

void main() {
  group('AtTelemetry', () {
    late FakeExporter exporter;
    late List<Object> errors;
    late AtTelemetry telemetry;

    setUp(() {
      exporter = FakeExporter();
      errors = <Object>[];
      telemetry = AtTelemetry(
        serviceName: 'svc',
        resourceAttributes: const <String, Object?>{'atsign': '@alice'},
        exporter: exporter,
        onError: (Object error, StackTrace _) => errors.add(error),
      );
    });

    test('builds the resource from serviceName and resourceAttributes', () {
      expect(telemetry.resource.serviceName, 'svc');
      expect(telemetry.resource.attributes, containsPair('atsign', '@alice'));
    });

    group('event', () {
      test('exports an Event with the given fields and the resource', () {
        final DateTime timestamp = DateTime.utc(2024, 1, 2);
        telemetry.event(
          'login',
          attributes: const <String, Object?>{'method': 'pkam'},
          body: 'ok',
          severity: AtTelemetrySeverity.info,
          timestamp: timestamp,
        );

        expect(exporter.exports, hasLength(1));
        final (AtTelemetryLogRecord record, AtTelemetryResource resource) =
            exporter.exports.single;
        expect(record.eventName, 'login');
        expect(record.isEvent, isTrue);
        expect(record.body, 'ok');
        expect(record.severityNumber, AtTelemetrySeverity.info);
        expect(record.timestamp, timestamp);
        expect(record.attributes, <String, Object?>{'method': 'pkam'});
        expect(resource, same(telemetry.resource));
      });

      test('carries the notification ids and keys the event produced', () {
        telemetry.event(
          'photos.album.shared',
          notificationIds: <String>['n7'],
          keys: <String>['@bob:album.photos@alice'],
        );

        expect(exporter.exports.single.$1.attributes, <String, Object?>{
          AtTelemetryAttributes.notificationIds: <String>['n7'],
          AtTelemetryAttributes.keys: <String>['@bob:album.photos@alice'],
        });
      });

      test('defaults the timestamp to now', () {
        final DateTime before = DateTime.now();
        telemetry.event('login');
        final DateTime after = DateTime.now();

        final DateTime timestamp = exporter.exports.single.$1.timestamp!;
        expect(timestamp.isBefore(before), isFalse);
        expect(timestamp.isAfter(after), isFalse);
      });

      test('throws ArgumentError for a blank name and exports nothing', () {
        expect(() => telemetry.event(''), throwsArgumentError);
        expect(() => telemetry.event('   '), throwsArgumentError);
        expect(exporter.exports, isEmpty);
      });

      test('throws ArgumentError for an attribute that is not an AnyValue', () {
        expect(
          () => telemetry.event(
            'login',
            attributes: <String, Object?>{'when': DateTime.utc(2024)},
          ),
          throwsArgumentError,
        );
        expect(exporter.exports, isEmpty);
      });

      test('throws ArgumentError for a timestamp OTLP cannot carry', () {
        expect(
          () => telemetry.event('login', timestamp: DateTime.utc(1969)),
          throwsArgumentError,
        );
        expect(exporter.exports, isEmpty);
      });
    });

    group('log', () {
      test('exports a plain log with the given fields', () {
        telemetry.log(
          'hello',
          severity: AtTelemetrySeverity.warn,
          severityText: 'WARN',
          attributes: const <String, Object?>{'a': 1},
        );

        final AtTelemetryLogRecord record = exporter.exports.single.$1;
        expect(record.isEvent, isFalse);
        expect(record.eventName, isNull);
        expect(record.body, 'hello');
        expect(record.severityNumber, AtTelemetrySeverity.warn);
        expect(record.severityText, 'WARN');
        expect(record.attributes, <String, Object?>{'a': 1});
        expect(record.timestamp, isNotNull);
      });
    });

    group('error handling', () {
      test('reports a synchronous export failure to onError', () {
        final StateError failure = StateError('sync');
        exporter.onExport = (AtTelemetryLogRecord _) => throw failure;

        expect(() => telemetry.event('login'), returnsNormally);
        expect(errors, <Object>[failure]);
      });

      test('reports a dropped record to onError', () async {
        exporter.onExport = (AtTelemetryLogRecord _) async => false;

        telemetry.event('login');
        await pumpEventQueue();

        expect(
          errors.single,
          isA<AtTelemetryDroppedException>().having(
            (AtTelemetryDroppedException error) => error.logRecord.eventName,
            'eventName',
            'login',
          ),
        );
      });

      test('reports an exporter that breaks its contract and fails', () async {
        final StateError failure = StateError('async');
        exporter.onExport =
            (AtTelemetryLogRecord _) => Future<bool>.error(failure);

        telemetry.event('login');
        await pumpEventQueue();

        expect(errors, <Object>[failure]);
      });

      test('a per-call onError wins over the constructor onError', () async {
        final List<Object> callErrors = <Object>[];
        exporter.onExport = (AtTelemetryLogRecord _) async => false;

        telemetry.event(
          'login',
          onError: (Object error, StackTrace _) => callErrors.add(error),
        );
        telemetry.log(
          'hello',
          onError: (Object error, StackTrace _) => callErrors.add(error),
        );
        await pumpEventQueue();

        expect(callErrors, hasLength(2));
        expect(errors, isEmpty);
      });

      test('a throwing onError does not escape', () async {
        final AtTelemetry throwing = AtTelemetry(
          serviceName: 'svc',
          exporter: exporter,
          onError: (Object _, StackTrace __) => throw StateError('handler'),
        );
        exporter.onExport = (AtTelemetryLogRecord record) =>
            record.body == 'sync'
                ? throw StateError('sync')
                : Future.value(false);

        expect(() => throwing.log('sync'), returnsNormally);
        throwing.log('dropped');
        await pumpEventQueue();
      });

      test('defaultOnError does not throw', () {
        expect(
          () => AtTelemetry.defaultOnError(StateError('x'), StackTrace.current),
          returnsNormally,
        );
      });
    });

    group('flush', () {
      test('asks the exporter to send and waits for that attempt', () async {
        final Completer<void> attempt = Completer<void>();
        exporter.onFlush = () => attempt.future;

        bool flushed = false;
        unawaited(telemetry.flush().then((void _) => flushed = true));
        await pumpEventQueue();
        expect(flushed, isFalse);

        attempt.complete();
        await pumpEventQueue();
        expect(flushed, isTrue);
        expect(exporter.flushCount, 1);
      });

      test('does not wait for records the exporter still holds', () async {
        final Completer<bool> delivery = Completer<bool>();
        exporter.onExport = (AtTelemetryLogRecord _) => delivery.future;
        telemetry.event('login');

        await telemetry.flush();

        expect(delivery.isCompleted, isFalse);
      });

      test('gives up after its timeout and reports it', () async {
        exporter.onFlush = () => Completer<void>().future;

        await telemetry.flush(timeout: const Duration(milliseconds: 10));

        expect(errors.single, isA<TimeoutException>());
      });

      test('reports an exporter flush failure to onError', () async {
        final StateError failure = StateError('flush');
        exporter.onFlush = () async => throw failure;

        await telemetry.flush();

        expect(errors, <Object>[failure]);
      });
    });

    group('shutdown', () {
      test('waits for the outcome of records still in flight', () async {
        final Completer<bool> delivery = Completer<bool>();
        exporter.onExport = (AtTelemetryLogRecord _) => delivery.future;
        telemetry.event('login');

        bool done = false;
        unawaited(telemetry.shutdown().then((void _) => done = true));
        await pumpEventQueue();
        expect(done, isFalse);

        delivery.complete(true);
        await pumpEventQueue();
        expect(done, isTrue);
      });

      test('returns at its deadline when the exporter hangs', () async {
        exporter.onShutdown = () => Completer<void>().future;

        final Stopwatch stopwatch = Stopwatch()..start();
        await telemetry.shutdown(timeout: const Duration(milliseconds: 50));

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(errors.single, isA<TimeoutException>());
      });

      test('returns at its deadline when a record never resolves', () async {
        exporter.onExport =
            (AtTelemetryLogRecord _) => Completer<bool>().future;
        telemetry.event('login');

        await telemetry.shutdown(timeout: const Duration(milliseconds: 50));

        expect(errors.single, isA<TimeoutException>());
      });

      test('only shuts the exporter down once', () async {
        await telemetry.shutdown();
        await telemetry.shutdown();

        expect(exporter.shutdownCount, 1);
      });

      test('reports an exporter shutdown failure to onError', () async {
        final StateError failure = StateError('shutdown');
        exporter.onShutdown = () async => throw failure;

        await telemetry.shutdown();

        expect(errors, <Object>[failure]);
      });

      test('reports a StateError for records sent after shutdown', () async {
        await telemetry.shutdown();
        final List<Object> callErrors = <Object>[];

        telemetry.event(
          'login',
          onError: (Object error, StackTrace _) => callErrors.add(error),
        );
        telemetry.log('hello');

        expect(exporter.exports, isEmpty);
        expect(callErrors.single, isA<StateError>());
        expect(errors.single, isA<StateError>());
      });
    });
  });
}
