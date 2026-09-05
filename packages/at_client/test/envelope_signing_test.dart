import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class TestEnvelopeSigner with ApkamSigning, EnvelopeSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestEnvelopeSigner');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings;

  TestEnvelopeSigner(this.atClient, {this.publicKeyCacheSettings});
}

void main() {
  const atSign = '@alice';

  late MockAtClient atClientA; // client A, enrollment enrollA
  late MockAtClient atClientB; // client B, enrollment enrollB
  late AtChops atChopsA;
  late AtChops atChopsB;
  late TestEnvelopeSigner signerA;
  late TestEnvelopeSigner verifierB;

  /// Gives [atClient] the [enrollmentId] that [ApkamSigning.enrollmentId]
  /// reads from.
  void stubEnrollment(MockAtClient atClient, String enrollmentId) {
    final remoteSecondary = MockRemoteSecondary();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);
  }

  /// Stubs [atClient]'s get of A's `_apsk` key to return [publicKey].
  void stubApskGet(MockAtClient atClient, String publicKey) {
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((_) async => AtValue()..value = publicKey);
  }

  String pkamPublicKey(AtChops atChops) =>
      atChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

  setUpAll(() {
    registerFallbackValue(AtKey());
  });

  setUp(() {
    atChopsA = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    atChopsB = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));

    atClientA = MockAtClient();
    when(() => atClientA.atChops).thenReturn(atChopsA);
    when(() => atClientA.getCurrentAtSign()).thenReturn(atSign);
    stubEnrollment(atClientA, 'enroll-a');

    atClientB = MockAtClient();
    when(() => atClientB.atChops).thenReturn(atChopsB);
    when(() => atClientB.getCurrentAtSign()).thenReturn(atSign);
    stubEnrollment(atClientB, 'enroll-b');

    signerA = TestEnvelopeSigner(atClientA);
    verifierB = TestEnvelopeSigner(atClientB);
  });

  group('wrapAndSign', () {
    test('envelope contains payload, signature, algos and enrollmentId',
        () async {
      final payload = {'hello': 'world', 'n': 42};
      final envelope = await signerA.wrapAndSign(payload);

      expect(envelope['payload'], same(payload));
      expect(envelope['signature'], isA<String>());
      expect(envelope['hashingAlgo'], 'sha256');
      expect(envelope['signingAlgo'], 'rsa2048');
      expect(envelope['enrollmentId'], 'enroll-a');
    });
  });

  group('verifyEnvelopeSignature', () {
    test('B verifies an envelope signed by A using A\'s published _apsk key',
        () async {
      final envelope = await signerA.wrapAndSign({'secret': 's3cr3t'});
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      await verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign);

      // The key fetched must be A's _apsk key, derived from the envelope's
      // enrollmentId.
      final captured = verify(() => atClientB.get(captureAny(),
          getRequestOptions: any(named: 'getRequestOptions'))).captured;
      expect(captured.single.toString(), 'public:_apsk.enroll-a.a.__e$atSign');
    });

    test('string payloads round-trip', () async {
      final envelope = await signerA.wrapAndSign('just a string');
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      await verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign);
    });

    test('tampered payload fails verification', () async {
      final envelope = await signerA.wrapAndSign({'amount': 10});
      (envelope['payload'] as Map)['amount'] = 1000000;
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      await expectLater(
          verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('verification against the wrong enrollment\'s key fails', () async {
      final envelope = await signerA.wrapAndSign({'secret': 's3cr3t'});
      // B's get returns B's own public key instead of A's
      stubApskGet(atClientB, pkamPublicKey(atChopsB));

      await expectLater(
          verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('public key caching', () {
    test('with caching enabled, the _apsk key is fetched only once', () async {
      final cachingVerifier = TestEnvelopeSigner(atClientB,
          publicKeyCacheSettings: (
            cacheExpiry: Duration(minutes: 1),
            resetOnLookup: false
          ));
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      final envelope = await signerA.wrapAndSign({'a': 1});
      await cachingVerifier.verifyEnvelopeSignature(envelope,
          signerAtSign: atSign);
      await cachingVerifier.verifyEnvelopeSignature(envelope,
          signerAtSign: atSign);

      verify(() => atClientB.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).called(1);
      // Cancel the purge timer so the test suite doesn't hang on it
      for (final v in cachingVerifier.pubKeyCache.values) {
        v.$2.cancel();
      }
    });

    test('with caching disabled, the _apsk key is fetched every time',
        () async {
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      final envelope = await signerA.wrapAndSign({'a': 1});
      await verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign);
      await verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign);

      verify(() => atClientB.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).called(2);
    });
  });
}
