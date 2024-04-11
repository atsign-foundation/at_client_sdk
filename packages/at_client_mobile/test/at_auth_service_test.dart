import 'dart:collection';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_auth_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {
  Map<String, String> dummyStorageFile = HashMap();
}

class MockAtLookUp extends Mock implements AtLookUp {}

class MockAtEnrollmentBase extends Mock implements AtEnrollmentBase {}

class FakeStorageFileInitOptions extends Fake
    implements StorageFileInitOptions {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

void main() {
  group('A group of tests related to submission of enrollment request', () {
    String atSign = '@alice';
    AtClientPreference atClientPreference = AtClientPreference();

    late AtAuthServiceImpl authServiceImpl;
    MockAtEnrollmentBase mockAtEnrollmentBase;
    late MockBiometricStorageFile mockBiometricStorageFile;
    late MockBiometricStorage mockBiometricStorage;
    late MockAtLookUp mockAtLookUp;

    setUp(() {
      authServiceImpl = AtAuthServiceImpl(atSign, atClientPreference);

      mockBiometricStorageFile = MockBiometricStorageFile();
      mockBiometricStorage = MockBiometricStorage();
      mockAtLookUp = MockAtLookUp();

      authServiceImpl.enrollmentKeychainStore = mockBiometricStorage;
      authServiceImpl.atLookUp = mockAtLookUp;
    });

    test('A test to verify submission of enrollment', () async {
      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr2nlIgyuezQuGNKAVeYPJMGcvYs13PeXqByuU6PkrCXA2pkDx91KynBv1+MzigMl/vjYiMr12+kE2fuvdlOGG5tOLz+b69s7WSUvwAy4Fa7hRVWxnfjoWD2Db5EdEcaVpKk0yL4KRO/K6grjkrtK92JeqLxkyMfOMwjTD/mO0BZfgCtGgSeJQPcw2IBuOAYpVJVUsIy5lPZKEk1lm7EYx3UfA5Ygw1VH8N9zYUu2OuHDvmQNMaDZxj2L+9HR71j5U1cq2PK6aJqEZc62nxoBLp4remaG66/EFzHNbCKVZ1BGh83PY9aTbw52PTaf7UxiVlNNy4Hqwp3C1Khq96rqJQIDAQAB';
      registerFallbackValue(FakeStorageFileInitOptions());
      registerFallbackValue(FakeLookupVerbBuilder());

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);

      when(() => mockBiometricStorageFile.read()).thenAnswer((_) =>
          Future.value(mockBiometricStorageFile
              .dummyStorageFile['${atSign}_enrollmentInfo']));

      when(() => mockBiometricStorageFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageFile.dummyStorageFile.putIfAbsent(
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
      expect(mockBiometricStorageFile.dummyStorageFile.length, 1);
    });

    test('A test to verify enrollment request is submitted and denied',
        () async {
      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr2nlIgyuezQuGNKAVeYPJMGcvYs13PeXqByuU6PkrCXA2pkDx91KynBv1+MzigMl/vjYiMr12+kE2fuvdlOGG5tOLz+b69s7WSUvwAy4Fa7hRVWxnfjoWD2Db5EdEcaVpKk0yL4KRO/K6grjkrtK92JeqLxkyMfOMwjTD/mO0BZfgCtGgSeJQPcw2IBuOAYpVJVUsIy5lPZKEk1lm7EYx3UfA5Ygw1VH8N9zYUu2OuHDvmQNMaDZxj2L+9HR71j5U1cq2PK6aJqEZc62nxoBLp4remaG66/EFzHNbCKVZ1BGh83PY9aTbw52PTaf7UxiVlNNy4Hqwp3C1Khq96rqJQIDAQAB';
      registerFallbackValue(FakeStorageFileInitOptions());
      registerFallbackValue(FakeLookupVerbBuilder());

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);

      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async {
        return Future.value(mockBiometricStorageFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      when(() => mockBiometricStorageFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo',
            () => invocation.positionalArguments[0]);
      });

      when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async {
        mockBiometricStorageFile.dummyStorageFile
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
      expect(mockBiometricStorageFile.dummyStorageFile.length, 1);

      Future<EnrollmentStatus> enrollmentStatus =
          authServiceImpl.getFinalEnrollmentStatus();

      await enrollmentStatus
          .then((value) => expect(value, EnrollmentStatus.denied));

      // Verify enrollment info is removed from the enrollment keychain when enrollment request is denied
      expect(mockBiometricStorageFile.dummyStorageFile.length, 0);
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
          .thenAnswer((_) async => mockBiometricStorageFile);

      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async {
        return Future.value(mockBiometricStorageFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      when(() => mockBiometricStorageFile
              .write(any(that: startsWith('{"enrollmentId"'))))
          .thenAnswer((Invocation invocation) async {
        mockBiometricStorageFile.dummyStorageFile.putIfAbsent(
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
          .thenAnswer((_) async => mockBiometricStorageFile);

      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async {
        return Future.value(mockBiometricStorageFile
            .dummyStorageFile['${atSign}_enrollmentInfo']);
      });

      EnrollmentStatus enrollmentStatus =
          await authServiceImpl.getFinalEnrollmentStatus();

      expect(enrollmentStatus, EnrollmentStatus.expired);
    });

    test('A test to verify enrollment approved and atkeys file is generated',
        () async {
      String encryptedDefaultEncryptionPrivateKey =
          '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';
      String encryptedDefaultSelfEncryptionKey =
          'LYp38EsUNznPAi+yMTAnHdtyfmIORJF6Ck5oNelgcplm6TiJMRzeBOiJQ4zRI+OB';

      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtEVcUP9FaAYi3uK3YM2z/O0qvidBGkPk34ttDGMrr3891AxK/n6Ejs29VsVW0YeEypFSMxEWvFa9UBhLq9yWBaHU534CxvsKVRN09963wu5F7asBEpbfhBOUrv8Xqa2Je6yavAbWX5QjHbrqXTNCASyfjFrtDrsVNQLK3y3YkxSBxTbAj+EC+wv7pp7dg42Rq3lGLVsh3JwDOFMQNn/fyxeDYgrFmEBpwjfnaCzinPzFkbwSuC+qMu5AiSXf7IlTjb3vrREuWMoM1T2i5MYmvnQHDVasXcPWXNHQ+cg6iC93ZBLy/rqJhGiCyvhLdkMZrKMAUuxrzveQvEq7Pi8zVwIDAQAB';
      String encryptionPrivateKey =
          'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC0RVxQ/0VoBiLe4rdgzbP87Sq+J0EaQ+Tfi20MYyuvfz3UDEr+foSOzb1WxVbRh4TKkVIzERa8Vr1QGEur3JYFodTnfgLG+wpVE3T33rfC7kXtqwESlt+EE5Su/xeprYl7rJq8BtZflCMduupdM0IBLJ+MWu0OuxU1AsrfLdiTFIHFNsCP4QL7C/umnt2DjZGreUYtWyHcnAM4UxA2f9/LF4NiCsWYQGnCN+doLOKc/MWRvBK4L6oy7kCJJd/siVONve+tES5YygzVPaLkxia+dAcNVqxdw9Zc0dD5yDqIL3dkEvL+uomEaILK+Et2QxmsowBS7GvO95C8Srs+LzNXAgMBAAECggEATSG0Sy+9+bFOcEFfJvs8vMaZWD0hfOR55DAa24b/JRrzUGxmFhf6DcP39E2BRSuP5MBjBFiWesU+QSv0DLfYNNa2asoe1BaLqDUoAfp4c95Ra0yUq+iEAFYEcw/QhxgqUBFdL4BZbxHKKKlWJ8SLxEbciUhKT9g6TbFBLlbGaL9N+Cx54pymRppiwTqouu3s9DLpIiF6rQsAA3l9NiQ08btTVSvssUKQpF2uYMRKU0SNLM6K7WPmSP/g3vefe3YDiYPK1ouFzWLo5tyjmcYOLrT6VSAORMBks+3bx3XE2BThp0EP0c5DEHX9j6KlbUiFhTPEAO3g7r7/PmXNJIXRWQKBgQD+v7QPgQoQUPoNinKCKkWBLWSawKe0qbEhS98zTU6KEp731cI2wwXK7wdfMtmuB2CNpiGmxzKf7Xj3zu9FTRpHTP6aLyxB2pNrIoK+2kUambt7N+XWUNWeJOn1sM1EriyS2krk/ZJlsFLwaUBRW0OjA3p7AUEDx0HZ7M3C868NbQKBgQC1KAQS/5H8GheKntJU0NgsqjtwhVFJTAbMyy4d0y/T5AQdu+QwiGI78bAxKeXeq7trQuSQjR0IZpQUO/dZzXp4B+UizUDrIjDXRae0nAyu8VIFjmjofBXNCQVImUKRvS7RLrVSAI2ylGV9u/Y2TlMJYiDU9VXBODJ6UJ2AoLqdUwKBgQD1NL0ytzhioC8wXXT/CYVBY9oUgyBp63SN4iQDk4PnryjI0T5Ry8KFpTJpVd7lfkBX1/NIPzDhc4kerlbtU9vZiaj/7Cwjbyq60ssavaoKgrNNVW6rrb8Qq+NvFDFgzG4nJGs2o0UJEIGk2wqHxNsDy9NXFsvnwSIHi8I6xqhWuQKBgQCyYkMQyiTgkHjaAWawKi6UXNTHCiBvArQ3eWNh7xFLn14GQXyD5eiFioqq/sziJU0aY/ZZ+Pq7yPbLrfj1rwaHp46UZHUmlLZvZKGtkXRT2EGiQwc+1uFI0zcms/P/OsEdLtdRdkYRsVr3It1hwGK3/K7DxQm6iDH8i+FsRdk9DQKBgEpW6lzyabAvgIsJH2uELap3+jL5glLLeHsOU+aCzIkgAIR6nANk1naLG1ZE7H9mW7Y8sy27CpNo0L2VW1xXKwTsTgcX8T6kMY7zdNMutIeAHUOEx96e7swFi6HsNqNRx6qjpVUcJDckPDVpMomEe5I69EJEA2jQvdmKUnTGx36j';
      String pkamPrivateKey =
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCLIk7PWdOT7MLIR0ktElNEe9vBLIWlC6PF9IXS61ZB12uavMuLAOKP0ZDIJKvBbOoqQC0mgIybDsOQIPjbBjQaj6LR3gS1KcvRaz0A0aB0ueX5XOV8jn1pnngAUtkOdnMUzDx92J38YkoSktBkpyNDV7ATNUTI69DmBOoVwEZP5Li9or1ef5BtynAqusrzMzt6kXxN2HaLPEhqmBtCZk7HqXQaFq3s4OqM1sQwED394FbgndnxjsjYD0HgrwJwDIZFz+0A50Od74FjWtqicmMlsYt+zG56tHVd8vRAH6sP32m0a9PPzttPmOLvqaLgFByh0V3lvwuMyP08X0c0sx+zAgMBAAECggEAUKd/thWlYAAE3iLs2ZLg8Dc4qd/MTWPU+YEJPr6rzxk4yIefGqJVs/dRDaSsaEFh8UIoqkQkvhIt7dQfTqBm/eq8ARrJ8dcbzvdycpISiPfmx8pBQhY7v0lc2RsttoOVrL3EZ1N2KgM0W1X+NgrplzUy3b+ocyy4eU7p/9fpKpBaTOuImCMh/6WObdmrsXmPqTMf+CJfw7QIKYwpn2uZfI01iNFDe7o+UoX75rDsjz50ogUDYoziRSVQ22aB96Tv26a97GrYJbxkbTu8FxHjMC6e7gir76sfTrt9FYeGe6QuGDqmQaa9fQxJVp2NulA0HwAGRssvSqOsDix9Hcd+gQKBgQDD7lIQL+rFakRoZK1ZyUCanby+lviIzczLouxCythpTPODtXmVg3yH9X2E6Md9ULzhrdDGtooA1d1SXS2SzumReaklggMsi5P8Ov+jYOeO+LZV/Zxf4zVdGQgzPhU8BvuacAMjikt8dU9gwJYm+sQb8cLkJXFyUFXnu7hoZA7UwQKBgQC1ykToX+bVJKOlMb0i7EFybERQozPxtxNmnQPH8nmx+D48oawITo+/I3PA2qQ7Y43+S6XomXFOFv4frNtg1K+tq1aGI3OyJyfJvnXue3IjLvT5pkB3HbuEvt0oMYyj9sru393OW0xuW/hLVWsmE25LuAbyZ3Xfp2wosBtjtWvNcwKBgAS0ppfo7rSLFtWDBX7QjJKqEyxop9NxTefeI9p+0K/Gv1p8c00Z+VWyma8lgBUMaVzqNcdv/uSCPmyJ/Fw4R/fMejmCY90gBQ/bwuQDocwXQRnTm3vaEyAHR+EjLpNgf453/jtOSP3WO2/RcEnDYA5jwhCErbLXJxkHsygerxSBAoGBAItWFarmls8X3jZoAUgbPa6uPU5xSQckA8LK5nMC7zPxygI/CNT1Ikimq7pN20OJ8vPOl8PImIf6J52vqBZ37o92nEMEOVF7oYuIaGv6QmmlPC99tjuWlnwQrwJ3uAyUxMaC4Eeiwtpzs8RKHG56xjdTPj/d/QMIGGa3VMb/7zjxAoGARlySlIcICZiCH7CKDImjtk+lN3PrZhCTq169/qLb9/a7wutKJHty0Fcu8B6C+2gH7bM9eik7wMxPhp3VuqB8ZTn9PwxO2BjNpGgcvnGgkXTM1IHZQY88vTHxIYZrTPvnpV2cirUgvI2TIcrqRTJsk0UG+yW12yP/sZLNApPXdvw=';
      String pkamPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiyJOz1nTk+zCyEdJLRJTRHvbwSyFpQujxfSF0utWQddrmrzLiwDij9GQyCSrwWzqKkAtJoCMmw7DkCD42wY0Go+i0d4EtSnL0Ws9ANGgdLnl+VzlfI59aZ54AFLZDnZzFMw8fdid/GJKEpLQZKcjQ1ewEzVEyOvQ5gTqFcBGT+S4vaK9Xn+QbcpwKrrK8zM7epF8Tdh2izxIapgbQmZOx6l0Ghat7ODqjNbEMBA9/eBW4J3Z8Y7I2A9B4K8CcAyGRc/tAOdDne+BY1raonJjJbGLfsxuerR1XfL0QB+rD99ptGvTz87bT5ji76mi4BQcodFd5b8LjMj9PF9HNLMfswIDAQAB';

      AtEncryptionKeyPair atEncryptionKeyPair =
          AtEncryptionKeyPair.create(encryptionPublicKey, encryptionPrivateKey);
      AtPkamKeyPair atPkamKeyPair =
          AtPkamKeyPair.create(pkamPublicKey, pkamPrivateKey);
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      atChopsKeys.selfEncryptionKey =
          AESKey('x1RB+Lbj9wDzpR23cx3FQiSCekQ1pFRSrNjouyGtrvk=');
      atChopsKeys.apkamSymmetricKey =
          AESKey('2KZWscShvALlJabtMDrvnkDUoGIQidicyZvIXDFgMsU=');

      AtChops atChops = AtChopsImpl(atChopsKeys);

      when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo',
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});

      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async {
        String jsonEncodedEnrollmentInfo =
            await Future.value(jsonEncode(EnrollmentInfo(
                '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                AtAuthKeys()
                  ..apkamPublicKey = pkamPublicKey
                  ..apkamPrivateKey = pkamPrivateKey
                  ..defaultEncryptionPublicKey = encryptionPublicKey
                  ..apkamSymmetricKey = atChopsKeys.apkamSymmetricKey?.key
                  ..enrollmentId = '010ad3dc-02ee-41c6-b74b-c82f5122b181',
                DateTime.now().microsecondsSinceEpoch,
                {'wavi': 'rw'})));

        mockBiometricStorageFile.dummyStorageFile.putIfAbsent(
            '${atSign}_enrollmentInfo', () => jsonEncodedEnrollmentInfo);

        return jsonEncodedEnrollmentInfo;
      });

      when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async {
        mockBiometricStorageFile.dummyStorageFile
            .remove('${atSign}_enrollmentInfo');
      });

      when(() => mockAtLookUp.atChops).thenAnswer((_) => atChops);

      when(() => mockAtLookUp.pkamAuthenticate(
              enrollmentId: any(named: "enrollmentId")))
          .thenAnswer((_) => Future.value(true));

      // Returns the encrypted defaultEncryptionPrivateKey from the server
      when(() => mockAtLookUp.executeCommand(
          any(that: contains(AtConstants.defaultEncryptionPrivateKey)),
          auth: true)).thenAnswer((invocation) => Future.value(
              'data:${jsonEncode({
                'value': encryptedDefaultEncryptionPrivateKey
              })}'));

      // Returns the encrypted defaultSelfEncryptionKey from the server
      when(() =>
          mockAtLookUp.executeCommand(
              any(that: contains(AtConstants.defaultSelfEncryptionKey)),
              auth: true)).thenAnswer((invocation) => Future.value(
          'data:${jsonEncode({'value': encryptedDefaultSelfEncryptionKey})}'));

      Future<EnrollmentStatus> enrollmentStatus =
          authServiceImpl.getFinalEnrollmentStatus();

      await enrollmentStatus.then((value) {
        expect(value, EnrollmentStatus.approved);
      });

      expect(mockBiometricStorageFile.dummyStorageFile.length, 0);
    });

    tearDown(() => tearDownMethod(
        mockBiometricStorageFile, mockAtLookUp, mockBiometricStorage));
  });
}

void tearDownMethod(MockBiometricStorageFile mockBiometricStorageFile,
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
