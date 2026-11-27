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
  });
}
