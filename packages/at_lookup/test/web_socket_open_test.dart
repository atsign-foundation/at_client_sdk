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
void main() {
  late _OpeningSocket socket;
  setUp(() => socket = _OpeningSocket());

  Matcher refused(String cause) => throwsA(isA<SecondaryConnectException>()
      .having((e) => e.message, 'message',
          allOf(contains('atserver.example:443'), contains(cause))));

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
    final opening = abandonment
        .run(() => awaitOpen(socket, 'atserver.example', '443'));
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
}
