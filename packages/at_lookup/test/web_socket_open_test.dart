import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/util/abandonment.dart';
import 'package:at_lookup/src/web/web_socket_open.dart';
import 'package:test/test.dart';

class _OpeningSocket implements OpeningWebSocket {
  final open = StreamController<void>.broadcast(sync: true);
  final error = StreamController<void>.broadcast(sync: true);
  final closed = StreamController<void>.broadcast(sync: true);
  int closes = 0;

  @override
  Stream<void> get onOpen => open.stream;

  @override
  Stream<void> get onError => error.stream;

  @override
  Stream<void> get onClose => closed.stream;

  @override
  void close() => closes++;
}

/// How a browser WebSocket's opening is waited for, which the browser glue
/// around it cannot be tested for in the VM.
///
/// Catalogue: features/at_lookup/web_socket_open_retry.feature
void main() {
  late _OpeningSocket socket;
  setUp(() => socket = _OpeningSocket());

  Matcher refused(String cause) =>
      throwsA(isA<SecondaryConnectException>().having((e) => e.message,
          'message', allOf(contains('atserver.example:443'), contains(cause))));

  test('completes once the socket opens, and leaves it open', () async {
    final opening = awaitOpen(socket, 'atserver.example', '443');
    socket.open.add(null);

    await opening;
    expect(socket.closes, 0);
  });

  test('an error before open is refused, and the socket closed', () async {
    final opening = awaitOpen(socket, 'atserver.example', '443');
    socket.error.add(null);

    await expectLater(opening, refused('WebSocket error'));
    expect(socket.closes, 1);
  });

  test('a close before open is refused, and the socket closed', () async {
    final opening = awaitOpen(socket, 'atserver.example', '443');
    socket.closed.add(null);

    await expectLater(opening, refused('closed before open'));
    expect(socket.closes, 1);
  });

  test('a socket that never opens is given up on after timeout', () async {
    await expectLater(
        awaitOpen(socket, 'atserver.example', '443',
            timeout: const Duration(milliseconds: 50)),
        refused('no answer within'));
    expect(socket.closes, 1);
  });

  test('with no timeout, the network default bounds the wait', () async {
    final previous = AtNetworkTimeouts.defaultTimeout;
    AtNetworkTimeouts.defaultTimeout = const Duration(milliseconds: 50);
    addTearDown(() => AtNetworkTimeouts.defaultTimeout = previous);

    await expectLater(awaitOpen(socket, 'atserver.example', '443'),
        refused('no answer within'));
    expect(socket.closes, 1);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('a close of the lookup it opens for ends the wait at once', () async {
    final abandonment = Abandonment();
    final opening =
        abandonment.run(() => awaitOpen(socket, 'atserver.example', '443'));
    abandonment.abandon();

    await expectLater(opening, refused('abandoned'));
    expect(socket.closes, 1);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('begun after its lookup was closed, it fails at once', () async {
    final abandonment = Abandonment()..abandon();

    await expectLater(
        abandonment.run(() => awaitOpen(socket, 'atserver.example', '443')),
        refused('abandoned'));
    expect(socket.closes, 1);
  }, timeout: const Timeout(Duration(seconds: 5)));

  group('openWithRetry', () {
    Matcher gaveUp(String cause) =>
        throwsA(isA<SecondaryConnectException>().having(
            (e) => e.message,
            'message',
            allOf(contains('atserver.example:443'), contains(cause))));

    _OpeningSocket farm(List<_OpeningSocket> sockets) {
      final socket = _OpeningSocket();
      sockets.add(socket);
      return socket;
    }

    test(
        'an open retries a socket that closed before open, on a fresh '
        'socket each time', () async {
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          attemptTimeout: const Duration(milliseconds: 100),
          backoff: const [Duration.zero, Duration.zero]);
      expect(sockets, hasLength(1), reason: 'the first attempt starts at once');

      sockets[0].closed.add(null);
      await pumpEventQueue();
      expect(sockets, hasLength(2));
      sockets[1].closed.add(null);
      await pumpEventQueue();
      expect(sockets, hasLength(3));

      sockets[2].open.add(null);

      expect(await opening, same(sockets[2]));
      expect(sockets[0].closes, 1);
      expect(sockets[1].closes, 1);
      expect(sockets[2].closes, 0);
    });

    test('an open waits one then two seconds between attempts', () async {
      expect(webSocketOpenAttempts, 3);
      expect(webSocketAttemptTimeout, const Duration(seconds: 5));
      expect(webSocketRetryBackoff,
          [const Duration(seconds: 1), const Duration(seconds: 2)],
          reason: 'attempts = backoff + 1, so the ladder lasts at most 18 s');

      const attempt = Duration(milliseconds: 20);
      const first = Duration(milliseconds: 30);
      const second = Duration(milliseconds: 40);
      final clock = Stopwatch()..start();
      final starts = <Duration>[];
      final opening = openWithRetry(() {
        starts.add(clock.elapsed);
        return _OpeningSocket();
      }, 'atserver.example', '443',
          attemptTimeout: attempt, backoff: const [first, second]);

      await expectLater(opening, gaveUp('no answer within'));
      final ended = clock.elapsed;

      expect(starts, hasLength(3));
      expect(starts[0].inMilliseconds, lessThan(15));
      expect((starts[1] - starts[0]).inMilliseconds, inInclusiveRange(45, 250),
          reason: 'one attempt bound of $attempt then a pause of $first');
      expect((starts[2] - starts[1]).inMilliseconds, inInclusiveRange(55, 300),
          reason: 'one attempt bound of $attempt then a pause of $second');
      expect(ended.inMilliseconds, inInclusiveRange(120, 600),
          reason: 'three bounded attempts and both pauses');
    });

    test('an open gives up after three failed attempts with the last cause',
        () async {
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          attemptTimeout: const Duration(milliseconds: 100),
          backoff: const [Duration.zero, Duration.zero]);
      final failure = expectLater(
          opening,
          throwsA(isA<SecondaryConnectException>().having(
              (e) => e.message,
              'message',
              allOf(contains('closed before open'), contains('3 attempts')))));

      for (var i = 0; i < 3; i++) {
        await pumpEventQueue();
        sockets[i].closed.add(null);
      }

      await failure;
      expect(sockets, hasLength(3));
      expect(sockets.map((s) => s.closes), [1, 1, 1]);
    });

    test('an open abandoned during a backoff opens no further socket',
        () async {
      final sockets = <_OpeningSocket>[];
      final abandonment = Abandonment();
      final clock = Stopwatch()..start();
      final opening = abandonment.run(() => openWithRetry(
              () => farm(sockets), 'atserver.example', '443',
              attemptTimeout: const Duration(milliseconds: 20),
              backoff: const [
                Duration(milliseconds: 200),
                Duration(milliseconds: 200),
              ]));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      abandonment.abandon();
      await expectLater(opening, gaveUp('abandoned'));
      expect(clock.elapsed.inMilliseconds, lessThan(180),
          reason: 'the pause ends at once rather than after its 200 ms');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(sockets, hasLength(1),
          reason: 'the ladder ended at the abandonment');
      expect(sockets.single.closes, 1);
    });

    test('an open abandoned while connecting is not retried', () async {
      final sockets = <_OpeningSocket>[];
      final abandonment = Abandonment();
      final opening = abandonment.run(() => openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          attemptTimeout: const Duration(seconds: 5),
          backoff: const [Duration.zero, Duration.zero]));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      abandonment.abandon();
      await expectLater(opening, gaveUp('abandoned'));
      await pumpEventQueue();
      expect(sockets, hasLength(1));
      expect(sockets.single.closes, 1);
    });

    test('a caller timeout caps the whole retry ladder', () async {
      const timeout = Duration(milliseconds: 130);
      final sockets = <_OpeningSocket>[];
      final clock = Stopwatch()..start();
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          timeout: timeout,
          attemptTimeout: const Duration(milliseconds: 50),
          backoff: const [
            Duration(milliseconds: 50),
            Duration(milliseconds: 50),
          ]);

      await expectLater(opening, gaveUp('no answer within'));
      expect(clock.elapsed.inMilliseconds, inInclusiveRange(120, 500));
      expect(sockets.length, lessThanOrEqualTo(2));
    });

    test('an open whose socket constructor throws is not retried', () async {
      var calls = 0;
      _OpeningSocket open() {
        calls++;
        throw StateError('refused URL');
      }

      final opening = openWithRetry(open, 'atserver.example', '443');

      await expectLater(opening, throwsA(isA<StateError>()));
      expect(calls, 1);
    });

    test('an open retries an attempt that errored before open', () async {
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          attemptTimeout: const Duration(milliseconds: 100),
          backoff: const [Duration.zero, Duration.zero]);

      sockets[0].error.add(null);
      await pumpEventQueue();
      expect(sockets, hasLength(2));

      sockets[1].open.add(null);
      expect(await opening, same(sockets[1]));
      expect(sockets[0].closes, 1);
    });

    // The pre-flight seam: a caller may give the ladder a probe to run once,
    // before its first socket, waiting no longer than `preflightWait` (capped
    // by half of what a caller timeout leaves) for it to answer.

    test('a connect prepares once, before its first socket', () async {
      expect(webSocketPreflightWait, const Duration(seconds: 2),
          reason: 'the pre-flight wait a caller gets without saying otherwise');
      final events = <String>[];
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () {
            events.add('open');
            return farm(sockets);
          },
          'atserver.example',
          '443',
          attemptTimeout: const Duration(milliseconds: 20),
          backoff: const [Duration.zero, Duration.zero],
          prepare: () {
            events.add('prepare');
            return Future<void>.value();
          },
          preflightWait: const Duration(milliseconds: 50));

      await expectLater(opening, gaveUp('no answer within'));
      expect(sockets, hasLength(3));
      expect(events.first, 'prepare',
          reason: 'the pre-flight comes before any socket is opened');
      expect(events.where((event) => event == 'prepare'), hasLength(1),
          reason: 'called once, not again before attempts 2 and 3');
    });

    test('a prepare that fails does not stop the open', () async {
      final events = <String>[];
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () {
            events.add('open');
            return farm(sockets);
          },
          'atserver.example',
          '443',
          attemptTimeout: const Duration(milliseconds: 100),
          backoff: const [Duration.zero, Duration.zero],
          prepare: () {
            events.add('prepare');
            throw StateError('the pre-flight refused');
          },
          preflightWait: const Duration(milliseconds: 50));

      await pumpEventQueue();
      expect(events, ['prepare', 'open'],
          reason: 'the throw from the pre-flight is caught, and ends it');
      sockets.single.open.add(null);
      expect(await opening, same(sockets.single));
    });

    test('a prepare that rejects does not stop the open', () async {
      final sockets = <_OpeningSocket>[];
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          attemptTimeout: const Duration(milliseconds: 100),
          backoff: const [Duration.zero, Duration.zero],
          prepare: () async => throw StateError('the pre-flight refused'),
          preflightWait: const Duration(milliseconds: 50));

      await pumpEventQueue();
      expect(sockets, hasLength(1),
          reason:
              'a rejected pre-flight ends the wait without ending the ladder');
      sockets.single.open.add(null);
      expect(await opening, same(sockets.single));
    });

    test(
        'a prepare that never answers is waited on for at most the '
        'pre-flight wait', () async {
      final clock = Stopwatch()..start();
      final starts = <Duration>[];
      final sockets = <_OpeningSocket>[];
      final preflight = Completer<void>();
      var settled = 0;
      final opening = openWithRetry(
          () {
            starts.add(clock.elapsed);
            return farm(sockets);
          },
          'atserver.example',
          '443',
          attemptTimeout: const Duration(seconds: 2),
          backoff: const [Duration.zero, Duration.zero],
          prepare: () {
            // A Future cannot be cancelled, so anything that settles it shows
            // here; the ladder must leave it pending rather than end it.
            unawaited(preflight.future
                .then((_) => settled++, onError: (_) => settled++));
            return preflight.future;
          },
          preflightWait: const Duration(milliseconds: 150));

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(starts, hasLength(1));
      expect(starts.single.inMilliseconds, greaterThanOrEqualTo(150),
          reason: 'the ladder waited out the whole pre-flight wait');
      expect(starts.single.inMilliseconds, lessThan(1000),
          reason: 'and no longer than it');
      expect(preflight.isCompleted, isFalse,
          reason: 'the ladder abandoned its wait, it did not answer for it');
      expect(settled, 0, reason: 'nothing cancelled the pre-flight');

      sockets.single.open.add(null);
      expect(await opening, same(sockets.single));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(
        'a prepare that fails after the ladder stopped waiting raises no '
        'uncaught error', () async {
      final uncaught = <Object>[];
      final starts = <Duration>[];
      final sockets = <_OpeningSocket>[];
      final clock = Stopwatch()..start();

      final opened = await runZonedGuarded(() async {
        final opening = openWithRetry(() {
          starts.add(clock.elapsed);
          return farm(sockets);
        }, 'atserver.example', '443',
            attemptTimeout: const Duration(seconds: 2),
            backoff: const [Duration.zero, Duration.zero],
            prepare: () => Future<void>.delayed(
                const Duration(milliseconds: 300),
                () => throw StateError('the pre-flight failed late')),
            preflightWait: const Duration(milliseconds: 100));

        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (sockets.isNotEmpty) sockets.first.open.add(null);
        final socket = await opening;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return socket;
      }, (error, stackTrace) => uncaught.add(error));

      expect(uncaught, isEmpty,
          reason: 'a handler is attached to the pre-flight future');
      expect(starts, hasLength(1));
      expect(starts.single.inMilliseconds, inInclusiveRange(95, 280),
          reason: 'attempt 1 starts at the 100 ms pre-flight wait, not at the '
              '300 ms rejection');
      expect(opened, same(sockets.single),
          reason: 'the ladder opens as it would with no pre-flight at all');
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a prepare that settles during the backoff is not awaited again',
        () async {
      const pause = Duration(milliseconds: 200);
      final clock = Stopwatch()..start();
      final starts = <Duration>[];
      final sockets = <_OpeningSocket>[];
      var prepares = 0;

      final opening = openWithRetry(
          () {
            starts.add(clock.elapsed);
            return farm(sockets);
          },
          'atserver.example',
          '443',
          attemptTimeout: const Duration(seconds: 2),
          backoff: const [pause, pause],
          prepare: () {
            prepares++;
            return Future<void>.delayed(const Duration(milliseconds: 150));
          },
          preflightWait: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sockets, hasLength(1),
          reason: 'attempt 1 starts at the 50 ms pre-flight wait');
      expect(prepares, 1);
      final first = starts.single;

      // The pre-flight settles at ~150 ms, inside the pause before attempt 2.
      sockets.single.error.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(starts, hasLength(1), reason: 'still inside the pause');

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(starts, hasLength(2));
      expect((starts[1] - first).inMilliseconds, inInclusiveRange(240, 700),
          reason: 'attempt 2 starts when the $pause pause ends, not later');

      sockets.last.open.add(null);
      expect(await opening, same(sockets.last));
      expect(prepares, 1, reason: 'the pre-flight is not awaited again');
    });

    test('an abandonment during prepare opens no socket', () async {
      var opens = 0;
      final preflight = Completer<void>();
      final abandonment = Abandonment();
      final clock = Stopwatch()..start();
      final opening = abandonment.run(() => openWithRetry(() {
            opens++;
            return _OpeningSocket();
          }, 'atserver.example', '443',
              attemptTimeout: const Duration(milliseconds: 100),
              backoff: const [Duration.zero, Duration.zero],
              prepare: () => preflight.future,
              preflightWait: const Duration(seconds: 5)));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      abandonment.abandon();
      await expectLater(opening, gaveUp('abandoned'));
      expect(clock.elapsed.inMilliseconds, lessThan(1000),
          reason: 'the wait for the pre-flight ends at once');
      expect(opens, 0, reason: 'no socket is opened after the abandonment');
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('prepare time counts against the ladder budget', () async {
      const timeout = Duration(milliseconds: 400);
      final clock = Stopwatch()..start();
      final starts = <Duration>[];
      final preflight = Completer<void>();
      final opening = openWithRetry(() {
        starts.add(clock.elapsed);
        return _OpeningSocket();
      }, 'atserver.example', '443',
          timeout: timeout,
          attemptTimeout: const Duration(seconds: 5),
          backoff: const [
            Duration(milliseconds: 10),
            Duration(milliseconds: 10),
          ],
          prepare: () => preflight.future,
          preflightWait: const Duration(seconds: 10));

      await expectLater(opening, gaveUp('no answer within'));
      expect(clock.elapsed.inMilliseconds, inInclusiveRange(390, 1200),
          reason: 'the caller timeout caps the ladder and the pre-flight');
      expect(starts, isNotEmpty, reason: 'at least one attempt is made');
      expect(starts.first.inMilliseconds, inInclusiveRange(190, 380),
          reason: 'half the $timeout budget, not the 10 s pre-flight wait');
      expect(preflight.isCompleted, isFalse);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a budget too small to wait on the pre-flight opens without waiting',
        () async {
      const timeout = Duration(milliseconds: 4);
      final clock = Stopwatch()..start();
      final sockets = <_OpeningSocket>[];
      final preflight = Completer<void>();
      var prepares = 0;
      final opening = openWithRetry(
          () => farm(sockets), 'atserver.example', '443',
          timeout: timeout,
          attemptTimeout: const Duration(seconds: 5),
          backoff: const [Duration.zero, Duration.zero], prepare: () {
        prepares++;
        return preflight.future;
      }, preflightWait: const Duration(seconds: 10));

      await expectLater(opening, gaveUp('no answer within'));
      expect(clock.elapsed.inMilliseconds, lessThan(1000),
          reason: 'the $timeout budget ends the ladder, not the 10 s wait');
      expect(prepares, 1, reason: 'the pre-flight is called exactly once');
      expect(preflight.isCompleted, isFalse,
          reason: 'the ladder stopped waiting; it did not answer for it');
      for (final socket in sockets) {
        expect(socket.closes, 1,
            reason: 'every socket the ladder did open was closed');
      }
    }, timeout: const Timeout(Duration(seconds: 5)));
  });

  group('preflightUri', () {
    test('a wss URL pre-flights the https origin', () {
      expect(preflightUri('wss', 'h', '1'), 'https://h:1/');
    });

    test('a ws URL has no pre-flight', () {
      expect(preflightUri('ws', 'h', '1'), isNull);
    });

    test('an IPv6 literal host is bracketed', () {
      expect(preflightUri('wss', '::1', '443'), 'https://[::1]:443/');
    });
  });

  group('preflightStep', () {
    test('a ws connect has no pre-flight', () {
      expect(preflightStep('ws', 'h', '1', (_) async {}), isNull);
    });

    test('a wss connect fetches its origin exactly once, when run', () async {
      final fetched = <String>[];
      final step =
          preflightStep('wss', 'h', '1', (origin) async => fetched.add(origin));
      expect(step, isNotNull);
      expect(fetched, isEmpty, reason: 'nothing is fetched until it is run');
      await step!();
      expect(fetched, ['https://h:1/']);
    });
  });
}
