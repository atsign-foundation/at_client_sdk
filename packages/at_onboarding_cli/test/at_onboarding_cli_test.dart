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

class MockEnrollmentBase extends Mock implements AtEnrollmentBase {}

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

    test('A test to check atOnboardingService.authenticate() returns true', () async {
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
              ..apkamPublicKey = AtBytes.fromString('dummy_apkam_public_key')
              ..apkamPrivateKey = AtBytes.fromString('dummy_private_key')
              ..defaultSelfEncryptionKey = AtBytes.fromString('dummy_self_encryption_key')
              ..defaultEncryptionPrivateKey = AtBytes.fromString('dummy_enc_priv_key')
              ..defaultEncryptionPublicKey = AtBytes.fromString('dummy_enc_pub_key')
              ..apkamSymmetricKey = AtBytes.fromString('dummy_apkam_sym_key')
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
      registerFallbackValue(EnrollmentRequest(
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
        ..defaultSelfEncryptionKey = AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey = AtBytes.fromString(onboardingService.generateAESKey());

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
        ..defaultSelfEncryptionKey = AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey = AtBytes.fromString(onboardingService.generateAESKey());

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
        ..defaultSelfEncryptionKey = AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey = AtBytes.fromString(onboardingService.generateAESKey());

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
        ..defaultSelfEncryptionKey = AtBytes.fromString(onboardingService.generateAESKey())
        ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPrivateKey = AtBytes.fromString(encryptionRsaKeyPair.privateKey.toString())
        ..apkamPublicKey = AtBytes.fromString(encryptionRsaKeyPair.publicKey.toString())
        ..apkamSymmetricKey = AtBytes.fromString(onboardingService.generateAESKey());

      var f = await onboardingService.createAtKeysFile(atEnrollmentResponse);
      expect(f.path.endsWith('$atsign-me.atKeys'), true);

      File file = File(f.path);
      expect(file.existsSync(), true);
      // Delete the file at the end of the test.
      file.deleteSync(recursive: true);
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
  preference.isLocalStoreRequired = true;
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

AtOnboardingPreference getOnboardingPreference() {
  return AtOnboardingPreference()
    ..hiveStoragePath = 'test/storage/hive/client'
    ..commitLogPath = 'test/storage/hive/client/commit'
    ..atKeysFilePath = 'test/storage'
    ..isLocalStoreRequired = true;
}

// creates an instance of AtAuthKeys by using the keys in AtChopsKeys
AtKeys getAtAuthKeysFromAtChopsKeys(AtChopsKeys atChopsKeys) {
  AtKeys atAuthKeys = AtKeys();

  if (atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.apkamPublicKey = AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.apkamPrivateKey = AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.defaultEncryptionPublicKey = AtBytes.fromString(atChopsKeys.atEncryptionKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.defaultEncryptionPrivateKey = AtBytes.fromString(atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.selfEncryptionKey?.key != null) {
    atAuthKeys.defaultSelfEncryptionKey = AtBytes.fromString(atChopsKeys.selfEncryptionKey!.key);
  }
  atAuthKeys.apkamSymmetricKey = AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key);

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
