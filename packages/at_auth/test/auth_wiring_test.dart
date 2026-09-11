/// Which wiring `AtAuthImpl` installs on its lookup to authenticate.
///
/// A lookup that can take an authenticator gets one and nothing else; a
/// lookup that cannot gets at_lookup's credential fields, because those are
/// the only route it has. The two arms are asserted separately, and each is
/// the other's control: a change that wrote both again, or neither, reddens
/// one of them.
///
/// The lookup is mocked past the point where authentication would run, so
/// nothing here would notice a wiring that authenticates as nobody. What is
/// asserted is the installation itself, which is the thing the handshake's
/// equivalent test found was covered by nothing.
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// `AtLookupImpl` implements `AtLookupMuxable`, so this double has the seam.
class MockMuxableLookUp extends Mock implements AtLookupImpl {}

/// The frozen interface alone: no authenticator seam, only the credential
/// fields. What a mock or a third-party implementation looks like to at_auth.
class MockPlainLookUp extends Mock implements AtLookUp {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockAtServerStatus extends Mock implements AtServerStatus {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeAtLookUp extends Fake implements AtLookupImpl {}

class FakeSecondaryAddressFinder extends Fake
    implements CacheableSecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('abcd', 123);
}

void main() {
  const atSign = '@alice🛠';

  /// The enrollment the committed legacy keyfile authenticates as.
  const legacyEnrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
  const onboardedEnrollmentId = 'abc123';
  const cramSecret = 'not-checked-the-lookup-is-mocked';

  setUpAll(() {
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
  });

  /// An `AtAuthImpl` around [lookUp], with everything past the lookup mocked
  /// to succeed.
  ///
  /// [activated] is what the atServer reports about the atSign: `onboard`
  /// refuses an activated one, and `authenticate` needs one.
  AtAuthImpl rig(AtLookUp lookUp,
      {required String enrollmentId, required bool activated}) {
    final pkam = MockPkamAuthenticator();
    when(() => pkam.authenticate(any(), any(), enrollmentId: enrollmentId))
        .thenAnswer((_) async => true);
    final status = MockAtServerStatus();
    when(() => status.get(any())).thenAnswer((_) async => activated
        ? AtStatus(
            serverStatus: ServerStatus.ready,
            rootStatus: RootStatus.found,
            atSignStatus: AtSignStatus.activated)
        : AtStatus(
            serverStatus: ServerStatus.teapot,
            rootStatus: RootStatus.found,
            atSignStatus: AtSignStatus.teapot));
    final enrollment = MockAtEnrollment();
    when(() => enrollment.submit(any(), lookUp)).thenAnswer((_) async =>
        AtEnrollmentResponse(onboardedEnrollmentId, EnrollmentStatus.approved));
    return AtAuthImpl(
        atLookUp: lookUp,
        pkamAuthenticator: pkam,
        atEnrollment: enrollment,
        atServerStatus: status)
      ..secondaryAddressFinder = FakeSecondaryAddressFinder()
      ..probeSocket = (host, port) async {};
  }

  /// Authenticates from the committed legacy keyfile, whose flat fields name
  /// no algorithm — so at_lookup's default is the right one and nothing
  /// should set it.
  Future<void> authenticate(AtAuthImpl auth) => auth.authenticate(AtAuthRequest(
        atSign,
        atKeysIo: FileAtKeysIo(
            filePath: (atsign) => 'test/data/${atsign}_key.atKeys'),
      ));

  /// Onboards with a PQ activation key, the case where an algorithm HAS to be
  /// named because at_lookup's default would sign an ML-DSA key with RSA.
  Future<void> onboard(AtAuthImpl auth, AtLookUp lookUp) {
    when(() => lookUp.cramAuthenticate(cramSecret)).thenAnswer((_) async => true);
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.close()).thenAnswer((_) async {});
    return auth.onboard(
        AtOnboardingRequest(atSign, signingAlgoType: SigningAlgoType.mldsa65)
          ..atKeysIo = InMemoryAtKeysIo()
          ..appName = 'wavi'
          ..deviceName = 'iphone',
        cramSecret);
  }

  group('a lookup that can take an authenticator', () {
    test('authenticate installs one, and never touches the ladder', () async {
      final lookUp = MockMuxableLookUp();

      await authenticate(
          rig(lookUp, enrollmentId: legacyEnrollmentId, activated: true));

      // The setter call, not the stored value: a mock keeps nothing.
      verify(() => lookUp.authenticator = any(that: isNotNull)).called(1);
      verifyNever(() => lookUp.atChops = any());
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65);
    });

    test('onboard installs one twice, and never touches the ladder',
        () async {
      // Twice: once for the CRAM leg, and again once the atServer has named
      // the enrollment, because the id is captured at install time.
      final lookUp = MockMuxableLookUp();

      await onboard(
          rig(lookUp, enrollmentId: onboardedEnrollmentId, activated: false),
          lookUp);

      verify(() => lookUp.authenticator = any(that: isNotNull)).called(2);
      verifyNever(() => lookUp.atChops = any());
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
    });
  });

  group('a lookup that cannot', () {
    test('authenticate sets the credential fields instead', () async {
      final lookUp = MockPlainLookUp();

      await authenticate(
          rig(lookUp, enrollmentId: legacyEnrollmentId, activated: true));

      verify(() => lookUp.atChops = any(that: isNotNull)).called(1);
      // Legacy material names no algorithm, so the default stands.
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65);
    });

    test('onboard sets the credential fields and names the algorithm',
        () async {
      final lookUp = MockPlainLookUp();

      await onboard(
          rig(lookUp, enrollmentId: onboardedEnrollmentId, activated: false),
          lookUp);

      verify(() => lookUp.atChops = any(that: isNotNull))
          .called(greaterThan(0));
      verify(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65)
          .called(greaterThan(0));
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
    });
  });
}
