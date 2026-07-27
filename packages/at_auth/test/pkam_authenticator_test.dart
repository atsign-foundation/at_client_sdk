import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

class MockAtLookup extends Mock implements AtLookUp {}

void main() {
  group('PkamAuthenticator tests', () {
    late PkamAuthenticator pkamAuthenticator;
    late MockAtLookup mockAtLookup;
    late AtKeys atKeys;
    final String atSign = '@alice';
    final String testEnrollmentId = 'testEnrollmentId';

    setUp(() {
      mockAtLookup = MockAtLookup();
      pkamAuthenticator = PkamAuthenticator();
      atKeys = legacyAtKeys();
    });

    test('authenticate() completes normally on success', () async {
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) async => true);

      await expectLater(
        pkamAuthenticator.authenticate(
          atSign,
          mockAtLookup,
          atKeys,
          enrollmentId: testEnrollmentId,
        ),
        completes,
      );
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate(
              enrollmentId: AtConstants.enrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await pkamAuthenticator.authenticate(
                atSign,
                mockAtLookup,
                atKeys,
                enrollmentId: AtConstants.enrollmentId,
              ),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('authenticate() should throw when lookup reports a soft failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) async => false);

      expect(
          () async => await pkamAuthenticator.authenticate(
                atSign,
                mockAtLookup,
                atKeys,
                enrollmentId: testEnrollmentId,
              ),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test(
        'authenticate() should throw AtAuthenticationException when no apkam '
        'private key is available to sign', () async {
      // ignore: deprecated_member_use
      atKeys.apkamPrivateKey = null;

      expect(
          () async => await pkamAuthenticator.authenticate(
                atSign,
                mockAtLookup,
                atKeys,
                enrollmentId: testEnrollmentId,
              ),
          throwsA(isA<AtAuthenticationException>()));
    });
  });
}
