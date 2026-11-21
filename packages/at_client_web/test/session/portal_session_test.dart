import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import '../test_utils.dart';
import 'wire_fakes.dart';

const _atSign = '@alice';
const _app = 'wavi';

/// A session key store counting the reads it served.
class _CountingKeysIo extends SessionKeysIo {
  _CountingKeysIo(super.atSign, super.keys);

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

  SessionTransport transport({AtRootDomain root = AtRootDomain.atsignDomain}) =>
      (lookUps: wire.lookUps, finder: finder, root: root);

  Future<AtClient> open(
          {String atSign = _atSign,
          AtKeys? keys,
          SessionTransport? over,
          AtClientPreference? prefs}) =>
      portalSession(
          atSign: atSign,
          app: _app,
          keys: keys ?? classicalAtKeys(),
          transport: over ?? transport(),
          prefs: prefs);

  setUp(() => wire = Wire());

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  test('a portal session given a key store runs its client on it', () async {
    final store = _CountingKeysIo(_atSign, classicalAtKeys());

    await portalSession(
        atSign: _atSign,
        app: _app,
        keys: classicalAtKeys(),
        transport: transport(),
        keysIo: store);

    expect(store.reads, greaterThan(0));
  });

  test(
      'A session opened without a preference takes its root from the transport',
      () async {
    final client =
        await open(over: transport(root: AtRootDomain('root.example', 6464)));
    client.notificationService.startListening();
    await pumpEventQueue();

    final prefs = client.getPreferences()!;
    expect((prefs.rootDomain, prefs.rootPort), ('root.example', 6464),
        reason: "the preference portalSession builds names the transport's "
            'root');
    expect(wire.roots, hasLength(greaterThan(1)),
        reason: "the client's own connection and the monitor's");
    final roots = {for (final r in wire.roots) (r.rootDomain, r.rootPort)};
    expect(roots, {('root.example', 6464)},
        reason: "every connection is built for the transport's root");
  });

