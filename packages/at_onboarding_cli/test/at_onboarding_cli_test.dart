import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/onboard/helpers/enrollment_checkpoint.dart';

// ignore: depend_on_referenced_packages
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
// ignore: depend_on_referenced_packages
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class MockAtAuthImpl extends Mock implements AtAuth {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

class MockAtClient extends Mock implements AtClient {}

class MockEnrollmentBase extends Mock implements AtEnrollment {}

class MockEnrollmentRequest extends Mock implements EnrollmentRequest {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

/// The approval handshake is at_auth's (`waitForApproval`); tests whose
/// subject is the CLI's own behaviour stub it at that seam. [body] runs in
/// place of the handshake — a test that needs "during approval" side effects
/// (or a denial) expresses them there.
void stubHandshake(MockEnrollmentBase mock, {Future<void> Function()? body}) {
  registerFallbackValue(
      AtEnrollmentResponse('fallback', EnrollmentStatus.pending));
  registerFallbackValue(MockAtLookupImpl());
  registerFallbackValue(Duration.zero);
  when(() => mock.progressStream).thenAnswer((_) => Stream.empty());
  when(() => mock.waitForApproval(any(),
      atLookup: any(named: 'atLookup'),
      retryInterval: any(named: 'retryInterval'),
      logProgress: any(named: 'logProgress'),
      maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async {
    if (body != null) await body();
  });
}

void main() {
  AtSignLogger.root_level = 'INFO';
  AtLookupImpl mockAtLookup = MockAtLookupImpl();
  AtAuth mockAtAuth = MockAtAuthImpl();

  setUp(() {
    reset(mockAtLookup);
    reset(mockAtAuth);
    registerFallbackValue(FakeAtAuthRequest());
    when(() => mockAtAuth.progressStream).thenAnswer((_) => Stream.empty());
  });

  group('A group of tests to verify at_chops creation in onboarding_cli', () {
    setUp(() {
      reset(mockAtLookup);
      reset(mockAtAuth);
      registerFallbackValue(FakeAtAuthRequest());
      when(() => mockAtAuth.progressStream).thenAnswer((_) => Stream.empty());
    });

    test('A test to check atOnboardingService.authenticate() returns true',
        () async {
      final atSign = '@alice🛠';
      AtOnboardingPreference onboardingPreference = AtOnboardingPreference()
        ..atKeysFilePath = 'test/data/@alice🛠_key.atKeys'
        ..namespace = 'unit_test';
      AtOnboardingService onboardingService =
          AtOnboardingServiceImpl(atSign, onboardingPreference);
      onboardingService.atLookUp = mockAtLookup;
      mockAtAuth.atChops = AtChopsImpl(AtChopsKeys());
      onboardingService.atAuth = mockAtAuth;
      onboardingService.atClient = await AtClientImpl.create(
          atSign, 'unit_test', getAtClientPreferenceAlice());
      when(() => mockAtLookup.pkamAuthenticate())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtAuth.authenticate(any()))
          .thenAnswer((_) => Future.value(AtAuthResponse(atSign)
            ..isSuccessful = true
            ..atAuthKeys = (AtKeys()
              ..apkamPublicKey = AtBytes.fromString('dumm')
              ..apkamPrivateKey = AtBytes.fromString('dumm')
              ..defaultSelfEncryptionKey = AtBytes.fromString('dumm')
              ..defaultEncryptionPrivateKey = AtBytes.fromString('dumm')
              ..defaultEncryptionPublicKey = AtBytes.fromString('dumm')
              ..apkamSymmetricKey = AtBytes.fromString('dumm')
              ..enrollmentId = 'dummy_enroll_id')));
      when(() => mockAtAuth.atChops)
          .thenAnswer((_) => AtChopsImpl(AtChopsKeys()));
      var authResult = await onboardingService.authenticate();
      expect(authResult, true);
    });

    test('authenticate hands the key source across to the client', () async {
      final atSign = '@alice🛠';
      AtOnboardingPreference onboardingPreference = AtOnboardingPreference()
        ..atKeysFilePath = 'test/data/@alice🛠_key.atKeys'
        ..namespace = 'unit_test';
      AtOnboardingService onboardingService =
          AtOnboardingServiceImpl(atSign, onboardingPreference);
      onboardingService.atLookUp = mockAtLookup;
      mockAtAuth.atChops = AtChopsImpl(AtChopsKeys());
      onboardingService.atAuth = mockAtAuth;
      when(() => mockAtLookup.pkamAuthenticate())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtAuth.authenticate(any()))
          .thenAnswer((_) => Future.value(AtAuthResponse(atSign)
            ..isSuccessful = true
            ..atAuthKeys = (AtKeys()
              ..apkamPublicKey = AtBytes.fromString('dumm')
              ..apkamPrivateKey = AtBytes.fromString('dumm')
              ..defaultSelfEncryptionKey = AtBytes.fromString('dumm')
              ..defaultEncryptionPrivateKey = AtBytes.fromString('dumm')
              ..defaultEncryptionPublicKey = AtBytes.fromString('dumm')
              ..apkamSymmetricKey = AtBytes.fromString('dumm')
              ..enrollmentId = 'source-handoff-enroll-id')));
      when(() => mockAtAuth.atChops)
          .thenAnswer((_) => AtChopsImpl(AtChopsKeys()));

      await onboardingService.authenticate();

      // The FileAtKeysIo authenticate() builds for AtAuth must reach the
      // client too. Without it the client has no key-material source at all —
      // it cannot resolve its PKAM algorithm from the keyfile, file conveyed
      // privates, or source per-algorithm signing keys — and every
      // at_cli_commons consumer inherits that.
      expect(AtClientManager.getInstance().atClient.atKeysIo, isNotNull);
    });
    // TODO: add more tests
    tearDown(() async => await tearDownFunc());
  });

  group('validate enrollment related operations', () {
    String atsign = '@alice_test';
    late AtPersistenceBundle persistenceBundle;

    setUp(() async {
      persistenceBundle = await setupLocalStorage(atsign);
      reset(mockAtLookup);
      reset(mockAtAuth);
      when(() => mockAtAuth.progressStream).thenAnswer((_) => Stream.empty());
      registerFallbackValue(FakeAtAuthRequest());
      registerFallbackValue(EnrollVerbBuilder());
      registerFallbackValue(mockAtLookup);
      registerFallbackValue(AtEnrollmentRequest(
          atSign: atsign,
          appName: 'appName',
          deviceName: 'deviceName',
          otp: 'otp',
          namespaces: {},
          // A mocktail fallback value: never submitted, only matched against.
          // rsa2048 because it is what this path minted before the parameter
          // existed, so nothing about what these tests exercise changes.
          signingAlgo: SigningAlgoType.rsa2048));
    });

    test('validate enrollment details being stored to LocalSecondary',
        () async {
      // setup dummy enrollment data
      String dummyEnrollmentId = '62212385-3b9f-4c98-8768-146f460c5ade';
      String appName = 'test_app';
      String deviceName = 'test_device';
      String otp = 'XXXXXX';
      Map<String, String> namespaces = {'test_namespace': 'rw'};

      // setup dependencies for mocking
      MockAtClient mockAtClient = MockAtClient();
      MockEnrollmentBase mockEnrollmentBase = MockEnrollmentBase();
      LocalSecondary localSecondary = LocalSecondary(mockAtClient,
          keyStore: persistenceBundle.keyValueStore);

      // mocking OnboardingServiceImpl
      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath =
            '${Directory.current.path}/test/storage/keys/${atsign}_key.atKeys';
      AtOnboardingServiceImpl onboardingService =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);
      onboardingService.atClient = mockAtClient;
      onboardingService.enrollmentBase = mockEnrollmentBase;
      onboardingService.atLookUp = mockAtLookup;
      onboardingService.atAuth = mockAtAuth;

      // setup AtChopsKeys and AtKeys
      AtEnrollmentResponse enrollmentResponse =
          AtEnrollmentResponse(dummyEnrollmentId, EnrollmentStatus.pending);
      AtChopsKeys atChopsKeys = getRandomAtChopsKeys();
      AtKeys dummyAuthKeys = getAtAuthKeysFromAtChopsKeys(atChopsKeys);
      enrollmentResponse.atAuthKeys = dummyAuthKeys;

      // setup mock behaviour
      when(() => mockEnrollmentBase.submit(any(), any()))
          .thenAnswer((_) => Future.value(enrollmentResponse));
      // The handshake would decrypt the keys the wire stubs below serve;
      // this response's atAuthKeys already hold them, so a no-op stands in.
      stubHandshake(mockEnrollmentBase);
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: dummyEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookup.atChops).thenReturn(AtChopsImpl(atChopsKeys));
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(atsign);
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);

      registerFallbackValue(AtKey.fromString('local:test.test$atsign'));
      when(() => mockAtClient.put(any(), any())).thenAnswer((i) async {
        AtKey atKey = i.positionalArguments[0];
        dynamic value = i.positionalArguments[1];
        return await localSecondary.putValue(atKey.toString(), value);
      });
      // mock EncryptionPrivateKey and SelfEncryption retrieval from server
      // server encrypts these keys with APKAMSymmetricKey
      String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
          dummyAuthKeys.defaultEncryptionPrivateKey!.toString(),
          dummyAuthKeys.apkamSymmetricKey!.toString());
      String encryptedSelfEncryptionKey = EncryptionUtil.encryptValue(
          dummyAuthKeys.defaultSelfEncryptionKey!.toString(),
          dummyAuthKeys.apkamSymmetricKey!.toString());
      String fetchEncryptionPrivateKeyCommand =
          'keys:get:keyName:$dummyEnrollmentId.${AtConstants.defaultEncryptionPrivateKey}.__manage$atsign\n';
      String fetchSelfEncryptionKeyCommand =
          'keys:get:keyName:$dummyEnrollmentId.${AtConstants.defaultSelfEncryptionKey}.__manage$atsign\n';
      String fetchEncryptionPrivateKeyResponse =
          'data:${jsonEncode({'value': encryptedEncryptionPrivateKey})}';
      String fetchSelfEncryptionKeyResponse =
          'data:${jsonEncode({'value': encryptedSelfEncryptionKey})}';
      when(() => mockAtLookup.executeCommand(fetchEncryptionPrivateKeyCommand,
              auth: true))
          .thenAnswer((_) => Future.value(fetchEncryptionPrivateKeyResponse));
      when(() => mockAtLookup.executeCommand(fetchSelfEncryptionKeyCommand,
              auth: true))
          .thenAnswer((_) => Future.value(fetchSelfEncryptionKeyResponse));

      // perform enrollment
      await onboardingService.enroll(appName, deviceName, otp, namespaces);

      // verify stored data in LocalSecondary
      final response =
          await localSecondary.keyStore!.get('local:$dummyEnrollmentId$atsign');
      Map<String, dynamic> jsonDecodedResponse = jsonDecode(response!.data!);
      expect(jsonDecodedResponse['namespace'], namespaces);
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group('A group of tests related to generation of AtKeys', () {
    test(
        'A test to verify createAtKeys generates atKeys in the location specified in onboarding preference atKeysFilePath',
        () async {
      String atsign = '@alice_test';
      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign';
      AtOnboardingServiceImpl onboardingService =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);

      AtEnrollmentResponse atEnrollmentResponse =
          AtEnrollmentResponse('123', EnrollmentStatus.approved);

      AtEncryptionKeyPair encryptionRsaKeyPair =
          onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      await expectSecureFilePermissions(file);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
    });

    test(
        'A test to verify createAtKeys when keys location as . in the filename',
        () async {
      String atsign = '@alice_test';
      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign.me';
      AtOnboardingServiceImpl onboardingService =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);

      AtEnrollmentResponse atEnrollmentResponse =
          AtEnrollmentResponse('123', EnrollmentStatus.approved);

      AtEncryptionKeyPair encryptionRsaKeyPair =
          onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign.me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      await expectSecureFilePermissions(file);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
    });

    test(
        'A test to verify createAtKeys when keys location as - in the filename',
        () async {
      String atsign = '@alice_test';
      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign-me';
      AtOnboardingServiceImpl onboardingService =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);

      AtEnrollmentResponse atEnrollmentResponse =
          AtEnrollmentResponse('123', EnrollmentStatus.approved);

      AtEncryptionKeyPair encryptionRsaKeyPair =
          onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign-me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      await expectSecureFilePermissions(file);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
    });

    test(
        'A test to verify createAtKeys does not append .atKeys when filename has .atKeys extension',
        () async {
      String atsign = '@alice_test';
      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign-me.atKeys';
      AtOnboardingServiceImpl onboardingService =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);

      AtEnrollmentResponse atEnrollmentResponse =
          AtEnrollmentResponse('123', EnrollmentStatus.approved);

      AtEncryptionKeyPair encryptionRsaKeyPair =
          onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPrivateKey.privateKey)
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.atPublicKey.publicKey)
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign-me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      await expectSecureFilePermissions(file);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
    });
  });

  group('Tests to assert enroll resume behaviour', () {
    MockEnrollmentBase mockEnrollmentBase = MockEnrollmentBase();

    setUp(() {
      reset(mockAtLookup);
      reset(mockAtAuth);
      when(() => mockAtAuth.progressStream).thenAnswer((_) => Stream.empty());
      reset(mockEnrollmentBase);
      registerFallbackValue(FakeAtAuthRequest());
      registerFallbackValue(FakeEnrollmentRequest());
      registerFallbackValue(
          AtEnrollmentResponse('123', EnrollmentStatus.pending));
      registerFallbackValue(MockAtLookupImpl());
      registerFallbackValue(AtKey.fromString('public:test_key.test@alice'));
    });

    test('when available enroll should use the checkpoint', () async {
      // also validates the checkpoint file is deleted after approval
      final atsign = '@syrax';
      final dummyEnrollmentId = '1234';

      final bundle = await setupLocalStorage(atsign);

      MockAtClient mockAtClient = MockAtClient();
      LocalSecondary localSecondary =
          LocalSecondary(mockAtClient, keyStore: bundle.keyValueStore);

      AtOnboardingPreference pref = getOnboardingPreference()
        ..atKeysFilePath = 'test/storage/keys/${atsign}_key.atKeys';
      AtOnboardingServiceImpl svc = AtOnboardingServiceImpl(atsign, pref);
      svc.atClient = mockAtClient;
      svc.enrollmentBase = mockEnrollmentBase;
      svc.atLookUp = mockAtLookup;
      svc.atAuth = mockAtAuth;

      // setup AtChopsKeys and AtKeys
      final atChopsKeys = getRandomAtChopsKeys();
      AtKeys atAuthKeys = getAtAuthKeysFromAtChopsKeys(atChopsKeys);
      AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
          dummyEnrollmentId, EnrollmentStatus.pending,
          atAuthKeys: atAuthKeys);

      // encrypt the keys with APKAMSymmetricKey
      String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
          atAuthKeys.defaultEncryptionPrivateKey!.toString(),
          atAuthKeys.apkamSymmetricKey!.toString());
      String encryptedSelfEncryptionKey = EncryptionUtil.encryptValue(
          atAuthKeys.defaultSelfEncryptionKey!.toString(),
          atAuthKeys.apkamSymmetricKey!.toString());
      String fetchEncryptionPrivateKeyCommand =
          'keys:get:keyName:$dummyEnrollmentId.${AtConstants.defaultEncryptionPrivateKey}.__manage$atsign\n';
      String fetchSelfEncryptionKeyCommand =
          'keys:get:keyName:$dummyEnrollmentId.${AtConstants.defaultSelfEncryptionKey}.__manage$atsign\n';

      // setup mock behaviour
      when(() => mockEnrollmentBase.submit(any(), any()))
          .thenAnswer((_) => Future.value(enrollmentResponse));
      // The checkpoint's atAuthKeys already hold the decrypted keys the
      // handshake would produce, so a no-op stands in for it.
      stubHandshake(mockEnrollmentBase);
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: dummyEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookup.atChops).thenReturn(AtChopsImpl(atChopsKeys));
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(atsign);
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockAtClient.put(any(), any())).thenAnswer((i) async {
        AtKey atKey = i.positionalArguments[0];
        dynamic value = i.positionalArguments[1];
        return await localSecondary.putValue(atKey.toString(), value);
      });
      when(() => mockAtLookup.executeCommand(fetchEncryptionPrivateKeyCommand,
              auth: true))
          .thenAnswer((_) => Future.value(
              'data:${jsonEncode({'value': encryptedEncryptionPrivateKey})}'));
      when(() => mockAtLookup.executeCommand(fetchSelfEncryptionKeyCommand,
              auth: true))
          .thenAnswer((_) => Future.value(
              'data:${jsonEncode({'value': encryptedSelfEncryptionKey})}'));

      final appName = 'enroll_test_1';
      final device = 'unit_test_1';
      final namespaces = {'test': 'rw'};

      // manually create a checkpoint
      await svc.enrollCheckpoint
          .save(enrollmentResponse, appName, device, namespaces);

      final checkpointFile =
          svc.enrollCheckpoint.getFile(appName, device, namespaces);
      expect(checkpointFile.existsSync(), isTrue);

      // the mocks will mimic enrollment approval and fetching keys from server
      // using the keys:get commands
      await svc.enroll(appName, device, 'ABCDE', namespaces);

      // ensure that after enroll() returns, the checkpoint is removed
      expect(checkpointFile.existsSync(), isFalse);
      expect(File(pref.atKeysFilePath!).existsSync(), isTrue);
      // assert that a new enrollment was not submitted
      verifyNever(() => mockEnrollmentBase.submit(any(), any()));
    });

    test('assert checkpoint deletion when enrollment is denied', () async {
      final atsign = '@caraxes';
      final dummyEnrollmentId = '1234abcdxyz';

      await setupLocalStorage(atsign);

      AtOnboardingPreference atOnboardingPreference = getOnboardingPreference()
        ..atKeysFilePath = 'test/storage/keys/${atsign}_key.atKeys';
      AtOnboardingServiceImpl svc =
          AtOnboardingServiceImpl(atsign, atOnboardingPreference);
      svc.atLookUp = mockAtLookup;

      // setup AtChopsKeys and AtKeys
      final atChopsKeys = getRandomAtChopsKeys();
      AtKeys atAuthKeys = getAtAuthKeysFromAtChopsKeys(atChopsKeys);
      AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
          dummyEnrollmentId, EnrollmentStatus.pending,
          atAuthKeys: atAuthKeys);

      // setup mock behaviour
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: dummyEnrollmentId))
          .thenThrow(UnAuthenticatedException(
              'error:AT0025')); // mimic enrollment denial

      // pre-seed checkpoint — params must match the enroll() call below
      await svc.enrollCheckpoint.save(
          enrollmentResponse, 'enroll_test_1', 'unit_test_1', {'test': 'rw'});

      final checkpointFile = svc.enrollCheckpoint
          .getFile('enroll_test_1', 'unit_test_1', {'test': 'rw'});
      expect(checkpointFile.existsSync(), isTrue);

      await expectLater(
          () => svc
              .enroll('enroll_test_1', 'unit_test_1', 'ABCDE', {'test': 'rw'}),
          throwsA(isA<AtEnrollmentException>()));
      expect(checkpointFile.existsSync(), isFalse);
    });

    test('enroll() creates a checkpoint', () async {
      final atsign = '@perrytheplatypus';
      final dummyEnrollmentId = 'xyz123abc';

      final atChopsKeys = getRandomAtChopsKeys();
      AtKeys atAuthKeys = getAtAuthKeysFromAtChopsKeys(atChopsKeys);
      AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
          dummyEnrollmentId, EnrollmentStatus.pending,
          atAuthKeys: atAuthKeys);

      AtOnboardingPreference pref = getOnboardingPreference();
      AtOnboardingServiceImpl svc = AtOnboardingServiceImpl(atsign, pref);
      svc.enrollmentBase = mockEnrollmentBase;
      svc.atLookUp = mockAtLookup;

      expect(
          svc.enrollCheckpoint
              .getFile('myApp', 'myDevice', {'test': 'rw'}).existsSync(),
          isFalse);

      bool checkpointExistedDuringApproval = false;

      when(() => mockEnrollmentBase.submit(any(), any()))
          .thenAnswer((_) => Future.value(enrollmentResponse));
      // check whether the checkpoint file exists during awaitApproval() execution
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: dummyEnrollmentId))
          .thenAnswer((_) {
        checkpointExistedDuringApproval = svc.enrollCheckpoint
            .getFile('myApp', 'myDevice', {'test': 'rw'}).existsSync();
        throw UnAuthenticatedException('error:AT0025');
      });
      // The stubbed handshake still authenticates on the lookup, so the
      // probe above observes the checkpoint mid-approval; the denial keeps
      // the real handshake's contract of throwing AtEnrollmentException.
      stubHandshake(mockEnrollmentBase, body: () async {
        try {
          await mockAtLookup.pkamAuthenticate(enrollmentId: dummyEnrollmentId);
        } on UnAuthenticatedException {
          throw AtEnrollmentException(
              'The enrollment: $dummyEnrollmentId is denied');
        }
      });

      await expectLater(
        () => svc.enroll('myApp', 'myDevice', 'OTP123', {'test': 'rw'}),
        throwsA(isA<AtEnrollmentException>()),
      );

      expect(checkpointExistedDuringApproval, isTrue);
      // finally ensure its removed after enroll() returns
      expect(
          svc.enrollCheckpoint
              .getFile('myApp', 'myDevice', {'test': 'rw'}).existsSync(),
          isFalse);
    });

    tearDown(() async => await tearDownFunc());
  });
  group('Validate enroll checkpoint methods', () {
    const appName = 'testApp';
    const deviceName = 'testDevice';
    final namespaces = {'ns': 'rw'};

    test('checkpoint.getFile() - filename does not contain atSign', () {
      final cp = EnrollmentCheckpoint('@lima');
      final file = cp.getFile(appName, deviceName, namespaces);
      expect(file.path, endsWith('.enrollment.checkpoint'));
      expect(file.path, isNot(contains('@lima')));
    });

    test(
        'checkpoint.getFile() - same params different atSigns produce different files',
        () {
      final checkpoint1 = EnrollmentCheckpoint('@dreamfyre')
          .getFile(appName, deviceName, namespaces);
      final checkpoint2 = EnrollmentCheckpoint('@sunfyre')
          .getFile(appName, deviceName, namespaces);
      expect(checkpoint1.path, isNot(equals(checkpoint2.path)));
    });

    test('checkpoint.save() - creates a checkpoint', () async {
      final cp = EnrollmentCheckpoint('@syrax');
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      await cp.save(
          AtEnrollmentResponse('1234', EnrollmentStatus.pending,
              atAuthKeys: atAuthKeys),
          appName,
          deviceName,
          namespaces);

      final file = cp.getFile(appName, deviceName, namespaces);
      expect(file.existsSync(), isTrue);
      if (!Platform.isWindows) {
        final stat = await FileStat.stat(file.path);
        expect(stat.mode & 0x1FF, equals(0x180),
            reason: 'checkpoint file must have chmod 600');
      }
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(data['enrollmentId'], '1234');
      expect(data['enrollStatus'], EnrollmentStatus.pending.name);
      expect(data['atAuthKeys'], atAuthKeys.toJson());
      expect(data['validTill'],
          greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('checkpoint.save() - overwrites an existing checkpoint', () async {
      final ckp = EnrollmentCheckpoint('@silverwing');
      final firstKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final secondKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      await ckp.save(
          AtEnrollmentResponse('first-id', EnrollmentStatus.pending,
              atAuthKeys: firstKeys),
          appName,
          deviceName,
          namespaces);
      await ckp.save(
          AtEnrollmentResponse('second-id', EnrollmentStatus.pending,
              atAuthKeys: secondKeys),
          appName,
          deviceName,
          namespaces);

      expect(
          ckp.load(appName, deviceName, namespaces)!.enrollmentId, 'second-id');

      ckp.delete(appName, deviceName, namespaces);
    });

    test('checkpoint.load() - loads the checkpoint file', () async {
      final cp = EnrollmentCheckpoint('@caraxes');
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final er = AtEnrollmentResponse('abc321', EnrollmentStatus.pending,
          atAuthKeys: atAuthKeys);

      await cp.save(er, appName, deviceName, namespaces);

      final loaded = cp.load(appName, deviceName, namespaces);
      expect(loaded, isNotNull);
      expect(loaded!.enrollmentId, er.enrollmentId);
      expect(loaded.enrollStatus, er.enrollStatus);
      expect(loaded.atAuthKeys!.apkamPublicKey.toString(),
          atAuthKeys.apkamPublicKey.toString());
      expect(loaded.atAuthKeys!.apkamPrivateKey.toString(),
          atAuthKeys.apkamPrivateKey.toString());
      expect(loaded.atAuthKeys!.defaultEncryptionPublicKey.toString(),
          atAuthKeys.defaultEncryptionPublicKey.toString());
      expect(loaded.atAuthKeys!.defaultSelfEncryptionKey.toString(),
          atAuthKeys.defaultSelfEncryptionKey.toString());
      expect(loaded.atAuthKeys!.apkamSymmetricKey.toString(),
          atAuthKeys.apkamSymmetricKey.toString());
    });

    test('checkpoint.load() - returns null when file is missing', () {
      expect(
          EnrollmentCheckpoint('@rhaegar')
              .load(appName, deviceName, namespaces),
          isNull);
    });

    test('checkpoint.load() - returns null for corrupt JSON', () async {
      final cp = EnrollmentCheckpoint('@vermithor');
      File checkpoint = cp.getFile(appName, deviceName, namespaces);
      checkpoint.writeAsStringSync('not valid json {{{');
      expect(cp.load(appName, deviceName, namespaces), isNull);
      expect(checkpoint.existsSync(), false);
    });

    test('checkpoint.load() - returns null for different params', () async {
      final cp = EnrollmentCheckpoint('@sheepstealer');
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      await cp.save(
          AtEnrollmentResponse('mismatch-test', EnrollmentStatus.pending,
              atAuthKeys: atAuthKeys),
          'app1',
          'device1',
          {'ns': 'rw'});

      expect(cp.load('app2', 'device2', {'ns': 'rw'}), isNull);

      // in-case of mismatch, the checkpoint is not automatically removed
      cp.delete('app1', 'device1', {'ns': 'rw'});
    });

    test('checkpoint.load() - returns null and deletes file when expired',
        () async {
      final cp = EnrollmentCheckpoint('@moondancer');
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      await cp.save(
          AtEnrollmentResponse('expired-test', EnrollmentStatus.pending,
              atAuthKeys: atAuthKeys),
          appName,
          deviceName,
          namespaces,
          expiry: Duration.zero);

      final file = cp.getFile(appName, deviceName, namespaces);
      expect(file.existsSync(), isTrue);
      expect(cp.load(appName, deviceName, namespaces), isNull);
      // checkpoint is deleted as it's expired
      expect(file.existsSync(), isFalse);
    });

    test('checkpoint.delete() - deletes existing checkpoint file', () async {
      final cp = EnrollmentCheckpoint('@meraxes');
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      await cp.save(
          AtEnrollmentResponse('del-test', EnrollmentStatus.pending,
              atAuthKeys: atAuthKeys),
          appName,
          deviceName,
          namespaces);
      expect(cp.getFile(appName, deviceName, namespaces).existsSync(), isTrue);

      cp.delete(appName, deviceName, namespaces);
      expect(cp.getFile(appName, deviceName, namespaces).existsSync(), isFalse);
    });

    test('checkpoint.delete() - is a no-op when file does not exist', () {
      expect(
          () => EnrollmentCheckpoint('@quicksilver')
              .delete(appName, deviceName, namespaces),
          returnsNormally);
    });

    test(
        'checkpoint files are created per atSign — same params generate different files',
        () async {
      final cp1 = EnrollmentCheckpoint('@dreamfyre');
      final cp2 = EnrollmentCheckpoint('@sunfyre');
      final keys1 = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final keys2 = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      await cp1.save(
          AtEnrollmentResponse('id-for-dreamfyre', EnrollmentStatus.pending,
              atAuthKeys: keys1),
          appName,
          deviceName,
          namespaces);
      await cp2.save(
          AtEnrollmentResponse('id-for-sunfyre', EnrollmentStatus.pending,
              atAuthKeys: keys2),
          appName,
          deviceName,
          namespaces);

      expect(cp1.load(appName, deviceName, namespaces)!.enrollmentId,
          'id-for-dreamfyre');
      expect(cp2.load(appName, deviceName, namespaces)!.enrollmentId,
          'id-for-sunfyre');

      cp1.delete(appName, deviceName, namespaces);
      cp2.delete(appName, deviceName, namespaces);
    });

    tearDown(() {
      // clean up any leftover checkpoint files from this group
      Directory(Directory.current.path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.enrollment.checkpoint'))
          .forEach((f) => f.deleteSync());
    });
  });
}

/// at_persistence 5.0.0 factories opened by [setupLocalStorage]; closed in
/// [tearDownFunc] so Hive boxes are released before the storage dir is deleted.
final List<HiveAtPersistenceFactory> _testPersistenceFactories = [];

Future<void> tearDownFunc() async {
  for (final factory in _testPersistenceFactories) {
    await factory.close();
  }
  _testPersistenceFactories.clear();
  var isExists = await Directory('test/storage').exists();
  if (isExists) {
    Directory('test/storage').deleteSync(recursive: true);
  }
}

AtClientPreference getAtClientPreferenceAlice() {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/storage/hive/client';
  preference.commitLogPath = 'test/storage/hive/client/commit';
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

AtOnboardingPreference getOnboardingPreference() {
  return AtOnboardingPreference()
    ..hiveStoragePath = 'test/storage/hive/client'
    ..commitLogPath = 'test/storage/hive/client/commit'
    ..atKeysFilePath = 'test/storage';
}

// creates an instance of AtAuthKeys by using the keys in AtChopsKeys
AtKeys getAtAuthKeysFromAtChopsKeys(AtChopsKeys atChopsKeys) {
  AtKeys atAuthKeys = AtKeys();

  if (atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.apkamPublicKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.apkamPrivateKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.defaultEncryptionPublicKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.defaultEncryptionPrivateKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.selfEncryptionKey?.key != null) {
    atAuthKeys.defaultSelfEncryptionKey =
        AtBytes.fromString(atChopsKeys.selfEncryptionKey!.key);
  }
  atAuthKeys.apkamSymmetricKey =
      AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key);

  return atAuthKeys;
}

AtChopsKeys getRandomAtChopsKeys() {
  AtEncryptionKeyPair encryptionKeyPair =
      AtChopsUtil.generateAtEncryptionKeyPair();
  AtPkamKeyPair pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
  AtChopsKeys atChopsKeys = AtChopsKeys.create(encryptionKeyPair, pkamKeyPair);
  atChopsKeys.selfEncryptionKey =
      AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
  atChopsKeys.apkamSymmetricKey =
      AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

  return atChopsKeys;
}

/// Bootstraps a client keystore for [atSign] via the at_persistence 5.0.0
/// factory/bundle API and returns the bundle (use [AtPersistenceBundle.keyValueStore]
/// as the LocalSecondary keystore). The factory is tracked for teardown.
Future<AtPersistenceBundle> setupLocalStorage(String atSign) async {
  const storageDir = 'test/storage/hive';
  final factory = HiveAtPersistenceFactory();
  final bundle = await factory.initialize(
      atSign, HivePersistenceConfig.clientDefaults(storagePath: storageDir));
  _testPersistenceFactories.add(factory);
  return bundle;
}

/// Asserts that [file] has secure (owner-only) permissions.
///
/// On POSIX: expects chmod 600 (mode bits 0x180).
/// On Windows: expects only the current user has Full control via icacls.
Future<void> expectSecureFilePermissions(File file) async {
  if (Platform.isWindows) {
    final username =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'];
    final result = await Process.run('icacls', [file.path]);
    final output = result.stdout as String;
    final permEntries = output
        .split('\n')
        .where((l) => l.contains(':(') && !l.startsWith('Successfully'))
        .toList();
    expect(permEntries.length, equals(1),
        reason: 'only the current user should have access');
    expect(permEntries.first, contains('$username:(F)'),
        reason: 'current user must have Full control');
  } else {
    final stat = await FileStat.stat(file.path);
    expect(stat.mode & 0x1FF, equals(0x180),
        reason: 'file must have chmod 600 (owner read/write only)');
  }
}
