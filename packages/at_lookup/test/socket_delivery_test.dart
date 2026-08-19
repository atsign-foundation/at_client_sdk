import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'fake_at_server_socket.dart';

/// Delivery THROUGH a socket, which nothing in this package covered before.
///
/// The existing `outbound_message_listener_test.dart` feeds bytes by calling
/// `messageHandler` directly, so it proves the parser and the waiting path but
/// says nothing about the socket wiring: that `listen()` reaches the stream,
/// that a paused subscription stops delivery, or that done and error close the
/// connection. Each test here builds its own rig; none shares state.
void main() {
  group('bytes reach the listener through the socket', () {
    test('a complete response in one packet', () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('data:phone@alice\n@alice@');

      expect(await rig.listener.read(), 'data:phone@alice');
      expect(rig.socket.listenCount, 1,
          reason: 'the listener must have subscribed exactly once');
    });

    test('a response split across packets, as the atServer sends it', () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('data:public:phone@');
      await rig.socket.serverSends('alice\n@ali');
      await rig.socket.serverSends('ce@');

      expect(await rig.listener.read(), 'data:public:phone@alice');
    });

    test('two responses in order on one connection', () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('data:one@alice\n@alice@');
      await rig.socket.serverSends('data:two@alice\n@alice@');

      expect(await rig.listener.read(), 'data:one@alice');
      expect(await rig.listener.read(), 'data:two@alice');
    });

    test('what the client writes arrives at the socket', () async {
      final rig = FakeAtServerRig();

      await rig.connection.write('from:@alice\n');

      expect(rig.socket.written, ['from:@alice\n']);
      expect(rig.socket.flushCount, 1,
          reason: 'BaseConnection.write must flush, or bytes can sit in the '
              'buffer while the test waits for a reply that was never sent');
    });
  });

  group('back-pressure reaches the socket', () {
    // The discriminating pair. A broadcast controller would ignore pause() and
    // deliver anyway, so the first expectation is what proves the harness can
    // detect a missing pause at all; the second proves it is not simply
    // dropping everything.
    test('a paused subscription delivers nothing, and resuming delivers it',
        () async {
      final rig = FakeAtServerRig();
      String? got;
      unawaited(rig.listener
          .read(transientWaitTimeMillis: 5000, maxWaitMilliSeconds: 5000)
          .then((v) => got = v));
      await rig.socket.settle();

      rig.socket.subscription!.pause();
      expect(rig.socket.pauseCount, 1,
          reason: 'pausing the subscription must reach the controller');

      await rig.socket.serverSends('data:paused@alice\n@alice@');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(got, isNull,
          reason: 'a paused subscription must not deliver, and the read must '
              'still be waiting');

      rig.socket.subscription!.resume();
      await Future.delayed(const Duration(milliseconds: 50));
      // Asserted after the wait, not at the call: a controller schedules
      // onResume rather than running it synchronously, so checking it on the
      // next line reads 0 and looks like a broken resume.
      expect(rig.socket.resumeCount, 1,
          reason: 'resuming must reach the controller');
      expect(got, 'data:paused@alice',
          reason: 'resuming must deliver the bytes buffered while paused');
    });
  });

  group('the far end going away closes the connection', () {
    test('onDone destroys the socket and marks the connection closed',
        () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverCloses();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(rig.socket.destroyed, isTrue);
      expect(rig.connection.getMetaData()!.isClosed, isTrue);
    });

    test('onError destroys the socket and marks the connection closed',
        () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverErrors(const SocketException('reset by peer'));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(rig.socket.destroyed, isTrue);
      expect(rig.connection.getMetaData()!.isClosed, isTrue);
    });
  });
}
