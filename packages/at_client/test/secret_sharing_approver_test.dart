import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockNotificationService extends Mock implements NotificationService {}

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

  /// Simulates the atServer's keystore (post-sync view shared by all mocked
  /// clients): full key string -> value.
  late Map<String, String> remoteData;
  late FakeEnrollmentDirectory directory;

  final Uint8List seedA = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final Uint8List seedB =
      Uint8List.fromList(List<int>.generate(32, (i) => 32 + i));

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(NotificationParams.forUpdate(AtKey()));
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

    final notificationService = MockNotificationService();
    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => notificationService.notify(any(),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        encryptValue:
            any(named: 'encryptValue'))).thenAnswer(
        (_) async => NotificationResult());

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

  TestSharer buildSharer(String enrollmentId, Uint8List seed) {
    final sharer = TestSharer(buildMockClient(enrollmentId))
      ..directory = directory;
    sharer.loadApkamKeys =
        () async => PersistedApkamKeys(xWingSeed: base64Encode(seed));
    return sharer;
  }

  late TestSharer approverA;

  setUp(() async {
    remoteData = {};
    directory = FakeEnrollmentDirectory();
    approverA = buildSharer('enroll-a', seedA);
    await approverA.register();
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

  group('shareAllSecretsWith', () {
    test(
        'only secrets whose namespace the recipient enrollment is '
        'authorized for are shared', () async {
      final clientB = buildSharer('enroll-b', seedB);
      await clientB.register();

      final shared = await approverA.shareAllSecretsWith(clientB.myKeyPackage,
          approvedNamespaces: {'myapp': 'rw'});

      expect(shared, 1);
      final envelopeKeys =
          remoteData.keys.where((k) => k.contains('.__ssenv.')).toList();
      expect(envelopeKeys, hasLength(1));
      expect(envelopeKeys.single,
          contains('.${clientB.kpid}.__ssenv.myapp@alice'));
    });

    test('without a namespace filter, all secrets are shared', () async {
      final clientB = buildSharer('enroll-b', seedB);
      await clientB.register();

      expect(await approverA.shareAllSecretsWith(clientB.myKeyPackage), 2);
    });

    test('excludeEnrollmentIds blocks sharing to a revoked enrollment',
        () async {
      final clientB = buildSharer('enroll-b', seedB);
      await clientB.register();

      expect(
          await approverA.shareAllSecretsWith(clientB.myKeyPackage,
              excludeEnrollmentIds: {'enroll-b'}),
          0);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
    });
  });

  group('received secrets', () {
    test(
        'a shared secret is stored in the recipient\'s store and emitted '
        'on receivedSecrets', () async {
      final clientB = buildSharer('enroll-b', seedB);
      await clientB.register();
      await approverA.shareAllSecretsWith(clientB.myKeyPackage,
          approvedNamespaces: {'myapp': 'rw'});

      final received = <ReceivedSecret>[];
      final sub = clientB.receivedSecrets.listen(received.add);
      expect(await clientB.sweepOnce(), 1);
      await Future.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.fromKpid, approverA.kpid);
      expect(received.single.secret.namespace, 'myapp');
      expect(received.single.secret.name, 'token');
      expect(received.single.secret.value, 'app-token');

      final stored = clientB.secretStore.getSecret('myapp', 'token');
      expect(stored, isNotNull);
      expect(stored!.value, 'app-token');

      await sub.cancel();
    });

    test(
        'an incoming secret older than the held one is consumed but '
        'neither stored nor emitted', () async {
      final clientB = buildSharer('enroll-b', seedB);
      await clientB.register();
      await clientB.secretStore.putSecret(Secret(
          namespace: 'myapp',
          name: 'token',
          value: 'newer-token',
          createdAt: DateTime.utc(2026, 6, 10)));

      // approver's copy is older (2026-06-01)
      await approverA.shareAllSecretsWith(clientB.myKeyPackage,
          approvedNamespaces: {'myapp': 'rw'});

      final received = <ReceivedSecret>[];
      final sub = clientB.receivedSecrets.listen(received.add);
      expect(await clientB.sweepOnce(), 1); // envelope is consumed...
      await Future.delayed(Duration.zero);

      expect(received, isEmpty); // ...but the older secret is not emitted
      expect(clientB.secretStore.getSecret('myapp', 'token')!.value,
          'newer-token');
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);

      await sub.cancel();
    });
  });

  group('shareAllSecretsWithEnrollment (approver flow)', () {
    test('shares namespace-authorized secrets with the approved enrollment',
        () async {
      // Per OQ4 the new enrollment's key package is in the record from request
      // time; approval makes it discoverable for the namespace.
      final clientB = buildSharer('enroll-b', seedB);
      // key package reaches the record via enroll:request (modelled by seed);
      // authorize makes it discoverable for the namespace.
      directory.seed('enroll-b', await clientB.register());
      directory.authorize('myapp', 'enroll-b');

      final shared = await approverA.shareAllSecretsWithEnrollment('enroll-b', {
        'myapp': 'rw',
      });

      expect(shared, 1);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.myapp@')),
          hasLength(1));
    });

    test('returns 0 when the enrollment has no discoverable key package',
        () async {
      final shared = await approverA.shareAllSecretsWithEnrollment('enroll-z', {
        'myapp': 'rw',
      });
      expect(shared, 0);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
    });

    test('honours excludeEnrollmentIds (revoked enrollment gets nothing)',
        () async {
      final clientB = buildSharer('enroll-b', seedB);
      // key package reaches the record via enroll:request (modelled by seed);
      // authorize makes it discoverable for the namespace.
      directory.seed('enroll-b', await clientB.register());
      directory.authorize('myapp', 'enroll-b');

      final shared = await approverA.shareAllSecretsWithEnrollment(
          'enroll-b', {'myapp': 'rw'},
          excludeEnrollmentIds: {'enroll-b'});
      expect(shared, 0);
      expect(remoteData.keys.where((k) => k.contains('.__ssenv.')), isEmpty);
    });
  });
}
