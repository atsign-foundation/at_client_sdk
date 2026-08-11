import 'dart:async' show StreamController, TimeoutException;
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {
}

class FakeSyncProgressListener extends Fake implements SyncProgressListener {}

class TestSharer
    with
        ApkamSigning,
        EnvelopeSigning,
        KeyPackageRegistration,
        PairwiseSecretSharing {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestSharer');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestSharer(this.atClient);
}

void main() {
  const atSign = '@alice';

  /// Simulates the atServer's keystore: full key string -> value. The same
  /// map backs every mocked client's put/get/scan/delete, modelling the
  /// post-sync state in which sender writes are visible to recipients.
  ///
  /// Because one map serves as both the local store and the atServer, this
  /// fixture **cannot** tell a local-first write from a remote-first one on
  /// the read side. That distinction matters — a local-first envelope waits
  /// for a sync cycle while its wake-up notify goes straight out, so a
  /// sync-less recipient can remote-sweep before the value lands — so the
  /// options each put was made with are recorded in [putOptions] and asserted
  /// directly instead.
  late Map<String, String> remoteData;

  /// Full key string -> the [PutRequestOptions] that wrote it, so routing can
  /// be asserted where [remoteData] alone is blind to it.
  late Map<String, PutRequestOptions> putOptions;

  /// One entry per envelope scan: whether it was routed to the atServer. Same
  /// reason as [putOptions] — the merged store makes a local scan and a remote
  /// one indistinguishable by their results.
  late List<bool> scanRoutedRemote;

  /// Simulates the atServer fanning self-notifications to every one of the
  /// atSign's monitors: a notify() on any client adds to this bus, and every
  /// client's subscribe() reads from it (filtered by regex).
  late StreamController<AtNotification> notificationBus;

  /// Shared across the test's sharers so one's registered key package is
  /// discoverable by another.
  late FakeEnrollmentDirectory directory;

  // Deterministic X-Wing seeds injected as stable identities.
  final Uint8List seedA = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final Uint8List seedB =
      Uint8List.fromList(List<int>.generate(32, (i) => 32 + i));
  final Uint8List seedC =
      Uint8List.fromList(List<int>.generate(32, (i) => 64 + i));

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeSyncProgressListener());
    registerFallbackValue(NotificationParams.forUpdate(AtKey()));
  });

  MockAtClient buildMockClient(String enrollmentId,
      {MockSyncService? syncService}) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    final sync = syncService ?? MockSyncService();
    when(() => atClient.syncService).thenReturn(sync);
    if (syncService == null) {
      // A client whose sync isn't delivering these envelopes: the wake-up
      // path is its only route, so listener registration is a no-op.
      when(() => sync.addProgressListener(any())).thenAnswer((_) {});
      when(() => sync.removeProgressListener(any())).thenAnswer((_) {});
    }

    final notificationService = MockNotificationService();
    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => notificationService.notify(any(),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        encryptValue: any(named: 'encryptValue'))).thenAnswer((inv) {
      // model the atServer fanning the self-notification to every monitor
      final params = inv.positionalArguments[0] as NotificationParams;
      notificationBus.add(AtNotification.empty()
        ..id = 'wake'
        ..key = params.atKey.toString()
        ..from = atSign
        ..to = atSign);
      return Future.value(NotificationResult());
    });
    when(() => notificationService.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return notificationBus.stream.where((n) => regex.hasMatch(n.key));
    });

    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookUp();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      final keyString = inv.positionalArguments[0].toString();
      remoteData[keyString] = inv.positionalArguments[1];
      final options = inv.namedArguments[#putRequestOptions];
      if (options is PutRequestOptions) {
        putOptions[keyString] = options;
      }
      return Future.value(true);
    });
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((inv) {
      final keyString = inv.positionalArguments[0].toString();
      final value = remoteData[keyString];
      if (value == null) {
        throw AtKeyNotFoundException('$keyString not found');
      }
      return Future.value(AtValue()..value = value);
    });
    when(() => atClient.get(any())).thenAnswer((inv) {
      final keyString = inv.positionalArguments[0].toString();
      final value = remoteData[keyString];
      if (value == null) {
        throw AtKeyNotFoundException('$keyString not found');
      }
      return Future.value(AtValue()..value = value);
    });
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      scanRoutedRemote.add(inv.namedArguments[#useRemoteAtServer] == true);
      return Future.value(remoteData.keys
          .where((k) => regex.hasMatch(k))
          .map(AtKey.fromString)
          .toList());
    });
    when(() => atClient.delete(any(),
        deleteRequestOptions: any(named: 'deleteRequestOptions'))).thenAnswer(
      (inv) {
        remoteData.remove(inv.positionalArguments[0].toString());
        return Future.value(true);
      },
    );
    when(() => atClient.delete(any())).thenAnswer(
      (inv) {
        remoteData.remove(inv.positionalArguments[0].toString());
        return Future.value(true);
      },
    );
    return atClient;
  }

  TestSharer buildSharer(String enrollmentId, Uint8List seed,
      {MockSyncService? syncService}) {
    final sharer =
        TestSharer(buildMockClient(enrollmentId, syncService: syncService))
          ..directory = directory
          // Deterministic and instant: the jitter exists to spread real
          // responders apart, and a test that waits for it is only testing
          // Future.delayed. The suppression it enables is asserted directly.
          ..requestAnswerJitter = Duration.zero;
    sharer.loadApkamKeys =
        () async => PersistedApkamKeys(encSeed: base64Encode(seed));
    return sharer;
  }

  late TestSharer sharerA;
  late TestSharer sharerB;

  setUp(() async {
    remoteData = {};
    putOptions = {};
    scanRoutedRemote = [];
    notificationBus = StreamController<AtNotification>.broadcast();
    directory = FakeEnrollmentDirectory();
    sharerA = buildSharer('enroll-a', seedA);
    sharerB = buildSharer('enroll-b', seedB);
    // register() prepares each keypair + publishes its signing key; the key
    // package reaches the directory via enroll:request in production, modelled
    // here with seed() so peers discover each other via listForNamespace.
    directory.seed('enroll-a', await sharerA.register());
    directory.seed('enroll-b', await sharerB.register());
  });

  tearDown(() async {
    sharerA.stopListening();
    sharerB.stopListening();
    await notificationBus.close();
  });

  group('sendEnvelope', () {
    test(
        'stores a raw-JSON, ttl\'d, unencrypted self key addressed to the '
        'recipient kpid through the app namespace', () async {
      sharerA.envelopeTtl = Duration(hours: 1);
      await sharerA
          .sendEnvelope(sharerB.myKeyPackage, 'myapp', {'hello': 'bob'});

      final envelopeKeys = remoteData.keys
          .where((k) => k.contains('.${sharerB.kpid}.__ssenv.myapp@alice'))
          .toList();
      expect(envelopeKeys, hasLength(1));
      // raw JSON, never whole-value base64: older readers' legacy decrypt
      // fallback must hit FormatException and return the value untouched
      expect(remoteData[envelopeKeys.single]!.startsWith('{'), isTrue);

      final captured = verify(() => sharerA.atClient.put(captureAny(), any(),
          putRequestOptions: captureAny(named: 'putRequestOptions'))).captured;
      AtKey? envKey;
      PutRequestOptions? envOpts;
      for (var i = 0; i < captured.length; i += 2) {
        final k = captured[i] as AtKey;
        if (k.toString().contains('.__ssenv.')) {
          envKey = k;
          envOpts = captured[i + 1] as PutRequestOptions;
        }
      }
      expect(envKey!.toString(), envelopeKeys.single);
      expect(envKey.metadata.ttl, Duration(hours: 1).inMilliseconds);
      expect(envOpts!.shouldEncrypt, isFalse);
    });

    test('the envelope key emits its exact layout, segment by segment',
        () async {
      // Emitter pin (frozen forever): <msgId uuidV4>.<recipientKpid>.__ssenv
      // .<appNamespace>@<sender>. The layout is hand-built and hand-parsed at
      // seven sites in this file's production twin plus two more in
      // enrollment_symmetric_key.dart — the sibling tests match fragments,
      // which would survive a segment being added, dropped or reordered.
      await sharerA
          .sendEnvelope(sharerB.myKeyPackage, 'myapp', {'hello': 'bob'});

      final key = remoteData.keys.singleWhere((k) => k.contains('.__ssenv.'));
      expect(
          key,
          matches(RegExp(
              '^[0-9a-f-]{36}\\.${sharerB.kpid}\\.__ssenv\\.myapp@alice\$')));
    });

    test('writes the envelope remote-first, so the wake-up cannot outrun it',
        () async {
      await sharerA
          .sendEnvelope(sharerB.myKeyPackage, 'myapp', {'hello': 'bob'});

      final envelopeKey = putOptions.keys
          .singleWhere((k) => k.contains('.${sharerB.kpid}.__ssenv.'));
      expect(putOptions[envelopeKey]!.useRemoteAtServer, isTrue,
          reason: 'the wake-up notify is a direct remote call, so a '
              'local-first envelope would still be waiting for a sync cycle '
              'when a sync-less recipient remote-sweeps — and the wake-up is '
              'one-shot. This fixture backs local and remote with one map, so '
              'the routing has to be asserted here or nothing sees it');
    });

    test('throws StateError when the recipient package has no supported key',
        () async {
      final futureOnly = KeyPackage(
        enrollmentId: 'enroll-x',
        createdAt: DateTime.now().toUtc(),
        keys: [
          PackageKey(use: 'enc', alg: 'x-wing-99', pub: 'future-pub'),
        ],
      );
      await expectLater(sharerA.sendEnvelope(futureOnly, 'myapp', {'a': 1}),
          throwsA(isA<StateError>()));
    });

    /// The construction the sender actually emitted: the envelope's declared
    /// suite, and the `pqSeal` version byte that leads its wire form.
    ({String suite, int version}) sentConstruction(String kpid) {
      final key = remoteData.keys
          .singleWhere((k) => k.contains('.$kpid.__ssenv.'));
      final payload =
          jsonDecode(remoteData[key]!)['payload'] as Map<String, dynamic>;
      return (
        suite: payload['suite'] as String,
        version: base64Decode(payload['sealed'] as String).first,
      );
    }

    test('negotiates RFC 9180 with a peer whose package says it opens it',
        () async {
      await sharerA.sendEnvelope(sharerB.myKeyPackage, 'myapp', {'a': 1});

      final sent = sentConstruction(sharerB.kpid);
      expect(sent.suite, SecretSharingAlgos.xWingRfc9180);
      expect(sent.version, 0x02,
          reason: 'the suite and the version byte must agree — the recipient '
              'opens by the version and this client accepts by the suite');
    });

    test('falls back to the original construction for a peer that predates it',
        () async {
      // Same X-Wing key, so the only thing that differs between these two
      // arms is what the package says it can open. That is the whole point of
      // the `suites` field: without it a second construction could only be
      // introduced by upgrading every reader first.
      final legacyPeer = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'keys': sharerB.myKeyPackage.keys.map((k) => k.toJson()).toList(),
        // no `suites` — written before the field existed
      }, enrollmentId: sharerB.enrollmentId);
      expect(legacyPeer.suites, KeyPackage.legacySuites);

      await sharerA.sendEnvelope(legacyPeer, 'myapp', {'a': 1});

      final sent = sentConstruction(sharerB.kpid);
      expect(sent.suite, SecretSharingAlgos.xWingHpke);
      expect(sent.version, 0x01,
          reason: 'a peer that never claimed RFC 9180 must not be sent it — '
              'it would reject the suite and the payload would be lost');
    });

    test('two ML-KEM-1024 clients exchange the no-hybrid construction',
        () async {
      // The whole chain under the other KEM: mint, advertise, negotiate, seal,
      // and open. Nothing here names X-Wing, and nothing here could pass by
      // falling back to it — a 1568-byte ML-KEM key cannot produce a 0x02
      // envelope, and an X-Wing decapsulation of a 0x03 one fails.
      TestSharer mlKemSharer(String enrollmentId, Uint8List seed) {
        final client = buildMockClient(enrollmentId);
        when(() => client.getPreferences()).thenReturn(AtClientPreference()
          ..keyEstablishmentAlgo = SecretSharingAlgos.mlKem1024);
        final sharer = TestSharer(client)
          ..directory = directory
          ..requestAnswerJitter = Duration.zero;
        sharer.loadApkamKeys = () async => PersistedApkamKeys(
            encSeed: base64Encode(seed),
            keyAlgo: SecretSharingAlgos.mlKem1024);
        return sharer;
      }

      // ML-KEM seeds are the 64-byte d||z, not X-Wing's 32.
      final mlSeedA =
          Uint8List.fromList(List<int>.generate(64, (i) => 100 + i));
      final mlSeedB =
          Uint8List.fromList(List<int>.generate(64, (i) => 164 + i));
      final senderML = mlKemSharer('enroll-ml-a', mlSeedA);
      final recipientML = mlKemSharer('enroll-ml-b', mlSeedB);
      directory.seed('enroll-ml-a', await senderML.register());
      directory.seed('enroll-ml-b', await recipientML.register());

      expect(recipientML.encKeyAlgo, SecretSharingAlgos.mlKem1024);

      final received = <ReceivedEnvelope>[];
      final sub = recipientML.receivedEnvelopes.listen(received.add);
      addTearDown(sub.cancel);

      await senderML
          .sendEnvelope(recipientML.myKeyPackage, 'myapp', {'hello': 'pq'});

      final sent = sentConstruction(recipientML.kpid);
      expect(sent.suite, SecretSharingAlgos.mlKem1024Rfc9180);
      expect(sent.version, 0x03);

      expect(await recipientML.sweepOnce(), 1);
      expect(received.single.payload, {'hello': 'pq'});
    });

    test('refuses rather than guessing when nothing is mutually supported',
        () async {
      // Stamping this client's own preference anyway would hand the recipient
      // an envelope it cannot unwrap, and the failure would surface on their
      // side as an opaque AEAD error.
      final noOverlap = KeyPackage(
        enrollmentId: 'enroll-x',
        createdAt: DateTime.now().toUtc(),
        keys: sharerB.myKeyPackage.keys,
        suites: const ['x-wing-hpke-v99'],
      );
      await expectLater(sharerA.sendEnvelope(noOverlap, 'myapp', {'a': 1}),
          throwsA(isA<StateError>()));
    });
  });

  group('sweepOnce', () {
    test(
        'A to B round trip: B receives, envelope is deleted, second sweep '
        'is empty', () async {
      await sharerA.sendEnvelope(
          sharerB.myKeyPackage, 'myapp', {'token': 'abc123', 'n': 7});

      final received = <ReceivedEnvelope>[];
      final sub = sharerB.receivedEnvelopes.listen(received.add);

      expect(await sharerB.sweepOnce(), 1);
      await Future.delayed(Duration.zero); // let the stream deliver
      expect(received, hasLength(1));
      expect(received.single.fromKpid, sharerA.kpid);
      expect(received.single.fromEnrollmentId, 'enroll-a');
      expect(received.single.appNamespace, 'myapp');
      expect(received.single.payload, {'token': 'abc123', 'n': 7});

      // consumed envelope was deleted
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
      expect(await sharerB.sweepOnce(), 0);
      await sub.cancel();
    });

    test('a dotted application namespace survives the round trip intact',
        () async {
      // regression: AtKey.namespace is only the LAST dot segment, so the
      // received namespace used to arrive truncated ('demos' instead of
      // 'examples.demos')
      await sharerA
          .sendEnvelope(sharerB.myKeyPackage, 'examples.demos', {'a': 1});
      expect(
          remoteData.keys
              .where((k) => k.endsWith('.__ssenv.examples.demos@alice')),
          hasLength(1));

      final received = <ReceivedEnvelope>[];
      final sub = sharerB.receivedEnvelopes.listen(received.add);
      expect(await sharerB.sweepOnce(), 1);
      await Future.delayed(Duration.zero);
      expect(received.single.appNamespace, 'examples.demos');
      await sub.cancel();
    });

    test(
        'a different keypair on the same enrollment is not the addressee '
        '(kpid differs); envelope is retained', () async {
      await sharerA.sendEnvelope(sharerB.myKeyPackage, 'myapp', {'a': 1});

      // Same enrollment, a different keypair (different seed) → different kpid:
      // the envelope is addressed to B's kpid, so this client's sweep does not
      // even match it.
      final restartedB = buildSharer('enroll-b', seedC);
      await restartedB.register();

      expect(await restartedB.sweepOnce(), 0);
      // not deleted: the envelope outlives the non-addressee's sweep
      expect(
          remoteData.keys.where((k) => k.contains('.__ssenv.')), hasLength(1));
    });

    test(
        'a tampered envelope fails signature verification, is not emitted, '
        'and is retained', () async {
      await sharerA.sendEnvelope(sharerB.myKeyPackage, 'myapp', {'a': 1});
      final envelopeKeyString =
          remoteData.keys.firstWhere((k) => k.contains('.__ssenv.'));
      final signedEnvelope = jsonDecode(remoteData[envelopeKeyString]!) as Map;
      final inner = signedEnvelope['payload'] as Map;
      // flip bytes in the sealed envelope; the APKAM signature over the
      // payload is what rejects this, before decryption is even attempted.
      inner['sealed'] = base64Encode(
          base64Decode(inner['sealed'] as String).reversed.toList());
      remoteData[envelopeKeyString] = jsonEncode(signedEnvelope);

      expect(await sharerB.sweepOnce(), 0);
      expect(remoteData.containsKey(envelopeKeyString), isTrue);
    });

    test(
        'an envelope with an unsupported sealing suite is skipped without '
        'crashing and retained', () async {
      // Validly signed by A, but uses a suite B does not support
      final envelope = SecretEnvelope(
        fromKpid: sharerA.kpid,
        fromEnrollmentId: 'enroll-a',
        toKpid: sharerB.kpid,
        suite: 'x-wing-hpke-v99',
        kid: sharerB.kpid,
        sealed: 'xx',
      );
      final signedJson =
          await sharerA.wrapAndSignAndJsonEncode(envelope.toJson());
      final keyName = 'future-msg.${sharerB.kpid}.__ssenv.myapp@alice';
      remoteData[keyName] = signedJson;

      expect(await sharerB.sweepOnce(), 0);
      expect(remoteData.containsKey(keyName), isTrue);
    });

    test(
        'an envelope whose payload is addressed to a different kpid than its '
        'key name is skipped', () async {
      final envelope = SecretEnvelope(
        fromKpid: sharerA.kpid,
        fromEnrollmentId: 'enroll-a',
        toKpid: 'some-other-kpid', // payload disagrees with the key name below
        suite: SecretSharingAlgos.xWingHpke,
        kid: sharerB.kpid,
        sealed: 'xx',
      );
      final signedJson =
          await sharerA.wrapAndSignAndJsonEncode(envelope.toJson());
      remoteData['mismatch-msg.${sharerB.kpid}.__ssenv.myapp@alice'] =
          signedJson;

      expect(await sharerB.sweepOnce(), 0);
    });
  });

  group('startListening', () {
    test('a syncing client sweeps locally — sync is what fills that store',
        () async {
      await sharerB.startListening();
      expect(scanRoutedRemote, isNotEmpty,
          reason: 'startListening does an initial sweep');
      expect(scanRoutedRemote, everyElement(isFalse),
          reason: 'sync already delivers envelopes to the local store, so '
              'remote sweeps would be traffic for nothing');
    });

    test('a client that does not sync sweeps the atServer instead', () async {
      sharerB.clientRunsSync = false;
      await sharerB.startListening();
      expect(scanRoutedRemote, isNotEmpty);
      expect(scanRoutedRemote, everyElement(isTrue),
          reason: 'envelopes reach the local store only via sync, so on a '
              'sync-less client a local sweep can never find anything — the '
              'wake-up would be its only automatic path, and one missed past '
              'its expiry would strand an envelope still readable on the '
              'atServer');
    });

    test('sync delivery of an envelope key triggers a sweep', () async {
      final syncService = MockSyncService();
      SyncProgressListener? registeredListener;
      when(() => syncService.addProgressListener(any())).thenAnswer((inv) {
        registeredListener = inv.positionalArguments[0];
      });
      when(() => syncService.removeProgressListener(any())).thenAnswer((_) {});

      final listeningB =
          buildSharer('enroll-b', seedB, syncService: syncService);
      await listeningB.register();

      final received = <ReceivedEnvelope>[];
      final sub = listeningB.receivedEnvelopes.listen(received.add);
      await listeningB.startListening(); // initial sweep finds nothing
      expect(registeredListener, isNotNull);
      expect(received, isEmpty);

      // an envelope arrives "via sync"
      await sharerA.sendEnvelope(listeningB.myKeyPackage, 'myapp', {'x': 1});
      final envelopeKeyString =
          remoteData.keys.firstWhere((k) => k.contains('.__ssenv.'));
      registeredListener!.onSyncProgressEvent(SyncProgress()
        ..keyInfoList = [
          KeyInfo(
              envelopeKeyString, SyncDirection.remoteToLocal, CommitOp.UPDATE)
        ]);
      // the listener fires an unawaited sweep; give it a beat
      await Future.delayed(Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received.single.payload, {'x': 1});

      listeningB.stopListening();
      verify(() => syncService.removeProgressListener(any())).called(1);
      await sub.cancel();
    });

    test(
        'a sync-less client receives an envelope via a wake-up notification '
        'and a remote sweep', () async {
      // sharerB's sync delivers nothing here (its progress listener is a
      // no-op); the wake-up notification + remote sweep is its only route.
      final received = <ReceivedEnvelope>[];
      final sub = sharerB.receivedEnvelopes.listen(received.add);
      await sharerB.startListening(); // subscribes for wake-ups; sweep empty
      expect(received, isEmpty);

      // sendEnvelope puts the envelope AND fires the wake-up notify, which the
      // bus fans to sharerB's subscription, triggering a remote sweep.
      await sharerA.sendEnvelope(sharerB.myKeyPackage, 'myapp', {'wake': 'up'});

      for (var i = 0; i < 100 && received.isEmpty; i++) {
        await Future.delayed(Duration(milliseconds: 10));
      }

      expect(received, hasLength(1));
      expect(received.single.payload, {'wake': 'up'});
      // the remote sweep deleted the consumed envelope
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
      await sub.cancel();
    });

    test('sendEnvelope can be told not to fire a wake-up notification',
        () async {
      final fired = <AtNotification>[];
      final sub = notificationBus.stream.listen(fired.add);

      sharerA.sendWakeUpNotification = false;
      await sharerA.sendEnvelope(sharerB.myKeyPackage, 'myapp', {'x': 1});
      await Future.delayed(Duration(milliseconds: 20));

      expect(fired, isEmpty);
      verifyNever(() => sharerA.atClient.notificationService.notify(any(),
          waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
          checkForFinalDeliveryStatus:
              any(named: 'checkForFinalDeliveryStatus'),
          encryptValue: any(named: 'encryptValue')));
      await sub.cancel();
    });
  });

  group('waitForSecret', () {
    test('returns immediately when the secret is already held', () async {
      await sharerB.secretStore
          .putSecret(Secret(namespace: 'myapp', name: 'token', value: 'v1'));
      final secret = await sharerB.waitForSecret('myapp', 'token',
          timeout: Duration(milliseconds: 100));
      expect(secret.value, 'v1');
    });

    test('completes when the secret arrives after the wait starts', () async {
      final wait = sharerB.waitForSecret('myapp', '__rk.current',
          timeout: Duration(seconds: 5));

      // arrival happens after the wait is already pending: A shares a
      // (reserved-name, system) secret and B's sweep consumes it
      await sharerA.secretStore.putSecret(
          Secret(namespace: 'myapp', name: '__rk.current', value: 'epoch-7'),
          allowReservedName: true);
      await sharerA.shareAllSecretsWith(sharerB.myKeyPackage);
      expect(await sharerB.sweepOnce(), 1);

      final secret = await wait;
      expect(secret.value, 'epoch-7');
      // the reserved-name secret was accepted by the arrival path and stored
      expect(sharerB.secretStore.getSecret('myapp', '__rk.current')!.value,
          'epoch-7');
    });

    test('throws TimeoutException when nothing arrives', () async {
      await expectLater(
          sharerB.waitForSecret('myapp', 'never',
              timeout: Duration(milliseconds: 100)),
          throwsA(isA<TimeoutException>()));
    });
  });

  group('a member with no mutually-supported key is skipped, not fatal', () {
    // A forward-compatible peer that advertises only a suite this client does
    // not understand has a null kpid. It must be skipped so delivery still
    // reaches the rest of the namespace — a null kpid used to satisfy the
    // `!= kpid` self-check and drive an aborting StateError.
    setUp(() {
      directory.authorize('myapp', 'enroll-a');
      directory.authorize('myapp', 'enroll-b');
      final futurePeer = KeyPackage(
        enrollmentId: 'enroll-future',
        createdAt: DateTime.utc(2026, 6, 11),
        keys: [PackageKey(use: 'enc', alg: 'x-wing-99', pub: 'future-pub')],
      );
      expect(futurePeer.kpid, isNull); // no key in SecretSharingAlgos.keyAlgos
      directory.seed('enroll-future', futurePeer);
      directory.authorize('myapp', 'enroll-future');
    });

    test('pushSecretToNamespaceMembers skips it and still reaches the rest',
        () async {
      await sharerA.secretStore
          .putSecret(Secret(namespace: 'myapp', name: 'token', value: 'v'));
      final pushed = await sharerA.pushSecretToNamespaceMembers(
          sharerA.secretStore.getSecret('myapp', 'token')!);
      expect(pushed, 1); // enroll-b only; enroll-future skipped, no StateError
      expect(await sharerB.sweepOnce(), 1);
    });

    test('requestSecretsFromNamespace skips it and still reaches the rest',
        () async {
      final sent = await sharerA.requestSecretsFromNamespace('myapp');
      expect(sent, 1); // enroll-b only; enroll-future skipped, no StateError
    });
  });

  group('a broadcast identifies itself by enrollment, not by kpid', () {
    // The roster serves enroll-a a package whose kpid is NOT the one this
    // instance holds. That is not hypothetical: an instance whose enrollment
    // changed under it (the self-retrofit) keeps its old keypair while the
    // directory serves the new package, and once a package may advertise more
    // than one key, KeyPackage.kpid is the *reader's* preferred key rather than
    // an identity. A kpid comparison calls that entry a peer and sends to an
    // address nobody is listening on; an enrollment comparison does not.
    late TestSharer staleSelf;

    setUp(() async {
      directory.authorize('myapp', 'enroll-a');
      directory.authorize('myapp', 'enroll-b');
      // Same enrollment, different key material -> different kpid.
      staleSelf = buildSharer('enroll-a', seedC);
      await staleSelf.register();
      directory.seed('enroll-a', staleSelf.myKeyPackage);
      expect(directory.registered['enroll-a']!.kpid, isNot(sharerA.kpid),
          reason: 'the arms must differ: a roster entry with this client\'s '
              'own kpid would pass either comparison');
    });

    test('pushSecretToNamespaceMembers reaches the peer and not itself',
        () async {
      await sharerA.secretStore
          .putSecret(Secret(namespace: 'myapp', name: 'token', value: 'v'));
      final pushed = await sharerA.pushSecretToNamespaceMembers(
          sharerA.secretStore.getSecret('myapp', 'token')!);
      expect(pushed, 1);
      expect(
          remoteData.keys.where(
              (k) => k.contains('.${staleSelf.kpid}.__ssenv.myapp@alice')),
          isEmpty,
          reason: 'nothing may be addressed to the stale self entry');
    });

    test('requestSecretsFromNamespace reaches the peer and not itself',
        () async {
      final sent = await sharerA.requestSecretsFromNamespace('myapp');
      expect(sent, 1);
    });
  });

  group('request/response pull flow', () {
    setUp(() {
      // Both enrollments authorized for the namespace so they discover each
      // other via the directory.
      directory.authorize('myapp', 'enroll-a');
      directory.authorize('myapp', 'enroll-b');
    });

    test('a holder answers a request and the requester receives the secret',
        () async {
      await sharerB.secretStore.putSecret(
          Secret(
              namespace: 'myapp', name: '__rk.1.deadbeef', value: 'KEYBYTES'),
          allowReservedName: true);

      // A asks the namespace for the epoch key it lacks.
      expect(
          await sharerA
              .requestSecretsFromNamespace('myapp', names: ['__rk.1.deadbeef']),
          1); // one holder (B) to ask

      // B consumes the request and shares the held secret back.
      expect(await sharerB.sweepOnce(), 1);
      // A consumes the answer and now holds the secret.
      expect(await sharerA.sweepOnce(), 1);
      expect(sharerA.secretStore.getSecret('myapp', '__rk.1.deadbeef')!.value,
          'KEYBYTES');
    });

    test('a second holder stays quiet once another has answered', () async {
      // Two holders of the same secret, both authorized, both seeing the same
      // request. Without suppression each seals and writes its own answer, so
      // the cost of a pull scales with the number of holders.
      final sharerC = buildSharer('enroll-c', seedC)..directory = directory;
      directory.authorize('myapp', 'enroll-c');
      directory.seed('enroll-c', await sharerC.register());
      for (final holder in [sharerB, sharerC]) {
        await holder.secretStore.putSecret(
            Secret(namespace: 'myapp', name: '__rk.1.dupe', value: 'KEYBYTES'),
            allowReservedName: true);
      }

      expect(
          await sharerA
              .requestSecretsFromNamespace('myapp', names: ['__rk.1.dupe']),
          2,
          reason: 'both holders are asked');

      // B answers first.
      expect(await sharerB.sweepOnce(), 1);
      final afterB = remoteData.keys
          .where((k) => k.contains('.${sharerA.kpid}.__ssenv.'))
          .length;
      expect(afterB, 1);

      // C sees the same request, observes B's answer, and adds nothing.
      expect(await sharerC.sweepOnce(), 1,
          reason: 'C still consumes the '
              'request envelope — it just declines to answer it');
      expect(
          remoteData.keys
              .where((k) => k.contains('.${sharerA.kpid}.__ssenv.'))
              .length,
          afterB,
          reason: 'a duplicate answer is merged away by putIfNewer, so this '
              'is about cost rather than correctness — N holders should not '
              'mean N seals and N writes');

      // And the requester still gets the secret.
      expect(await sharerA.sweepOnce(), 1);
      expect(sharerA.secretStore.getSecret('myapp', '__rk.1.dupe')!.value,
          'KEYBYTES');
    });

    test('namePrefix request pulls every matching held secret', () async {
      await sharerB.secretStore.putSecret(
          Secret(namespace: 'myapp', name: '__rk.1.aaaa', value: 'k1'),
          allowReservedName: true);
      await sharerB.secretStore.putSecret(
          Secret(namespace: 'myapp', name: '__rk.2.bbbb', value: 'k2'),
          allowReservedName: true);
      await sharerB.secretStore.putSecret(
          Secret(namespace: 'myapp', name: 'token', value: 'not-an-rk'),
          allowReservedName: true);

      await sharerA.requestSecretsFromNamespace('myapp', namePrefix: '__rk.');
      expect(await sharerB.sweepOnce(), 1); // request
      // Two epoch keys shared back (the non-__rk token is excluded).
      expect(await sharerA.sweepOnce(), 2);
      expect(
          sharerA.secretStore.getSecret('myapp', '__rk.1.aaaa')!.value, 'k1');
      expect(
          sharerA.secretStore.getSecret('myapp', '__rk.2.bbbb')!.value, 'k2');
      expect(sharerA.secretStore.getSecret('myapp', 'token'), isNull);
    });

    test('answerSecretRequests=false suppresses the answer', () async {
      sharerB.answerSecretRequests = (request, requester) => false;
      await sharerB.secretStore.putSecret(
          Secret(
              namespace: 'myapp', name: '__rk.1.deadbeef', value: 'KEYBYTES'),
          allowReservedName: true);

      await sharerA
          .requestSecretsFromNamespace('myapp', names: ['__rk.1.deadbeef']);
      expect(await sharerB.sweepOnce(), 1); // request consumed
      // Policy declined → nothing shared back → A's sweep finds nothing.
      expect(await sharerA.sweepOnce(), 0);
      expect(sharerA.secretStore.getSecret('myapp', '__rk.1.deadbeef'), isNull);
    });

    group('per-enrollment secrets on the request path', () {
      const rootName =
          '${PairwiseSecretSharing.perEnrollmentSecretPrefix}pqSigningRoot';

      setUp(() async {
        // B holds the atSign's signing-root private, primed into its store
        // the way a privileged holder's start does.
        await sharerB.secretStore.putSecret(
            Secret(namespace: 'myapp', name: rootName, value: 'ROOTPRIVATE'),
            allowReservedName: true);
      });

      test('with no privilege resolver wired, the request is never answered',
          () async {
        // sharerB is a bare mixin composition: perEnrollmentSecretRequestGate
        // is null, which must FAIL CLOSED.
        expect(
            await sharerA
                .requestSecretsFromNamespace('myapp', names: [rootName]),
            1);
        expect(await sharerB.sweepOnce(), 1); // request consumed
        expect(await sharerA.sweepOnce(), 0,
            reason: 'namespace authorization is the only other check on this '
                'path, and ANY enrollment approved for the namespace clears '
                'it — per-enrollment material must not be servable on that '
                'bar alone, so a sharing with no resolver serves none of it');
        expect(sharerA.secretStore.getSecret('myapp', rootName), isNull);
      });

      test('a requester the resolver rejects is refused', () async {
        final consulted = <String>[];
        sharerB.perEnrollmentSecretRequestGate = (enrollmentId) async {
          consulted.add(enrollmentId);
          return false;
        };

        await sharerA.requestSecretsFromNamespace('myapp', names: [rootName]);
        expect(await sharerB.sweepOnce(), 1);
        expect(await sharerA.sweepOnce(), 0);
        expect(sharerA.secretStore.getSecret('myapp', rootName), isNull);
        expect(consulted, ['enroll-a'],
            reason: 'the refusal must be the resolver\'s answer about THIS '
                'requester — a gate that never ran would refuse identically, '
                'and this test would pass on a broken serve path');
      });

      test(
          'a holder answers a named per-enrollment secret it filed under a '
          'DIFFERENT namespace', () async {
        // The shape this exists for: the signing root is atSign-level and
        // carries no namespace, so a holder files it under whichever app
        // namespace it happens to run in. Two privileged enrollments of one
        // atSign belonging to different apps would otherwise never match.
        //
        // A name the group's setUp did NOT seed under 'myapp', so the only
        // copy in B's store is the other namespace's. Reusing the seeded name
        // would let the ordinary namespace-scoped lookup answer and the test
        // would pass with this widening reverted.
        const crossName =
            '${PairwiseSecretSharing.perEnrollmentSecretPrefix}crossNsProbe';
        await sharerB.secretStore.putSecret(
            Secret(
                namespace: 'someotherapp',
                name: crossName,
                value: 'ROOTPRIVATE'),
            allowReservedName: true);
        expect(sharerB.secretStore.getSecret('myapp', crossName), isNull,
            reason: 'the precondition that makes this a cross-namespace test '
                'at all');
        sharerB.perEnrollmentSecretRequestGate = (_) async => true;

        await sharerA.requestSecretsFromNamespace('myapp', names: [crossName]);
        expect(await sharerB.sweepOnce(), 1);
        expect(await sharerA.sweepOnce(), greaterThan(0),
            reason: 'the root is the one key that can never be re-minted, and '
                'this pull is the only route to it — a namespace mismatch '
                'must not silently swallow the request');
        expect(
            sharerA.secretStore
                .listSecrets()
                .where((s) => s.name == crossName)
                .map((s) => s.value),
            contains('ROOTPRIVATE'));
      });

      test(
          'the cross-namespace reach is limited to NAMED per-enrollment '
          'secrets', () async {
        // A boundary assertion rather than a differential: it holds before
        // and after the widening, which is exactly the point — the widening
        // must not have moved this line. An ordinary secret in another
        // namespace stays out of reach, and so does a per-enrollment one that
        // was not asked for by name.
        await sharerB.secretStore.putSecret(
            Secret(
                namespace: 'someotherapp',
                name: '__rk.1.elsewhere',
                value: 'OTHERAPPKEY'),
            allowReservedName: true);
        await sharerB.secretStore.putSecret(
            Secret(
                namespace: 'someotherapp',
                name: '${PairwiseSecretSharing.perEnrollmentSecretPrefix}other',
                value: 'OTHERAPPEN'),
            allowReservedName: true);
        sharerB.perEnrollmentSecretRequestGate = (_) async => true;

        await sharerA.requestSecretsFromNamespace('myapp', namePrefix: '__');
        expect(await sharerB.sweepOnce(), 1);
        await sharerA.sweepOnce();
        final got = sharerA.secretStore.listSecrets().map((s) => s.value);
        expect(got, isNot(contains('OTHERAPPKEY')),
            reason: 'a namespace boundary is still a boundary — this widening '
                'is for atSign-level material asked for BY NAME, not a way to '
                'sweep another app\'s secrets');
        expect(got, isNot(contains('OTHERAPPEN')));
      });

      test('a handler failure after emission never re-emits the envelope',
          () async {
        // The gate is the injection point: it runs inside the request
        // handler, strictly after the envelope has been emitted on
        // [receivedEnvelopes] — so a claim released on ITS failure would
        // hand the same envelope to the next sweep for a second emission.
        var gateCalls = 0;
        sharerB.perEnrollmentSecretRequestGate = (enrollmentId) async {
          gateCalls++;
          throw StateError('resolver outage');
        };
        final emitted = <ReceivedEnvelope>[];
        final sub = sharerB.receivedEnvelopes.listen(emitted.add);

        await sharerA.requestSecretsFromNamespace('myapp', names: [rootName]);
        await sharerB.sweepOnce();
        await sharerB.sweepOnce();
        await pumpEventQueue();

        expect(emitted, hasLength(1),
            reason: 'sweepOnce\'s own contract: the same payload is never '
                'emitted twice. A handler failure is not a consume failure — '
                'the envelope has already been delivered to listeners, and '
                'retrying it from scratch re-emits it');
        expect(gateCalls, 1,
            reason: 'the claim must survive the handler failure — a released '
                'claim is what turns the next sweep into a repeat');
        await sub.cancel();
      });

      test('a requester the resolver accepts is served', () async {
        sharerB.perEnrollmentSecretRequestGate =
            (enrollmentId) async => enrollmentId == 'enroll-a';

        await sharerA.requestSecretsFromNamespace('myapp', names: [rootName]);
        expect(await sharerB.sweepOnce(), 1);
        expect(await sharerA.sweepOnce(), 1);
        expect(sharerA.secretStore.getSecret('myapp', rootName)!.value,
            'ROOTPRIVATE',
            reason: 'the gate restricts, it does not disable: the pull is '
                'the one heal an enrollment that missed the approve-time '
                'conveyance has');
      });
    });

    group('the revocation guard', () {
      // What makes a rotation's exclusion hold. Excluding an enrollment from
      // the push is worth nothing on its own — it can ask any other holder
      // for the successor private and get it — so the serve side has to
      // refuse it too. It does, and the thing it honours is the atServer's
      // roster rather than any list a client remembers: `enroll:listns`
      // returns approved enrollments only, so revocation is what every
      // holder sees, including ones that never heard of the rotation.
      const successor = '__nskey.gen2';

      setUp(() async {
        await sharerB.secretStore.putSecret(
            Secret(namespace: 'myapp', name: successor, value: 'SUCCESSOR'),
            allowReservedName: true);
      });

      test('a holder refuses a requester the roster no longer lists', () async {
        // The request goes out while A is still approved — a revoked
        // enrollment cannot authenticate, so the envelope it left behind is
        // the realistic shape, not one it sends afterwards.
        expect(
            await sharerA
                .requestSecretsFromNamespace('myapp', names: [successor]),
            1);

        // After the request is written and before it is swept — so a serve
        // path that consulted a roster cached from send time would answer,
        // and this would pass for the wrong reason.
        directory.revoke('enroll-a');

        expect(await sharerB.sweepOnce(), 1,
            reason: 'B still consumes the request envelope — it declines to '
                'answer it');
        expect(await sharerA.sweepOnce(), 0);
        expect(sharerA.secretStore.getSecret('myapp', successor), isNull,
            reason: 'otherwise a revoke-then-rotate would be undone by the '
                'self-heal: the excluded enrollment pulls the very generation '
                'the rotation cut it off from, from a holder that has no idea '
                'a rotation happened');
      });

      test('and serves the same request while it is still listed', () async {
        // The control arm. Without it the refusal above is equally explained
        // by a serve path that answers nobody.
        await sharerA.requestSecretsFromNamespace('myapp', names: [successor]);
        expect(await sharerB.sweepOnce(), 1);
        expect(await sharerA.sweepOnce(), 1);
        expect(sharerA.secretStore.getSecret('myapp', successor)!.value,
            'SUCCESSOR');
      });
    });

    test('requestSecret convenience resolves the single named secret',
        () async {
      await sharerB.secretStore.putSecret(
          Secret(namespace: 'myapp', name: '__rk.1.deadbeef', value: 'KB'),
          allowReservedName: true);
      // requestSecret sends the request, then waits (its own internal
      // waitForSecret subscription observes the arrival).
      final pending = sharerA.requestSecret('myapp', '__rk.1.deadbeef',
          timeout: Duration(seconds: 5));
      // let the request send and the internal waitForSecret subscribe
      await Future.delayed(Duration(milliseconds: 50));
      expect(await sharerB.sweepOnce(), 1); // B answers
      expect(await sharerA.sweepOnce(), 1); // A consumes -> emits -> completes
      final secret = await pending;
      expect(secret.value, 'KB');
    });
  });
}
