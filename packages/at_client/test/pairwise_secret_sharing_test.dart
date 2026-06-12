import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockSyncService extends Mock implements SyncService {}

class FakeSyncProgressListener extends Fake implements SyncProgressListener {}

class TestSharer
    with
        ApkamSigning,
        EnvelopeSigning,
        PairwiseClientRegistration,
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

  // RSA keygen is slow; generate once and inject as stable identities.
  late RSAKeypair keyPairA;
  late RSAKeypair keyPairB;
  late RSAKeypair keyPairC;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeSyncProgressListener());
    keyPairA = RSAKeypair.fromRandom();
    keyPairB = RSAKeypair.fromRandom();
    keyPairC = RSAKeypair.fromRandom();
  });

  MockAtClient buildMockClient(String enrollmentId,
      {MockSyncService? syncService}) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    if (syncService != null) {
      when(() => atClient.syncService).thenReturn(syncService);
    }

    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

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

  TestSharer buildSharer(
      String enrollmentId, String clientId, RSAKeypair keyPair,
      {MockSyncService? syncService}) {
    final sharer =
        TestSharer(buildMockClient(enrollmentId, syncService: syncService));
    sharer.loadClientKeys = () async => PersistedClientKeys(
          clientId: clientId,
          rsaPublicKey: keyPair.publicKey.toString(),
          rsaPrivateKey: keyPair.privateKey.toString(),
        );
    return sharer;
  }

  late TestSharer sharerA;
  late TestSharer sharerB;

  setUp(() async {
    remoteData = {};
    sharerA = buildSharer('enroll-a', 'cid-a', keyPairA);
    sharerB = buildSharer('enroll-b', 'cid-b', keyPairB);
    await sharerA.registerClient();
    await sharerB.registerClient();
  });

  tearDown(() async {
    await sharerA.deregisterClient();
    await sharerB.deregisterClient();
    sharerA.stopListening();
    sharerB.stopListening();
  });

  group('sendEnvelope', () {
    test(
        'stores a raw-JSON, ttl\'d, unencrypted self key addressed to the '
        'recipient through the app namespace', () async {
      sharerA.envelopeTtl = Duration(hours: 1);
      await sharerA.sendEnvelope(sharerB.myBundle!, 'myapp', {'hello': 'bob'});

      final envelopeKeys = remoteData.keys
          .where((k) => k.contains('.cid-b.__ssenv.myapp@alice'))
          .toList();
      expect(envelopeKeys, hasLength(1));
      // raw JSON, never whole-value base64: older readers' legacy decrypt
      // fallback must hit FormatException and return the value untouched
      expect(remoteData[envelopeKeys.single]!.startsWith('{'), isTrue);

      final captured = verify(() => sharerA.atClient.put(captureAny(), any(),
          putRequestOptions: captureAny(named: 'putRequestOptions'))).captured;
      // last put is the envelope (earlier ones are registration keys)
      final atKey = captured[captured.length - 2] as AtKey;
      final options = captured.last as PutRequestOptions;
      expect(atKey.toString(), envelopeKeys.single);
      expect(atKey.metadata.ttl, Duration(hours: 1).inMilliseconds);
      expect(options.shouldEncrypt, isFalse);
    });

    test('throws StateError when the recipient bundle has no supported key',
        () async {
      final futureOnlyBundle = ClientKeyBundle(
        clientId: 'cid-x',
        enrollmentId: 'enroll-x',
        createdAt: DateTime.now().toUtc(),
        keys: [
          BundleKey(use: 'enc', alg: 'x-wing-99', pub: 'future-pub'),
        ],
      );
      await expectLater(
          sharerA.sendEnvelope(futureOnlyBundle, 'myapp', {'a': 1}),
          throwsA(isA<StateError>()));
    });
  });

  group('sweepOnce', () {
    test(
        'A to B round trip: B receives, envelope is deleted, second sweep '
        'is empty', () async {
      await sharerA.sendEnvelope(
          sharerB.myBundle!, 'myapp', {'token': 'abc123', 'n': 7});

      final received = <ReceivedEnvelope>[];
      final sub = sharerB.receivedEnvelopes.listen(received.add);

      expect(await sharerB.sweepOnce(), 1);
      await Future.delayed(Duration.zero); // let the stream deliver
      expect(received, hasLength(1));
      expect(received.single.fromClientId, 'cid-a');
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
      await sharerA.sendEnvelope(sharerB.myBundle!, 'examples.demos', {'a': 1});
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
        'the sender itself cannot decrypt what it sent (kid mismatch); '
        'envelope is retained for the recipient', () async {
      await sharerA.sendEnvelope(sharerB.myBundle!, 'myapp', {'a': 1});

      // A client that is NOT the addressee but matches the regex would not
      // normally occur (the clientId is in the key name); simulate a client
      // that restarted with new keys but kept its clientId: same clientId
      // 'cid-b', different keypair.
      final restartedB = buildSharer('enroll-b', 'cid-b', keyPairC);
      await restartedB.registerClient();

      expect(await restartedB.sweepOnce(), 0);
      // not deleted: the envelope outlives the failed attempt
      expect(
          remoteData.keys.where((k) => k.contains('.__ssenv.')), hasLength(1));
      await restartedB.deregisterClient();
    });

    test(
        'a tampered envelope fails signature verification, is not emitted, '
        'and is retained', () async {
      await sharerA.sendEnvelope(sharerB.myBundle!, 'myapp', {'a': 1});
      final envelopeKeyString =
          remoteData.keys.firstWhere((k) => k.contains('.__ssenv.'));
      final signedEnvelope = jsonDecode(remoteData[envelopeKeyString]!) as Map;
      final inner = signedEnvelope['payload'] as Map;
      // flip the ciphertext: CTR is malleable, only the signature stops this
      inner['ciphertext'] = base64Encode(
          base64Decode(inner['ciphertext'] as String).reversed.toList());
      remoteData[envelopeKeyString] = jsonEncode(signedEnvelope);

      expect(await sharerB.sweepOnce(), 0);
      expect(remoteData.containsKey(envelopeKeyString), isTrue);
    });

    test(
        'an envelope with unsupported algorithms is skipped without '
        'crashing and retained', () async {
      // Validly signed by A, but uses algorithms B does not support
      final envelope = SecretEnvelope(
        fromClientId: 'cid-a',
        fromEnrollmentId: 'enroll-a',
        to: 'cid-b',
        keyAlg: 'x-wing-99',
        kid: 'whatever',
        encryptedKey: 'xx',
        encAlg: 'aes-256-gcm',
        iv: 'xx',
        ciphertext: 'xx',
      );
      final signedJson =
          await sharerA.wrapAndSignAndJsonEncode(envelope.toJson());
      remoteData['future-msg.cid-b.__ssenv.myapp@alice'] = signedJson;

      expect(await sharerB.sweepOnce(), 0);
      expect(remoteData.containsKey('future-msg.cid-b.__ssenv.myapp@alice'),
          isTrue);
    });

    test(
        'an envelope whose payload is addressed to a different clientId '
        'than its key name is skipped', () async {
      final contentKeyEnvelope = SecretEnvelope(
        fromClientId: 'cid-a',
        fromEnrollmentId: 'enroll-a',
        to: 'cid-x', // payload disagrees with the key name below
        keyAlg: 'rsa-2048',
        kid: BundleKey.computeKid(keyPairB.publicKey.toString()),
        encryptedKey: 'xx',
        encAlg: 'aes-256-ctr',
        iv: 'xx',
        ciphertext: 'xx',
      );
      final signedJson =
          await sharerA.wrapAndSignAndJsonEncode(contentKeyEnvelope.toJson());
      remoteData['mismatch-msg.cid-b.__ssenv.myapp@alice'] = signedJson;

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
          buildSharer('enroll-b', 'cid-b', keyPairB, syncService: syncService);
      await listeningB.registerClient();

      final received = <ReceivedEnvelope>[];
      final sub = listeningB.receivedEnvelopes.listen(received.add);
      await listeningB.startListening(); // initial sweep finds nothing
      expect(registeredListener, isNotNull);
      expect(received, isEmpty);

      // an envelope arrives "via sync"
      await sharerA.sendEnvelope(listeningB.myBundle!, 'myapp', {'x': 1});
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
      await listeningB.deregisterClient();
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
      await sharerA.shareAllSecretsWith(sharerB.myBundle!);
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
}
