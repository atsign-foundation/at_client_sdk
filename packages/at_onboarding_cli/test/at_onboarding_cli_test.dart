import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
// ignore: depend_on_referenced_packages
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class MockAtAuthImpl extends Mock implements AtAuth {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

class MockAtClient extends Mock implements AtClient {}

class MockEnrollmentBase extends Mock implements AtEnrollment {}

void main() {
  AtSignLogger.root_level = 'INFO';
  AtLookupImpl mockAtLookup = MockAtLookupImpl();
  AtAuth mockAtAuth = MockAtAuthImpl();

  setUp(() {
    reset(mockAtLookup);
    reset(mockAtAuth);
    registerFallbackValue(FakeAtAuthRequest());
  });

  group('A group of tests to verify at_chops creation in onboarding_cli', () {
    setUp(() {
      reset(mockAtLookup);
      reset(mockAtAuth);
      registerFallbackValue(FakeAtAuthRequest());
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
    // TODO: add more tests
    tearDown(() async => await tearDownFunc());
  });

  group('validate enrollment related operations', () {
    String atsign = '@alice_test';

    setUp(() async {
      await setupLocalStorage(atsign);
      reset(mockAtLookup);
      reset(mockAtAuth);
      registerFallbackValue(FakeAtAuthRequest());
      registerFallbackValue(EnrollVerbBuilder());
      registerFallbackValue(mockAtLookup);
      registerFallbackValue(AtEnrollmentRequest(
          atSign: atsign,
          appName: 'appName',
          deviceName: 'deviceName',
          otp: 'otp',
          namespaces: {}));
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
      var keyStore = SecondaryPersistenceStoreFactory.getInstance()
          .getSecondaryPersistenceStore(atsign)
          ?.getSecondaryKeyStore();
      LocalSecondary localSecondary =
          LocalSecondary(mockAtClient, keyStore: keyStore);

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
      AtData response =
          await localSecondary.keyStore?.get('local:$dummyEnrollmentId$atsign');
      Map<String, dynamic> jsonDecodedResponse = jsonDecode(response.data!);
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

      RSAKeypair encryptionRsaKeyPair = onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
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

      RSAKeypair encryptionRsaKeyPair = onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign.me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
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

      RSAKeypair encryptionRsaKeyPair = onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign-me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
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

      RSAKeypair encryptionRsaKeyPair = onboardingService.generateRsaKeypair();
      atEnrollmentResponse.atAuthKeys = AtKeys()
        ..enrollmentId = '123'
        ..defaultSelfEncryptionKey =
            AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey =
            AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey =
            AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey =
            AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign-me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
    });
  });

  group('Collision handling tests', () {
    late Directory tempDir;
    late AtOnboardingPreference onboardingPreference;
    late AtOnboardingServiceImpl onboardingService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('collision_test_');
      onboardingPreference = AtOnboardingPreference()
        ..hiveStoragePath = '${tempDir.path}/hive'
        ..commitLogPath = '${tempDir.path}/commit'
        ..atKeysFilePath = '${tempDir.path}/@test.atKeys'
        ..namespace = 'wavi'
        ..rootDomain = 'vip.ve.atsign.zone';

      onboardingService = AtOnboardingServiceImpl(
        '@test',
        onboardingPreference,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'createAtKeysFile() with default collision handler aborts on existing file',
        () async {
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final enrollmentResponse =
          AtEnrollmentResponse('test-enroll-123', EnrollmentStatus.approved)
            ..atAuthKeys = atAuthKeys;

      // First write should succeed
      final file1 =
          await onboardingService.createAtKeysFile(enrollmentResponse);
      expect(file1.existsSync(), isTrue);

      // Second write should fail with default abort handler
      await expectLater(
        onboardingService.createAtKeysFile(enrollmentResponse),
        throwsA(isA<AtKeysFileExistsException>()),
      );
    });

    test(
        'createAtKeysFile() with custom collision handler uses alternative path',
        () async {
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final enrollmentResponse =
          AtEnrollmentResponse('test-enroll-456', EnrollmentStatus.approved)
            ..atAuthKeys = atAuthKeys;

      // First write
      await onboardingService.createAtKeysFile(enrollmentResponse);

      // Second write with custom handler
      final altPath = '${tempDir.path}/@test-backup.atKeys';
      final file2 = await onboardingService.createAtKeysFile(
        enrollmentResponse,
        onKeysFileCollision: (context) {
          return AtKeysFileCollisionUseAlternative(altPath);
        },
      );

      expect(file2.path, equals(altPath));
      expect(file2.existsSync(), isTrue);

      // Both files should exist
      expect(File('${tempDir.path}/@test.atKeys').existsSync(), isTrue);
      expect(File(altPath).existsSync(), isTrue);
    });

    test('createAtKeysFile() handles collision with multiple retry attempts',
        () async {
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final enrollmentResponse =
          AtEnrollmentResponse('retry-test', EnrollmentStatus.approved)
            ..atAuthKeys = atAuthKeys;

      // First write
      await onboardingService.createAtKeysFile(enrollmentResponse);

      // Create 2 files that will collide, 1 that won't
      final firstFile = File('${tempDir.path}/@test-alt1.atKeys');
      final secondFile = File('${tempDir.path}/@test-alt2.atKeys');
      final thirdFile = File('${tempDir.path}/@test-alt3.atKeys');
      // writing to the files will ensure the file exists
      await firstFile.writeAsString('dummy');
      await secondFile.writeAsString('dummy');

      int attempts = 0;
      final finalFile = await onboardingService.createAtKeysFile(
        enrollmentResponse,
        onKeysFileCollision: (context) {
          attempts++;
          if (attempts == 1) {
            return AtKeysFileCollisionUseAlternative(firstFile.path);
          } else if (attempts == 2) {
            return AtKeysFileCollisionUseAlternative(secondFile.path);
          } else {
            return AtKeysFileCollisionUseAlternative(thirdFile.path);
          }
        },
      );

      expect(attempts, equals(3));
      expect(finalFile.path, thirdFile.path);
      expect(finalFile.existsSync(), isTrue);
    });

    test('enroll() flow writes keys file with collision handling', () async {
      final mockEnrollmentBase = MockEnrollmentBase();
      final mockAtLookup = MockAtLookupImpl();
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());

      onboardingService.enrollmentBase = mockEnrollmentBase;
      onboardingService.atLookUp = mockAtLookup;

      const enrollmentId = 'enroll-flow-test';
      final enrollmentResponse =
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved)
            ..atAuthKeys = atAuthKeys;

      // Mock the enrollment process
      when(() => mockEnrollmentBase.submit(any(), any()))
          .thenAnswer((_) => Future.value(enrollmentResponse));
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: enrollmentId))
          .thenAnswer((_) => Future.value(true));

      // Create properly encrypted values using the apkamSymmetricKey
      String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
          atAuthKeys.defaultEncryptionPrivateKey!.toString(),
          atAuthKeys.apkamSymmetricKey!.toString());
      String encryptedSelfEncryptionKey = EncryptionUtil.encryptValue(
          atAuthKeys.defaultSelfEncryptionKey!.toString(),
          atAuthKeys.apkamSymmetricKey!.toString());

      String fetchEncryptionPrivateKeyCommand =
          'keys:get:keyName:$enrollmentId.${AtConstants.defaultEncryptionPrivateKey}.__manage@test\n';
      String fetchSelfEncryptionKeyCommand =
          'keys:get:keyName:$enrollmentId.${AtConstants.defaultSelfEncryptionKey}.__manage@test\n';
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

      final atChopsKeys = getRandomAtChopsKeys()
        ..apkamSymmetricKey = AESKey(atAuthKeys.apkamSymmetricKey!.toString());
      final atChops = AtChopsImpl(atChopsKeys);
      when(() => mockAtLookup.atChops).thenReturn(atChops);

      // First enroll - should succeed
      await onboardingService
          .enroll('testApp', 'testDevice', 'otp123', {'wavi': 'rw'});

      expect(File('${tempDir.path}/@test.atKeys').existsSync(), isTrue);

      // Second enroll with collision handler
      final result2 = await onboardingService.enroll(
        'testApp2',
        'testDevice2',
        'otp456',
        {'wavi': 'rw'},
        onKeysFileCollision: (context) {
          return AtKeysFileCollisionUseAlternative(
              '${tempDir.path}/@test-enroll2.atKeys');
        },
      );

      expect(result2.enrollmentId, equals(enrollmentId));
      expect(File('${tempDir.path}/@test-enroll2.atKeys').existsSync(), isTrue);
    });

    test('Collision handler receives correct context information', () async {
      final atAuthKeys = getAtAuthKeysFromAtChopsKeys(getRandomAtChopsKeys());
      final enrollmentResponse =
          AtEnrollmentResponse('context-test', EnrollmentStatus.approved)
            ..atAuthKeys = atAuthKeys;

      // First write
      await onboardingService.createAtKeysFile(enrollmentResponse);

      // Second write, will cause a collision — capture context object
      AtKeysFileCollisionContext? capturedContext;
      try {
        await onboardingService.createAtKeysFile(
          enrollmentResponse,
          onKeysFileCollision: (context) {
            capturedContext = context;
            return AtKeysFileCollisionAbort();
          },
        );
      } catch (e) {
        // do nothing
      }

      expect(capturedContext, isNotNull);
      expect(capturedContext!.targetFilePath, contains('@test.atKeys'));
      expect(capturedContext!.keysContent.isNotEmpty, isTrue);
    });
  });
}

Future<void> tearDownFunc() async {
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
  if (atChopsKeys.apkamSymmetricKey?.key != null) {
    atAuthKeys.apkamSymmetricKey =
        AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key);
  }

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

Future<void> setupLocalStorage(String atSign) async {
  String storageDir = 'test/storage/hive';
  var persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore(atSign)!;
  await persistenceManager.getHivePersistenceManager()!.init(storageDir);
}
