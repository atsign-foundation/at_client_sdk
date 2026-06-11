import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

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

  /// Simulates the atServer's keystore (post-sync view shared by all mocked
  /// clients): full key string -> value.
  late Map<String, String> remoteData;

  late RSAKeypair keyPairA;
  late RSAKeypair keyPairB;

  setUpAll(() {
    registerFallbackValue(AtKey());
    keyPairA = RSAKeypair.fromRandom();
    keyPairB = RSAKeypair.fromRandom();
  });

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);

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
    Future<AtValue> getFromRemoteData(Invocation inv) {
      final keyString = inv.positionalArguments[0].toString();
      final value = remoteData[keyString];
      if (value == null) {
        throw AtKeyNotFoundException('$keyString not found');
      }
      return Future.value(AtValue()..value = value);
    }

    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer(getFromRemoteData);
    when(() => atClient.get(any())).thenAnswer(getFromRemoteData);
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
    Future<bool> deleteFromRemoteData(Invocation inv) {
      remoteData.remove(inv.positionalArguments[0].toString());
      return Future.value(true);
    }

    when(() => atClient.delete(any(),
            deleteRequestOptions: any(named: 'deleteRequestOptions')))
        .thenAnswer(deleteFromRemoteData);
    when(() => atClient.delete(any())).thenAnswer(deleteFromRemoteData);
    return atClient;
  }

  TestSharer buildSharer(
      String enrollmentId, String clientId, RSAKeypair keyPair) {
    final sharer = TestSharer(buildMockClient(enrollmentId));
    sharer.loadClientKeys = () async => PersistedClientKeys(
          clientId: clientId,
          rsaPublicKey: keyPair.publicKey.toString(),
          rsaPrivateKey: keyPair.privateKey.toString(),
        );
    return sharer;
  }

  late TestSharer approverA;

  setUp(() async {
    remoteData = {};
    approverA = buildSharer('enroll-a', 'cid-a', keyPairA);
    await approverA.registerClient();
    await approverA.secretStore.putSecret(Secret(
        namespace: 'myapp',
        name: 'token',
        value: 'app-token',
        createdAt: DateTime.utc(2026, 6, 1)));
    await approverA.secretStore.putSecret(Secret(
        namespace: 'mychat',
        name: 'token',
        value: 'chat-token',
        createdAt: DateTime.utc(2026, 6, 1)));
  });

  tearDown(() async {
    await approverA.deregisterClient();
  });

  group('shareAllSecretsWith', () {
    test(
        'only secrets whose namespace the recipient enrollment is '
        'authorized for are shared', () async {
      final clientB = buildSharer('enroll-b', 'cid-b', keyPairB);
      await clientB.registerClient();

      final shared = await approverA.shareAllSecretsWith(clientB.myBundle!,
          approvedNamespaces: {'myapp': 'rw'});

      expect(shared, 1);
      final envelopeKeys =
          remoteData.keys.where((k) => k.contains('.__ssenv.')).toList();
      expect(envelopeKeys, hasLength(1));
      expect(envelopeKeys.single, contains('.cid-b.__ssenv.myapp@alice'));
      await clientB.deregisterClient();
    });

    test('without a namespace filter, all secrets are shared', () async {
      final clientB = buildSharer('enroll-b', 'cid-b', keyPairB);
      await clientB.registerClient();

      expect(await approverA.shareAllSecretsWith(clientB.myBundle!), 2);
      await clientB.deregisterClient();
    });
  });

  group('received secrets', () {
    test(
        'a shared secret is stored in the recipient\'s store and emitted '
        'on receivedSecrets', () async {
      final clientB = buildSharer('enroll-b', 'cid-b', keyPairB);
      await clientB.registerClient();
      await approverA.shareAllSecretsWith(clientB.myBundle!,
          approvedNamespaces: {'myapp': 'rw'});

      final received = <ReceivedSecret>[];
      final sub = clientB.receivedSecrets.listen(received.add);
      expect(await clientB.sweepOnce(), 1);
      await Future.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.fromClientId, 'cid-a');
      expect(received.single.secret.namespace, 'myapp');
      expect(received.single.secret.name, 'token');
      expect(received.single.secret.value, 'app-token');

      final stored = clientB.secretStore.getSecret('myapp', 'token');
      expect(stored, isNotNull);
      expect(stored!.value, 'app-token');

      await sub.cancel();
      await clientB.deregisterClient();
    });

    test(
        'an incoming secret older than the held one is consumed but '
        'neither stored nor emitted', () async {
      final clientB = buildSharer('enroll-b', 'cid-b', keyPairB);
      await clientB.registerClient();
      await clientB.secretStore.putSecret(Secret(
          namespace: 'myapp',
          name: 'token',
          value: 'newer-token',
          createdAt: DateTime.utc(2026, 6, 10)));

      // approver's copy is older (2026-06-01)
      await approverA.shareAllSecretsWith(clientB.myBundle!,
          approvedNamespaces: {'myapp': 'rw'});

      final received = <ReceivedSecret>[];
      final sub = clientB.receivedSecrets.listen(received.add);
      expect(await clientB.sweepOnce(), 1); // envelope is consumed...
      await Future.delayed(Duration.zero);

      expect(received, isEmpty); // ...but the older secret is not emitted
      expect(clientB.secretStore.getSecret('myapp', 'token')!.value,
          'newer-token');
      // and the envelope was still cleaned up
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);

      await sub.cancel();
      await clientB.deregisterClient();
    });
  });

  group('shareAllSecretsWithEnrollment (approver flow)', () {
    test(
        'waits for the new enrollment\'s client to register, then shares '
        'namespace-authorized secrets', () async {
      // B is not registered yet when the approver starts waiting
      final clientB = buildSharer('enroll-b', 'cid-b', keyPairB);
      final sharedFuture = approverA.shareAllSecretsWithEnrollment(
        'enroll-b',
        {'myapp': 'rw'},
        timeout: Duration(seconds: 5),
        pollInterval: Duration(milliseconds: 50),
      );
      // ...B registers a moment later (post-approval authentication)
      await Future.delayed(Duration(milliseconds: 150));
      await clientB.registerClient();

      expect(await sharedFuture, 1);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.myapp@')),
          hasLength(1));
      await clientB.deregisterClient();
    });

    test('returns 0 when no client of the enrollment registers in time',
        () async {
      final shared = await approverA.shareAllSecretsWithEnrollment(
        'enroll-z',
        {'myapp': 'rw'},
        timeout: Duration(milliseconds: 150),
        pollInterval: Duration(milliseconds: 50),
      );
      expect(shared, 0);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
    });
  });
}
