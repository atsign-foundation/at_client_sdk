import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client_io.dart';
import 'package:at_auth/at_auth.dart'
    show AtKeysAssurance, AtKeysPassphraseEnvelopeCodec;
import 'package:at_auth/passkey.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'support/custody_fakes.dart' show DerivedKeys;
import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// A key store that records, in the order they happen, its closes and what it
/// was told by [events].
class _KeysIo extends InMemoryAtKeysIo implements ClosableAtKeysIo {
  _KeysIo(this.atSign, this.events, {this.closedByClient = false}) {
    flushSeed();
  }

  final String atSign;
  final List<String> events;

  @override
  final bool closedByClient;

  /// What `close()` throws, when set.
  Object? closeThrows;
  int closes = 0;

  void flushSeed() => flush(atSign.toAtsign(), AtKeys());

  @override
  Future<void> close() async {
    closes++;
    events.add('keys.close');
    if (closeThrows case final e?) throw e;
  }
}

/// A key store holding a slot for [enrollmentId], that is closed by its
/// client and records any update that arrives after it was closed.
class _EnrolledKeysIo extends InMemoryAtKeysIo implements ClosableAtKeysIo {
  _EnrolledKeysIo(this.atSign, this.events);

  final String atSign;
  final List<String> events;
  static const enrollmentId = 'stored-1';

  @override
  bool get closedByClient => true;

  int closes = 0;
  bool closed = false;
  final failures = <Object>[];

  Future<void> seed() => write(
      atSign.toAtsign(),
      AtKeys.legacy(
          apkamPublicKey: 'YQ==',
          apkamPrivateKey: 'Yg==',
          encryptionPublicKey: 'Yw==',
          encryptionPrivateKey: 'ZA==',
          selfEncryptionKey: 'ZQ==',
          enrollmentId: enrollmentId));

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) change) async {
    if (closed) {
      final error = StateError('update on a closed key store');
      failures.add(error);
      throw error;
    }
    events.add('keys.update');
    await super.update(atsign, change);
  }

  @override
  Future<void> close() async {
    closes++;
    closed = true;
    events.add('keys.close');
  }
}

/// A storage whose attach is refused, so the client's init fails.
class _RefusingStorage extends InMemoryAtClientStorage {
  _RefusingStorage(String atSign) : super(atSign: atSign);

  @override
  Future<void> attach(AtClient client) async =>
      throw StateError('the storage refused the client');
}

