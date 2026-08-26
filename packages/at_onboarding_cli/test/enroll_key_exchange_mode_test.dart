// The PQ enrolment surface is @experimental while it matures; this test drives
// it deliberately.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart' show PqPosture;
import 'package:at_commons/at_commons.dart' show AtBytes, EnrollmentStatus;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_progress.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// `at_onboarding_cli` builds its enrolment request from the posture's
/// key-exchange axis, and a caller can override it.
///
/// **The axis used to reach nothing.** `sendEnrollRequest` built the unnamed
/// `AtEnrollmentRequest(...)`, whose initialiser hard-sets
/// `EnrollmentKeyExchangeMode.legacy` — only the `.pq` named constructor sets
/// `pq`. So `at_activate enroll --posture pqActive` submitted a legacy request,
/// the enrolment advertised no key package, and nothing said so. The posture
/// was a partial instruction: it reached the preference and the authentication
/// key and stopped.
///
/// **What is asserted is the request that reaches `submit`**, captured off the
/// `AtEnrollment` seam, because that is the object at_auth turns into the wire
/// command. A test that built an `AtEnrollmentRequest` itself and checked its
/// `keyExchangeMode` would pass for a service that never consulted the posture
/// at all — it would be testing at_auth's constructor, which already has its
/// own tests.
///
/// ⚠️ **`keyExchangeMode` is not settable**, by design: the constructor decides
/// it, so that a mode and the callbacks it requires cannot be chosen
/// separately. That is why every cell below asserts the callbacks alongside the
/// mode — a `pq` request without them is a state at_auth refuses to construct,
/// and asserting the mode alone would not notice if that ever changed.
class _MockEnrollment extends Mock implements AtEnrollment {}

class _FakeAtLookUp extends Fake implements AtLookUp {}

