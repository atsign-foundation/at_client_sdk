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
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/pkam_pin.dart';

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
  ///
  /// [chops] is a signer injected through the constructor, the door a caller
  /// with a hardware-backed key uses.
  AtAuthImpl rig(AtLookUp lookUp,
      {required String? enrollmentId,
      required bool activated,
      // ignore: deprecated_member_use
      AtChops? chops}) {
    final pkam = MockPkamAuthenticator();
    when(() => pkam.authenticate(any(), any(),
            enrollmentId: enrollmentId ?? any(named: 'enrollmentId')))
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
        atChops: chops,
        pkamAuthenticator: pkam,
        atEnrollment: enrollment,
        atServerStatus: status)
      ..secondaryAddressFinder = FakeSecondaryAddressFinder()
      ..probeSocket = (host, port) async {};
  }

  /// Authenticates from the committed legacy keyfile, whose flat fields name
  /// no algorithm — so at_lookup's default is the right one and nothing
  /// should set it.
  Future<void> authenticate(AtAuthImpl auth, {AtKeysIo? keysIo}) =>
      auth.authenticate(AtAuthRequest(
        atSign,
        atKeysIo: keysIo ??
            FileAtKeysIo(
                filePath: (atsign) => 'test/data/${atsign}_key.atKeys'),
      ));

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

  /// Runs the authenticator [lookUp] was handed against the pinned challenge
  /// and returns the `pkam:` command it sent.
  Future<String> pkamSentBy(MockMuxableLookUp lookUp) async {
    final installed = verify(() => lookUp.authenticator = captureAny())
        .captured
        .single as AtAuthenticator;
    final executor =
        _RecordingExecutor(['data:$pkamPinChallenge', 'data:success']);
    expect(await installed(executor), isTrue);
    return executor.sent.last;
  }

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

  group('what the installed authenticator signs with', () {
    test('the keyfile\'s own keypair, to the byte', () async {
      final lookUp = MockMuxableLookUp();

      await authenticate(rig(lookUp, enrollmentId: null, activated: true),
          keysIo: await demoKeyfile(pkamPinAtSign));

      expect(await pkamSentBy(lookUp), endsWith(':$expectedPkamSignature\n'),
          reason: 'the bytes openssl produces for this challenge under the '
              'keyfile\'s PKAM key: what signs may move, the signature may not');
    });

    test('a signer the caller injected, over the keyfile', () async {
      // The keyfile holds another atSign's keypair, so if the keyfile signed
      // the signature would not be the pin's. The door for a signer that is
      // not a keyfile at all - a hardware-backed one - and this is its test.
      final lookUp = MockMuxableLookUp();
      // ignore: deprecated_member_use
      final injected = AtChopsImpl(AtChopsKeys.create(
          null,
          // ignore: deprecated_member_use
          AtPkamKeyPair.create(demo.pkamPublicKeyMap[pkamPinAtSign]!,
              demo.pkamPrivateKeyMap[pkamPinAtSign]!)));
      final auth =
          rig(lookUp, enrollmentId: null, activated: true, chops: injected);

      await authenticate(auth, keysIo: await demoKeyfile('@bob🛠'));

      expect(await pkamSentBy(lookUp), endsWith(':$expectedPkamSignature\n'),
          reason: 'the injected signer\'s key, not the keyfile\'s');
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
