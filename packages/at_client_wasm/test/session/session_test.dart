import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/session/remote_only_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../../tool/src/cut.dart';
import '../test_utils.dart';

const _atSign = '@alice';
const _app = 'wavi';

class FakeAtLookUp implements AtLookupMuxable {
  @override
  AtAuthenticator? authenticator;

  final inbound = StreamController<String>();
  var notificationStarts = 0;

  @override
  Stream<String> get notifications => inbound.stream;

  @override
  Stream<bool> get notificationConnectionUp => const Stream.empty();

  @override
  Future<void> startNotifications(
      {String? regex,
      Future<int?> Function()? getLastNotificationTime,
      bool selfNotificationsEnabled = true}) async {
    notificationStarts++;
  }

  @override
  bool isConnectionAvailable() => false;

  @override
  Future<void> close() async {}

  @override
  Future<void> stopNotifications() async {}

  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

AtLookupMuxable fakeLookUps(
        {required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder}) =>
    FakeAtLookUp()..authenticator = authenticator;

class FakeServerCopy implements ServerCopy {
  final Map<String, Uint8List> data = {};
  int fetches = 0;
  int puts = 0;

  void seed(Uint8List envelope) =>
      data[atKeysRecordKey(_atSign, _app)] = envelope;

  Uint8List? get held => data[atKeysRecordKey(_atSign, _app)];

  @override
  Future<Uint8List?> fetch(String atSign, String app) async {
    fetches++;
    return data[atKeysRecordKey(atSign, app)];
  }

  @override
  Future<void> put(String atSign, String app, Uint8List envelope) async {
    puts++;
    data[atKeysRecordKey(atSign, app)] = envelope;
  }
}

class CountingKeyBytesStore extends InMemoryKeyBytesStore {
  int puts = 0;

  @override
  Future<void> put(String atSign, Uint8List bytes) {
    puts++;
    return super.put(atSign, bytes);
  }
}

class FakeCredentialHintStore implements CredentialHintStore {
  final Map<String, Uint8List> data = {};

  @override
  Future<Uint8List?> credentialId(String atSign) async => data[atSign];

  @override
  Future<void> putCredentialId(String atSign, Uint8List id) async =>
      data[atSign] = id;
}

/// One passkey whose PRF output is [prfFirst]; [getError] / [createError] are
/// thrown by the matching ceremony when set.
class FakePasskeyPort implements PasskeyPort {
  FakePasskeyPort({int seed = 0})
      : prfFirst = Uint8List.fromList(List.generate(32, (i) => i + seed));

  Uint8List? prfFirst;
  Uint8List credentialId = Uint8List.fromList([1, 2, 3]);
  Object? getError;
  Object? createError;
  Uint8List? lastAllowCredential;

  PrfSecret get secret => PrfSecret(prfFirst!);

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput}) async {
    if (createError case final e?) throw e;
    return (credentialId: credentialId, prfFirst: prfFirst);
  }

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    lastAllowCredential = allowCredential;
    if (getError case final e?) throw e;
    return (credentialId: credentialId, prfFirst: prfFirst);
  }
}

class _CountingLocalRecordStore extends InMemoryLocalRecordStore {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }
}