void main() {
  final events = <String>[];

  AtClientPreference prefs() => AtClientPreference()
    ..namespace = 'wavi'
    ..monitorAutoStart = false
    ..rootDomain = 'test.atsign.wtf';

  MockAtLookupImpl handedLookUp() {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    when(() => lookUp.close())
        .thenAnswer((_) async => events.add('lookUp.close'));
    when(() => lookUp.stop())
        .thenAnswer((_) async => events.add('lookUp.stop'));
    when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'data:null');
    return lookUp;
  }

  AtLookupMuxable recording({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'data:null');
    return lookUp;
  }

  Future<AtClientImpl> build(String atSign, AtKeysIo keys,
          {AtLookUp? atLookUp, AtClientStorage? storage}) async =>
      await buildAtClient(
              atSign: atSign,
              namespace: 'wavi',
              preference: prefs(),
              secondaryAddressFinder: defaultAtDirectory,
              atKeysIo: keys,
              atLookUp: atLookUp,
              lookUps: recording,
              storage: storage ?? InMemoryAtClientStorage(atSign: atSign))
          as AtClientImpl;

  setUpAll(() => registerFallbackValue(AtKey()));

  setUp(events.clear);

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      try {
        await c.stop();
      } catch (_) {
        // Teardown: a client the test already stopped or broke may fail to stop again.
      }
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('stop() and the key store', () {
    test('closes a flagged key store once, after the lookUp has stopped',
        () async {
      final keys = _KeysIo('@keysflagged', events, closedByClient: true);
      final client =
          await build('@keysflagged', keys, atLookUp: handedLookUp());

      await client.stop();
      await client.stop();

      expect(keys.closes, 1);
      expect(events, ['lookUp.stop', 'keys.close']);
    });

    test('never closes a key store it was lent', () async {
      final keys = _KeysIo('@keyslent', events);
      final client = await build('@keyslent', keys, atLookUp: handedLookUp());

      await client.stop();

      expect(keys.closes, 0);
    });

    test('an Exception from the close is rethrown once every step has run',
        () async {
      final error = Exception('close failed');
      final keys = _KeysIo('@keysthrows', events, closedByClient: true)
        ..closeThrows = error;
      final client = await build('@keysthrows', keys);

      await expectLater(client.stop(), throwsA(same(error)));

      expect(keys.closes, 1);
      expect(AtClientImpl.atClientInstanceMap.containsValue(client), isFalse,
          reason: 'the step after the keys close ran before the rethrow');
      expect(client.isStopped, isTrue);
    });

    test('an Error from the close is rethrown once every step has run',
        () async {
      final error = StateError('close defect');
      final keys = _KeysIo('@keysdefect', events, closedByClient: true)
        ..closeThrows = error;
      final client = await build('@keysdefect', keys);

      await expectLater(client.stop(), throwsA(same(error)));

      expect(AtClientImpl.atClientInstanceMap.containsValue(client), isFalse,
          reason: 'the step after the keys close ran before the rethrow');
      await expectLater(client.stop(), throwsA(same(error)),
          reason: 'a second stop() reports the one teardown, and runs nothing');
      expect(keys.closes, 1);
    });

    test('a client that failed to build leaves the key store open', () async {
      final keys = _KeysIo('@keysfailed', events, closedByClient: true);

      await expectLater(
          build('@keysfailed', keys, storage: _RefusingStorage('@keysfailed')),
          throwsStateError);
      expect(AtClientImpl.atClientInstanceMap, isEmpty);

      expect(keys.closes, 0,
          reason: 'the key store is still the caller\'s: it passed to the '
              'client only once the client was built');
    });

    test('a key store that is not closable is stopped without a close',
        () async {
      final keys = _PlainKeysIo('@keysplain');
      final client = await build('@keysplain', keys);

      await client.stop();

      expect(keys.reads, greaterThan(0),
          reason: 'the client ran on the store that has no close');
    });

    test('a mocked key store that says it is lent is not closed', () async {
      final keys = MockKeysIo();
      when(() => keys.closedByClient).thenReturn(false);
      when(() => keys.read(any())).thenAnswer((_) async => AtKeys());
      final client = await build('@keysmock', keys);

      await client.stop();

      verifyNever(() => keys.close());
    });
  });

  group('stop() and a PQ startup still writing the key store', () {
    late Completer<void> fetchGate;
    late Completer<void> fetched;
    var fetches = 0;

    setUp(() {
      fetchGate = Completer<void>();
      fetched = Completer<void>();
      fetches = 0;
    });

    tearDown(() {
      if (!fetchGate.isCompleted) fetchGate.complete();
    });

    // A client whose only startup step is the one that records the
    // enrollment snapshot, held at the atServer's answer so the write to the
    // key store is still to come.
    Future<AtClientImpl> buildHeld(_EnrolledKeysIo keys) async {
      await keys.seed();
      final remote = MockRemoteSecondary();
      when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((invocation) async {
        final command = invocation.positionalArguments[0] as String;
        if (!command.startsWith('enroll:fetch')) return 'data:null';
        fetches++;
        if (!fetched.isCompleted) fetched.complete();
        await fetchGate.future;
        return 'data:${jsonEncode({
              'appName': 'app',
              'deviceName': 'device',
              'namespace': {'wavi': 'rw'},
            })}';
      });
      final client = await AtClientImpl.create(
          keys.atSign,
          'wavi',
          AtClientPreference(
              pqStartupGates: const PqStartupGates(
            hydrateHeldSecrets: false,
            collectConveyedKeys: false,
            startEnvelopeListener: false,
            mintInUseSigningKeys: false,
            refreshOwnLinks: false,
            reconcileKeyPackage: false,
            seedNamespaceKeys: false,
            requestRootPrivate: false,
            requestMissingPrivates: false,
            anchorOwnKeys: false,
            sweepUnanchoredEnrollments: false,
            askOnReadMiss: false,
          ))
            ..namespace = 'wavi'
            ..monitorAutoStart = false
            ..rootDomain = 'test.atsign.wtf',
          lookUps: recording,
          secondaryAddressFinder: defaultAtDirectory,
          atKeysIo: keys,
          remoteSecondary: remote,
          storage: InMemoryAtClientStorage(atSign: keys.atSign));
      await fetched.future.timeout(const Duration(seconds: 5));
      expect(fetches, 1, reason: 'the startup is waiting on the atServer');
      return client as AtClientImpl;
    }

    test('waits for the write in flight, then closes the key store', () async {
      final keys = _EnrolledKeysIo('@keysinflight', events);
      final client = await buildHeld(keys);

      final stopped = client.stop();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(keys.closes, 0, reason: 'the startup has a write to make');
      fetchGate.complete();
      await stopped;

      expect(keys.failures, isEmpty);
      expect(keys.closes, 1);
      expect(events.indexOf('keys.update'),
          lessThan(events.indexOf('keys.close')));
    });

    test('a step that never finishes holds stop only for the grace period',
        () async {
      final keys = _EnrolledKeysIo('@keysnever', events);
      final client = await buildHeld(keys)
        ..pqStartupStopGrace = Duration.zero;

      // The fetch gate is never released, so only the grace period, which
      // is not waited out in real time here, lets stop() finish.
      await client.stop();

      expect(keys.closes, 1);
      expect(client.isStopped, isTrue);
    });
  });

  group('stop() and a key-store write held open past the grace', () {
    test('stop completes; the write finishes whole and none starts after',
        () async {
      final atSign = '@keyswrite';
      final derived = await DerivedKeys.derive(
          Uint8List.fromList(List.generate(32, (i) => i + 1)), atSign);
      final pair = await apkamKeyPairFromSeed(
          Uint8List.fromList(List.generate(32, (i) => i + 100)));
      final documents = _GatedDocuments(await derived.vault
          .seal(PasskeyRecordType.atkeys, AtKeys().toJson()));
      final keys = AtServerAtKeysIo(
          documents: documents,
          vault: derived.vault,
          enrollmentId: 'e1',
          apkamKeyPair: pair,
          closedByClient: true);
      final client = await build(atSign, keys, atLookUp: handedLookUp())
        ..pqStartupStopGrace = Duration.zero;
      documents.hold = Completer<void>();
      final write = keys.update(atSign.toAtsign(), (k) => true);
      await documents.putArrived.future;
      final late = keys.update(atSign.toAtsign(), (k) => true);
      final lateOutcome =
          expectLater(late, throwsA(isA<AtServerAtKeysWriteException>()));

      await client.stop();

      expect(client.isStopped, isTrue);
      documents.hold!.complete();
      await write;
      await lateOutcome;
      expect(documents.puts, 1, reason: 'the held write only; none after');
      await expectLater(
          derived.vault.withAuthSeed((_) async {}), throwsStateError);
    });
  });

  group('stop() and the lookUp it was handed', () {
    test('stops that lookUp, and does not close it', () async {
      final lookUp = handedLookUp();
      final client = await build('@handedlookup', noKeysFor('@handedlookup'),
          atLookUp: lookUp);

      await client.stop();

      verify(() => lookUp.stop()).called(1);
      verifyNever(() => lookUp.close());
      expect(events, ['lookUp.stop']);
    });
  });
}

