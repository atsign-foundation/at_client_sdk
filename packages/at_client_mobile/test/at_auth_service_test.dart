import 'dart:collection';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_client_mobile/src/auth/at_auth_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

import 'at_client_service_test.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockEnrollmentBiometricStorageFile extends Mock
    implements BiometricStorageFile {
  Map<String, String> dummyStorageFile = HashMap();
}

class MockKeychainBiometricStorageFile extends Mock
    implements BiometricStorageFile {
  Map<String, String> dummyStorageFile = HashMap();
}

class MockAtLookUp extends Mock implements AtLookUp {}

class MockAtEnrollmentBase extends Mock implements AtEnrollmentBase {}

class MockPackageInfo extends Mock implements PackageInfo {
  fromPlatform() {}
}

class MockAtServiceFactor extends Mock implements AtServiceFactory {}

class MockAtClient extends Mock implements AtClient {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockNotificationService extends Mock implements NotificationService {}

class MockSyncService extends Mock implements SyncService {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class FakeStorageFileInitOptions extends Fake
    implements StorageFileInitOptions {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

class FakeAtKey extends Fake implements AtKey {}

void main() {
  group('A group of tests related to submission of enrollment request', () {
    String atSign = '@alice';
    AtClientPreference atClientPreference = AtClientPreference()
      ..namespace = 'me';

    late AtAuthServiceImpl authServiceImpl;
    MockAtEnrollmentBase mockAtEnrollmentBase;
    late MockEnrollmentBiometricStorageFile mockBiometricStorageEnrollmentFile;
    late MockKeychainBiometricStorageFile mockBiometricStorageKeychainFile;
    late MockBiometricStorage mockBiometricStorage;
    late MockAtLookUp mockAtLookUp;

    setUp(() {
      mockBiometricStorageEnrollmentFile = MockEnrollmentBiometricStorageFile();
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageKeychainFile = MockKeychainBiometricStorageFile();
      mockAtLookUp = MockAtLookUp();

      authServiceImpl =
          AtAuthServiceImpl(atSign, atClientPreference, atLookUp: mockAtLookUp);
      authServiceImpl.keyChainManager.biometricStorage = mockBiometricStorage;
    });

    test('A test to verify submission of enrollment', () async {
      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr2nlIgyuezQuGNKAVeYPJMGcvYs13PeXqByuU6PkrCXA2pkDx91KynBv1+MzigMl/vjYiMr12+kE2fuvdlOGG5tOLz+b69s7WSUvwAy4Fa7hRVWxnfjoWD2Db5EdEcaVpKk0yL4KRO/K6grjkrtK92JeqLxkyMfOMwjTD/mO0BZfgCtGgSeJQPcw2IBuOAYpVJVUsIy5lPZKEk1lm7EYx3UfA5Ygw1VH8N9zYUu2OuHDvmQNMaDZxj2L+9HR71j5U1cq2PK6aJqEZc62nxoBLp4remaG66/EFzHNbCKVZ1BGh83PY9aTbw52PTaf7UxiVlNNy4Hqwp3C1Khq96rqJQIDAQAB';
      registerFallbackValue(FakeStorageFileInitOptions());
      registerFallbackValue(FakeLookupVerbBuilder());

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

      when(() => mockBiometricStorageEnrollmentFile.read()).thenAnswer((_) =>
          Future.value(mockBiometricStorageEnrollmentFile
              .dummyStorageFile['${atSign}_enrollmentInfo']));

      when(() => mockBiometricStorageEnrollmentFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo',
            () => invocation.positionalArguments[0]);
      });

      when(() =>
              mockAtLookUp.executeVerb(any(that: LookupVerbBuilderMatcher())))
          .thenAnswer((_) => Future.value('data:$encryptionPublicKey'));

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:request'))))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'enrollmentId': '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                    'status': 'pending'
                  })}'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});

      AtEnrollmentResponse atEnrollmentResponse = await authServiceImpl.enroll(
          EnrollmentRequest(
              appName: 'wavi',
              deviceName: 'my-device',
              otp: 'ABC123',
              namespaces: {'wavi': 'rw'}));

      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.isNotEmpty, true);
      expect(
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.isNotEmpty, true);
      expect(
          atEnrollmentResponse
              .atAuthKeys!.defaultEncryptionPublicKey!.isNotEmpty,
          true);
      expect(
          atEnrollmentResponse.atAuthKeys!.apkamSymmetricKey!.isNotEmpty, true);
      expect(atEnrollmentResponse.atAuthKeys!.enrollmentId!.isNotEmpty, true);
      expect(atEnrollmentResponse.enrollmentId.isNotEmpty, true);
      expect(mockBiometricStorageEnrollmentFile.dummyStorageFile.length, 1);
    });

    test('A test to verify enrollment request is submitted and denied',
        () async {
      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr2nlIgyuezQuGNKAVeYPJMGcvYs13PeXqByuU6PkrCXA2pkDx91KynBv1+MzigMl/vjYiMr12+kE2fuvdlOGG5tOLz+b69s7WSUvwAy4Fa7hRVWxnfjoWD2Db5EdEcaVpKk0yL4KRO/K6grjkrtK92JeqLxkyMfOMwjTD/mO0BZfgCtGgSeJQPcw2IBuOAYpVJVUsIy5lPZKEk1lm7EYx3UfA5Ygw1VH8N9zYUu2OuHDvmQNMaDZxj2L+9HR71j5U1cq2PK6aJqEZc62nxoBLp4remaG66/EFzHNbCKVZ1BGh83PY9aTbw52PTaf7UxiVlNNy4Hqwp3C1Khq96rqJQIDAQAB';
      registerFallbackValue(FakeStorageFileInitOptions());
      registerFallbackValue(FakeLookupVerbBuilder());

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

      when(() => mockBiometricStorageEnrollmentFile.read())
          .thenAnswer((_) async {
        return Future.value(mockBiometricStorageEnrollmentFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      when(() => mockBiometricStorageEnrollmentFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo',
            () => invocation.positionalArguments[0]);
      });

      when(() => mockBiometricStorageEnrollmentFile.delete())
          .thenAnswer((_) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile
            .remove('${atSign}_enrollmentInfo');
      });

      when(() =>
              mockAtLookUp.executeVerb(any(that: LookupVerbBuilderMatcher())))
          .thenAnswer((_) => Future.value('data:$encryptionPublicKey'));

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:request'))))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'enrollmentId': '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                    'status': 'pending'
                  })}'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});

      AtEnrollmentResponse atEnrollmentResponse = await authServiceImpl.enroll(
          EnrollmentRequest(
              appName: 'wavi',
              deviceName: 'my-device',
              otp: 'ABC123',
              namespaces: {'wavi': 'rw'}));

      when(() => mockAtLookUp.pkamAuthenticate(
              enrollmentId: any(named: "enrollmentId")))
          .thenAnswer((_) => throw UnAuthenticatedException(
              'Failed to authenticate error: AT0025 enrollment is denied'));

      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.isNotEmpty, true);
      expect(
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.isNotEmpty, true);
      expect(
          atEnrollmentResponse
              .atAuthKeys!.defaultEncryptionPublicKey!.isNotEmpty,
          true);
      expect(
          atEnrollmentResponse.atAuthKeys!.apkamSymmetricKey!.isNotEmpty, true);
      expect(atEnrollmentResponse.atAuthKeys!.enrollmentId!.isNotEmpty, true);
      expect(atEnrollmentResponse.enrollmentId.isNotEmpty, true);
      expect(mockBiometricStorageEnrollmentFile.dummyStorageFile.length, 1);

      Future<EnrollmentStatus> enrollmentStatus =
          authServiceImpl.getFinalEnrollmentStatus();

      await enrollmentStatus
          .then((value) => expect(value, EnrollmentStatus.denied));

      // Verify enrollment info is removed from the enrollment keychain when enrollment request is denied
      expect(mockBiometricStorageEnrollmentFile.dummyStorageFile.length, 0);
    });

    test(
        'A test to verify submission of new enrollment without fulfilling the previous enrollment throws exception',
        () async {
      registerFallbackValue(FakeEnrollmentRequest());

      mockAtEnrollmentBase = MockAtEnrollmentBase();
      authServiceImpl.atEnrollmentBase = mockAtEnrollmentBase;

      when(() => mockAtEnrollmentBase.submit(
              any(that: EnrollmentRequestMatcher()), mockAtLookUp))
          .thenAnswer((_) => Future.value(AtEnrollmentResponse(
              '010ad3dc-02ee-41c6-b74b-c82f5122b181', EnrollmentStatus.pending)
            ..atAuthKeys = AtAuthKeys()));
      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

      when(() => mockBiometricStorageEnrollmentFile.read())
          .thenAnswer((_) async {
        return Future.value(mockBiometricStorageEnrollmentFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      when(() => mockBiometricStorageEnrollmentFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo',
            () => invocation.positionalArguments[0]);
      });

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});

      AtEnrollmentResponse atEnrollmentResponse = await authServiceImpl.enroll(
          EnrollmentRequest(
              appName: 'wavi',
              deviceName: 'my-device',
              otp: 'ABC123',
              namespaces: {'wavi': 'rw'}));

      expect(atEnrollmentResponse.enrollmentId,
          '010ad3dc-02ee-41c6-b74b-c82f5122b181');

      // Submit another enrollment
      expect(
          () async => await authServiceImpl.enroll(EnrollmentRequest(
              appName: 'wavi',
              deviceName: 'my-device',
              otp: 'ABC123',
              namespaces: {'wavi': 'rw'})),
          throwsA(predicate((dynamic e) =>
              e is AtEnrollmentException &&
              e.message ==
                  'Cannot submit new enrollment request until the pending enrollment request is fulfilled')));
    });

    test(
        'A test to verify getFinalEnrollmentStatus returns expired when there are no pending enrollments in keychain',
        () async {
      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

      when(() => mockBiometricStorageEnrollmentFile.read())
          .thenAnswer((_) async {
        return Future.value(mockBiometricStorageEnrollmentFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      EnrollmentStatus enrollmentStatus =
          await authServiceImpl.getFinalEnrollmentStatus();

      expect(enrollmentStatus, EnrollmentStatus.expired);
    });

    test('A test to verify enrollment approved', () async {
      registerFallbackValue(FakeAtClientPreference());
      registerFallbackValue(FakeAtKey());

      AtEncryptionKeyPair atEncryptionKeyPair =
          AtChopsUtil.generateAtEncryptionKeyPair();
      AtPkamKeyPair atPkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      atChopsKeys.selfEncryptionKey =
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      atChopsKeys.apkamSymmetricKey =
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

      AtChops atChops = AtChopsImpl(atChopsKeys);
      AtServiceFactory mockAtServiceFactory = MockAtServiceFactor();
      AtClient mockAtClient = MockAtClient();
      LocalSecondary mockLocalSecondary = MockLocalSecondary();

      InitialisationVector encryptionPrivateKeyIV =
          AtChopsUtil.generateRandomIV(16);

      String encryptedDefaultEncryptionPrivateKey = atChops
          .encryptString(
              atChops.atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey,
              EncryptionKeyType.aes256,
              keyName: 'apkamSymmetricKey',
              iv: encryptionPrivateKeyIV)
          .result;

      InitialisationVector selfEncryptionKeyIV =
          AtChopsUtil.generateRandomIV(16);
      // Fetch the selfEncryptionKey from the atChops and encrypt with APKAM Symmetric key.
      String encryptedDefaultSelfEncryptionKey = atChops
          .encryptString(atChops.atChopsKeys.selfEncryptionKey!.key,
              EncryptionKeyType.aes256,
              keyName: 'apkamSymmetricKey', iv: selfEncryptionKeyIV)
          .result;

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

      when(() => mockBiometricStorage.getStorage(
          any(that: startsWith('@atsigns')),
          options: any(named: 'options'))).thenAnswer(
        (_) async => mockBiometricStorageKeychainFile,
      );

      when(() => mockBiometricStorageKeychainFile.read()).thenAnswer((_) =>
          Future.value(mockBiometricStorageKeychainFile
              .dummyStorageFile['${atSign}_enrollmentInfo']));

      when(() =>
              mockBiometricStorageKeychainFile.write(any(that: startsWith(''))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageKeychainFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo_keychain',
            () => invocation.positionalArguments[0]);
      });

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});

      when(() => mockBiometricStorageEnrollmentFile.read())
          .thenAnswer((_) async {
        String jsonEncodedEnrollmentInfo =
            await Future.value(jsonEncode(EnrollmentInfo(
                '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                AtAuthKeys()
                  ..apkamPublicKey =
                      atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey
                  ..apkamPrivateKey =
                      atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey
                  ..defaultEncryptionPublicKey =
                      atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey
                  ..apkamSymmetricKey = atChopsKeys.apkamSymmetricKey?.key
                  ..enrollmentId = '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                DateTime.now().microsecondsSinceEpoch,
                {'wavi': 'rw'})));

        mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo', () => jsonEncodedEnrollmentInfo);

        return jsonEncodedEnrollmentInfo;
      });

      when(() => mockBiometricStorageEnrollmentFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
            jsonEncode(
              EnrollmentInfo(
                  '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                  AtAuthKeys()
                    ..apkamPublicKey =
                        atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey
                    ..apkamPrivateKey =
                        atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey
                    ..defaultEncryptionPublicKey =
                        atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey
                    ..apkamSymmetricKey = atChopsKeys.apkamSymmetricKey?.key
                    ..enrollmentId = '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                  DateTime.now().microsecondsSinceEpoch,
                  {'wavi': 'rw'}),
            ),
            () => invocation.positionalArguments[0]);
      });

      when(() => mockBiometricStorageEnrollmentFile.delete())
          .thenAnswer((_) async {
        mockBiometricStorageEnrollmentFile.dummyStorageFile = {};
      });

      when(() => mockAtLookUp.atChops).thenAnswer((_) => atChops);

      when(() => mockAtLookUp.pkamAuthenticate(
              enrollmentId: any(named: "enrollmentId")))
          .thenAnswer((_) => Future.value(true));

      // Returns the encrypted defaultEncryptionPrivateKey from the server
      when(() => mockAtLookUp.executeCommand(
              any(that: contains(AtConstants.defaultEncryptionPrivateKey)),
              auth: true))
          .thenAnswer((invocation) => Future.value('data:${jsonEncode({
                    'value': encryptedDefaultEncryptionPrivateKey,
                    'iv': base64Encode(encryptionPrivateKeyIV.ivBytes)
                  })}'));

      // Returns the encrypted defaultSelfEncryptionKey from the server
      when(() => mockAtLookUp.executeCommand(
              any(that: contains(AtConstants.defaultSelfEncryptionKey)),
              auth: true))
          .thenAnswer((invocation) => Future.value('data:${jsonEncode({
                    'value': encryptedDefaultSelfEncryptionKey,
                    'iv': base64Encode(selfEncryptionKeyIV.ivBytes)
                  })}'));

      when(() => mockAtServiceFactory.atClient(
              any(that: startsWith('@alice')),
              any(that: startsWith('me')),
              any(that: FakeAtClientPreferenceMatcher()),
              AtClientManager.getInstance(),
              atChops: any(named: "atChops"),
              enrollmentId: '010ad3dc-02ee-41c6-b74b-c82f5122b181'))
          .thenAnswer((_) => Future.value(mockAtClient));

      NotificationService mockNotificationService = MockNotificationService();

      when(() => mockAtServiceFactory.notificationService(
              mockAtClient, AtClientManager.getInstance()))
          .thenAnswer((_) => Future.value(mockNotificationService));

      when(() => mockAtServiceFactory.syncService(mockAtClient,
              AtClientManager.getInstance(), mockNotificationService))
          .thenAnswer((_) => Future.value(MockSyncService()));

      when(() => mockAtServiceFactory.enrollmentService(mockAtClient))
          .thenAnswer((_) => MockEnrollmentService());

      authServiceImpl.atServiceFactory = mockAtServiceFactory;
      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);

      when(() => mockAtClient.put(
              any(that: FakeAtKeyMatcher()), any(that: contains('wavi'))))
          .thenAnswer((Invocation invocation) async {
        expect(
            'local:010ad3dc-02ee-41c6-b74b-c82f5122b181.new.enrollments.__manage@alice',
            invocation.positionalArguments[0].toString());
        expect('{"wavi":"rw"}', invocation.positionalArguments[1].toString());
        return Future.value(true);
      });

      Future<EnrollmentStatus> enrollmentStatus =
          authServiceImpl.getFinalEnrollmentStatus();

      await enrollmentStatus.then((value) {
        expect(value, EnrollmentStatus.approved);
      });

      expect(mockBiometricStorageEnrollmentFile.dummyStorageFile.length, 0);
      expect(mockBiometricStorageKeychainFile.dummyStorageFile.length, 1);
    });

    tearDown(() => tearDownMethod(mockBiometricStorageEnrollmentFile,
        mockAtLookUp, mockBiometricStorage));
  });

  group('A group of tests related to authenticate an atSign', () {
    String atSign = '@alice';
    AtClientPreference atClientPreference = AtClientPreference()
      ..namespace = 'me';

    test(
        'A test to verify AtClient initializes successfully in offline mode upon network failure when keychain manager contains keys',
        () async {
      KeyChainManager mockKeyChainManager = MockKeyChainManager();
      RSAKeypair pkamKeyPair = KeyChainManager.getInstance().generateKeyPair();
      RSAKeypair encryptionKeyPair =
          KeyChainManager.getInstance().generateKeyPair();
      String selfEncryptionKey = KeyChainManager.getInstance().generateAESKey();
      AtAuthService atAuthService =
          AtClientMobile.authService(atSign, atClientPreference);
      (atAuthService as AtAuthServiceImpl).keyChainManager =
          mockKeyChainManager;

      AtsignKey atsignKey = AtsignKey(
          atSign: atSign,
          encryptionPublicKey: encryptionKeyPair.publicKey.toString());

      // Mock object to return keys from keychain manager
      when(() => mockKeyChainManager.readAtsign(name: atSign))
          .thenAnswer((_) => Future.value(atsignKey));

      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.atAuthKeys = AtAuthKeys()
        ..apkamPrivateKey = pkamKeyPair.privateKey.toString()
        ..apkamPublicKey = pkamKeyPair.publicKey.toString()
        ..defaultEncryptionPublicKey = encryptionKeyPair.publicKey.toString()
        ..defaultEncryptionPrivateKey = encryptionKeyPair.privateKey.toString()
        ..defaultSelfEncryptionKey = selfEncryptionKey
        ..enrollmentId = '123';

      AtAuthResponse atAuthResponse =
          await atAuthService.authenticate(atAuthRequest);

      expect(atAuthResponse.isSuccessful, true);
      expect(atAuthResponse.atSign, atSign);
      expect(atAuthResponse.atAuthKeys?.apkamPublicKey,
          pkamKeyPair.publicKey.toString());
      expect(atAuthResponse.atAuthKeys?.apkamPrivateKey,
          pkamKeyPair.privateKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultEncryptionPrivateKey,
          encryptionKeyPair.privateKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultEncryptionPublicKey,
          encryptionKeyPair.publicKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultSelfEncryptionKey,
          selfEncryptionKey);
    });

    test(
        'A test to verify atClient initialization fails when network is offline and keychain manager does not have keys',
        () async {
      KeyChainManager mockKeyChainManager = MockKeyChainManager();
      RSAKeypair pkamKeyPair = KeyChainManager.getInstance().generateKeyPair();
      RSAKeypair encryptionKeyPair =
          KeyChainManager.getInstance().generateKeyPair();
      AtAuthService atAuthService =
          AtClientMobile.authService(atSign, atClientPreference);
      (atAuthService as AtAuthServiceImpl).keyChainManager =
          mockKeyChainManager;

      AtsignKey atsignKey = AtsignKey(atSign: atSign, encryptionPublicKey: '');

      // Mock object to return keys from keychain manager
      when(() => mockKeyChainManager.readAtsign(name: atSign))
          .thenAnswer((_) => Future.value(atsignKey));

      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.atAuthKeys = AtAuthKeys()
        ..apkamPrivateKey = pkamKeyPair.privateKey.toString()
        ..apkamPublicKey = pkamKeyPair.publicKey.toString()
        ..defaultEncryptionPublicKey = encryptionKeyPair.publicKey.toString()
        ..defaultEncryptionPrivateKey = encryptionKeyPair.privateKey.toString()
        ..defaultSelfEncryptionKey =
            KeyChainManager.getInstance().generateAESKey();

      AtAuthResponse atAuthResponse =
          await atAuthService.authenticate(atAuthRequest);

      expect(atAuthResponse.isSuccessful, false);
    });

    test(
        'A test to verify authentication is successful when pkamAuthentication returns true',
        () async {
      KeyChainManager mockKeyChainManager = MockKeyChainManager();
      AtLookUp mockAtLookup = MockAtLookUp();

      RSAKeypair pkamKeyPair = KeyChainManager.getInstance().generateKeyPair();
      RSAKeypair encryptionKeyPair =
          KeyChainManager.getInstance().generateKeyPair();
      String selfEncryptionKey = KeyChainManager.getInstance().generateAESKey();
      AtAuthService atAuthService = AtClientMobile.authService(
          atSign, atClientPreference,
          atLookUp: mockAtLookup);
      (atAuthService as AtAuthServiceImpl).keyChainManager =
          mockKeyChainManager;

      AtsignKey atsignKey = AtsignKey(
          atSign: atSign,
          encryptionPublicKey: encryptionKeyPair.publicKey.toString());

      // Mock object to return keys from keychain manager
      when(() => mockKeyChainManager.readAtsign(name: atSign))
          .thenAnswer((_) => Future.value(atsignKey));

      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: '123'))
          .thenAnswer((_) => Future.value(true));

      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.atAuthKeys = AtAuthKeys()
        ..apkamPrivateKey = pkamKeyPair.privateKey.toString()
        ..apkamPublicKey = pkamKeyPair.publicKey.toString()
        ..defaultEncryptionPublicKey = encryptionKeyPair.publicKey.toString()
        ..defaultEncryptionPrivateKey = encryptionKeyPair.privateKey.toString()
        ..defaultSelfEncryptionKey = selfEncryptionKey
        ..enrollmentId = '123';

      AtAuthResponse atAuthResponse =
          await atAuthService.authenticate(atAuthRequest);

      expect(atAuthResponse.isSuccessful, true);
      expect(atAuthResponse.atSign, atSign);
      expect(atAuthResponse.atAuthKeys?.enrollmentId, '123');
      expect(atAuthResponse.atAuthKeys?.apkamPublicKey,
          pkamKeyPair.publicKey.toString());
      expect(atAuthResponse.atAuthKeys?.apkamPrivateKey,
          pkamKeyPair.privateKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultEncryptionPrivateKey,
          encryptionKeyPair.privateKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultEncryptionPublicKey,
          encryptionKeyPair.publicKey.toString());
      expect(atAuthResponse.atAuthKeys?.defaultSelfEncryptionKey,
          selfEncryptionKey);
    });
  });
}

void tearDownMethod(MockEnrollmentBiometricStorageFile mockBiometricStorageFile,
    MockAtLookUp mockAtLookUp, MockBiometricStorage mockBiometricStorage) {
  resetMocktailState();
  reset(mockBiometricStorageFile);
  reset(mockAtLookUp);
  reset(mockBiometricStorage);
  mockBiometricStorageFile.dummyStorageFile.clear();
}

class LookupVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is LookupVerbBuilder && item.atKey.key.startsWith('publickey')) {
      return true;
    }
    return false;
  }
}

class EnrollmentRequestMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is EnrollmentRequest) {
      return true;
    }
    return false;
  }
}

class FakeAtClientPreferenceMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtClientPreference) {
      return true;
    }
    return false;
  }
}

class FakeAtKeyMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtKey) {
      return true;
    }
    return false;
  }
}
