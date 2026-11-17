import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookupMuxable;
import 'package:at_client_wasm/src/session/session_open.dart';
import 'package:test/test.dart';

import '../test_utils.dart';
import 'wire_fakes.dart';

const _atSign = '@alice';
const _app = 'wavi';

/// A [RecordSealer] that only records being closed.
class _Sealer implements RecordSealer {
  var closed = false;

  @override
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}

/// The key store a client is built on, counting the reads it served. The
/// client closes it as it stops, which runs [_onClose].
class _KeysIo extends SessionKeysIo implements ClosableAtKeysIo {
  _KeysIo(super.atSign, super.keys, [this._onClose]);

  final void Function()? _onClose;
  var reads = 0;

  @override
  bool get closedByClient => _onClose != null;

  @override
  void close() => _onClose?.call();

  @override
  FutureOr<AtKeys> read(String atsign) {
    reads++;
    return super.read(atsign);
  }
}

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;
  late _Sealer sealer;
  late PasskeyVault vault;

  SessionTransport transport() =>
      (lookUps: wire.lookUps, finder: finder, root: AtRootDomain.atsignDomain);

  AtLookupMuxable lookUp() => wire.lookUps(
      atSign: _atSign,
      rootDomain: AtRootDomain.atsignDomain,
      authenticator: null,
      secondaryAddressFinder: finder);

  var closeCalls = 0;

  /// The key store a passkey client runs on: closing it closes the vault.
  _KeysIo vaultKeysIo(String enrollmentId) =>
      _KeysIo(_atSign, classicalAtKeys(enrollmentId: enrollmentId), () {
        closeCalls++;
        vault.close();
      });

  Future<AtClient> open({String enrollmentId = 'eid1', _KeysIo? keysIo}) =>
      openSession(
          lookUp: lookUp(),
          atSign: _atSign,
          enrollmentId: enrollmentId,
          keysIo: keysIo ?? vaultKeysIo(enrollmentId),
          app: _app,
          transport: transport());

  setUp(() {
    wire = Wire();
    sealer = _Sealer();
    closeCalls = 0;
    vault = PasskeyVault((
      lookupHex: '0' * 64,
      ns: '1' * 64,
      authSeed: Uint8List(32)..fillRange(0, 32, 7),
      sealer: sealer,
    ), atSign: '@alice');
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    vault.close();
  });

  group('the keys store closes with the client', () {
    test('stopping the client closes the vault', () async {
      final client = await open();
      await expectLater(vault.withAuthSeed((_) async {}), completes,
          reason: 'the vault lives as long as the client');

      await client.stop();

      expect(sealer.closed, isTrue);
      await expectLater(
          vault.withAuthSeed((_) async {}), throwsA(isA<StateError>()));
      expect(closeCalls, 1);
    });

    test('a second stop does not close the session again', () async {
      final client = await open();

      await client.stop();
      await client.stop();

      expect(closeCalls, 1);
    });

    test('a client that is online has not closed its session', () async {
      await open();

      expect(closeCalls, 0);
      expect(sealer.closed, isFalse);
    });

    test('a client that does not come online closes its session', () async {
      wire.pkamAccepted = false;

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));

      expect(closeCalls, 1);
      expect(sealer.closed, isTrue);
      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
    });

    test('a session whose close fails still ends with the vault closed',
        () async {
      final client = await open();
      wire.stopThrows = true;
      addTearDown(() => wire.stopThrows = false);

      await expectLater(client.stop(), throwsA(isA<StateError>()));

      expect(sealer.closed, isTrue);
    });

    test('a close failure never replaces the error of an open that failed',
        () async {
      wire.pkamAccepted = false;
      wire.stopThrows = true;
      addTearDown(() => wire.stopThrows = false);

      await expectLater(open(), throwsA(isA<PortalSessionOfflineException>()));

      expect(sealer.closed, isTrue);
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

  test('the client reads its keys from the key store it was given', () async {
    final keysIo = vaultKeysIo('eid1');

    final client = await open(keysIo: keysIo);

    expect(keysIo.reads, greaterThan(0));
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
