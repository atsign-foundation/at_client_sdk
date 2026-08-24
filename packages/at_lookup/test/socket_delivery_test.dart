import 'dart:async';
import 'dart:io';

import 'package:at_commons/at_commons.dart' show ConnectionInvalidException;
import 'package:at_lookup/at_lookup.dart';
// Not in the barrel by design - decision 4 keeps the listener private
// to the package, so tests reach it by path as the fake socket does.
import 'package:at_lookup/src/connection/outbound_message_listener.dart';

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

    // The pair above pauses through the FAKE's handle on the subscription,
    // which proves the controller honours pause but says nothing about the
    // listener. These pause through the LISTENER, which is the handle
    // production code has - `listen()` used to discard its subscription, so
    // nothing in at_lookup could stop delivery at all.
    test('the listener can stop delivery through its own subscription',
        () async {
      final rig = FakeAtServerRig();
      String? got;
      unawaited(rig.listener
          .read(transientWaitTimeMillis: 5000, maxWaitMilliSeconds: 5000)
          .then((v) => got = v));
      await rig.socket.settle();

      expect(rig.listener.isDeliveryPaused, isFalse,
          reason: 'a fresh listener is delivering');
      rig.listener.pauseDelivery();
      expect(rig.socket.pauseCount, 1,
          reason: 'pauseDelivery must reach the socket, not just set a flag - '
              'if listen() discarded its subscription this is 0');
      expect(rig.listener.isDeliveryPaused, isTrue);

      await rig.socket.serverSends('data:held@alice\n@alice@');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(got, isNull,
          reason: 'bytes must not be delivered while the listener has paused '
              'its own subscription');

      rig.listener.resumeDelivery();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(rig.listener.isDeliveryPaused, isFalse);
      expect(got, 'data:held@alice',
          reason: 'and must arrive once the listener resumes');
    });

    test('pauses are counted, so two need two resumes', () async {
      // Measured, not assumed: StreamSubscription counts pauses. A design that
      // pairs one resume against two pauses leaves the socket stopped for
      // good, and the symptom is a hang with no error anywhere.
      final rig = FakeAtServerRig();

      rig.listener.pauseDelivery();
      rig.listener.pauseDelivery();
      rig.listener.resumeDelivery();
      expect(rig.listener.isDeliveryPaused, isTrue,
          reason: 'one resume must NOT undo two pauses');

      rig.listener.resumeDelivery();
      expect(rig.listener.isDeliveryPaused, isFalse,
          reason: 'the second resume balances the second pause');
    });

    test('resuming a listener that never paused is harmless', () async {
      final rig = FakeAtServerRig();

      rig.listener.resumeDelivery();

      expect(rig.listener.isDeliveryPaused, isFalse);
      await rig.socket.serverSends('data:fine@alice\n@alice@');
      expect(
          await rig.listener
              .read(maxWaitMilliSeconds: 500, transientWaitTimeMillis: 500),
          'data:fine@alice',
          reason: 'an unmatched resume must not disturb delivery');
    });

    test('pausing before listen() is a no-op, not a crash', () async {
      // The muxable wires pause/resume to a stream controller, and a listener
      // can be handed one before its socket exists. Null-safe by design.
      final socket = FakeAtServerSocket();
      final connection = OutboundConnectionImpl(socket);
      final listener = OutboundMessageListener(connection);

      expect(listener.isDeliveryPaused, isFalse);
      expect(() => listener.pauseDelivery(), returnsNormally);
      expect(() => listener.resumeDelivery(), returnsNormally);
      expect(socket.pauseCount, 0,
          reason: 'there is no subscription yet, so nothing to pause');
    });
  });

  group('a response with no colon', () {
    // The bare `@<atSign>@` that completes the handshake carries no colon, and
    // `_isValidResponse` accepts it, so it reaches `_stripPrompt`. Before the
    // guard, `substring(0, -1)` threw a RangeError inside the socket's data
    // handler; `runZonedGuarded` reported that as a socket error and destroyed
    // a healthy connection, and the caller saw only a timeout.
    test('comes back, and leaves the connection alive', () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('@alice@\n@alice@');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(rig.socket.destroyed, isFalse,
          reason: 'a colonless response must not destroy the connection - a '
              'RangeError raised in the data handler surfaces as a socket '
              'error and closes it');
      expect(rig.connection.getMetaData()!.isClosed, isFalse,
          reason: 'and must not mark the connection closed');
      expect(
          await rig.listener
              .read(maxWaitMilliSeconds: 500, transientWaitTimeMillis: 500),
          '@alice@',
          reason: 'the handshake prompt is a valid response and must be '
              'returned unchanged');
    });
  });

  group('the notification framing', () {
    // A verb response ends `\n@<atSign>@`; a notification is not a reply to
    // anything, so no prompt follows it and it ends at a bare `\n`. One
    // listener has to know both.
    test('a notification goes to onNotification, not to the verb queue',
        () async {
      final rig = FakeAtServerRig();
      final seen = <String>[];
      rig.listener.onNotification = seen.add;

      await rig.socket.serverSends('notification: {"id":"abc"}\n');
      expect(seen, ['notification: {"id":"abc"}']);

      // and the verb channel is undisturbed by it
      await rig.socket.serverSends('data:phone@alice\n@alice@');
      expect(
          await rig.listener
              .read(maxWaitMilliSeconds: 500, transientWaitTimeMillis: 500),
          'data:phone@alice');
      expect(seen, hasLength(1),
          reason: 'a verb response must not be delivered as a notification');
    });

    test('a data value containing newlines is not mistaken for one', () async {
      final rig = FakeAtServerRig();
      final seen = <String>[];
      rig.listener.onNotification = seen.add;

      await rig.socket
          .serverSends('data:the_key_is\n@bob:phone@alice\n@alice@');

      // Asserted before the read, so a listener that routes this away fails
      // here with the reason - not thirty seconds later on a starved read.
      expect(seen, isEmpty,
          reason: 'the test is on the buffer prefix, so a multi-line value '
              'still reads as data: and is never routed');
      expect(
          await rig.listener
              .read(maxWaitMilliSeconds: 500, transientWaitTimeMillis: 500),
          'data:the_key_is\n@bob:phone@alice');
    });

    test('two notifications in one packet are two, not one', () async {
      // The atServer has no reason to put one notification per TCP segment.
      // messageHandler's fast path appends everything up to the LAST newline
      // in bulk, so an intermediate newline never reaches the framing check
      // and both lines arrive fused into one string.
      final rig = FakeAtServerRig();
      final seen = <String>[];
      rig.listener.onNotification = seen.add;

      await rig.socket
          .serverSends('notification: {"id":"a"}\nnotification: {"id":"b"}\n');

      expect(seen, [
        'notification: {"id":"a"}',
        'notification: {"id":"b"}',
      ]);
    });

    test('a notification split across packets still arrives once', () async {
      final rig = FakeAtServerRig();
      final seen = <String>[];
      rig.listener.onNotification = seen.add;

      await rig.socket.serverSends('notification: {"id":');
      expect(seen, isEmpty, reason: 'incomplete - no newline yet');
      await rig.socket.serverSends('"split"}\n');

      expect(seen, ['notification: {"id":"split"}']);
    });

    test('with nothing installed, a notification poisons the next response',
        () async {
      // The behaviour the seam exists to fix, pinned so its absence is
      // visible: with no callback the notification bytes stay in the buffer
      // and prefix whatever the atServer says next, which then fails
      // _isValidResponse. This is why Monitor was given a listener of its own.
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('notification: {"id":"abc"}\n');
      await rig.socket.serverSends('data:after@alice\n@alice@');

      expect(
          () => rig.listener
              .read(maxWaitMilliSeconds: 500, transientWaitTimeMillis: 500),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorMessage == 'Unexpected response found')),
          reason: 'the unrouted notification is still in the buffer and is '
              'returned joined to the response that followed it');
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

  group('a request in flight when the connection goes away', () {
    /// A response can only arrive on the socket the listener is reading, so a
    /// connection that is gone can never produce one. Until `read` gives up it
    /// holds `AtLookupImpl.requestResponseMutex`, so every later request on the
    /// same instance queues behind a dead one for the whole transient budget.
    ///
    /// Each arm measures the WAIT, not the throw: the throw happens either way,
    /// and only its timing distinguishes "noticed the connection died" from
    /// "sat out the budget".
    Future<int> millisUntilReadFails(
      FakeAtServerRig rig,
      Future<void> Function() killIt,
    ) async {
      final sw = Stopwatch()..start();
      Object? thrown;
      final done = rig.listener.read(transientWaitTimeMillis: 3000).then<void>(
        (_) {},
        onError: (Object e) {
          thrown = e;
        },
      );
      await rig.socket.settle();

      await killIt();
      await done;
      sw.stop();

      expect(thrown, isA<ConnectionInvalidException>(),
          reason: 'the TYPE is the user-visible half of this fix: a caller '
              'told the connection went away can reconnect, where an '
              'AtTimeoutException sends it looking at the atServer. Asserting '
              'only that something was thrown leaves that swap unpinned - the '
              'timing bound below catches the mechanism being absent, not the '
              'wrong exception coming out of it');
      return sw.elapsedMilliseconds;
    }

    test('a locally closed connection fails the pending read at once',
        () async {
      final rig = FakeAtServerRig();

      final waited = await millisUntilReadFails(rig, rig.connection.close);

      expect(waited, lessThan(1000),
          reason: 'closing the connection from this side - what '
              'AtClientImpl.stop() does on every atSign switch - must fail the '
              'request in flight immediately. Waiting out the transient budget '
              'holds the request mutex, and the next request on this '
              'AtLookupImpl queues behind a response that can never come');
    });

    test('a far end that hangs up fails the pending read at once', () async {
      final rig = FakeAtServerRig();

      final waited = await millisUntilReadFails(rig, rig.socket.serverCloses);

      expect(waited, lessThan(1000),
          reason: 'onDone already closes the connection; the read waiting on '
              'that same socket must not then wait out its budget');
    });

    test('a far end that faults fails the pending read at once', () async {
      final rig = FakeAtServerRig();

      final waited = await millisUntilReadFails(
          rig, () => rig.socket.serverErrors(const SocketException('reset')));

      expect(waited, lessThan(1000),
          reason: 'onError already closes the connection; the read waiting on '
              'that same socket must not then wait out its budget');
    });

    test('a response already queued when the connection dies is still returned',
        () async {
      final rig = FakeAtServerRig();

      await rig.socket.serverSends('data:phone@alice\n@alice@');
      await rig.connection.close();

      expect(await rig.listener.read(transientWaitTimeMillis: 3000),
          'data:phone@alice',
          reason: 'the bytes arrived before the connection went away, so the '
              'caller is owed the response - aborting on a closed connection '
              'must not discard one already parsed');
    });
  });
}
