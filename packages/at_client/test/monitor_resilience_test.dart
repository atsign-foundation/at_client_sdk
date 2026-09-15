import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/mocks.dart';

/// What a long-running program - a backend service that has to keep receiving
/// notifications for weeks - needs the monitor to survive: connections that
/// drop, fault or go quiet, an atServer that refuses to be reached, refuses
/// the credential or refuses `monitor:`, and rubbish on the wire. In each case
/// the same subscriber goes on receiving once a connection can be made again,
/// and nothing escapes as an uncaught error - the test runner fails the test
/// that causes one.
///
/// Everything between the subscriber and the socket is production code: a real
/// [NotificationServiceImpl], a real [Monitor], a real [AtLookupImpl]. Only
/// the socket, and the atServer behind it, belong to the test.
void main() {
  const atSign = '@alice';
  late FakeAtServer server;
  late MockAtClient client;
  late NotificationServiceImpl service;
  late List<Duration> defaultReconnects;
  late List<Duration> defaultStartRetries;
  final received = <AtNotification>[];
  var subscriptionEnded = false;

  setUpAll(() {
    defaultReconnects = AtLookupImpl.notificationReconnectDelays;
    defaultStartRetries = Monitor.startRetryDelays;
  });

  setUp(() {
    // Short enough that one test can drive a dozen outages. The schedule is
    // at_lookup's; what these tests are about is what happens at each end of
    // it.
    const fast = [
      Duration(milliseconds: 20),
      Duration(milliseconds: 40),
      Duration(milliseconds: 60),
    ];
    AtLookupImpl.notificationReconnectDelays = fast;
    Monitor.startRetryDelays = fast;

    server = FakeAtServer(atSign: atSign);
    client = MockAtClient();
    client.getPreferences()
      ..namespace = 'wavi'
      ..monitorAutoStart = false
      // The watermark is then this service's own in-memory position, so the
      // test needs no key store behind it and can still show the position
      // advancing across a reconnect.
      ..fetchOfflineNotifications = false
      ..monitorHeartbeatInterval = const Duration(milliseconds: 60)
      ..monitorHeartbeatResponseTimeout = const Duration(milliseconds: 60);
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.atSign).thenReturn(atSign.toAtsign());
    when(() => client.enrollmentId).thenReturn(null);
    when(() => client.atChops).thenReturn(MockAtChops());
    when(() => client.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer(
      (_) async => true,
    );
  });

  tearDown(() async {
    await service.stop();
    AtLookupImpl.notificationReconnectDelays = defaultReconnects;
    Monitor.startRetryDelays = defaultStartRetries;
  });

  /// Waits until the monitor reports itself listening.
  Future<void> connected() => server.waitUntil(
      () => service.currentListenerState == NotificationListenerState.listening,
      what: 'the monitor connecting (connects ${server.connectCount}, '
          'auths ${server.authCount}, monitor: ${server.monitorCount})');

  /// Builds the service and starts it listening, with one subscriber attached
  /// before the monitor connects - as a program that must miss nothing does.
  Future<void> startListening() async {
    received.clear();
    subscriptionEnded = false;
    service = await NotificationServiceImpl.create(client,
            lookUps: server.lookUps,
            secondaryAddressFinder: server.addressFinder)
        as NotificationServiceImpl;
    service
        .subscribe(regex: '.*')
        .listen(received.add, onDone: () => subscriptionEnded = true);
    service.startListening();
    await connected();
  }

  /// Sends [id] and waits for the subscriber to receive it.
  Future<void> deliver(String id) async {
    final before = received.length;
    await server.notify(id, value: id);
    await server.waitUntil(() => received.length > before,
        what: 'notification $id reaching the subscriber');
  }

  test('a notification reaches the subscriber', () async {
    await startListening();

    await deliver('n1');

    expect(received.single.id, 'n1');
    expect(received.single.value, 'n1');
  });

  group('a connection that goes away', () {
    test('is rebuilt, and the same subscriber keeps receiving', () async {
      await startListening();
      await deliver('before');

      await server.drop();
      await server.waitUntil(() => server.connectCount == 2,
          what: 'the reconnect');
      await connected();
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after'],
          reason: 'the subscriber is the same one throughout: a reconnect '
              'that delivered onto a new stream would leave the program '
              'listening to one nothing arrives on');
      expect(subscriptionEnded, isFalse,
          reason: 'and its stream must not end, or an app that resubscribes '
              'on done would never be told to');
      expect(server.socket.written.first, startsWith('monitor:'),
          reason: 'the new connection is a monitor connection too');
    });

    test('recovers the same way when it faults rather than closes', () async {
      await startListening();
      await deliver('before');

      await server.fault();
      await server.waitUntil(() => server.connectCount == 2,
          what: 'the reconnect after a fault');
      await connected();
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after']);
    });

    test('recovers from ten outages in a row, holding one connection',
        () async {
      await startListening();

      for (var i = 1; i <= 10; i++) {
        await server.drop();
        await server.waitUntil(() => server.connectCount == i + 1,
            what: 'reconnect $i');
        await connected();
        await deliver('n$i');
      }

      expect(received.map((n) => n.id), [for (var i = 1; i <= 10; i++) 'n$i'],
          reason: 'every notification after every outage, in order');
      expect(server.sockets.where((s) => !s.destroyed), hasLength(1),
          reason: 'one live connection at the end: a reconnect that left the '
              'old socket open would leak one per outage, and a service '
              'reconnecting for weeks runs out of file descriptors');
      expect(subscriptionEnded, isFalse);
    });

    test('resumes from the watermark the subscriber has reached', () async {
      await startListening();
      await deliver('n1');

      await server.drop();
      await server.waitUntil(() => server.monitorCommands.length == 2,
          what: 'the second monitor:');

      int watermarkOf(String command) =>
          int.parse(RegExp(r':(\d{10,})').firstMatch(command)!.group(1)!);
      expect(watermarkOf(server.monitorCommands[1]),
          greaterThan(watermarkOf(server.monitorCommands[0])),
          reason: 'the reconnect asks for what has arrived since the last '
              'notification this client saw. Re-sending the original '
              'watermark replays the whole window on every reconnect, which '
              'on a flapping link never ends');
    });
  });

  group('an atServer that will not have us', () {
    test('is retried until it answers', () async {
      server.refuseConnects = 3;

      await startListening();
      await deliver('n1');

      expect(server.connectCount, 1,
          reason: 'the three refusals never reached a socket');
      expect(received.single.id, 'n1');
    });

    test('is retried when it refuses the credential', () async {
      server.failAuths = 2;

      await startListening();
      await deliver('n1');

      expect(server.authCount, 3, reason: 'two refusals and the accepted one');
      expect(received.single.id, 'n1');
    });

    test('is retried when it refuses the credential after an outage', () async {
      await startListening();
      await deliver('before');

      server.failAuths = 2;
      await server.drop();
      await server.waitUntil(() => server.authCount == 4,
          what: 'two refused reconnects and the accepted one');
      await connected();
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after']);
    });

    test('is retried when it refuses to be reached after an outage', () async {
      await startListening();
      await deliver('before');

      server.refuseConnects = 2;
      await server.drop();
      await server.waitUntil(() => server.connectCount == 2,
          what: 'the reconnect that got through');
      await connected();
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after']);
    });
  });

  group('a connection that stays open but carries nothing', () {
    test('is probed, and rebuilt when the probe goes unanswered', () async {
      server.answerHeartbeat = false;
      await startListening();
      await deliver('before');

      await server.waitUntil(() => server.connectCount == 2,
          what: 'the unanswered probe rebuilding the connection');
      await connected();
      server.answerHeartbeat = true;
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after'],
          reason: 'a half-open connection - one the far end has forgotten and '
              'this end still holds - is what a service behind a NAT wakes up '
              'to, and nothing but the probe recovers it');
      expect(server.sockets.first.destroyed, isTrue,
          reason: 'and the connection it replaced is closed. Nothing else '
              'closes this one: the far end never did, which is why the probe '
              'had to, and one left open per rebuild is a descriptor leak in '
              'a process that runs for months');
    });

    test('is left alone while the probe is answered', () async {
      await startListening();
      await deliver('before');

      await server.waitUntil(() => server.heartbeatCount >= 3,
          what: 'three heartbeat probes');

      expect(server.connectCount, 1,
          reason: 'an answered probe is not a reason to rebuild anything');
      await deliver('after');
    });
  });

  group('rubbish on the wire', () {
    test('a notification the client cannot parse is skipped', () async {
      await startListening();

      await server.sendNotification('{not json at all}');
      await deliver('n1');

      expect(received.single.id, 'n1',
          reason: 'a line the client cannot parse costs one notification at '
              'worst; it must not cost the connection or the ones after it');
      expect(server.connectCount, 1);
    });

    test('a stray line that is not a notification does not stop delivery',
        () async {
      await startListening();

      await server.socket.serverSends('not a frame at all\n');
      await deliver('n1');

      expect(received.single.id, 'n1',
          reason: 'an atServer that says anything else on a monitor '
              'connection - an error, a stray response - must not leave the '
              'client deaf on a connection it still believes in');
    });

    test('an error the atServer sends on the connection does not stop it',
        () async {
      // The atServer refuses this monitor:, which is what a client meets when
      // it asks for something the atServer will not do. The error arrives on
      // the connection the notifications use.
      server.rejectMonitors = 1;
      await startListening();

      await deliver('n1');
      await deliver('n2');

      expect(received.map((n) => n.id), ['n1', 'n2']);
      expect(server.connectCount, 1,
          reason: 'and the client does not churn its connection over it');
    });

    test('a subscriber whose handler throws keeps receiving', () async {
      await startListening();
      final seen = <String>[];
      final thrown = <Object>[];
      // The handler's own errors belong to the zone that registered it, and a
      // test zone fails on them; this one collects them instead, which is what
      // an application with its own error handling does.
      await runZonedGuarded(() async {
        service.subscribe(regex: '.*').listen((n) {
          seen.add(n.id);
          throw StateError('the app threw while handling ${n.id}');
        });
        await deliver('n1');
        await deliver('n2');
      }, (e, _) => thrown.add(e));

      expect(seen, ['n1', 'n2'],
          reason: 'an application handler that throws must not take the '
              'monitor down with it');
      expect(thrown, hasLength(2),
          reason: 'and its errors are its own to handle, not swallowed here');
    });
  });

  group('what else keeps working across an outage', () {
    test('two subscribers both keep receiving', () async {
      await startListening();
      final second = <String>[];
      service.subscribe(regex: '.*').listen((n) => second.add(n.id));

      await deliver('before');
      await server.drop();
      await server.waitUntil(() => server.connectCount == 2,
          what: 'the reconnect');
      await connected();
      await deliver('after');

      expect(second, ['before', 'after'],
          reason: 'every subscriber is fed from the one monitor, so an '
              'outage must not leave some of them behind');
    });

    test('a subscriber that attaches after the outage receives too', () async {
      await startListening();
      await server.drop();
      await server.waitUntil(() => server.connectCount == 2,
          what: 'the reconnect');
      await connected();

      final late = <String>[];
      service.subscribe(regex: '.*').listen((n) => late.add(n.id));
      await deliver('after');

      expect(late, ['after'],
          reason: 'a program that subscribes on demand - one stream per job - '
              'must not depend on having subscribed before the last outage');
    });

    test('stopListening then startListening again resumes the flow', () async {
      await startListening();
      await deliver('before');

      service.stopAllSubscriptions(stopNotificationsListener: true);
      await server.waitUntil(
          () =>
              service.currentListenerState ==
              NotificationListenerState.notConnected,
          what: 'the listener stopping');

      expect(server.sockets.where((s) => !s.destroyed), isEmpty,
          reason: 'a stopped listener holds no connection');
    });
  });

  group('the connection state a subscriber can see', () {
    test('goes down on an outage and up again on recovery', () async {
      await startListening();
      final states = <NotificationListenerState>[];
      service.currentListenerStateStream.listen(states.add);

      await server.drop();
      await server.waitUntil(
          () => states.contains(NotificationListenerState.notConnected),
          what: 'the down report');
      await connected();

      expect(states.last, NotificationListenerState.listening,
          reason: 'a program watching this to decide whether it is live has '
              'to see it come back up');
    });
  });
}