  test(
      'A session opened with a preference on another root is refused before '
      'any connection', () async {
    final prefs = AtClientPreference()
      ..namespace = _app
      ..rootDomain = 'root.atsign.org'
      ..rootPort = 64
      ..monitorAutoStart = false;

    await expectLater(
        open(
            over: transport(root: AtRootDomain('root.example', 6464)),
            prefs: prefs),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'prefs')),
        reason: "a preference on another root would build connections for a "
            'root the transport does not name');
    expect(wire.dials, 0, reason: 'the refusal comes before any connection');
  });

  AtClientPreference prefsOn(String rootDomain, int rootPort) =>
      AtClientPreference()
        ..namespace = _app
        ..rootDomain = rootDomain
        ..rootPort = rootPort
        ..monitorAutoStart = false;

  Matcher refusedNamingPrefs() =>
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'prefs'));

  group('Given a transport whose root is root.example at port 6464', () {
    final root = AtRootDomain('root.example', 6464);

    test(
        'when a prefs differs from it only in its host, then the open is '
        'refused before any connection', () async {
      await expectLater(
          open(
              over: transport(root: root),
              prefs: prefsOn('other.example', 6464)),
          refusedNamingPrefs(),
          reason: 'a prefs on another host names another root');
      expect(wire.dials, 0, reason: 'the refusal comes before any connection');
    });

    test(
        'when a prefs differs from it only in its port, then the open is '
        'refused before any connection', () async {
      await expectLater(
          open(over: transport(root: root), prefs: prefsOn('root.example', 64)),
          refusedNamingPrefs(),
          reason: 'a prefs on another port names another root');
      expect(wire.dials, 0, reason: 'the refusal comes before any connection');
    });

    test(
        'when a prefs differs from it only in the case of its host, then the '
        'open goes ahead', () async {
      final opened = await open(
              over: transport(root: root), prefs: prefsOn('Root.Example', 6464))
          .then<Object>((c) => c, onError: (Object e) => e);
      expect(opened, isA<AtClient>(),
          reason: 'host names are compared ignoring case');
    });

    test(
        'when a prefs is changed to another root while its open waits for an '
        'earlier one, then the open is refused', () async {
      final held = Completer<bool>();
      wire.pkamScript.add(held);
      final first = open(over: transport(root: root))
          .then<Object>((c) => c, onError: (Object e) => e);
      await pumpEventQueue();
      final prefs = prefsOn('root.example', 6464);
      final second = open(over: transport(root: root), prefs: prefs);
      await pumpEventQueue();

      prefs.rootDomain = 'other.example';
      held.complete(false);

      expect(await first, isA<PortalSessionOfflineException>());
      await expectLater(second, refusedNamingPrefs(),
          reason: 'prefs is checked when its open runs, not when it queues');
      final roots = {for (final r in wire.roots) r.rootDomain};
      expect(roots, {'root.example'},
          reason: 'no connection is built for the changed root');
    });
  });

  group('Given a proxy transport whose root is proxy:proxy.example at port 443',
      () {
    final root = AtRootDomain('proxy:proxy.example', 443);

    test(
        'when portalSession opens with no prefs, then every connection is '
        'built for the proxy: root', () async {
      final client = await open(over: transport(root: root));
      client.notificationService.startListening();
      await pumpEventQueue();

      final prefs = client.getPreferences()!;
      expect((prefs.rootDomain, prefs.rootPort), ('proxy:proxy.example', 443),
          reason: "the preference portalSession builds names the proxy: root");
      expect(wire.roots, hasLength(greaterThan(1)),
          reason: "the client's own connection and the monitor's");
      final roots = {
        for (final r in wire.roots) (r.rootDomain, r.rootPort, r.isProxyAddress)
      };
      expect(roots, {('proxy:proxy.example', 443, true)},
          reason: 'every connection is built for the proxy: root, so '
              'at_lookup sends from:<atSign> on each');
    });

    test(
        'when a prefs names its host with a Proxy: prefix in another case, '
        'then the open is refused before any connection', () async {
      await expectLater(
          open(
              over: transport(root: root),
              prefs: prefsOn('Proxy:proxy.example', 443)),
          refusedNamingPrefs(),
          reason: 'a root that is not proxy: gets no from:<atSign> from '
              'at_lookup');
      expect(wire.dials, 0, reason: 'the refusal comes before any connection');
    });

    test(
        'when a default AtClientPreference is passed, then the open is '
        'refused before any connection', () async {
      await expectLater(
          open(
              over: transport(root: root),
              prefs: AtClientPreference()
                ..namespace = _app
                ..monitorAutoStart = false),
          refusedNamingPrefs(),
          reason: 'a default preference names the production atDirectory, '
              'not the proxy');
      expect(wire.dials, 0, reason: 'the refusal comes before any connection');
    });
  });

  group('transport', () {
    test('a failed direct connect rejects and dials no proxy', () async {
      final proxy = Wire();
      wire.connectFails = true;

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));

      expect(wire.dials, greaterThan(0));
      expect(proxy.dials, 0, reason: 'there is no fallback transport to dial');
      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
    });
  });

  group('open', () {
    test('PKAM runs before the client is returned', () async {
      final client = await open();

      expect(wire.pkams, greaterThan(0));
      expect(client.connection.current.isOnline, isTrue);
      expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
    });

    test('a refused PKAM rejects, registers no client, and a retry succeeds',
        () async {
      wire.pkamAccepted = false;
      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));
      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);

      wire.pkamAccepted = true;
      await open();
      expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
    });

    for (final (name, failure) in <(String, Object Function())>[
      ('Exception', () => Exception('monitor lookUp')),
      ('Error', () => StateError('monitor lookUp')),
    ]) {
      test(
          'a $name after the client is registered leaves none registered '
          'and a retry succeeds', () async {
        // The first dial is the client's own connection, the second the
        // notification monitor's, which is built after registration.
        wire.onDial = (n) {
          if (n == 2) throw failure();
        };
        await expectLater(open(), throwsA(isA<Object>()));
        expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);

        wire.onDial = null;
        await open();
        expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
      });
    }
  });

  group('concurrent opens', () {
    test('two opens for one atSign started together give one client', () async {
      final outcomes = await Future.wait([
        for (final atSign in [_atSign, 'Alice'])
          open(atSign: atSign).then<Object>((c) => c, onError: (Object e) => e),
      ]);

      final clients = outcomes.whereType<AtClient>().toList();
      expect(clients, hasLength(1), reason: '$outcomes');
      expect(outcomes.whereType<StateError>(), hasLength(1),
          reason: 'the second open fails as it would after the first');
      expect(AtClientImpl.liveClientsFor(_atSign), [same(clients.single)]);
    });

    test('an open started while a failing one runs builds afresh', () async {
      wire.pkamAccepted = false;
      // The atServer accepts again once the first open has failed.
      final first = open().then<Object>((c) => c, onError: (Object e) {
        wire.pkamAccepted = true;
        return e;
      });
      final second = open();

      expect(await first, isA<PortalSessionOfflineException>());
      final client = await second;
      expect(AtClientImpl.liveClientsFor(_atSign), [same(client)]);
    });

    test(
        'opens for two enrollments of one atSign are not held up by each other',
        () async {
      final held = Completer<bool>();
      wire.pkamScript.add(held);
      final first = open();
      await pumpEventQueue();
      expect(wire.pkams, 1, reason: 'the first open waits on its PKAM');

      final other = classicalAtKeys(enrollmentId: 'second-enrollment');
      final second = await open(keys: other).timeout(Duration(seconds: 2));

      expect(second.connection.current.isOnline, isTrue);
      held.complete(true);
      await first;
      expect(AtClientImpl.liveClientsFor(_atSign), hasLength(2));
    });

    test('opens that overlap one after another still run one at a time',
        () async {
      wire.pkamScript.add(Completer<bool>()..complete(false));

      Future<Object> outcome(Future<AtClient> f) =>
          f.then<Object>((c) => c, onError: (Object e) => e);
      // The second and third queue behind the first. The fourth starts the
      // moment the first ends, while the second is still on its way in.
      final fourth = Completer<Object>();
      final first = outcome(open());
      unawaited(first.whenComplete(() => fourth.complete(outcome(open()))));
      final second = outcome(open());
      final third = outcome(open());

      final outcomes = await Future.wait([first, second, third, fourth.future]);

      expect(outcomes.first, isA<PortalSessionOfflineException>());
      expect(outcomes.whereType<AtClient>(), hasLength(1), reason: '$outcomes');
      expect(outcomes.whereType<StateError>(), hasLength(2));
      expect(AtClientImpl.liveClientsFor(_atSign), hasLength(1));
    });

    test('opens for different atSigns are not held up by each other', () async {
      final bob = open(atSign: '@bob', keys: classicalAtKeys());
      final alice = open();

      final clients = await Future.wait([alice, bob]);
      expect(clients.map((c) => c.getCurrentAtSign()), [_atSign, '@bob']);
    });
  });

  group('open failure', () {
    test('a stop that throws does not mask the open failure', () async {
      wire
        ..pkamAccepted = false
        ..stopThrows = true;

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));
    });

    test('a stop that throws is logged as a warning', () async {
      final records = <String>[];
      final previous = AtSignLogger.defaultLoggingHandler;
      AtSignLogger.defaultLoggingHandler = _Collect(records);
      addTearDown(() => AtSignLogger.defaultLoggingHandler = previous);
      wire
        ..pkamAccepted = false
        ..stopThrows = true;

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));

      expect(records.where((r) => r.startsWith('WARNING|portalSession|')),
          isNotEmpty);
      expect(records.join('\n'), contains('stop failed'));
    });
  });

  group('routing', () {
    final greeting =
        (AtKey.public('greeting', namespace: _app)..sharedBy(_atSign)).build();
    const llookup = 'llookup:all:public:greeting.$_app$_atSign';

    test('with the default preference a read goes to the atServer', () async {
      final client = await open();
      wire.answer = (_) => 'data:null';

      await client.get(greeting);

      expect(wire.commands.map((c) => c.trim()), contains(llookup));
    });

    test('a passed localOnly prefs is kept and reads stay on the device',
        () async {
      final prefs = AtClientPreference()
        ..namespace = _app
        ..monitorAutoStart = false;

      final client = await open(prefs: prefs);
      await client.get(greeting).then((_) {}, onError: (_) {});

      expect(client.getPreferences(), same(prefs));
      expect(wire.commands.map((c) => c.trim()), isNot(contains(llookup)));
    });
  });

  group('sync', () {
    // Under remoteOnly only an explicit `useRemoteAtServer = false` keeps a
    // write local, so only then does sync carry it to the atServer.
    test(
        'a remoteOnly session syncs what a write with explicit false left local',
        () async {
      final client = await open();
      // A put checks the enrollment's namespace access first.
      wire.answer = (c) {
        if (c.startsWith('enroll:fetch')) {
          return 'data:{"appName":"a","deviceName":"d",'
              '"namespace":{"$_app":"rw","__manage":"rw"},"status":"approved"}';
        }
        // An atServer with nothing committed yet.
        if (c.startsWith('stats')) {
          return 'data:[{"id":"3","name":"lastCommitID","value":"-1"}]';
        }
        return null;
      };
      final note =
          (AtKey.self('note', namespace: _app)..sharedBy(_atSign)).build();
      await client.put(note, 'hello',
          putRequestOptions: PutRequestOptions()
            ..shouldEncrypt = false
            ..useRemoteAtServer = false);

      expect(wire.commands.where((c) => c.startsWith('update')), isEmpty,
          reason: 'the write went to local storage');
      final keyStore = client.getLocalSecondary()!.keyStore!;
      final local =
          await (await keyStore.getKeys(regex: 'note.$_app')).toList();
      expect(local, isNotEmpty);
      expect(wire.commands.where((c) => c.startsWith('batch:')), isEmpty,
          reason: 'nothing is pushed before sync runs');

      client.syncService.sync();
      await pumpEventQueue();
      expect(
          wire.commands.where((c) =>
              c.startsWith('batch:') && c.contains('note.$_app$_atSign')),
          isNotEmpty,
          reason: 'sync must push the local write: ${wire.commands}');
    });

    test('a localOnly session syncs', () async {
      final client = await open(
          prefs: AtClientPreference()
            ..namespace = _app
            ..monitorAutoStart = false);
      client.syncService.sync();
      await pumpEventQueue();

      expect(wire.commands.where((c) => c.startsWith('stats')), isNotEmpty);
    });
  });

  group('notifications', () {
    test('every connection is built with the injected finder', () async {
      final client = await open();
      client.notificationService.startListening();
      await pumpEventQueue();

      expect(wire.finders, isNotEmpty);
      // The client wraps the injected finder to remember its answer; every
      // connection must still resolve to the injected finder's address.
      for (final f in wire.finders) {
        final address = await f!.findSecondary(_atSign);
        expect('${address.host}:${address.port}', 'atserver.test:1');
      }
    });

    test('the notification monitor connects through the injected lookUps',
        () async {
      final client = await open();

      client.notificationService.startListening();
      await pumpEventQueue();

      final monitor = wire.lookUpsBuilt.where((l) => l.notificationStarts > 0);
      expect(monitor, hasLength(1));
      expect(monitor.single.authenticator, isNotNull);
    });

    test('a started monitor delivers what its lookUp receives to subscribers',
        () async {
      final client = await open();
      final service = client.notificationService;
      final received = service.subscribe(regex: 'ai6bh', shouldDecrypt: false);

      service.startListening();
      await pumpEventQueue();
      final lookUp =
          wire.lookUpsBuilt.singleWhere((l) => l.notificationStarts > 0);
      lookUp.inbound.add(jsonEncode({
        'id': 'n1',
        'from': '@bob',
        'to': _atSign,
        'key': '$_atSign:attalk.ai6bh@bob',
        'value': 'hi',
        'operation': 'update',
        'epochMillis': 42,
      }));

      final n = await received.first.timeout(Duration(seconds: 2));
      expect((n.from, n.value), ('@bob', 'hi'));
    });
  });

  group('atSign normalization', () {
    test('an atSign with whitespace is rejected before any dial', () async {
      await expectLater(
          open(atSign: '@alice '), throwsA(isA<InvalidAtSignException>()));
      expect(wire.dials, 0);
    });

    for (final input in ['alice', '@Alice']) {
      test('portalSession opens "$input" as @alice', () async {
        final client = await open(atSign: input);

        expect(client.getCurrentAtSign(), _atSign);
        expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
        await client.stop();
        await open(atSign: _atSign);
      });
    }
  });

  group('no key material is minted (D8)', () {
    test('classical keys: nothing written to the key store or the wire',
        () async {
      final keysIo = SessionKeysIo(_atSign, classicalAtKeys());
      await portalSession(
          atSign: _atSign,
          app: _app,
          keys: classicalAtKeys(),
          transport: transport(),
          keysIo: keysIo);
      await pumpEventQueue();

      expect(keysIo.refusedWrites, 0);
      expect(keysIo.refusedFlushes, 0);
      expect(wire.pkams, greaterThan(0));
      expect(wire.wroteToServer, isFalse, reason: '${wire.commands}');
    });

    for (final (name, keys) in <(String, AtKeys Function())>[
      ('an ML-DSA-65 signing key', mlDsaSigningAtKeys),
      ('a namespace key private', nskeyAtKeys),
    ]) {
      test('$name is rejected before any dial', () async {
        await expectLater(open(keys: keys()),
            throwsA(isA<UnsupportedKeyMaterialException>()));

        expect(wire.dials, 0);
        expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
      });
    }

    test('the session key store refuses write and flush', () async {
      final keysIo = SessionKeysIo(_atSign, classicalAtKeys());

      expect(await keysIo.read(_atSign), isA<AtKeys>());
      await expectLater(
          keysIo.write(_atSign, classicalAtKeys()), throwsStateError);
      expect(() => keysIo.flush(Atsign(_atSign), classicalAtKeys()),
          throwsStateError);
      expect((keysIo.refusedWrites, keysIo.refusedFlushes), (1, 1));
    });
  });
}

/// A [LoggingHandler] that appends `LEVEL|logger|message|error` to [lines].
class _Collect implements LoggingHandler {
  final List<String> lines;

  _Collect(this.lines);

  @override
  void call(record) => lines.add(
      '${record.level.name}|${record.loggerName}|${record.message}|${record.error}');
}
