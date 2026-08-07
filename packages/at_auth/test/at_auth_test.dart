import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class MockAtServerStatus extends Mock implements AtServerStatus {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeAtLookUp extends Fake implements AtLookUp {}

class FakeSecondaryAddressFinder extends Fake
    implements CacheableSecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    return SecondaryAddress('abcd', 123);
  }
}

void main() {
  late AtAuthImpl atAuth;
  late MockAtLookUp mockAtLookUp;
  late MockPkamAuthenticator mockPkamAuthenticator;
  late MockAtServerStatus mockAtServerStatus;
  late AtEnrollment mockAtEnrollment;
  late FileAtKeysIo fileAtKeysIo;
  final String testEnrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
  final alice = '@alice🛠'.toAtsign();
  late FakeSecondaryAddressFinder fakeSecondaryAddressFinder;

  /// Every AtLookUp the factory handed out, in construction order, paired with
  /// the keys it was built from. Onboarding builds two, and which keys each one
  /// got is the thing worth asserting.
  late List<({AtKeys? keys, String? enrollmentId})> builtLookUps;

  // mocktail's fallback registry is process-global; registering once is enough.
  setUpAll(() {
    // Several tests assert a failure path, and AtAuthImpl logs those at SEVERE
    // with a stack trace. Quieten it so a green run reads as green.
    AtSignLogger.root_level = 'shout';
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeAtLookUp());
    registerFallbackValue(legacyAtKeys());
  });

  setUp(() {
    // Reads the committed @alice🛠 fixture. Tests that *write* keys use their
    // own io over a temp dir, so nothing lands in test/data.
    fileAtKeysIo =
        FileAtKeysIo(filePath: (atsign) => 'test/data/${atsign}_key.atKeys');
  });

  /// Fresh mocks plus the stubs every test in either group needs: a reachable
  /// atServer of [atStatus] and a closeable AtLookup.
  ///
  /// `atLookUpFactory` is the seam: at_auth builds its own AtLookUp from the
  /// keys it reads, so a test substitutes the construction rather than injecting
  /// a connection.
  void buildAtAuth(
      {required AtStatus atStatus,
      RetryOptions? retryOptions,
      ApkamSigningScheme signing = ApkamSigningScheme.legacy}) {
    mockAtLookUp = MockAtLookUp();
    mockPkamAuthenticator = MockPkamAuthenticator();
    mockAtServerStatus = MockAtServerStatus();
    mockAtEnrollment = MockAtEnrollment();
    fakeSecondaryAddressFinder = FakeSecondaryAddressFinder();
    builtLookUps = [];
    when(() => mockAtServerStatus.get(any()))
        .thenAnswer((_) => Future.value(atStatus));
    when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
    atAuth = AtAuthImpl(
      retryOptions: retryOptions ?? RetryOptions.defaultRetryOptions,
      signing: signing,
      pkamAuthenticator: mockPkamAuthenticator,
      atServerStatus: mockAtServerStatus,
      enrollmentFactory: (_) => mockAtEnrollment,
      atLookUpFactory: (_, __, keys, {enrollmentId}) {
        builtLookUps.add((keys: keys, enrollmentId: enrollmentId));
        return mockAtLookUp;
      },
    );
    atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
    atAuth.probeSocket = (host, port) async {};
  }

  group('AtAuthImpl.enrollmentFactory', () {
    test('the default builds an enrollment signing the same scheme', () {
      // An enrollment stamping a different scheme than at_auth signs with
      // would enroll a key the atServer then refuses to verify PKAM against.
      for (final signing in ApkamSigningScheme.values) {
        final atAuth = AtAuthImpl(
          retryOptions: RetryOptions.defaultRetryOptions,
          signing: signing,
        );

        expect(atAuth.enrollmentFactory(MockAtLookUp()).signing, signing);
      }
    });
  });

  group('AtAuthImpl authentication tests', () {
    setUp(() {
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.ready,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.activated));
    });

    test('Test authenticate() with keys file exposes the connection it used',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: testEnrollmentId)).thenAnswer((_) async {});

      await atAuth.authenticate(alice, AtRootDomain.atsignDomain, fileAtKeysIo,
          enrollmentId: testEnrollmentId);

      // Completing without throwing IS the success signal; the connection it
      // authenticated is what a client adopts to skip a second handshake.
      expect(atAuth.atLookUp, same(mockAtLookUp));
      // The keys read from the io were bound into that connection.
      expect(builtLookUps, hasLength(1));
      expect(builtLookUps.single.enrollmentId, testEnrollmentId);
      expect(builtLookUps.single.keys!.atsign, alice);
    });

    test('Test authenticate() takes the enrollmentId from the keys file',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: any(named: 'enrollmentId'))).thenAnswer((_) async {});

      // The fixture keyfile carries this enrollmentId and the caller leaves it
      // unset, so authenticate must fall back to the one in the keys — and it
      // must reach the connection, which is what the pkam verb is stamped with.
      await atAuth.authenticate(alice, AtRootDomain.atsignDomain, fileAtKeysIo);

      expect(builtLookUps.single.enrollmentId, testEnrollmentId);
      verify(() => mockPkamAuthenticator.authenticate(alice, mockAtLookUp,
          enrollmentId: testEnrollmentId)).called(1);
    });

    test('Test authenticate() with an in-memory AtKeysIo', () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: testEnrollmentId)).thenAnswer((_) async {});

      // The modern replacement for handing AtKeys over directly: supply them
      // through an in-memory AtKeysIo.
      final memoryIo = EphemeralAtKeysIo();
      final keys = legacyAtKeys(atsign: alice);
      await memoryIo.write(alice, keys);

      await atAuth.authenticate(alice, AtRootDomain.atsignDomain, memoryIo,
          enrollmentId: testEnrollmentId);

      expect(atAuth.atLookUp, same(mockAtLookUp));
      expect(builtLookUps.single.keys!.apkamPrivateKey, keys.apkamPrivateKey);
    });

    test('Test authenticate() invalid keys file path', () async {
      final missingIo =
          FileAtKeysIo(filePath: (_) => 'test/hello/data/@alice🛠_key.atKeys');

      expect(
          () async => await atAuth.authenticate(
              alice, AtRootDomain.atsignDomain, missingIo,
              enrollmentId: testEnrollmentId),
          throwsA(isA<AtException>()));
    });

    test('Test authenticate() wraps a failed PKAM in AtAuthenticationException',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      await expectLater(
          () async => await atAuth.authenticate(
              alice, AtRootDomain.atsignDomain, fileAtKeysIo,
              enrollmentId: testEnrollmentId),
          throwsA(isA<AtAuthenticationException>()));
      // The connection we opened must not leak when authenticate throws, and
      // must not be left exposed as though it were usable.
      verify(() => mockAtLookUp.close()).called(1);
      expect(atAuth.atLookUp, isNull);
    });

    test(
        'validateAtServer honours overallTimeout instead of retrying until the '
        'network gives up', () async {
      // Every probe fails, so without a deadline validateAtServer would keep
      // retrying every retryDelay(2s). A short overallTimeout must cut that
      // short and surface an AtTimeoutException.
      buildAtAuth(
        atStatus: AtStatus(
            serverStatus: ServerStatus.ready,
            rootStatus: RootStatus.found,
            atSignStatus: AtSignStatus.activated),
        retryOptions: const RetryOptions(
            retryDelay: Duration(seconds: 2),
            overallTimeout: Duration(milliseconds: 300)),
      );
      atAuth.probeSocket = (host, port) async {
        throw Exception('simulated unreachable atServer');
      };

      final sw = Stopwatch()..start();
      await expectLater(
        atAuth.validateAtServer(alice, AtRootDomain.atsignDomain),
        throwsA(isA<AtTimeoutException>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'should honour overallTimeout (300ms), not keep retrying');
    });
  });

  group('AtAuthImpl onboarding tests', () {
    var testCramSecret = 'cram123';
    // Onboarding mints and persists keys, so it gets a throwaway directory
    // rather than writing into the committed test/data.
    late Directory keysDir;
    late FileAtKeysIo onboardingKeysIo;

    setUp(() {
      keysDir = Directory.systemTemp.createTempSync('at_auth_onboard_test');
      addTearDown(() => keysDir.deleteSync(recursive: true));
      onboardingKeysIo = FileAtKeysIo(
          filePath: (atsign) => '${keysDir.path}/${atsign}_key.atKeys');
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.teapot,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.teapot));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
    });

    /// Stubs the happy path: CRAM succeeds, the server approves the first
    /// enrollment as 'abc123', and PKAM succeeds.
    void stubSuccessfulOnboarding() {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: 'abc123')).thenAnswer((_) async {});
      when(() => mockAtEnrollment.firstEnrollment(any(),
              appName: any(named: 'appName'),
              deviceName: any(named: 'deviceName')))
          .thenAnswer((_) => Future.value(
              AtEnrollmentResponse('abc123', EnrollmentStatus.approved)));
    }

    /// The `(apkamPublicKey, appName, deviceName)` onboarding sent to the
    /// atServer's first enrollment.
    ({String apkamPublicKey, String? appName, String? deviceName})
        capturedFirstEnrollment() {
      final captured = verify(() => mockAtEnrollment.firstEnrollment(
          captureAny(),
          appName: captureAny(named: 'appName'),
          deviceName: captureAny(named: 'deviceName'))).captured;
      return (
        apkamPublicKey: captured[0] as String,
        appName: captured[1] as String?,
        deviceName: captured[2] as String?,
      );
    }

    test('Test onboard - cramAuthenticate returns false', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(false));

      expect(
          () async => await atAuth.onboard('@aaron🛠'.toAtsign(),
              AtRootDomain.atsignDomain, onboardingKeysIo, testCramSecret),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('Test onboard with appName and deviceName supplied', () async {
      stubSuccessfulOnboarding();
      final bob = '@bob🛠'.toAtsign();

      await atAuth.onboard(
          bob, AtRootDomain.atsignDomain, onboardingKeysIo, testCramSecret,
          appName: 'wavi', deviceName: 'iphone');

      final request = capturedFirstEnrollment();
      expect(request.appName, 'wavi');
      expect(request.deviceName, 'iphone');
      // Onboarding persisted the freshly minted keys through the io it was
      // given, and the connection it ends on is the PKAM-authenticated one.
      expect(File('${keysDir.path}/@bob🛠_key.atKeys').existsSync(), isTrue);
      expect(atAuth.atLookUp, same(mockAtLookUp));
    });

    test('Test onboard leaves the activation naming to firstEnrollment',
        () async {
      stubSuccessfulOnboarding();
      final colin = '@colin🛠'.toAtsign();

      await atAuth.onboard(
          colin, AtRootDomain.atsignDomain, onboardingKeysIo, testCramSecret);

      // onboard passes nothing through, so the reserved 'firstApp'/'firstDevice'
      // names come from firstEnrollment's own defaults — asserted on the wire in
      // enrollment_test.dart's `firstEnrollment` group. Naming them in two
      // places is how they would drift.
      final request = capturedFirstEnrollment();
      expect(request.appName, isNull);
      expect(request.deviceName, isNull);
    });

    test(
        'Test onboard CRAMs on a keyless connection and PKAMs on one built '
        'from the minted keys', () async {
      stubSuccessfulOnboarding();

      await atAuth.onboard('@colin🛠'.toAtsign(), AtRootDomain.atsignDomain,
          onboardingKeysIo, testCramSecret);

      // at_lookup binds its PKAM key at construction, so activation cannot run
      // on one connection: the first has no keys to sign with, and the second
      // carries the keypair that did not exist when the first was built.
      expect(builtLookUps, hasLength(2));
      expect(builtLookUps.first.keys, isNull);
      expect(builtLookUps.first.enrollmentId, isNull);
      expect(builtLookUps.last.keys, isNotNull);
      expect(builtLookUps.last.keys!.apkamPrivateKey, isNotNull);
      expect(builtLookUps.last.enrollmentId, 'abc123');
    });

    test('Test onboard enrolls the public key of its signing scheme', () async {
      // The key enrolled must be the one PKAM then signs with. Under the default
      // legacy scheme that is the flat RSA field of the keyset just minted —
      // which is also the keyset the second connection was built from.
      stubSuccessfulOnboarding();

      await atAuth.onboard('@colin🛠'.toAtsign(), AtRootDomain.atsignDomain,
          onboardingKeysIo, testCramSecret);

      final mintedKeys = builtLookUps.last.keys!;
      final enrolled = capturedFirstEnrollment().apkamPublicKey;
      expect(enrolled, mintedKeys.apkamPublicKey.toString());
      // base64, not a stringified Uint8List — the atServer has to be able to
      // decode what it was handed.
      expect(
          AtBytes.fromString(enrolled).bytes, mintedKeys.apkamPublicKey!.bytes);
    });

    test('Test onboard enrolls the ML-DSA key under the post-quantum scheme',
        () async {
      // Same rule, other scheme: a PQ activation must enroll the key its PQ
      // PKAM connection will sign with, never the legacy one.
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.teapot,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.teapot),
          signing: ApkamSigningScheme.postQuantum);
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      stubSuccessfulOnboarding();

      await atAuth.onboard('@colin🛠'.toAtsign(), AtRootDomain.atsignDomain,
          onboardingKeysIo, testCramSecret);

      final mintedKeys = builtLookUps.last.keys!;
      expect(
          capturedFirstEnrollment().apkamPublicKey,
          ApkamSigningScheme.postQuantum
              .requireApkamPublicKey(mintedKeys)
              .toString());
    });

    test('Test onboard rejects a keyset with no key for its scheme', () async {
      // mintLegacy: false mints only PQ material, so the default legacy scheme
      // has nothing to enroll. That has to be a clear failure, not a
      // null-assertion crash or — worse — silently enrolling the PQ key and
      // then PKAMing with a key the atServer never saw.
      stubSuccessfulOnboarding();

      await expectLater(
          () async => await atAuth.onboard('@colin🛠'.toAtsign(),
              AtRootDomain.atsignDomain, onboardingKeysIo, testCramSecret,
              mintLegacy: false),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('Test onboard completes with a post-quantum-only keyset', () async {
      // The same keyset the previous test rejects is exactly what a postQuantum
      // activation wants — the scheme is what decides, not the material.
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.teapot,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.teapot),
          signing: ApkamSigningScheme.postQuantum);
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      stubSuccessfulOnboarding();

      await atAuth.onboard('@colin🛠'.toAtsign(), AtRootDomain.atsignDomain,
          onboardingKeysIo, testCramSecret,
          mintLegacy: false);

      final mintedKeys = builtLookUps.last.keys!;
      expect(mintedKeys.apkamPrivateKey, isNull);
      expect(mintedKeys.keysForKeyId(KeyIds.apkamPQ), isNotEmpty);
      expect(atAuth.atLookUp, same(mockAtLookUp));
    });

    test('Test onboard leaves no connection exposed when it fails', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(false));

      await expectLater(
          () async => await atAuth.onboard('@aaron🛠'.toAtsign(),
              AtRootDomain.atsignDomain, onboardingKeysIo, testCramSecret),
          throwsA(isA<AtAuthenticationException>()));

      expect(atAuth.atLookUp, isNull);
      verify(() => mockAtLookUp.close()).called(greaterThanOrEqualTo(1));
    });
  });
}
