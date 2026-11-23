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

  SessionTransport transport() =>
      (lookUps: wire.lookUps, finder: finder, root: AtRootDomain.atsignDomain);

  AtLookupMuxable lookUp() => wire.lookUps(
      atSign: _atSign,
      rootDomain: AtRootDomain.atsignDomain,
      authenticator: null,
      secondaryAddressFinder: finder);

  _KeysIo keysIoFor(String enrollmentId) =>
      _KeysIo(_atSign, classicalAtKeys(enrollmentId: enrollmentId));

  Future<AtClient> open({String enrollmentId = 'eid1', _KeysIo? keysIo}) =>
      openSession(
          lookUp: lookUp(),
          atSign: _atSign,
          enrollmentId: enrollmentId,
          keysIo: keysIo ?? keysIoFor(enrollmentId),
          app: _app,
          transport: transport());

  setUp(() {
    wire = Wire();
  });

  tearDown(() async {
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

      await expectLater(open(), throwsA(isA<SessionOfflineException>()));
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

  test('the client reads its keys from the key store it was given', () async {
    final store = keysIoFor('eid1');

    final client = await open(keysIo: store);

    expect(store.reads, greaterThan(0));
    expect(client.enrollmentId, 'eid1');
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