/// A key store that implements the interface and nothing about lifetime.
class _PlainKeysIo implements WrittenAtKeysIo {
  _PlainKeysIo(String atSign) {
    inner.flush(atSign.toAtsign(), AtKeys());
  }

  final inner = InMemoryAtKeysIo();
  int reads = 0;

  @override
  AtKeysPassphraseEnvelopeCodec get passphraseCodec => inner.passphraseCodec;

  @override
  AtKeysAssurance get assurance => inner.assurance;

  @override
  Future<AtKeys> read(String atsign) async {
    reads++;
    return inner.read(atsign);
  }

  @override
  Future write(String atsign, AtKeys atKeys) => inner.write(atsign, atKeys);

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) =>
      inner.flush(atsign, atKeys);

  @override
  Future<void> update(
          Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) =>
      inner.update(atsign, mutate);
}

class MockKeysIo extends Mock implements WrittenAtKeysIo, ClosableAtKeysIo {}

/// A document store whose put can be held open, counting the puts it saw.
class _GatedDocuments implements EnrollmentDocumentStore {
  _GatedDocuments(this._document);

  String _document;
  Completer<void>? hold;
  final putArrived = Completer<void>();
  int puts = 0;

  @override
  Future<String?> get(String atSign, String enrollmentId) async => _document;

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    puts++;
    if (!putArrived.isCompleted) putArrived.complete();
    await hold?.future;
    _document = document;
  }
}
