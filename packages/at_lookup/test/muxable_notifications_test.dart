import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Captures what at_lookup logs, so a claim about a level is asserted.
///
/// Installed from `setUpAll`, before any lookup is built: each instance binds
/// the default handler as it stands when its logger is constructed.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records
      .add((level: '${record.level.name}', message: '${record.message}'));

  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);
}

/// [AtLookupMuxable] - the notification stream, over a REAL listener.
///
/// The factories are mocked only to get a [FakeAtServerTransport] underneath; the
/// connection, the listener and the framing are all production code, so a
/// notification here travels the same path it does against a live atServer.
/// A test that stubbed the listener would pass whether or not the framing
/// worked.
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  final recorded = _RecordedLogs();

  setUpAll(() {
    AtSignLogger.root_level = 'info';
    AtSignLogger.defaultLoggingHandler = recorded;
  });

  late MockSecondaryAddressFinder addressFinder;

  /// The ONE injection point. Everything above it - the connection, the
  /// listener, both framings, reconnect - is production code, so a
  /// notification here travels the path it travels live.
  late FakeAtServerTransportFactory transportFactory;

  /// Every transport the factory has handed out, in order.
  ///
  /// A fresh one per connection, because reconnection is under test: a rig
  /// that returned the same destroyed transport would make a successful
  /// reconnect indistinguishable from a failed one.
  List<FakeAtServerTransport> transports() => transportFactory.created;

  /// The transport currently in use - the most recent one handed out.
  FakeAtServerTransport transport() => transportFactory.last;

  setUp(() {
    addressFinder = MockSecondaryAddressFinder();
    transportFactory = FakeAtServerTransportFactory();

    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  /// Built through the FACTORY, and held as the INTERFACE.
  ///
  /// Not a stylistic choice: this is the shape every caller has at the end of
  /// this project, so testing through it is what proves the factory produces
  /// something fully usable without naming the concrete class. Reaching for
  /// `AtLookupImpl(...)` here would leave the factory's own seam unexercised.
  AtLookupMuxable build({AtAuthenticator? authenticator}) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: authenticator,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(
          transportFactory: transportFactory,
        ),
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

      await transport().serverSends('notification: {"id":"n1"}\n');
      await transport().settle();

      expect(seen, ['notification: {"id":"n1"}']);
    });

    test('notifications arriving BEFORE a listener attaches are not lost',
        () async {
      // The single-subscription property, and the reason for it. A broadcast
      // controller drops everything sent before someone subscribes, and a
      // dropped notification is indistinguishable from one never sent.
      final atLookup = authenticated();
      await atLookup.startNotifications();

      await transport().serverSends('notification: {"id":"early"}\n');
      await transport().settle();

      final seen = <String>[];
      atLookup.notifications.listen(seen.add);
      await transport().settle();

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

      await transport()
          .serverSends('data:the_key_is\n@bob:phone@alice\n@alice@');
      await transport().settle();

      expect(seen, isEmpty,
          reason: 'a multi-line data value still reads as data: on its prefix, '
              'so it is never routed to the notification stream');
    });
  });

  group('back-pressure reaches the transport() through the stream', () {
    test('pausing the notification stream pauses the transport()', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      final seen = <String>[];
      final sub = atLookup.notifications.listen(seen.add);
      await transport().settle();

      sub.pause();
      await transport().settle();
      expect(transport().pauseCount, greaterThanOrEqualTo(1),
          reason: 'pausing the notification stream must reach the SOCKET, not '
              'merely buffer in this process - onPause is wired through to '
              'the listener, which pauses its subscription');

      sub.resume();
      await transport().settle();
      await transport().serverSends('notification: {"id":"after"}\n');
      await transport().settle();
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

      await atLookup.startNotifications(
          getLastNotificationTime: () async => 1755600000000);

      expect(
          transport().written, ['monitor:selfNotifications:1755600000000\n']);
      expect(transport().written.single, isNot(contains('multiplexed')),
          reason: 'no atServer implements this flag; sending it would claim a '
              'safety property that is not there');
      expect(atLookup.isNotifying, isTrue);
    });

    test('a regex is passed through', () async {
      final atLookup = authenticated();

      await atLookup.startNotifications(regex: '.wavi');

      expect(transport().written, ['monitor:selfNotifications .wavi\n']);
    });

    test('called twice, it sends once', () async {
      final atLookup = authenticated();

      await atLookup.startNotifications();
      await atLookup.startNotifications();

      expect(transport().written, hasLength(1),
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
    test(
        'losing the connection reconnects, reauthenticates, and re-issues '
        'monitor: with the same regex', () async {
      var authCount = 0;
      final atLookup = build(authenticator: (_) async {
        authCount++;
        return true;
      })
        // Parked, so this test measures reconnection and not the probe.
        ..heartbeatInterval = const Duration(hours: 1);

      await atLookup.startNotifications(
          regex: '.wavi', getLastNotificationTime: () async => 1755600000000);
      expect(transports(), hasLength(1));
      expect(authCount, 1);
      final first = transport();
      expect(
          first.written, ['monitor:selfNotifications:1755600000000 .wavi\n']);

      // The far end goes away.
      await first.serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atLookup.isReconnectingNotifications, isTrue,
          reason: 'the listener must tell the muxable the transport() died - '
              'without the onDisconnect seam nothing here ever learns it');

      // First delay in the backoff is 1s.
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(transports(), hasLength(2),
          reason: 'a new connection must have been opened');
      expect(authCount, 2,
          reason: 'the new connection is unauthenticated, so the authenticator '
              'must run again - reconnecting without reauthenticating gives a '
              'transport() the atServer will not send notifications on');
      expect(transport().written,
          ['monitor:selfNotifications:1755600000000 .wavi\n'],
          reason: 'the regex is REMEMBERED across a reconnect - dropping it '
              'would start delivering everything. The watermark beside it is '
              'not remembered but re-asked, and this callback returns a '
              'constant, so the command matches; the advancing case is its '
              'own test');
      expect(atLookup.isReconnectingNotifications, isFalse,
          reason: 'and the loop must finish once it succeeds');

      await atLookup.stopNotifications();
    });

    test('notifications flow again on the reconnected transport()', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications();
      final seen = <String>[];
      atLookup.notifications.listen(seen.add);

      await transport().serverCloses();
      await Future.delayed(const Duration(milliseconds: 1400));
      await transport().serverSends('notification: {"id":"after-reconnect"}\n');
      await transport().settle();

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

      await transport().serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atLookup.isReconnectingNotifications, isTrue);

      await atLookup.stopNotifications();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(transports(), hasLength(1),
          reason: 'a reconnect landing after stopNotifications would resurrect '
              'the connection the caller just asked to be rid of');
    });

    test('the heartbeat probes a quiet connection with noop:0', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 40);
      await atLookup.startNotifications();
      final s = transport();
      expect(s.written, hasLength(1), reason: 'just the monitor: so far');

      await Future.delayed(const Duration(milliseconds: 90));

      expect(s.written.last, 'noop:0\n',
          reason: 'a connection that only ever reads cannot tell a quiet '
              'atServer from a dead transport()');
      await s.serverSends('data:ok\n@alice@');
      await atLookup.stopNotifications();
    });

    test('an answered heartbeat logs when the last notification arrived',
        () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 40)
        ..heartbeatResponseTimeout = const Duration(seconds: 5);
      await atLookup.startNotifications();
      atLookup.notifications.listen((_) {});
      final s = transport();

      final before = DateTime.now().toUtc();
      await s.serverSends('notification: {"id":"n1"}\n');
      await s.settle();
      final after = DateTime.now().toUtc();

      for (var i = 0; i < 50 && s.written.last != 'noop:0\n'; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(s.written.last, 'noop:0\n', reason: 'the probe must be out');
      // Answered well after the notification, so a line stamped with the time
      // the heartbeat was answered would fall outside [before, after].
      await Future.delayed(const Duration(milliseconds: 150));
      recorded.records.clear();
      await s.serverSends('data:ok\n@alice@');
      await s.settle();

      // Raw literal: noports operators grep logs for this wording, which is
      // at_client's Monitor's, so a change to it is a change they notice.
      final heartbeatOk = RegExp(r'^Heartbeat OK: lastReceipt (\S+ \S+)$');
      final logged = recorded
          .at('INFO')
          .map(heartbeatOk.firstMatch)
          .whereType<RegExpMatch>()
          .toList();
      expect(logged, hasLength(1),
          reason: 'one answered heartbeat, one line, at info');
      final lastReceipt = DateTime.parse(logged.single.group(1)!);
      expect(lastReceipt.isUtc, isTrue);
      expect(
          !lastReceipt.isBefore(before) && !lastReceipt.isAfter(after), isTrue,
          reason: 'the time is when the notification arrived '
              '($before to $after), not when the heartbeat was answered; '
              'got $lastReceipt');
      await atLookup.stopNotifications();
    });

    test('an unanswered heartbeat starts recovery', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 30)
        ..heartbeatResponseTimeout = const Duration(milliseconds: 60);
      await atLookup.startNotifications();
      final s = transport();

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

    test('a paused subscriber does not lose its connection to the heartbeat',
        () async {
      // Pausing is the back-pressure contract this stream advertises, not
      // misuse - and a paused subscription stops the transport() being read, so
      // nothing can fill the read queue and a probe could never be answered.
      // Probing anyway times the read out and destroys a healthy connection.
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(milliseconds: 30)
        ..heartbeatResponseTimeout = const Duration(milliseconds: 60);
      await atLookup.startNotifications();
      final s = transport();
      final states = <bool>[];
      atLookup.notificationConnectionUp.listen(states.add);

      final sub = atLookup.notifications.listen((_) {});
      sub.pause();
      // Several intervals and several response budgets.
      await Future.delayed(const Duration(milliseconds: 300));

      expect(s.written.where((w) => w.startsWith('noop:')), isEmpty,
          reason: 'the probe must be SKIPPED while delivery is paused. This '
              'is the mechanism: asserting only that the transport() survived '
              'would pass even if a probe went out and happened to be '
              'answered');
      expect(s.destroyed, isFalse,
          reason: 'a subscriber applying back-pressure must not have its '
              'connection torn down underneath it');
      expect(states, isNot(contains(false)),
          reason: 'and must not be told the connection went down');

      sub.resume();
      await atLookup.stopNotifications();
    });

    test('a restart replaces the connection-up stream, it does not reuse it',
        () async {
      // stopNotifications closes this stream. A caller that held one
      // subscription across a stop/start would be listening to a closed
      // stream and would never learn the new connection came up - so the
      // contract is that both streams are re-read after each start, and this
      // pins it rather than leaving it to the dartdoc alone.
      final atLookup = authenticated();
      // Registered up front: a failing expect below would otherwise skip the
      // teardown and leave a live reconnect loop, which then builds transports()
      // into the NEXT test's list through the shared factory.
      addTearDown(atLookup.stopNotifications);

      await atLookup.startNotifications();
      final before = <bool>[];
      var beforeClosed = false;
      atLookup.notificationConnectionUp
          .listen(before.add, onDone: () => beforeClosed = true);
      await transport().settle();

      await atLookup.stopNotifications();
      await transport().settle();
      expect(beforeClosed, isTrue,
          reason: 'the stop must close the stream, which is what makes the '
              'old subscription useless rather than merely silent');
      // The stop emits its own `false` before closing, so this subscriber has
      // seen its own session end. What it must never see is anything about
      // the session that follows.
      final seenByStopTime = before.length;

      await atLookup.startNotifications();
      final after = <bool>[];
      atLookup.notificationConnectionUp.listen(after.add);
      await transport().serverCloses();
      await transport().settle();

      expect(after, contains(false),
          reason: 'a subscription taken after the restart tracks the new '
              'connection');
      expect(before, hasLength(seenByStopTime),
          reason: 'and the pre-stop subscription learns nothing about the new '
              'connection - the reason a caller must re-read the getter after '
              'each start');
    });

    test('a watermark read that throws does not leave the client deaf',
        () async {
      // This callback is CALLER code running inside the reconnect loop. If it
      // throws and the attempt aborts, the connection it already opened and
      // authenticated stays valid - so every later attempt skips the connect,
      // re-runs only this call, and backs off forever with `monitor:` never
      // sent. The symptom is nothing at all: no notifications, no error, just
      // an `up` that never arrives.
      var boom = false;
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      addTearDown(atLookup.stopNotifications);

      await atLookup.startNotifications(getLastNotificationTime: () async {
        if (boom) throw StateError('watermark store unreadable');
        return 1755600000000;
      });
      expect(
          transport().written, ['monitor:selfNotifications:1755600000000\n']);

      boom = true;
      await transport().serverCloses();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(transports(), hasLength(2),
          reason: 'the attempt must have reached the point of opening a '
              'transport(), or this proves nothing about what follows the connect');
      expect(transports().last.written, ['monitor:selfNotifications\n'],
          reason: 'a failed watermark read must still send monitor: - without '
              'one the atServer replays a window, which is recoverable, where '
              'sending nothing is a connection that can never deliver');
      expect(atLookup.isReconnectingNotifications, isFalse,
          reason: 'and the reconnect must be considered finished, not left '
              'spinning on a connection it will never speak to');

      // The control arm: the same callback recovering must behave normally,
      // so this cannot pass by the watermark being ignored altogether.
      boom = false;
      await transports().last.serverCloses();
      await Future.delayed(const Duration(milliseconds: 1400));
      expect(transports().last.written,
          ['monitor:selfNotifications:1755600000000\n'],
          reason: 'a transient watermark failure is not terminal');
    });

    test('a reconnect asks the caller for its CURRENT watermark', () async {
      // The caller's position moves as it consumes notifications, and it is
      // the caller that holds it durably. Freezing the value at
      // startNotifications makes every reconnect re-request the whole retained
      // backlog — which is exactly what a caller keeping a watermark is
      // keeping one to avoid.
      var watermark = 1755600000000;
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications(
          getLastNotificationTime: () async => watermark);
      final first = transport();
      expect(first.written, ['monitor:selfNotifications:1755600000000\n']);

      // The caller consumes notifications and advances; then the far end goes.
      watermark = 1755600009999;
      await first.serverCloses();
      await first.settle();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(transports(), hasLength(2),
          reason: 'the test needs an actual reconnect to have happened');
      expect(transports().last.written,
          ['monitor:selfNotifications:1755600009999\n'],
          reason: 'the reconnect must carry where the caller has got to, not '
              'where it was when notifications started');

      await atLookup.stopNotifications();
    });

    test('a restart inside the backoff window is not disturbed by the old loop',
        () async {
      // stopNotifications puts `_isNotifying` back to false and a following
      // startNotifications puts it back to true - so a reconnect loop still
      // sleeping from before the stop wakes to a flag that says "carry on",
      // and would act on the connection the RESTART established: a second
      // `monitor:` on a live transport(), its heartbeat reset, and an `up` with no
      // preceding down.
      final atLookup = authenticated();
      await atLookup.startNotifications();

      // Drop the connection so a reconnect loop starts and parks on its
      // first backoff (1s), then stop and restart well inside that window.
      await transport().serverCloses();
      await transport().settle();
      expect(atLookup.isReconnectingNotifications, isTrue,
          reason: 'the test needs a loop actually sleeping, or it proves '
              'nothing about what happens when one wakes');

      await atLookup.stopNotifications();
      expect(atLookup.isReconnectingNotifications, isFalse,
          reason: 'a stop must not leave this reading true - it is what '
              'disarms the disconnect handler on the next connection');

      await atLookup.startNotifications();
      final restarted = transport();
      final states = <bool>[];
      atLookup.notificationConnectionUp.listen(states.add);

      // Past the first backoff, so the orphaned loop has woken.
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(restarted.written.where((w) => w.startsWith('monitor:')),
          hasLength(1),
          reason: 'the restart sent its own monitor:; a loop from the '
              'previous session must not send a second one on this transport()');
      expect(states, isNot(contains(true)),
          reason: 'and must not announce an `up` the restart already made');

      await atLookup.stopNotifications();
    });

    test('dropConnection() fails a pending read even while delivery is paused',
        () async {
      // The case `_closeConnection`'s own dartdoc names: with delivery paused
      // the transport()'s done event is buffered, so the onDone route that fails a
      // pending read never runs, and the abort inside `_closeConnection` is
      // the only thing left. A test that closes while delivery is live cannot
      // see that - onDone gets there first and the abort could be deleted
      // without anything going red.
      final atLookup = authenticated();
      await atLookup.pkamAuthenticate();
      await atLookup.startNotifications();
      final sub = atLookup.notifications.listen((_) {});
      sub.pause();
      recorded.records.clear();

      Object? thrown;
      final pending = atLookup.executeCommand('noop:0\n').then<void>(
            (_) {},
            onError: (Object e) => thrown = e,
          );
      await Future.delayed(const Duration(milliseconds: 50));

      await atLookup.dropConnection();
      await pending.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('the pending read was never failed, so it is '
              'sitting out its transient budget holding the request mutex - '
              'the next request on this instance would queue behind a '
              'response that can never arrive'));

      expect(thrown, isNotNull,
          reason: 'closing must fail the request in flight, and while paused '
              'only the abort inside _closeConnection can do it');
      expect(
          thrown,
          isA<ConnectionInvalidException>().having(
              (e) => e.message,
              'message',
              'The connection was closed by this client before a response '
                  'arrived'),
          reason: 'this side closed it on purpose, and the failure says so '
              'rather than sending the caller to look at the network');
      expect(
          recorded.at('INFO'),
          contains(contains(
              'Connection closed by this client with a request in flight')),
          reason: 'the abort is logged once, where it is decided');
      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'a close this client asked for is not an error in sending '
              'to the server, and at_lookup used to log it as one twice');

      sub.resume();
      await atLookup.close();
    });

    test('a connection built before the stream is read still reconnects',
        () async {
      // The ordering the `notifications` getter exists for: authenticating -
      // or any verb - builds the connection while no controller exists, so
      // createConnection installs no seams at all. Reading the stream
      // afterwards has to install BOTH of them. With only the routing seam,
      // the transport() going away reaches nothing and the muxable never learns it
      // is down.
      final atLookup = authenticated();
      await atLookup.pkamAuthenticate();
      await atLookup.startNotifications();
      final states = <bool>[];
      atLookup.notificationConnectionUp.listen(states.add);

      await transport().serverCloses();
      await transport().settle();

      expect(states, contains(false),
          reason: 'the disconnect seam must be installed by the stream getter '
              'as well as by createConnection - without it a connection built '
              'before the first read goes down in silence');
      expect(atLookup.isReconnectingNotifications, isTrue,
          reason: 'and losing it must start the reconnect loop');

      await atLookup.stopNotifications();
    });
  });

  group('a connection that cannot be established', () {
    // Ported from at_client's monitor_test.dart, which asserted the same
    // behaviour on machinery that now lives here: a monitor that cannot
    // connect must not report itself as listening. The failure has to surface
    // rather than be swallowed, or a permanently deaf client looks healthy.
    test('a failure to connect surfaces, and reports nothing as up', () async {
      final atLookup = authenticated();
      final seen = <bool>[];
      atLookup.notificationConnectionUp.listen(seen.add);
      transportFactory.connectFailure = SecondaryConnectException('refused');

      await expectLater(
          atLookup.startNotifications(), throwsA(isA<Exception>()));

      expect(atLookup.isNotifying, isFalse,
          reason: 'a connection that never opened is not notifying');
      expect(seen, isEmpty,
          reason: 'nothing may report the connection up - a subscriber that '
              'saw `true` here would wait forever for notifications on a '
              'transport() that does not exist');
    });

    test('a failure to send monitor: surfaces the same way', () async {
      final atLookup = authenticated();
      final seen = <bool>[];
      atLookup.notificationConnectionUp.listen(seen.add);
      // Connect succeeds; the write does not. at_client's monitor_test had
      // this as "secondary reachable but rejecting commands".
      transportFactory.onCreate = (t) => t.failWrites = true;

      await expectLater(
          atLookup.startNotifications(), throwsA(isA<Exception>()));

      expect(atLookup.isNotifying, isFalse);
      expect(seen, isEmpty);
    });
  });

  group('notificationConnectionUp', () {
    test('reports up on start, down on loss, up again on reconnect', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      // Subscribed BEFORE the trigger: it is a broadcast stream, so it does
      // not replay, and a listener attached afterwards sees nothing.
      final seen = <bool>[];
      atLookup.notificationConnectionUp.listen(seen.add);

      await atLookup.startNotifications();
      await transport().settle();
      expect(seen, [true], reason: 'monitor: accepted on a live connection');

      await transport().serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(seen, [true, false],
          reason: 'the muxable owns reconnection, so it is the only thing that '
              'knows the connection dropped - a subscriber cannot tell an '
              'outage from a quiet atServer any other way');

      await Future.delayed(const Duration(milliseconds: 1400));
      expect(seen, [true, false, true],
          reason: 'and it must say so again when the reconnect succeeds');

      await atLookup.stopNotifications();
    });

    test('reports down when notifications are stopped', () async {
      final atLookup = authenticated()
        ..heartbeatInterval = const Duration(hours: 1);
      final seen = <bool>[];
      atLookup.notificationConnectionUp.listen(seen.add);

      await atLookup.startNotifications();
      await transport().settle();
      await atLookup.stopNotifications();
      await transport().settle();

      expect(seen, [true, false],
          reason: 'a deliberate stop is still a transition a subscriber must '
              'see - otherwise it reads as a connection that is still up');
    });
  });

  group('stopNotifications', () {
    test('closes the stream and the connection', () async {
      final atLookup = authenticated();
      await atLookup.startNotifications();
      var done = false;
      atLookup.notifications.listen((_) {}, onDone: () => done = true);
      await transport().settle();

      await atLookup.stopNotifications();
      await transport().settle();

      expect(atLookup.isNotifying, isFalse);
      expect(done, isTrue,
          reason: 'a stream that can never produce another event must close, '
              'not hang');
      expect(transport().destroyed, isTrue);
    });
  });

  group('a reconnect the atServer refuses', () {
    late List<Duration> defaultReconnects;

    // Distinct at every index, so each delay taken names the schedule it came
    // from.
    const network = [
      Duration(milliseconds: 10),
      Duration(milliseconds: 11),
      Duration(milliseconds: 12),
    ];
    const refusal = [
      Duration(milliseconds: 20),
      Duration(milliseconds: 21),
      Duration(milliseconds: 22),
      Duration(milliseconds: 23),
    ];

    setUp(() {
      defaultReconnects = AtLookupImpl.notificationReconnectDelays;
      AtLookupImpl.notificationReconnectDelays = network;
    });

    tearDown(() {
      AtLookupImpl.notificationReconnectDelays = defaultReconnects;
    });

    UnAuthenticatedException refusedByAtServer() =>
        UnAuthenticatedException('Failed connecting to @alice. '
            'error:AT0027:enrollment_id: e1 is revoked');

    /// Answers each authentication with the next of [outcomes], and accepts
    /// once they run out.
    AtAuthenticator scripted(List<_Attempt> outcomes) {
      var next = 0;
      return (_) async {
        final outcome =
            next < outcomes.length ? outcomes[next++] : _Attempt.accept;
        switch (outcome) {
          case _Attempt.accept:
            return true;
          case _Attempt.refuse:
            throw refusedByAtServer();
          case _Attempt.timeOut:
            throw AtTimeoutException('Waited for 10 millis. No response');
        }
      };
    }

    /// A lookup authenticating with [outcomes], waiting on [afterRefusal]
    /// after a refusal and recording into [taken] the delay chosen before each
    /// reconnect attempt.
    AtLookupMuxable recording(List<_Attempt> outcomes, List<Duration> taken,
        {List<Duration> afterRefusal = refusal}) {
      final atLookup = build(authenticator: scripted(outcomes))
        ..heartbeatInterval = const Duration(hours: 1);
      (atLookup as AtLookupImpl)
        ..onNotificationReconnectDelay = taken.add
        ..refusalReconnectDelays = afterRefusal;
      addTearDown(atLookup.stopNotifications);
      return atLookup;
    }

    Future<void> until(bool Function() condition, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('$what did not happen within 5 seconds');
        }
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    Duration ms(int n) => Duration(milliseconds: n);

    test(
        'a refused attempt is followed by a wait from the refusal schedule, '
        'for as long as the refusals last', () async {
      final taken = <Duration>[];
      final atLookup = recording([
        _Attempt.accept,
        ...List.filled(6, _Attempt.refuse),
      ], taken);
      atLookup.notifications.listen((_) {}, onError: (_) {});
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 7 && !atLookup.isReconnectingNotifications,
          'six refused reconnects and the accepted one');

      expect(taken, [ms(10), ms(21), ms(22), ms(23), ms(23), ms(23), ms(23)],
          reason: 'the first wait follows the drop, from the network '
              'schedule; every wait after a refusal is from the refusal '
              'schedule at the same attempt count, holding at its last entry '
              'once the attempts outnumber it');
      expect(atLookup.isNotifying, isTrue,
          reason: 'refusals never end reconnecting: the seventh attempt was '
              'accepted');

      await transport().serverCloses();
      await until(
          () => taken.length == 8 && !atLookup.isReconnectingNotifications,
          'the reconnect after a second drop');
      expect(taken.last, ms(10),
          reason: 'an accepted reconnect resets the count, so the next outage '
              'starts again from the first network delay');
    });

    test(
        'a failure that is not a refusal is followed by a wait from the '
        'network schedule', () async {
      final taken = <Duration>[];
      final atLookup = recording([
        _Attempt.accept,
        _Attempt.timeOut,
        _Attempt.refuse,
        _Attempt.timeOut,
        _Attempt.timeOut,
      ], taken);
      atLookup.notifications.listen((_) {}, onError: (_) {});
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 5 && !atLookup.isReconnectingNotifications,
          'four failed reconnects and the accepted one');

      expect(taken, [ms(10), ms(11), ms(22), ms(12), ms(12)],
          reason: 'only the wait straight after the refusal comes from the '
              'refusal schedule; after a timeout the wait is from the network '
              'schedule, held at its own last entry');
    });

    test(
        'refusals after more failures than the network schedule holds wait '
        'from the step past its last, longer after each refusal', () async {
      final taken = <Duration>[];
      final atLookup = recording(
          [
            _Attempt.accept,
            ...List.filled(4, _Attempt.timeOut),
            ...List.filled(3, _Attempt.refuse),
          ],
          taken,
          afterRefusal: [
            for (final n in [20, 21, 22, 23, 24, 25]) ms(n),
          ]);
      atLookup.notifications.listen((_) {}, onError: (_) {});
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 8 && !atLookup.isReconnectingNotifications,
          'four timed-out and three refused reconnects, and the accepted one');

      expect(taken.take(5), [ms(10), ms(11), ms(12), ms(12), ms(12)],
          reason: 'the timeouts wait on the network schedule, held at its '
              'last entry');
      expect(taken.skip(5), [ms(23), ms(24), ms(25)],
          reason: 'the first refusal waits one step past the network '
              'schedule\'s last, not as far along the refusal schedule as the '
              'attempts so far would reach, and each refusal after it waits '
              'longer');
    });

    test(
        'a reconnect whose connection preamble fails with a refusal code is '
        'retried on the network schedule and adds no error', () async {
      var connects = 0;
      final atLookup = AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: (_) async => true,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: transportFactory),
        onConnect: (_) async {
          connects++;
          if (connects == 2 || connects == 3) {
            throw AtLookUpException('AT0027', 'enrollment_id: e1 is revoked');
          }
        },
      )..heartbeatInterval = const Duration(hours: 1);
      final taken = <Duration>[];
      (atLookup as AtLookupImpl).onNotificationReconnectDelay = taken.add;
      addTearDown(atLookup.stopNotifications);
      final errors = <Object>[];
      atLookup.notifications.listen((_) {}, onError: errors.add);
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 3 && !atLookup.isReconnectingNotifications,
          'two failed preambles and the reconnect after them');

      expect(connects, 4,
          reason: 'the start, two failed preambles, and one '
              'that succeeded');
      expect(taken, [ms(10), ms(11), ms(12)],
          reason: 'only an UnAuthenticatedException is a refusal; any other '
              'failure, whatever code it carries, waits on the network '
              'schedule');
      expect(errors, isEmpty,
          reason: 'and is not reported on the stream as a refusal');
    });

    test(
        'each refused attempt arrives as an error on notifications, which '
        'stays open', () async {
      final taken = <Duration>[];
      final atLookup = recording([
        _Attempt.accept,
        _Attempt.refuse,
        _Attempt.refuse,
      ], taken);
      final seen = <String>[];
      final errors = <Object>[];
      var done = false;
      atLookup.notifications
          .listen(seen.add, onError: errors.add, onDone: () => done = true);
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 3 && !atLookup.isReconnectingNotifications,
          'two refused reconnects and the accepted one');
      await transport().serverSends('notification: {"id":"after"}\n');
      await transport().settle();

      expect(errors, hasLength(2),
          reason: 'one error event per refused attempt');
      expect(
          errors,
          everyElement(isA<UnAuthenticatedException>()
              .having((e) => e.message, 'message', contains('error:AT0027'))),
          reason: 'the error is the refusal itself, carrying what the '
              'atServer answered');
      expect(done, isFalse,
          reason: 'a refusal does not close the stream: reconnecting carries '
              'on, and a subscriber whose stream ended would have to know to '
              'subscribe again');
      expect(seen, ['notification: {"id":"after"}'],
          reason: 'the same subscription receives once a reconnect is '
              'accepted');
    });

    test('a failure that is not a refusal adds no error', () async {
      final taken = <Duration>[];
      final atLookup = recording([
        _Attempt.accept,
        _Attempt.timeOut,
        _Attempt.timeOut,
      ], taken);
      final errors = <Object>[];
      atLookup.notifications.listen((_) {}, onError: errors.add);
      await atLookup.startNotifications();

      await transport().serverCloses();
      await until(
          () => taken.length == 3 && !atLookup.isReconnectingNotifications,
          'two timed-out reconnects and the accepted one');

      expect(errors, isEmpty,
          reason: 'only a refusal is reported on the stream; a network '
              'failure is retried as it always was');
    });

    test(
        'a refusal that arrives after a restart adds no error to the '
        'restarted stream', () async {
      final attemptStarted = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final atLookup = build(authenticator: (_) async {
        calls++;
        if (calls == 2) {
          attemptStarted.complete();
          await release.future;
          throw refusedByAtServer();
        }
        return true;
      })
        ..heartbeatInterval = const Duration(hours: 1);
      addTearDown(atLookup.stopNotifications);
      atLookup.notifications.listen((_) {}, onError: (_) {});
      await atLookup.startNotifications();

      await transport().serverCloses();
      await attemptStarted.future.timeout(const Duration(seconds: 5));
      await atLookup.stopNotifications();
      final restarting = atLookup.startNotifications();
      final errors = <Object>[];
      atLookup.notifications.listen((_) {}, onError: errors.add);
      release.complete();
      await restarting;
      await transport().settle();

      expect(atLookup.isNotifying, isTrue,
          reason: 'the restart has to have completed, or nothing here says '
              'what the stale refusal did to it');
      expect(calls, 3, reason: 'the stale attempt and the restart');
      expect(errors, isEmpty,
          reason: 'the refusal belongs to the session the stop ended, so it '
              'must not reach the stream the restart opened');
    });

    test('a refusal that arrives after stopNotifications adds no error',
        () async {
      final attemptStarted = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final atLookup = build(authenticator: (_) async {
        calls++;
        if (calls == 2) {
          attemptStarted.complete();
          await release.future;
          throw refusedByAtServer();
        }
        return true;
      })
        ..heartbeatInterval = const Duration(hours: 1);
      final errors = <Object>[];
      var done = false;
      atLookup.notifications
          .listen((_) {}, onError: errors.add, onDone: () => done = true);
      await atLookup.startNotifications();

      await transport().serverCloses();
      await attemptStarted.future.timeout(const Duration(seconds: 5));
      await atLookup.stopNotifications();
      release.complete();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(done, isTrue, reason: 'the stop closed the stream');
      expect(errors, isEmpty, reason: 'a stopped session reports nothing more');
      expect(calls, 2,
          reason: 'and the stop ended reconnecting: no attempt follows the '
              'refused one');
    });

    test(
        'waits up to 5 minutes after a refusal, and up to 34 seconds after '
        'any other failure', () {
      // Raw literals: these are what a refused device costs its atServer, one
      // attempt every 5 minutes once it has settled.
      expect((build() as AtLookupImpl).refusalReconnectDelays, [
        for (final s in [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 300])
          Duration(seconds: s),
      ]);
      expect(defaultReconnects, [
        for (final s in [1, 2, 3, 5, 8, 13, 21, 34]) Duration(seconds: s),
      ]);
    });
  });
}

/// How a scripted authentication answers.
enum _Attempt { accept, refuse, timeOut }
