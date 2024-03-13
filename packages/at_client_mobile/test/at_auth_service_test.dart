import 'dart:collection';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
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

class FakeStorageFileInitOptions extends Fake
    implements StorageFileInitOptions {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

void main() {
  group('A group of tests related to submission of enrollment request', () {
    test('A test to verify submission of enrollment', () async {
      String encryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr2nlIgyuezQuGNKAVeYPJMGcvYs13PeXqByuU6PkrCXA2pkDx91KynBv1+MzigMl/vjYiMr12+kE2fuvdlOGG5tOLz+b69s7WSUvwAy4Fa7hRVWxnfjoWD2Db5EdEcaVpKk0yL4KRO/K6grjkrtK92JeqLxkyMfOMwjTD/mO0BZfgCtGgSeJQPcw2IBuOAYpVJVUsIy5lPZKEk1lm7EYx3UfA5Ygw1VH8N9zYUu2OuHDvmQNMaDZxj2L+9HR71j5U1cq2PK6aJqEZc62nxoBLp4remaG66/EFzHNbCKVZ1BGh83PY9aTbw52PTaf7UxiVlNNy4Hqwp3C1Khq96rqJQIDAQAB';
      registerFallbackValue(FakeStorageFileInitOptions());
      registerFallbackValue(FakeLookupVerbBuilder());

      String atSign = '@alice';
      AtClientPreference atClientPreference = AtClientPreference();
      AtAuthServiceImpl authServiceImpl =
          AtAuthServiceImpl(atSign, atClientPreference);
      BiometricStorage mockBiometricStorage = MockBiometricStorage();
      MockBiometricStorageFile mockBiometricStorageFile =
          MockBiometricStorageFile();
      MockAtLookUp mockAtLookUp = MockAtLookUp();

      authServiceImpl.enrollmentKeychainStore = mockBiometricStorage;
      authServiceImpl.atLookUp = mockAtLookUp;

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

      String atSign = '@alice';
      AtClientPreference atClientPreference = AtClientPreference();
      AtAuthServiceImpl authServiceImpl =
          AtAuthServiceImpl(atSign, atClientPreference);
      BiometricStorage mockBiometricStorage = MockBiometricStorage();
      MockBiometricStorageFile mockBiometricStorageFile =
          MockBiometricStorageFile();
      MockAtLookUp mockAtLookUp = MockAtLookUp();

      authServiceImpl.enrollmentKeychainStore = mockBiometricStorage;
      authServiceImpl.atLookUp = mockAtLookUp;

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
  });
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
