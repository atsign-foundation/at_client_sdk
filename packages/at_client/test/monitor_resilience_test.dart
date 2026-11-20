import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart' show RSAKeypair;
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
  late String pkamPrivateKey;
  final received = <AtNotification>[];
  var subscriptionEnded = false;

  /// The delay chosen before each reconnect, and before each retry of the
  /// first connect, since the service was built.
  final reconnectDelays = <Duration>[];
  final startDelays = <Duration>[];

  /// The delays the last service's monitor and lookup would have waited on
  /// after a refusal, before the test set its own.
  late List<Duration> builtStartRefusalDelays;
  late List<Duration> builtReconnectRefusalDelays;

  /// The delays after a refusal, for a reconnect and a first start alike:
  /// distinct at every index from the network delays [setUp] sets, so each
  /// delay taken names the schedule it came from.
  const afterRefusal = [
    Duration(milliseconds: 30),
    Duration(milliseconds: 50),
    Duration(milliseconds: 70),
    Duration(milliseconds: 90),
  ];

  setUpAll(() {
    defaultReconnects = AtLookupImpl.notificationReconnectDelays;
    defaultStartRetries = Monitor.startRetryDelays;
    pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
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
  ///
  /// [connection] is the client's connection state the monitor reports into;
  /// with [untilListening] false this returns without waiting to connect.
  /// [refusalDelays] are waited on after a refusal.
  Future<void> startListening(
      {AtConnection? connection,
      bool untilListening = true,
      List<Duration> refusalDelays = afterRefusal}) async {
    received.clear();
    subscriptionEnded = false;
    reconnectDelays.clear();
    startDelays.clear();
    service = await NotificationServiceImpl.create(client,
        lookUps: server.lookUps,
        secondaryAddressFinder: server.addressFinder,
        connection: connection) as NotificationServiceImpl;
    final lookUp = service.monitor.lookUp as AtLookupImpl;
    builtStartRefusalDelays = service.monitor.startRefusalRetryDelays;
    builtReconnectRefusalDelays = lookUp.refusalReconnectDelays;
    service.monitor
      ..onStartRetryDelay = startDelays.add
      ..startRefusalRetryDelays = refusalDelays;
    lookUp
      ..onNotificationReconnectDelay = reconnectDelays.add
      ..refusalReconnectDelays = refusalDelays;
    service
        .subscribe(regex: '.*')
        .listen(received.add, onDone: () => subscriptionEnded = true);
    service.startListening();
    if (untilListening) await connected();
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

      service.stopListening();
      await server.waitUntil(
          () =>
              service.currentListenerState ==
              NotificationListenerState.notConnected,
          what: 'the listener stopping');
      expect(server.sockets.where((s) => !s.destroyed), isEmpty,
          reason: 'a stopped listener holds no connection');

      service.startListening();
      await connected();
      await deliver('after');

      expect(received.map((n) => n.id), ['before', 'after'],
          reason: 'a service that stops listening on purpose - while it has '
              'no work to do, or over a maintenance window - has to come '
              'back to the same subscriber when it starts again');
      expect(server.connectCount, 2,
          reason: 'on a new connection, since the old one was closed');
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

  late AtConnection connection;
  final changes = <AtConnectionState>[];

  /// Points the test at an atServer whose `pkam:` answers decide whether
  /// at_auth's own authenticator is accepted, so a refusal reaches the client
  /// in the words at_auth composes around the atServer's answer, and builds
  /// the connection state the monitor reports into.
  void refusableServer() {
    server = FakeAtServer(atSign: atSign, pkamPrivateKey: pkamPrivateKey);
    connection = AtConnection(
        atSign: atSign,
        attempt: (_) async =>
            fail('only the monitor reports the connection here'));
    changes.clear();
    connection.changes.listen(changes.add);
    addTearDown(connection.close);
  }

  Duration ms(int n) => Duration(milliseconds: n);

  Duration longest(List<Duration> delays) =>
      delays.reduce((a, b) => a > b ? a : b);

  // Each as an atServer answers a `pkam:` before the connection has
  // authenticated: an enrollment's state as `error:<code>:<message>`, an
  // exception as `error:<code>-<description>`.
  const enrollment = '7f3a2c1e-4b5d-4e6f-8a9b-0c1d2e3f4a5b';
  const refusals = [
    (
      code: 'AT0027',
      cause: AtConnectionCause.revoked,
      answer: 'error:AT0027:enrollment_id: $enrollment is revoked',
    ),
    (
      code: 'AT0025',
      cause: AtConnectionCause.enrollmentDenied,
      answer: 'error:AT0025:enrollment_id: $enrollment is denied',
    ),
    (
      code: 'AT0029',
      cause: AtConnectionCause.invalidEnrollment,
      answer: 'error:AT0029-Exception: enrollment $enrollment has expired',
    ),
    (
      code: 'AT0026',
      cause: AtConnectionCause.enrollmentNotApproved,
      answer: 'error:AT0026:enrollment_id: $enrollment is pending',
    ),
    (
      code: 'AT0401',
      cause: AtConnectionCause.unauthenticated,
      answer: 'error:AT0401-Exception: pkam authentication failed',
    ),
  ];

  /// Answers that let the client in no more than a refusal does, and are
  /// not one: [pkam] answers each `pkam:`, [from] each `from:`.
  const turnedAway = [
    (
      answer: 'AT0011',
      pkam: 'error:AT0011-Exception: Internal server exception',
      from: null,
    ),
    (
      answer: 'a code this build does not know',
      pkam: 'error:AT9999:an answer this build has no name for',
      from: null,
    ),
    (answer: 'no challenge to sign', pkam: null, from: 'data:'),
  ];

  void answerWith(({String answer, String? pkam, String? from}) row) => server
    ..pkamRefusal = row.pkam
    ..pkamFromAnswer = row.from;

  /// Asserts the connection reads refused with [cause], reported once
  /// however many refusals there were.
  void refusedWith(AtConnectionCause cause) {
    expect(connection.current.outcome, AtConnectionOutcome.refused,
        reason: 'the app can see the atServer refused this client');
    expect(connection.current.cause, cause,
        reason: 'and why, from the code the atServer answered with');
    expect(changes.where((c) => c.isRefused), hasLength(1),
        reason: 'one change for many refusals: a repeated refusal is not a '
            'new situation');
  }

  group(
      'a notification reconnect the atServer refuses as <cause> is retried '
      'less often', () {
    setUp(refusableServer);

    for (final row in refusals) {
      test('${row.code} | ${row.cause.name}', () async {
        await startListening(connection: connection);
        server.pkamRefusal = row.answer;

        await server.drop();
        await server.waitUntil(() => server.authCount >= 7,
            what: 'six refused reconnects');

        expect(reconnectDelays.take(6),
            [ms(20), ms(50), ms(70), ms(90), ms(90), ms(90)],
            reason: 'the wait after the drop is the network one; after each '
                'refusal the wait is from the refusal schedule, longer each '
                'time and holding at its last entry, and the attempts go on '
                'past it');
        expect(longest(builtReconnectRefusalDelays), const Duration(minutes: 5),
            reason: 'the refusal schedule a client runs on grows to 5 '
                'minutes');
        refusedWith(row.cause);
      });
    }
  });

  group(
      'a notification start the atServer refuses as <cause> is retried '
      'less often', () {
    setUp(refusableServer);

    for (final row in refusals) {
      test('${row.code} | ${row.cause.name}', () async {
        server.pkamRefusal = row.answer;

        await startListening(connection: connection, untilListening: false);
        await server.waitUntil(() => server.authCount >= 6,
            what: 'six refused starts');

        expect(startDelays.take(5), [ms(30), ms(50), ms(70), ms(90), ms(90)],
            reason: 'each retry of a refused start waits from the refusal '
                'schedule, longer each time and holding at its last entry, '
                'and the retries go on past it');
        expect(builtStartRefusalDelays, builtReconnectRefusalDelays,
            reason: 'a refused start backs off on the schedule a refused '
                'reconnect does');
        expect(longest(builtStartRefusalDelays), const Duration(minutes: 5),
            reason: 'which grows to 5 minutes');
        refusedWith(row.cause);
      });
    }
  });

  group(
      'a notification reconnect the atServer answers with <answer> is retried '
      'less often, leaving the connection state as it was', () {
    setUp(refusableServer);

    for (final row in turnedAway) {
      test(row.answer, () async {
        await startListening(connection: connection);
        answerWith(row);

        await server.drop();
        await server.waitUntil(() => reconnectDelays.length >= 6,
            what: 'five reconnects turned away');

        expect(reconnectDelays.take(6),
            [ms(20), ms(50), ms(70), ms(90), ms(90), ms(90)],
            reason: 'the wait after the drop is the network one; after each '
                'attempt turned away the wait is from the slower schedule, '
                'longer each time and holding at its last entry');
        expect(longest(builtReconnectRefusalDelays), const Duration(minutes: 5),
            reason: 'which grows to 5 minutes');
        expect(changes.map((c) => (c.outcome, c.cause)),
            [(AtConnectionOutcome.online, null)],
            reason: 'an answer that is not a refusal leaves the connection '
                'state as it was before the drop');
      });
    }
  });

  group(
      'a notification start the atServer answers with <answer> is retried '
      'less often, leaving the connection state as it was', () {
    setUp(refusableServer);

    for (final row in turnedAway) {
      test(row.answer, () async {
        answerWith(row);

        await startListening(connection: connection, untilListening: false);
        await server.waitUntil(() => startDelays.length >= 5,
            what: 'five starts turned away');

        expect(startDelays.take(5), [ms(30), ms(50), ms(70), ms(90), ms(90)],
            reason: 'each retry of a start turned away waits from the slower '
                'schedule, longer each time and holding at its last entry');
        expect(builtStartRefusalDelays, builtReconnectRefusalDelays,
            reason: 'the schedule a reconnect turned away waits on');
        expect(longest(builtStartRefusalDelays), const Duration(minutes: 5),
            reason: 'which grows to 5 minutes');
        expect(changes, isEmpty,
            reason: 'an answer that is not a refusal leaves the connection '
                'state as it was before the start');
      });
    }
  });

  test(
      'refused starts after more failed starts than the network schedule '
      'holds wait from the step past its last, longer after each refusal',
      () async {
    refusableServer();
    server.refuseConnects = 5;
    server.pkamRefusal = refusals.first.answer;

    await startListening(
        connection: connection,
        untilListening: false,
        refusalDelays: [
          for (final n in [30, 50, 70, 90, 110, 130]) ms(n)
        ]);
    await server.waitUntil(() => startDelays.length >= 8,
        what: 'five unreachable starts and three refused ones');

    expect(startDelays.take(5), [ms(20), ms(40), ms(60), ms(60), ms(60)],
        reason: 'the unreachable starts wait on the network schedule, held at '
            'its last entry');
    expect(startDelays.skip(5).take(3), [ms(90), ms(110), ms(130)],
        reason: 'the first refused start waits one step past the network '
            'schedule\'s last, not as far along the refusal schedule as the '
            'starts so far would reach, and each refusal after it waits '
            'longer');
    refusedWith(AtConnectionCause.revoked);
  });

  test('an app keeps its notifications through a refusal that clears',
      () async {
    refusableServer();
    await startListening(connection: connection);
    await deliver('before');
    server.pkamRefusal = refusals.first.answer;
    await server.drop();
    await server.waitUntil(
        () => connection.current.isRefused && server.authCount >= 3,
        what: 'two refused reconnects');

    server.pkamRefusal = null;
    await connected();
    await deliver('after');

    expect(received.map((n) => n.id), ['before', 'after'],
        reason: 'the subscription the app took before the refusal is the one '
            'that receives once the atServer accepts the client again');
    expect(subscriptionEnded, isFalse,
        reason: 'a refusal does not end the app\'s stream');
    expect(connection.current.isOnline, isTrue);
    expect(changes.map((c) => (c.outcome, c.cause)), [
      (AtConnectionOutcome.online, null),
      (AtConnectionOutcome.refused, AtConnectionCause.revoked),
      (AtConnectionOutcome.online, null),
    ]);
  });

  test(
      'a dropped notification connection to an unreachable atServer is '
      'retried as before', () async {
    refusableServer();
    await startListening(connection: connection);
    await deliver('before');

    server.refuseConnects = 5;
    await server.drop();
    await server.waitUntil(() => server.connectCount == 2,
        what: 'the reconnect that got through');
    await connected();
    await deliver('after');

    expect(reconnectDelays, [ms(20), ms(40), ms(60), ms(60), ms(60), ms(60)],
        reason: 'an atServer that cannot be reached is retried on the '
            'network schedule, held at its last entry');
    expect(longest(defaultReconnects), const Duration(seconds: 34),
        reason: 'the network schedule a client runs on grows to 34 seconds');
    expect(received.map((n) => n.id), ['before', 'after']);
    expect(changes.where((c) => c.isRefused), isEmpty,
        reason: 'an unreachable atServer is not a refusal');
  });

  test('a start that cannot reach the atServer is retried as before', () async {
    refusableServer();
    server.refuseConnects = 3;

    await startListening(connection: connection);

    expect(startDelays, [ms(20), ms(40), ms(60)],
        reason: 'a start that never reached the atServer retries on the '
            'network schedule');
    expect(changes.where((c) => c.isRefused), isEmpty);
  });

  group(
      'Given an atServer that answers the notification connection the same '
      'way every time', () {
    /// Each answer, how the atServer gives it, whether it turns the client
    /// away, and the connection state the client reports for it.
    final answers = <({
      String answer,
      void Function(FakeAtServer) give,
      bool turnedAway,
      List<(AtConnectionOutcome, AtConnectionCause?)> reported,
    })>[
      for (final row in refusals)
        (
          answer: row.code,
          give: (s) => s.pkamRefusal = row.answer,
          turnedAway: true,
          reported: [(AtConnectionOutcome.refused, row.cause)],
        ),
      (
        answer: 'AT0028',
        give: (s) => s.pkamRefusal =
            'error:AT0028:enrollment_id: $enrollment is expired',
        turnedAway: true,
        reported: [
          (AtConnectionOutcome.refused, AtConnectionCause.invalidEnrollment)
        ],
      ),
      (
        answer: 'a reply with no code',
        give: (s) => s.pkamRefusal = 'data:failure',
        turnedAway: true,
        reported: [
          (AtConnectionOutcome.refused, AtConnectionCause.unauthenticated)
        ],
      ),
      for (final row in turnedAway)
        (
          answer: row.answer,
          give: (s) => s
            ..pkamRefusal = row.pkam
            ..pkamFromAnswer = row.from,
          turnedAway: true,
          reported: const [],
        ),
      (
        answer: 'a failed connect',
        give: (s) => s.refuseConnects = 1000,
        turnedAway: false,
        reported: const [],
      ),
      (
        answer: 'a drop during from:',
        give: (s) => s.dropOnFrom = true,
        turnedAway: false,
        reported: const [],
      ),
    ];

    String scheduleOf(Duration delay) => afterRefusal.contains(delay)
        ? 'slower'
        : AtLookupImpl.notificationReconnectDelays.contains(delay)
            ? 'network'
            : '$delay';

    for (final row in answers) {
      test(
          '${row.answer}: when the client starts listening and when it '
          'reconnects, then both wait on the same schedule and report the '
          'same connection state', () async {
        expect(defaultStartRetries, defaultReconnects,
            reason: 'a start and a reconnect that never reached the atServer '
                'wait on the same network schedule');

        refusableServer();
        row.give(server);
        await startListening(connection: connection, untilListening: false);
        await server.waitUntil(() => startDelays.length >= 3,
            what: 'three failed starts');
        final startWaits = startDelays.take(3).map(scheduleOf).toList();
        final startReported = changes.map((c) => (c.outcome, c.cause)).toList();
        await service.stop();

        refusableServer();
        await startListening(connection: connection);
        row.give(server);
        await server.drop();
        await server.waitUntil(() => reconnectDelays.length >= 4,
            what: 'three failed reconnects');
        // NOTE: the first wait after a drop is the network one whatever
        // follows, so a reconnect's waits after a failure start at the second.
        final reconnectWaits =
            reconnectDelays.skip(1).take(3).map(scheduleOf).toList();
        final reconnectReported =
            changes.skip(1).map((c) => (c.outcome, c.cause)).toList();

        final waits = List.filled(3, row.turnedAway ? 'slower' : 'network');
        expect(startWaits, waits,
            reason: 'a start waits on the slower schedule exactly when the '
                'atServer answered without letting the client in');
        expect(reconnectWaits, waits,
            reason: 'and a reconnect waits on the schedule a start does');
        expect(startReported, row.reported,
            reason: 'a start reports a refusal of the credentials, with its '
                'cause, and nothing for any other failure');
        expect(reconnectReported, row.reported,
            reason: 'and a reconnect reports what a start does');
      });
    }
  });
}