class _FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAtLookUp());
    registerFallbackValue(_FakeEnrollmentRequest());
  });

  const atSign = '@alice';

  /// The request the service handed to `submit`, for one call under [posture].
  ///
  /// The service is otherwise untouched: no network, because the only thing
  /// reached past the request build is the injected seam.
  Future<AtEnrollmentRequest> submittedUnder(
    PqPosture posture, {
    EnrollmentKeyExchangeMode? keyExchangeMode,
  }) async {
    final enrollment = _MockEnrollment();
    late AtEnrollmentRequest captured;

    when(() => enrollment.progressStream)
        .thenAnswer((_) => const Stream<ProgressEvent>.empty());
    when(() => enrollment.submit(any(), any())).thenAnswer((invocation) async {
      captured = invocation.positionalArguments[0] as AtEnrollmentRequest;
      return AtEnrollmentResponse('dummy-id', EnrollmentStatus.pending);
    });

    final service = AtOnboardingServiceImpl(
        atSign, AtOnboardingPreference(posture: posture))
      ..enrollmentBase = enrollment;

    await service.sendEnrollRequest(
      'wavi',
      'iphone',
      'ABC123',
      const {'wavi': 'rw'},
      keyExchangeMode: keyExchangeMode,
    );
    return captured;
  }

  group('the posture decides how the symmetric key travels', () {
    test('PqPosture.legacy submits a legacy request, carrying no key package',
        () async {
      final request = await submittedUnder(PqPosture.legacy);

      expect(request.keyExchangeMode, EnrollmentKeyExchangeMode.legacy,
          reason: 'PqPosture.legacy.keyExchangeMode is legacy, so the request '
              'must be the wrapped-key shape');
      expect(request.metadataBuilder, isNull,
          reason: 'a legacy request advertises no key package: the approver '
              'unwraps the symmetric key this request carries instead');
      expect(request.apkamSymmetricKeyResolver, isNull,
          reason: 'a legacy request carries its own symmetric key in, so there '
              'is nothing to collect after approval');
    });

    test('PqPosture.pqReady submits a pq request, with both callbacks',
        () async {
      final request = await submittedUnder(PqPosture.pqReady);

      expect(request.keyExchangeMode, EnrollmentKeyExchangeMode.pq,
          reason: 'PqPosture.pqReady.keyExchangeMode is pq. This is the cell '
              'that matters most: pqReady is the SDK default, so it is what '
              'an `at_activate enroll` naming no --posture gets');
      expect(request.metadataBuilder, isNotNull,
          reason: 'a pq request must advertise a key package — it is the '
              'public half the approver encapsulates the symmetric key to');
      expect(request.apkamSymmetricKeyResolver, isNotNull,
          reason: 'a pq request mints no symmetric key of its own, so without '
              'a resolver nothing ever collects what the approver sealed');
      expect(request.encryptedAPKAMSymmetricKey, isNull,
          reason:
              'the point of pq mode: nothing RSA-wrapped rides the request');
    });

    test('PqPosture.pqActive submits a pq request', () async {
      final request = await submittedUnder(PqPosture.pqActive);

      expect(request.keyExchangeMode, EnrollmentKeyExchangeMode.pq,
          reason: 'this is the posture whose name was in the defect report: '
              '`enroll --posture pqActive` used to submit legacy');
      expect(request.metadataBuilder, isNotNull);
      expect(request.apkamSymmetricKeyResolver, isNotNull);
    });

    test('the request states the posture\'s authentication algorithm',
        () async {
      expect((await submittedUnder(PqPosture.legacy)).signingAlgo,
          SigningAlgoType.rsa2048,
          reason: 'PqPosture.legacy.authenticationKeyAlgorithm is rsa2048');
      expect((await submittedUnder(PqPosture.pqReady)).signingAlgo,
          SigningAlgoType.mldsa65,
          reason: 'PqPosture.pqReady.authenticationKeyAlgorithm is mldsa65');
    });

    test('the key package is built under that algorithm too, not a constant',
        () async {
      // ⚠️ **This test exists because the assertion above does NOT cover it,
      // and a mutation proved that.** Writing `SigningAlgoType.rsa2048` by
      // hand into the `enrollmentKeyPackageBuilder(...)` call left every other
      // cell in this file green: `request.signingAlgo` is a different field
      // from the one handed to the builder, so asserting it says nothing about
      // what the package is signed with.
      //
      // Running the builder is the only way to observe the algorithm it was
      // given. It signs with the APKAM keypair in the AtKeysIo it is handed,
      // so an ML-DSA keypair plus a builder told "rsa2048" is a size mismatch
      // at_chops refuses — which is exactly the production failure this
      // guards: a key package signed by a key the enrollment record does not
      // name verifies against nothing, so every peer that resolves `_apsk`
      // before sealing a secret to this enrollment declines, and the
      // enrollment is created and then receives no conveyed material at all.
      final request = await submittedUnder(PqPosture.pqReady);

      final pair = await MlDsa65KeyPair.generate();
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(
          atSign,
          AtKeys()
            ..apkamPublicKey = AtBytes.fromString(pair.atPublicKey.publicKey)
            ..apkamPrivateKey =
                AtBytes.fromString(pair.atPrivateKey.privateKey));

      final metadata = await request.metadataBuilder!(keysIo);

      expect(metadata, isNotNull,
          reason: 'the builder must produce a key package for the ML-DSA-65 '
              'APKAM keypair pqReady mints. A null or a throw here means it '
              'was handed an algorithm that is not the one the request states');
      expect(metadata!['keyPackage'], isNotNull,
          reason: 'the metadata the builder files is the key package itself — '
              'assert the payload, not merely that something came back');
    });
  });

  group('an explicit mode overrides the posture, in both directions', () {
    // The override exists for the half a posture cannot see: the APPROVER. A pq
    // request relies on the approver sealing a symmetric key to the advertised
    // key package, and against an approver that predates conveyance the
    // enrollment is approved and then cannot decrypt anything. Only the person
    // running the command knows which approver will pick the request up.
    test('legacy is reachable from a pq posture — the escape hatch', () async {
      final request = await submittedUnder(PqPosture.pqActive,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);

      expect(request.keyExchangeMode, EnrollmentKeyExchangeMode.legacy,
          reason: 'naming legacy must win over pqActive, or an app enrolling '
              'against a known-legacy approver has no way through');
      expect(request.metadataBuilder, isNull);
    });

    test('pq is reachable from a legacy posture', () async {
      final request = await submittedUnder(PqPosture.legacy,
          keyExchangeMode: EnrollmentKeyExchangeMode.pq);

      expect(request.keyExchangeMode, EnrollmentKeyExchangeMode.pq,
          reason: 'the override is symmetric. Asserted so that a resolution '
              'written as "pq only if the posture also says pq" — which would '
              'pass every other cell in this file — goes red here');
      expect(request.apkamSymmetricKeyResolver, isNotNull);
    });
  });
}
