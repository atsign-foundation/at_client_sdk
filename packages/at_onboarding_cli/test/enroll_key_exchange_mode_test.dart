// The PQ enrolment surface is @experimental; this test drives it deliberately.
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
/// What is asserted is the request that reaches `submit`, captured off the
/// `AtEnrollment` seam, because that is the object at_auth turns into the wire
/// command; a test that built an `AtEnrollmentRequest` itself would be testing
/// at_auth's constructor instead.
///
/// `keyExchangeMode` is not settable — the constructor decides it, so a mode
/// and the callbacks it requires cannot be chosen separately, which is why
/// every cell below asserts the callbacks alongside the mode.
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
      // NOTE: `request.signingAlgo` is a different field from the one handed
      // to the key package builder, so asserting it says nothing about what
      // the package is signed with; running the builder is the only way to
      // observe the algorithm it was given. A package signed by a key the
      // enrollment record does not name verifies against nothing, so every
      // peer declines to seal anything to that enrollment.
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
    // The override exists for the half a posture cannot see: the approver. A
    // pq request relies on the approver sealing a symmetric key to the
    // advertised key package, and only the person running the command knows
    // which approver will pick the request up.
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

  /// The enrolment owns a data signing key from birth, under the algorithm the
  /// in-use set names.
  ///
  /// Without one, `_apsk` advertises the APKAM authentication key, and the new
  /// client's first start mints a signing key and republishes — dropping that
  /// entry, so the key package stops verifying and any link the approver
  /// conveyed against the advertised value stops matching.
  group('the enrolment advertises a data signing key of its own', () {
    test('pqReady advertises rsa2048, not the APKAM key', () async {
      final request = await submittedUnder(PqPosture.pqReady);

      expect(request.advertisedSigningKey?.algorithm, SigningAlgoType.rsa2048,
          reason: 'the bare `_apsk` form takes exactly one active rsa2048 '
              'entry, and that is the spelling an un-upgraded peer parses');
      expect(request.advertisedSigningKey!.publicKey, isNotEmpty);
      expect(request.advertisedSigningKey!.privateKey, isNotEmpty,
          reason: 'the private half travels on the request so at_auth can FILE '
              'it once the atServer names the enrollment; advertising without '
              'filing is what makes the first start mint a second keypair');
    });

    test('pqActive advertises mldsa65 — the algorithm the enrollment keeps',
        () async {
      final request = await submittedUnder(PqPosture.pqActive);

      expect(request.advertisedSigningKey?.algorithm, SigningAlgoType.mldsa65,
          reason: 'minting rsa2048 here would leave the first start finding '
              'ML-DSA missing, minting again and republishing `_apsk` — which '
              'invalidates the link the approver conveyed, since a link is '
              'bound to the exact advertised value it vouched for');
    });

    test('legacy advertises none', () async {
      final request = await submittedUnder(PqPosture.legacy);

      expect(request.advertisedSigningKey, isNull,
          reason: 'PqPosture.legacy names no data signing algorithm at all: '
              'its authentication keypair does both jobs');
    });

    test('a legacy-MODE enrolment under a pq posture still advertises one',
        () async {
      // The mode decides whether a key package exists; `_apsk` is what peers
      // verify signatures against whatever the mode. Conflating the two would
      // leave this enrolment advertising its APKAM key.
      final request = await submittedUnder(PqPosture.pqReady,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);

      expect(request.metadataBuilder, isNull,
          reason: 'the control: no key package, because the mode says legacy');
      expect(request.advertisedSigningKey?.algorithm, SigningAlgoType.rsa2048,
          reason: 'and yet it still owns its signing key, because the posture '
              'names one');
    });
  });
}
