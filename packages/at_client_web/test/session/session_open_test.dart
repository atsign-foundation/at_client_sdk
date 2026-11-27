import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookupMuxable;
import 'package:at_client_web/src/session/session_open.dart';
import 'package:test/test.dart';

import '../test_utils.dart';
import 'wire_fakes.dart';

const _atSign = '@alice';
const _app = 'wavi';

/// The key store a client is built on, counting the reads it served.
class _KeysIo extends SessionKeysIo {
  _KeysIo(super.atSign, super.keys);

  var reads = 0;

  @override
  FutureOr<AtKeys> read(String atsign) {
    reads++;
    return super.read(atsign);
  }
}

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;

  /// The process-wide network default as the suite found it, put back after
  /// each test so a test that shortens it changes no other.
  late Duration networkDefault;

  SessionTransport transport() =>
      (lookUps: wire.lookUps, finder: finder, root: AtRootDomain.atsignDomain);

  AtLookupMuxable lookUp() => wire.lookUps(
      atSign: _atSign,
      rootDomain: AtRootDomain.atsignDomain,
      authenticator: null,
      secondaryAddressFinder: finder);

  _KeysIo keysIoFor(String enrollmentId) =>
      _KeysIo(_atSign, classicalAtKeys(enrollmentId: enrollmentId));

  Future<AtClient> open(
          {String enrollmentId = 'eid1',
          _KeysIo? keysIo,
          String? appName,
          String? appVersion}) =>
      openSession(
          lookUp: lookUp(),
          atSign: _atSign,
          enrollmentId: enrollmentId,
          keysIo: keysIo ?? keysIoFor(enrollmentId),
          app: _app,
          transport: transport(),
          appName: appName,
          appVersion: appVersion);

  setUp(() {
    wire = Wire();
    networkDefault = AtNetworkTimeouts.defaultTimeout;
  });

  tearDown(() async {
    AtNetworkTimeouts.defaultTimeout = networkDefault;
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  group('a client that does not come online', () {
    test('a stop failure never replaces the error of an open that failed',
        () async {
      wire.pkamAccepted = false;
      wire.stopThrows = true;
      addTearDown(() => wire.stopThrows = false);

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));
    });
  });

  test('stopping the client closes the in-memory storage it built', () async {
    final client = await open();
    final storage = (client as AtClientImpl).storage!;
    expect(storage.closedByClient, isTrue);

    await client.stop();

    await expectLater(
        storage.attach(client),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('closed and cannot be reopened'))),
        reason: 'the client closed the storage it built');
  });

  test('the client a session opens starts no monitor of its own', () async {
    final client = await open();
    await pumpEventQueue();

    expect(client.getPreferences()!.monitorAutoStart, isFalse);
    expect(wire.lookUpsBuilt.map((l) => l.notificationStarts), everyElement(0));
  });

  group('naming the app', () {
    test(
        'an open with appName and appVersion names the app on the client '
        'preference', () async {
      final client = await open(appName: 'Tally', appVersion: '1.2.3');

      final particulars = client.getPreferences()!.atClientParticulars;
      expect((particulars.appName, particulars.appVersion), ('Tally', '1.2.3'));
    });

    test('an open without appName leaves the particulars unset', () async {
      final client = await open();

      final particulars = client.getPreferences()!.atClientParticulars;
      expect((particulars.appName, particulars.appVersion), (null, null));
    });

    test('appName with explicit prefs is refused naming appName', () async {
      final prefs = AtClientPreference()
        ..namespace = _app
        ..monitorAutoStart = false;

      await expectLater(
          openOnline(
              atSign: _atSign,
              app: _app,
              keys: keysIoFor('eid1'),
              transport: transport(),
              prefs: prefs,
              appName: 'Tally',
              logger: 'session_open_test'),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'appName')));

      expect(wire.dials, 0, reason: 'the refusal comes before any connection');
    });
  });

  test('the client reads its keys from the key store it was given', () async {
    final store = keysIoFor('eid1');

    final client = await open(keysIo: store);

    expect(store.reads, greaterThan(0));
    expect(client.enrollmentId, 'eid1');
  });

  group('the network default is the open budget', () {
    test('an open whose authentication finishes after five seconds succeeds',
        () async {
      final held = Completer<bool>();
      wire.pkamScript.add(held);
      Timer(const Duration(milliseconds: 5200), () => held.complete(true));

      final client = await open();

      expect(client.connection.current.isOnline, isTrue,
          reason: 'the open waited past the five second connection budget '
              'for its PKAM');
    });

    test(
        'an open passes the network default as its budget on both session '
        'forms', () async {
      AtNetworkTimeouts.defaultTimeout = const Duration(seconds: 7);
      final forms = <(String, Future<AtClient> Function())>[
        ('passkey (openSession)', open),
        (
          'keys (portalSession)',
          () => portalSession(
              atSign: _atSign,
              app: _app,
              keys: classicalAtKeys(enrollmentId: 'eid1'),
              transport: transport())
        ),
      ];

      for (final (name, start) in forms) {
        wire.pkamScript.add(Completer<bool>());
        final watch = Stopwatch()..start();
        await expectLater(
            start(), throwsA(isA<PortalSessionOfflineException>()),
            reason: 'the $name open waits the network default for its PKAM');
        watch.stop();

        expect(watch.elapsed, greaterThan(const Duration(seconds: 6)),
            reason: 'the $name open did not fail at the five second '
                'connection budget');
        expect(watch.elapsed, lessThan(const Duration(seconds: 8)),
            reason: 'the $name open ended within the seven second network '
                'default');
      }
    });

    test('an open that cannot finish within thirty seconds rejects offline',
        () async {
      AtNetworkTimeouts.defaultTimeout = const Duration(seconds: 7);
      wire.pkamScript.add(Completer<bool>());

      final watch = Stopwatch()..start();
      await expectLater(
          open(),
          throwsA(isA<PortalSessionOfflineException>()
              .having((e) => e.state.outcome, 'outcome',
                  AtConnectionOutcome.offline)
              .having((e) => e.state.cause, 'cause',
                  AtConnectionCause.unreachable)));
      watch.stop();

      expect(watch.elapsed, greaterThan(const Duration(seconds: 6)),
          reason: 'the open waited the network default, not the five second '
              'connection budget');
    });
  });

  group('concurrent opens', () {
    test('two opens for one atSign and enrollment give one client', () async {
      final outcomes = await Future.wait([
        for (var i = 0; i < 2; i++)
          open().then<Object>((c) => c, onError: (Object e) => e),
      ]);

      final clients = outcomes.whereType<AtClient>().toList();
      expect(clients, hasLength(1), reason: '$outcomes');
      expect(outcomes.whereType<StateError>(), hasLength(1),
          reason: 'the second open fails as it would after the first');
      expect(AtClientImpl.liveClientsFor(_atSign), [same(clients.single)]);
    });

    test('an open for another enrollment is not held up by one in flight',
        () async {
      final held = Completer<bool>();
      wire.pkamScript.add(held);
      final first = open();
      await pumpEventQueue();
      expect(wire.pkams, 1, reason: 'the first open waits on its PKAM');

      final second =
          await open(enrollmentId: 'eid2').timeout(Duration(seconds: 2));

      expect(second.connection.current.isOnline, isTrue);
      held.complete(true);
      await first;
      expect(AtClientImpl.liveClientsFor(_atSign), hasLength(2));
    });

    test('an open and a portal session for one enrollment run one at a time',
        () async {
      final outcomes = await Future.wait([
        open(enrollmentId: 'eid1')
            .then<Object>((c) => c, onError: (Object e) => e),
        portalSession(
                atSign: _atSign,
                app: _app,
                keys: classicalAtKeys(enrollmentId: 'eid1'),
                transport: transport())
            .then<Object>((c) => c, onError: (Object e) => e),
      ]);

      expect(outcomes.whereType<AtClient>(), hasLength(1), reason: '$outcomes');
      expect(outcomes.whereType<StateError>(), hasLength(1),
          reason: 'the later open fails as it would after the first');
      expect(AtClientImpl.liveClientsFor(_atSign), hasLength(1));
    });
  });
}
