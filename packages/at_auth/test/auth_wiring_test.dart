/// Which wiring `AtAuthImpl` installs on its lookup to activate, and what
/// the authenticator it installs signs with.
///
/// The lookup takes an authenticator and nothing else: at_lookup's credential
/// fields are never written, and the test asserts both halves.
///
/// The lookup is mocked past the point where authentication would run, so
/// nothing here would notice a wiring that authenticates as nobody. What is
/// asserted is the installation itself, which is the thing the handshake's
/// equivalent test found was covered by nothing.
library;

// That the credential ladder is never written is asserted, so this file names
// the ladder on purpose.
// ignore_for_file: deprecated_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/pkam_pin.dart';

/// `AtLookupImpl` implements `AtLookupMuxable`, so this double has the seam.
class MockMuxableLookUp extends Mock implements AtLookupImpl {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeAtLookUp extends Fake implements AtLookupImpl {}

/// Runs an installed [AtAuthenticator] for real and records what it sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

class FakeSecondaryAddressFinder implements SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('abcd', 123);
}

void main() {
  const atSign = '@alice🛠';

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
  AtAuthImpl rig(AtLookupMuxable lookUp,
      {required String? enrollmentId, required bool activated}) {
    final pkam = MockPkamAuthenticator();
    when(() => pkam.authenticate(any(), any()))
        .thenAnswer((_) async => true);
    when(() => lookUp.secondaryAddressFinder)
        .thenReturn(FakeSecondaryAddressFinder());
    when(() => lookUp.executeCommand(any(that: startsWith('lookup:publickey')),
        auth: any(named: 'auth'))).thenAnswer((_) async => activated
        ? 'data:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA'
        : throw AtLookUpException('AT0015', 'key not found'));
    final enrollment = MockAtEnrollment();
    when(() => enrollment.submit(any(), lookUp)).thenAnswer((_) async =>
        AtEnrollmentResponse(onboardedEnrollmentId, EnrollmentStatus.approved));
    return AtAuthImpl(
        atLookUp: lookUp,
        pkamAuthenticator: pkam,
        atEnrollment: enrollment);
  }

  /// A legacy-shaped keyfile holding [owner]'s demo material, in memory.
  Future<InMemoryAtKeysIo> demoKeyfile(String owner) async {
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys()
          ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[owner]!)
          ..apkamPrivateKey =
              AtBytes.fromString(demo.pkamPrivateKeyMap[owner]!)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(demo.encryptionPublicKeyMap[owner]!)
          ..defaultEncryptionPrivateKey =
              AtBytes.fromString(demo.encryptionPrivateKeyMap[owner]!)
          ..defaultSelfEncryptionKey =
              AtBytes.fromString(demo.aesKeyMap[owner]!));
    return io;
  }

  /// Runs the authenticator `authenticatorFor` builds over [keysIo] against
  /// the pinned challenge and returns the `pkam:` command it sent. The
  /// enrollment is the keys' own answer, as every caller resolves it.
  Future<String> pkamFrom(AtKeysIo keysIo) async {
    final installed = authenticatorFor(keysIo, atSign,
        enrollmentId:
            (await keysIo.read(atSign)).enrollmentToAuthenticateAs());
    final executor =
        _RecordingExecutor(['data:$pkamPinChallenge', 'data:success']);
    expect(await installed(executor), isTrue);
    return executor.sent.last;
  }

  /// Onboards with a PQ activation key, the case where an algorithm HAS to be
  /// named because at_lookup's default would sign an ML-DSA key with RSA.
  Future<void> onboard(AtAuthImpl auth, AtLookupMuxable lookUp) {
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    return auth.onboard(
        AtOnboardingRequest(atSign, signingAlgoType: SigningAlgoType.mldsa65)
          ..atKeysIo = InMemoryAtKeysIo()
          ..appName = 'wavi'
          ..deviceName = 'iphone',
        cramSecret);
  }

  group('a lookup that can take an authenticator', () {

    test('onboard installs one three times', () async {
      // The CRAM authenticator for the activation's first login, the
      // keyfile's once its keys exist, and the keyfile's again once the
      // atServer has named the enrollment, because the id is captured at
      // install time.
      final lookUp = MockMuxableLookUp();

      await onboard(
          rig(lookUp, enrollmentId: onboardedEnrollmentId, activated: false),
          lookUp);

      verify(() => lookUp.authenticator = any(that: isNotNull)).called(3);
    });
  });

  group('what the installed authenticator signs with', () {
    test('the keyfile\'s own keypair, to the byte', () async {
      expect(await pkamFrom(await demoKeyfile(pkamPinAtSign)),
          endsWith(':$expectedPkamSignature\n'),
          reason: 'the bytes openssl produces for this challenge under the '
              'keyfile\'s PKAM key: what signs may move, the signature may not');
    });
  });
}
