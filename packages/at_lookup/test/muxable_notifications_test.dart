import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_socket.dart';

/// [AtLookupMuxable] - the notification stream, over a REAL listener.
///
/// The factories are mocked only to get a [FakeAtServerSocket] underneath; the
/// connection, the listener and the framing are all production code, so a
/// notification here travels the same path it does against a live atServer.
/// A test that stubbed the listener would pass whether or not the framing
/// worked.
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  /// Every socket the factory has handed out, in order.
  ///
  /// A fresh one per connection, because reconnection is under test: a rig
  /// that returned the same destroyed socket would make a successful
  /// reconnect indistinguishable from a failed one.
  late List<FakeAtServerSocket> sockets;

  /// The socket currently in use - the most recent one the factory handed out.
  late FakeAtServerSocket socket;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;

  setUp(() {
    sockets = [];
    addressFinder = MockSecondaryAddressFinder();
    socketFactory = MockSecureSocketFactory();
    registerFallbackValue(SecureSocketConfig());

    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    // The ONE injection point: a fresh fake socket per connection, reaching
    // the muxable through the factory's `transport` parameter. Everything
    // above it - the connection, the listener, both framings, reconnect - is
    // production code, so a notification here travels the path it travels
    // live. A fresh socket per call because reconnection is under test: reuse
    // a destroyed one and a successful reconnect looks like a failed one.
    when(() => socketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) async {
      final s = FakeAtServerSocket();
      sockets.add(s);
      socket = s;
      return s;
    });
  });

  /// Built through the FACTORY, and held as the INTERFACE.
  ///
  /// Not a stylistic choice: this is the shape every caller has at the end of
  /// this project, so testing through it is what proves the factory produces
  /// something fully usable without naming the concrete class. Reaching for
  /// `AtLookupImpl(...)` here would test a constructor the plan is retiring
  /// and would leave the factory's own seam unexercised.
  AtLookupMuxable build({AtAuthenticator? authenticator}) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        secureSocketConfig: SecureSocketConfig(),
        authenticator: authenticator,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(socketFactory: socketFactory),
      );

  /// An authenticator that succeeds without doing anything. `_authenticateWith`
  /// records the authentication itself, so returning true is enough to get
  /// past `monitor:`'s auth gate.
  AtLookupMuxable authenticated() => build(authenticator: (_) async => true);

  group('the notification stream', () {
    test('a notification from the atServer arrives on it', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      final seen = <String>[];
      atLookup.notifications.listen(seen.add);

      await socket.serverSends('notification: {"id":"n1"}\n');
      await socket.settle();

      expect(seen, ['notification: {"id":"n1"}']);
    });

    test('notifications arriving BEFORE a listener attaches are not lost',
        () async {
      // The single-subscription property, and the reason for it. A broadcast
      // controller drops everything sent before someone subscribes, and a
      // dropped notification is indistinguishable from one never sent.
      final atLookup = authenticated();
      await atLookup.startNotifications();

      await socket.serverSends('notification: {"id":"early"}\n');
      await socket.settle();

      final seen = <String>[];
      atLookup.notifications.listen(seen.add);
      await socket.settle();

      expect(seen, ['notification: {"id":"early"}'],
          reason: 'a buffered notification must be delivered on subscribe - '
              'this is exactly what a broadcast controller would have lost');
    });

    test('it is single-subscription, so a second listener is refused',
        () async {
      final atLookup = authenticated();
      atLookup.notifications.listen((_) {});

      expect(() => atLookup.notifications.listen((_) {}), throwsStateError,
          reason: 'a broadcast stream would accept this, and with it lose '
              'buffering and pause');
    });

    test('a verb response is not delivered as a notification', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      final seen = <String>[];
      atLookup.notifications.listen(seen.add);

      await socket.serverSends('data:the_key_is\n@bob:phone@alice\n@alice@');
      await socket.settle();

      expect(seen, isEmpty,
          reason: 'a multi-line data value still reads as data: on its prefix, '
              'so it is never routed to the notification stream');
    });
  });

  group('back-pressure reaches the socket through the stream', () {
    test('pausing the notification stream pauses the socket', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      final seen = <String>[];
      final sub = atLookup.notifications.listen(seen.add);
      await socket.settle();

      sub.pause();
      await socket.settle();
      expect(socket.pauseCount, greaterThanOrEqualTo(1),
          reason: 'pausing the notification stream must reach the SOCKET, not '
              'merely buffer in this process - onPause is wired through to '
              'the listener, which pauses its subscription');

      sub.resume();
      await socket.settle();
      await socket.serverSends('notification: {"id":"after"}\n');
      await socket.settle();
      expect(seen, ['notification: {"id":"after"}'],
          reason: 'and resuming must restore delivery');

      await sub.cancel();
    });
  });

  group('startNotifications', () {
    test('sends monitor: with selfNotifications, and NOT multiplexed',
        () async {
      // A RAW-LITERAL wire pin. `multiplexed` is accepted by the shared verb
      // syntax and read by no atServer - measured against at_server
      // origin/trunk, zero occurrences - so setting it would advertise an
      // interlock that does not exist, and the atServer would not refuse it.
      final atLookup = authenticated();

      await atLookup.startNotifications(lastNotificationTime: 1755600000000);

      expect(socket.written, ['monitor:selfNotifications:1755600000000\n']);
      expect(socket.written.single, isNot(contains('multiplexed')),
          reason: 'no atServer implements this flag; sending it would claim a '
              'safety property that is not there');
      expect(atLookup.isNotifying, isTrue);
    });

    test('a regex is passed through', () async {
      final atLookup = authenticated();

      await atLookup.startNotifications(regex: '.wavi');

      expect(socket.written, ['monitor:selfNotifications .wavi\n']);
    });

    test('called twice, it sends once', () async {
      final atLookup = authenticated();

      await atLookup.startNotifications();
      await atLookup.startNotifications();

      expect(socket.written, hasLength(1),
          reason: 'a second monitor: on the same connection would duplicate '
              'every notification');
    });

    test('it refuses when nothing can authenticate', () async {
      // No authenticator, and the ladder has no credential either.
      final atLookup = build();

      expect(() => atLookup.startNotifications(),
          throwsA(isA<UnAuthenticatedException>()),
          reason: 'monitor requires authentication; failing loudly beats a '
              'connection that silently never receives anything');
    });
  });

  group('reconnect, reauth and heartbeat', () {
    test('losing the connection reconnects, reauthenticates, and re-issues '
        'the SAME monitor:', () async {
      var authCount = 0;
      final atLookup = build(authenticator: (_) async {
        authCount++;
        return true;
      })
        // Parked, so this test measures reconnection and not the probe.
        ..heartbeatInterval = const Duration(hours: 1);

      await atLookup.startNotifications(
          regex: '.wavi', lastNotificationTime: 1755600000000);
      expect(sockets, hasLength(1));
      expect(authCount, 1);
      final first = socket;
      expect(first.written, ['monitor:selfNotifications:1755600000000 .wavi\n']);

      // The far end goes away.
      await first.serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atLookup.isReconnectingNotifications, isTrue,
          reason: 'the listener must tell the muxable the socket died - '
              'without the onDisconnect seam nothing here ever learns it');

      // First delay in the backoff is 1s.
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(sockets, hasLength(2),
          reason: 'a new connection must have been opened');
      expect(authCount, 2,
          reason: 'the new connection is unauthenticated, so the authenticator '
              'must run again - reconnecting without reauthenticating gives a '
              'socket the atServer will not send notifications on');
      expect(socket.written, ['monitor:selfNotifications:1755600000000 .wavi\n'],
          reason: 'the reconnect must re-issue the SAME monitor: - dropping '
              'the regex would start delivering everything, and dropping the '
              'watermark would replay from the beginning');
      expect(atLookup.isReconnectingNotifications, isFalse,
          reason: 'and the loop must finish once it succeeds');

      await atLookup.stopNotifications();
    });

    test('notifications flow again on the reconnected socket', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications();
      final seen = <String>[];
      atLookup.notifications.listen(seen.add);

      await socket.serverCloses();
      await Future.delayed(const Duration(milliseconds: 1400));
      await socket.serverSends('notification: {"id":"after-reconnect"}\n');
      await socket.settle();

      expect(seen, ['notification: {"id":"after-reconnect"}'],
          reason: 'the framing seam must be re-installed on the NEW listener - '
              'createConnection builds a fresh one, so a seam wired only at '
              'startup would go quiet after the first outage');

      await atLookup.stopNotifications();
    });

    test('stopNotifications ends the reconnect loop', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications();

      await socket.serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atLookup.isReconnectingNotifications, isTrue);

      await atLookup.stopNotifications();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(sockets, hasLength(1),
          reason: 'a reconnect landing after stopNotifications would resurrect '
              'the connection the caller just asked to be rid of');
    });

    test('the heartbeat probes a quiet connection with noop:0', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 40);
      await atLookup.startNotifications();
      final s = socket;
      expect(s.written, hasLength(1), reason: 'just the monitor: so far');

      await Future.delayed(const Duration(milliseconds: 90));

      expect(s.written.last, 'noop:0\n',
          reason: 'a connection that only ever reads cannot tell a quiet '
              'atServer from a dead socket');
      await s.serverSends('data:ok\n@alice@');
      await atLookup.stopNotifications();
    });

    test('an unanswered heartbeat starts recovery', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 30)
        ..heartbeatResponseTimeout = const Duration(milliseconds: 60);
      await atLookup.startNotifications();
      final s = socket;

      // Probe goes out at ~30ms, times out at ~90ms, closes the connection,
      // whose onDone drives the disconnect seam.
      await Future.delayed(const Duration(milliseconds: 300));

      expect(s.destroyed, isTrue,
          reason: 'an unanswered probe must close the connection');
      expect(atLookup.isReconnectingNotifications, isTrue,
          reason: 'and closing it must start the reconnect loop - closing '
              'without reconnecting leaves a listener that is silent forever');

      await atLookup.stopNotifications();
    });
  });

  group('stopNotifications', () {
    test('closes the stream and the connection', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      var done = false;
      atLookup.notifications.listen((_) {}, onDone: () => done = true);
      await socket.settle();

      await atLookup.stopNotifications();
      await socket.settle();

      expect(atLookup.isNotifying, isFalse);
      expect(done, isTrue,
          reason: 'a stream that can never produce another event must close, '
              'not hang');
      expect(socket.destroyed, isTrue);
    });
  });
}
