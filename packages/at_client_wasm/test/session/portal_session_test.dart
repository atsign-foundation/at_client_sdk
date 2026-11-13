import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import '../test_utils.dart';
import 'wire_fakes.dart';

const _atSign = '@alice';
const _app = 'wavi';

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;

  SessionTransport transport() => (lookUps: wire.lookUps, finder: finder);

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
    test('the default preference routes reads to the atServer', () async {
      final client = await open();

      expect(
          client.getPreferences()!.remoteLocalPref, RemoteLocalPref.remoteOnly);
    });

    test('a passed prefs is kept as it is', () async {
      final prefs = AtClientPreference()
        ..namespace = _app
        ..monitorAutoStart = false;

      final client = await open(prefs: prefs);

      expect(client.getPreferences(), same(prefs));
      expect(prefs.remoteLocalPref, RemoteLocalPref.localOnly);
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
    for (final input in ['alice', '@Alice', ' @alice ']) {
      test('portalSession opens "$input" as @alice', () async {
        final client = await open(atSign: input);

        expect(client.getCurrentAtSign(), _atSign);
        expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
        await client.stop();
        await open(atSign: _atSign);
      });

      test('DevSessionOptions holds "$input" as @alice', () {
        expect(DevSessionOptions(atSign: input, app: _app).atSign, _atSign);
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
