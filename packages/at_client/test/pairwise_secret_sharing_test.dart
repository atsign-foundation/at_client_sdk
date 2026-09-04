import 'dart:async' show StreamController, TimeoutException;
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockSyncService extends Mock implements SyncService {}

class MockNotificationService extends Mock implements NotificationService {}

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
  late Map<String, String> remoteData;

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
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);

    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      remoteData[inv.positionalArguments[0].toString()] =
          inv.positionalArguments[1];
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
          ..directory = directory;
    sharer.loadApkamKeys =
        () async => PersistedApkamKeys(xWingSeed: base64Encode(seed));
    return sharer;
  }

  late TestSharer sharerA;
  late TestSharer sharerB;

  setUp(() async {
    remoteData = {};
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
