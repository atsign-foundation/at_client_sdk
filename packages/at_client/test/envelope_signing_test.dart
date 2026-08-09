import 'dart:convert' show utf8;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, signEnvelope;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
}

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

  /// Wires [atClient] to a remote secondary whose atLookUp carries
  /// [enrollmentId], which is where [ApkamSigning.enrollmentId] reads from.
  void stubEnrollment(MockAtClient atClient, String enrollmentId) {
    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);
  }

  /// Stubs [atClient]'s get of A's `_apsk` key to return [publicKey].
  void stubApskGet(MockAtClient atClient, String publicKey) {
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((_) async => AtValue()..value = publicKey);
  }

  String pkamPublicKey(AtChops atChops) =>
      atChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

  String pkamPrivateKey(AtChops atChops) =>
      atChops.atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey;

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

  group('the hashingAlgo claim cannot choose the routine', () {
    // `hashingAlgo` sits outside the signature, exactly like `signingAlgo`,
    // so it is an unsigned field naming a cryptographic routine. The
    // signingAlgo half was already pinned against the published _apsk; this
    // half resolved straight through `HashingAlgoType.values.byName`.
    //
    // The concrete defect that fixes is narrower than it first looks, and the
    // last test in this group records the bound: `byName` throws
    // `ArgumentError` for a name outside the enum and a type error for a
    // missing field, so a malformed envelope escaped as an exception no caller
    // was told to catch. It was never a hash downgrade — `RsaSigningAlgo`
    // implements sha256 and sha512 only, and refuses the rest at both ends.
    test('MD5 cannot be signed under in the first place', () {
      // Worth pinning, because it is what bounds the whole finding. An
      // MD5-signed envelope is not constructible with this stack:
      // RsaSigningAlgo.sign supports sha256 and sha512 and throws on anything
      // else. So the unsigned hashingAlgo field was never a downgrade — only a
      // way to pick a routine that then refuses. The allowlist above is
      // defence in depth, and it stops the refusal depending on a switch
      // statement two packages away.
      expect(
        () => RsaSigningAlgo(
                RsaKeyPair.create(
                    pkamPublicKey(atChopsA), pkamPrivateKey(atChopsA)),
                HashingAlgoType.md5)
            .sign(utf8.encode('x')),
        throwsA(isA<AtSigningException>()),
      );
    });

    test('an unknown hashingAlgo fails verification rather than escaping',
        () async {
      // `byName` threw ArgumentError for this, which is not the documented
      // failure type and escaped past callers catching the documented one.
      final envelope = await signerA.wrapAndSign({'amount': 10});
      envelope['hashingAlgo'] = 'sha3-512';
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      await expectLater(
          verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a missing hashingAlgo fails verification rather than escaping',
        () async {
      // And this was a type error, for the same reason.
      final envelope = await signerA.wrapAndSign({'amount': 10});
      envelope.remove('hashingAlgo');
      stubApskGet(atClientB, pkamPublicKey(atChopsA));

      await expectLater(
          verifierB.verifyEnvelopeSignature(envelope, signerAtSign: atSign),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('sha512 is still accepted, so the allowlist is not just sha256', () {
      // Without this the two tests above would also pass on a build that
      // refused every hash but the default.
      expect(
        () => signEnvelope('x',
            keys: ApkamSigningKeys(
                publicKey: pkamPublicKey(atChopsA),
                privateKey: pkamPrivateKey(atChopsA)),
            hashingAlgo: HashingAlgoType.sha512),
        returnsNormally,
      );
    });

    test('signing under a hash the verifier refuses is itself refused', () {
      // Otherwise a caller can mint a well-formed envelope nobody can check.
      expect(
        () => signEnvelope('x',
            keys: ApkamSigningKeys(
                publicKey: pkamPublicKey(atChopsA),
                privateKey: pkamPrivateKey(atChopsA)),
            hashingAlgo: HashingAlgoType.md5),
        throwsA(isA<AtSigningVerificationException>()),
      );
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