void main() {
  final codec =
      KeyEnvelopeCodec(passphraseParams: Pbkdf2Sha256Params(iterations: 1));
  late AtKeys keys;
  late ({Uint8List envelope, PassphraseSecret passphrase}) cut;
  late FakeServerCopy server;
  late CountingKeyBytesStore store;
  late FakeCredentialHintStore hints;
  late int prompts;

  setUp(() async {
    keys = legacyAtKeys(atsign: Atsign(_atSign));
    cut = await cutEnvelope(keys, codec: codec);
    server = FakeServerCopy()..seed(cut.envelope);
    store = CountingKeyBytesStore();
    hints = FakeCredentialHintStore();
    prompts = 0;
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
  });

  Future<Uint8List> withUnlockFor(Uint8List envelope, PrfSecret prf) async =>
      (await codec.open(_atSign, envelope, cut.passphrase)).withUnlock(prf);

  Future<bool> opens(Uint8List? envelope, UnlockSecret secret) async {
    if (envelope == null) return false;
    try {
      await codec.open(_atSign, envelope, secret);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<AcquiredKeys> acquire(FakePasskeyPort port) => acquireKeys(
        atSign: _atSign,
        app: _app,
        store: store,
        kek: PasskeyKek(port),
        server: server,
        promptPassphrase: (_) async {
          prompts++;
          return cut.passphrase;
        },
        codec: codec,
        hintStore: hints,
      );

  group('acquireKeys', () {
    test(
        'first visit with no passkey prompts, registers, and keeps both '
        'unlocks on the device only', () async {
      final port = FakePasskeyPort()
        ..getError = PasskeyCeremonyException('no credential');

      final acquired = await acquire(port);

      expect(prompts, 1);
      expect(acquired.prf?.output, port.secret.output);
      expect(await opens(await store.get(_atSign), port.secret), isTrue);
      expect(await opens(await store.get(_atSign), cut.passphrase), isTrue);
      expect(server.puts, 0);
      expect(hints.data[_atSign], port.credentialId);
      expect((await acquired.keysIo.read(_atSign)).enrollmentToAuthenticateAs(),
          keys.enrollmentToAuthenticateAs());
    });

    test('return visit opens the device copy with the hinted passkey',
        () async {
      final port = FakePasskeyPort();
      await store.put(_atSign, await withUnlockFor(cut.envelope, port.secret));
      hints.data[_atSign] = port.credentialId;

      final acquired = await acquire(port);

      expect(prompts, 0);
      expect(server.fetches, 0);
      expect(port.lastAllowCredential, port.credentialId);
      expect(acquired.prf?.output, port.secret.output);
    });

    test(
        'return visit with the passkey gone falls back to the passphrase '
        'and registers a new passkey', () async {
      final old = FakePasskeyPort();
      await store.put(_atSign, await withUnlockFor(cut.envelope, old.secret));
      final port = FakePasskeyPort(seed: 100)
        ..getError = PasskeyCeremonyException('NotAllowedError');

      final acquired = await acquire(port);

      expect(prompts, 1);
      expect(server.fetches, 0);
      expect(acquired.prf?.output, port.secret.output);
      expect(await opens(await store.get(_atSign), port.secret), isTrue);
    });

    test(
        'a cleared device with a synced passkey opens the server copy '
        'without a prompt', () async {
      final port = FakePasskeyPort();
      server.seed(await withUnlockFor(cut.envelope, port.secret));

      final acquired = await acquire(port);

      expect(prompts, 0);
      expect(await store.get(_atSign), server.held);
      expect(acquired.prf?.output, port.secret.output);
    });

    for (final (name, port) in [
      ('returns no PRF result', FakePasskeyPort()..prfFirst = null),
      (
        'is cancelled',
        FakePasskeyPort()..createError = PasskeyCeremonyException('cancelled')
      ),
    ]) {
      test(
          'registration that $name holds the keys in memory and writes '
          'nothing', () async {
        port.getError = PasskeyCeremonyException('no credential');

        final acquired = await acquire(port);

        expect(acquired.prf, isNull);
        expect(store.puts, 0);
        expect(server.puts, 0);
        expect(
            (await acquired.keysIo.read(_atSign)).enrollmentToAuthenticateAs(),
            keys.enrollmentToAuthenticateAs());
      });
    }

    test('a wrong passphrase surfaces the codec error', () async {
      final port = FakePasskeyPort()
        ..getError = PasskeyCeremonyException('no credential');

      await expectLater(
          acquireKeys(
              atSign: _atSign,
              app: _app,
              store: store,
              kek: PasskeyKek(port),
              server: server,
              promptPassphrase: (_) async => PassphraseSecret.generate(),
              codec: codec),
          throwsA(isA<EnvelopeUnlockFailedException>()));
      expect(store.puts, 0);
    });

    test('a passkey failure that is not a ceremony outcome propagates',
        () async {
      final port = FakePasskeyPort()..getError = StateError('port bug');

      await expectLater(acquire(port), throwsStateError);
      expect(prompts, 0);
    });

    test('no device copy and no server copy is a StateError', () async {
      server.data.clear();

      await expectLater(acquire(FakePasskeyPort()), throwsStateError);
    });
  });

  group('acquireKeys with an upload callback', () {
    late int uploads;
    late AtKeys uploaded;

    setUp(() {
      server.data.clear();
      uploads = 0;
      uploaded = keys;
    });

    Future<AcquiredKeys> acquireUploading(FakePasskeyPort port) => acquireKeys(
          atSign: _atSign,
          app: _app,
          store: store,
          kek: PasskeyKek(port),
          server: server,
          promptPassphrase: (_) async {
            prompts++;
            return cut.passphrase;
          },
          uploadAtKeys: (_) async {
            uploads++;
            return uploaded;
          },
          codec: codec,
          hintStore: hints,
        );

    test('seals the upload under the passkey alone and stores it', () async {
      final port = FakePasskeyPort();

      final acquired = await acquireUploading(port);

      expect(uploads, 1);
      expect(prompts, 0);
      expect(acquired.prf?.output, port.secret.output);
      final stored = await store.get(_atSign);
      expect(await opens(stored, port.secret), isTrue);
      expect(await opens(stored, cut.passphrase), isFalse);
      expect(hints.data[_atSign], port.credentialId);
      expect(server.puts, 0);
      expect((await acquired.keysIo.read(_atSign)).enrollmentToAuthenticateAs(),
          keys.enrollmentToAuthenticateAs());
    });

    test('the next open uses the passkey and never asks for the file',
        () async {
      final port = FakePasskeyPort();
      await acquireUploading(port);

      final again = await acquireUploading(port);

      expect(uploads, 1);
      expect(prompts, 0);
      expect(again.prf?.output, port.secret.output);
    });

    test('a passkey with no PRF holds the upload in memory and writes nothing',
        () async {
      final port = FakePasskeyPort()..prfFirst = null;

      final acquired = await acquireUploading(port);

      expect(acquired.prf, isNull);
      expect(store.puts, 0);
      expect(server.puts, 0);
      expect((await acquired.keysIo.read(_atSign)).enrollmentToAuthenticateAs(),
          keys.enrollmentToAuthenticateAs());
    });

    test('a file for another atSign is rejected and nothing is stored',
        () async {
      uploaded = legacyAtKeys(atsign: Atsign('@bob'));

      await expectLater(
          acquireUploading(FakePasskeyPort()), throwsArgumentError);
      expect(store.puts, 0);
    });

    test('a legacy file that names no atSign is accepted', () async {
      // Real `.atKeys` files carry no atSign; the page's filename is the
      // only claim, so rejecting null would reject every genuine file.
      uploaded = legacyAtKeys();

      final acquired = await acquireUploading(FakePasskeyPort());

      expect(uploads, 1);
      expect(await opens(await store.get(_atSign), FakePasskeyPort().secret),
          isTrue);
      expect(acquired.prf, isNotNull);
    });

    test('a device copy means the callback is never called', () async {
      final port = FakePasskeyPort();
      await store.put(_atSign, await withUnlockFor(cut.envelope, port.secret));
      hints.data[_atSign] = port.credentialId;

      await acquireUploading(port);

      expect(uploads, 0);
    });

    test('a server copy means the callback is never called', () async {
      final port = FakePasskeyPort();
      server.seed(await withUnlockFor(cut.envelope, port.secret));

      await acquireUploading(port);

      expect(uploads, 0);
    });
  });

  group('heal', () {
    final prf = FakePasskeyPort().secret;

    Future<HealOutcome> healNow() => heal(
        atSign: _atSign,
        app: _app,
        store: store,
        server: server,
        prf: prf,
        codec: codec);

    test('adds our unlock to a server copy that lacks it', () async {
      await store.put(_atSign, await withUnlockFor(cut.envelope, prf));

      expect(await healNow(), HealOutcome.healed);
      expect(server.puts, 1);
      expect(await opens(server.held, prf), isTrue);
      expect(await opens(server.held, cut.passphrase), isTrue);
    });

    test('leaves a server copy that already opens with our unlock', () async {
      server.seed(await withUnlockFor(cut.envelope, prf));
      await store.put(_atSign, server.held!);

      expect(await healNow(), HealOutcome.alreadyPresent);
      expect(server.puts, 0);
    });

    test('writes nothing when the device has no copy', () async {
      expect(await healNow(), HealOutcome.missingCopy);
      expect(server.puts, 0);
    });

    test('leaves a server copy sealed under another content key', () async {
      final recut = await cutEnvelope(keys, codec: codec);
      server.seed(recut.envelope);
      await store.put(_atSign, await withUnlockFor(cut.envelope, prf));

      expect(await healNow(), HealOutcome.contentKeyMismatch);
      expect(server.puts, 0);
      expect(server.held, recut.envelope);
    });
  });

  group('sessions', () {
    final prefs = AtClientPreference()
      ..namespace = _app
      ..monitorAutoStart = false;
    final finder = FixedSecondaryAddressFinder('proxy.test', 1);

    Future<AtClient> remoteOnly(
            AtClientPreference prefs, AtLookUpFactory lookUps) async =>
        (await remoteOnlyClient(
                atSign: _atSign,
                app: _app,
                prefs: prefs,
                keysIo: InMemoryAtKeysIo.holding(_atSign, keys),
                lookUps: lookUps,
                secondaryAddressFinder: finder))
            .client;

    test(
        'remote-only client retries cleanly after a start that failed past storage attach',
        () async {
      final failing = AtClientPreference()
        ..namespace = _app
        ..monitorAutoStart = false
        ..crypto = CryptoConfig(defaultProviderId: 'missing');

      Future<AtClient> attempt(AtClientPreference p) =>
          remoteOnly(p, fakeLookUps);

      await expectLater(
          attempt(failing), throwsA(isA<CryptoProviderNotRegistered>()));
      final client = await attempt(prefs);

      expect(
          (client as AtClientImpl).storage, isA<RemoteOnlyAtClientStorage>());
    });

    test(
        'remote-only client retries cleanly after a start that failed past client build',
        () async {
      var calls = 0;
      AtLookupMuxable failingMonitor(
              {required String atSign,
              required AtRootDomain rootDomain,
              required AtAuthenticator? authenticator,
              SecondaryAddressFinder? secondaryAddressFinder}) =>
          ++calls > 1
              ? throw StateError('monitor lookUp')
              : fakeLookUps(
                  atSign: atSign,
                  rootDomain: rootDomain,
                  authenticator: authenticator);

      Future<AtClient> attempt(AtLookUpFactory lookUps) =>
          remoteOnly(prefs, lookUps);

      await expectLater(attempt(failingMonitor), throwsStateError);
      final client = await attempt(fakeLookUps);

      expect(
          (client as AtClientImpl).storage, isA<RemoteOnlyAtClientStorage>());
    });

    test('the notification monitor connects through the injected lookUps',
        () async {
      final client = await remoteOnly(prefs, fakeLookUps);

      final service = client.notificationService as NotificationServiceImpl;
      expect(service.monitor.lookUp, isA<FakeAtLookUp>());
      expect((service.monitor.lookUp as FakeAtLookUp).authenticator, isNotNull);
    });

    test('the notification service resolves atSigns with the injected finder',
        () async {
      final client = await remoteOnly(prefs, fakeLookUps);

      final service = client.notificationService as NotificationServiceImpl;
      final address =
          await service.secondaryAddressFinder.findSecondary('@bob');
      expect((address.host, address.port), ('proxy.test', 1));
    });

    test('a started monitor delivers what its lookUp receives to subscribers',
        () async {
      final client = await remoteOnly(prefs, fakeLookUps);
      final service = client.notificationService as NotificationServiceImpl;
      final lookUp = service.monitor.lookUp as FakeAtLookUp;
      final received = service.subscribe(regex: 'ai6bh', shouldDecrypt: false);

      service.startListening();
      await pumpEventQueue();
      expect(lookUp.notificationStarts, 1);

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

    test('remote-only client storage is remote-only and authenticates',
        () async {
      final client = await remoteOnly(prefs, fakeLookUps);

      final storage =
          (client as AtClientImpl).storage! as RemoteOnlyAtClientStorage;
      expect((storage.remoteSecondary.atLookUp as FakeAtLookUp).authenticator,
          isNotNull);
    });

    test('Mode P first visit heals the server copy after start', () async {
      final port = FakePasskeyPort()
        ..getError = PasskeyCeremonyException('no credential');

      final client = await portalSession(
          atSign: _atSign,
          app: _app,
          prefs: prefs,
          lookUps: fakeLookUps,
          secondaryAddressFinder: finder,
          store: store,
          kek: PasskeyKek(port),
          server: server,
          healServer: (_) => server,
          promptPassphrase: (_) async => cut.passphrase,
          codec: codec);

      expect(
          (client as AtClientImpl).storage, isA<RemoteOnlyAtClientStorage>());
      expect(server.puts, 1);
      expect(await opens(server.held, port.secret), isTrue);
      expect(await opens(server.held, cut.passphrase), isTrue);
    });

    test('Mode P resolves atSigns with the injected finder', () async {
      final client = await portalSession(
          atSign: _atSign,
          app: _app,
          prefs: prefs,
          lookUps: fakeLookUps,
          secondaryAddressFinder: finder,
          store: store,
          kek: PasskeyKek(FakePasskeyPort()
            ..getError = PasskeyCeremonyException('no credential')),
          server: server,
          healServer: (_) => server,
          promptPassphrase: (_) async => cut.passphrase,
          codec: codec);

      final service = client.notificationService as NotificationServiceImpl;
      final address =
          await service.secondaryAddressFinder.findSecondary('@bob');
      expect((address.host, address.port), ('proxy.test', 1));
    });

    test('Mode P heals over the client\'s own RemoteSecondary', () async {
      final port = FakePasskeyPort()
        ..getError = PasskeyCeremonyException('no credential');
      RemoteSecondary? healedOver;

      final client = await portalSession(
          atSign: _atSign,
          app: _app,
          prefs: prefs,
          lookUps: fakeLookUps,
          secondaryAddressFinder: finder,
          store: store,
          kek: PasskeyKek(port),
          server: server,
          healServer: (remote) {
            healedOver = remote;
            return server;
          },
          promptPassphrase: (_) async => cut.passphrase,
          codec: codec);

      final storage =
          (client as AtClientImpl).storage! as RemoteOnlyAtClientStorage;
      expect(healedOver, same(storage.remoteSecondary));
      expect(healedOver, same(client.getRemoteSecondary()));
    });

    test('a create that fails closes the local record store it was given once',
        () async {
      final localStore = _CountingLocalRecordStore();
      final failing = AtClientPreference()
        ..namespace = _app
        ..monitorAutoStart = false
        ..crypto = CryptoConfig(defaultProviderId: 'missing');

      await expectLater(
          remoteOnlyClient(
              atSign: _atSign,
              app: _app,
              prefs: failing,
              keysIo: InMemoryAtKeysIo.holding(_atSign, keys),
              lookUps: fakeLookUps,
              secondaryAddressFinder: finder,
              openLocalRecords: (_) async => localStore),
          throwsA(isA<CryptoProviderNotRegistered>()));

      expect(localStore.closeCount, 1);
    });

    test('a local record store that fails to open builds no connection',
        () async {
      var lookUpCalls = 0;
      AtLookupMuxable countingLookUps(
          {required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder}) {
        lookUpCalls++;
        return fakeLookUps(
            atSign: atSign,
            rootDomain: rootDomain,
            authenticator: authenticator,
            secondaryAddressFinder: secondaryAddressFinder);
      }

      await expectLater(
          remoteOnlyClient(
              atSign: _atSign,
              app: _app,
              prefs: prefs,
              keysIo: InMemoryAtKeysIo.holding(_atSign, keys),
              lookUps: countingLookUps,
              secondaryAddressFinder: finder,
              openLocalRecords: (_) async => throw StateError('no db')),
          throwsA(isA<StateError>()));

      expect(lookUpCalls, 0);
    });

    test(
        'a connection that fails to build closes the opened local record store once',
        () async {
      final localStore = _CountingLocalRecordStore();

      await expectLater(
          remoteOnlyClient(
              atSign: _atSign,
              app: _app,
              prefs: prefs,
              keysIo: InMemoryAtKeysIo.holding(_atSign, keys),
              lookUps: ({
                required String atSign,
                required AtRootDomain rootDomain,
                required AtAuthenticator? authenticator,
                SecondaryAddressFinder? secondaryAddressFinder,
              }) =>
                  throw StateError('no lookup'),
              secondaryAddressFinder: finder,
              openLocalRecords: (_) async => localStore),
          throwsA(isA<StateError>()));

      expect(localStore.closeCount, 1);
    });

    test(
        'openLocalRecords is called with the keys enrollment and its store holds local: records',
        () async {
      final localStore = InMemoryLocalRecordStore();
      final opened = <String?>[];

      final client = (await remoteOnlyClient(
              atSign: _atSign,
              app: _app,
              prefs: prefs,
              keysIo: InMemoryAtKeysIo.holding(_atSign, keys),
              lookUps: fakeLookUps,
              secondaryAddressFinder: finder,
              openLocalRecords: (enrollmentId) async {
                opened.add(enrollmentId);
                return localStore;
              }))
          .client;

      expect(opened, [keys.enrollmentToAuthenticateAs()]);

      await (client as AtClientImpl).storage!.keyStore.put(
          'local:a@alice',
          AtData()
            ..data = 'v1'
            ..metaData = AtMetaData());

      expect((await localStore.get('local:a@alice'))!.data, 'v1');
    });
  });
}
