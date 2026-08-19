import 'dart:async';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
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

  late FakeAtServerSocket socket;
  late OutboundConnectionImpl connection;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;
  late MockSecureSocketListenerFactory listenerFactory;
  late MockOutboundConnectionFactory connectionFactory;

  setUp(() {
    socket = FakeAtServerSocket();
    connection = OutboundConnectionImpl(socket);
    addressFinder = MockSecondaryAddressFinder();
    socketFactory = MockSecureSocketFactory();
    listenerFactory = MockSecureSocketListenerFactory();
    connectionFactory = MockOutboundConnectionFactory();
    registerFallbackValue(SecureSocketConfig());

    final tokenSocket = createMockAtServerSocket(host, port);
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => socketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) => Future<SecureSocket>.value(tokenSocket));
    // The real connection, over the fake socket. The token SecureSocket above
    // only satisfies the factory chain and is never read from.
    when(() => connectionFactory.createOutboundConnection(tokenSocket))
        .thenAnswer((_) => connection);
    // The real listener, so the two framings actually run.
    when(() => listenerFactory.createListener(connection))
        .thenAnswer((_) => OutboundMessageListener(connection));
  });

  AtLookupImpl build() => AtLookupImpl('@alice', host, 64,
      secondaryAddressFinder: addressFinder,
      secureSocketFactory: socketFactory,
      socketListenerFactory: listenerFactory,
      outboundConnectionFactory: connectionFactory);

  /// An authenticator that succeeds without doing anything. `_authenticateWith`
  /// records the authentication itself, so returning true is enough to get
  /// past `monitor:`'s auth gate.
  AtLookupImpl authenticated() => build()..authenticator = (_) async => true;

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
