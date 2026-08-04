import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookup extends Mock implements AtLookUp {}

void main() {
  group('PkamAuthenticator tests', () {
    late PkamAuthenticator pkamAuthenticator;
    late MockAtLookup mockAtLookup;
    final Atsign atSign = '@alice'.toAtsign();
    final String testEnrollmentId = 'testEnrollmentId';

    setUp(() {
      mockAtLookup = MockAtLookup();
      pkamAuthenticator = PkamAuthenticator();
    });

    test('authenticate() completes normally on success', () async {
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) async => true);

      await expectLater(
        pkamAuthenticator.authenticate(atSign, mockAtLookup,
            enrollmentId: testEnrollmentId),
        completes,
      );
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await pkamAuthenticator.authenticate(atSign, mockAtLookup,
              enrollmentId: testEnrollmentId),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('authenticate() should throw when lookup reports a soft failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) async => false);

      expect(
          () async => await pkamAuthenticator.authenticate(atSign, mockAtLookup,
              enrollmentId: testEnrollmentId),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('authenticate() passes a null enrollmentId straight through',
        () async {
      // A null enrollmentId means "use the one the connection was built with",
      // which at_lookup resolves — the authenticator must not substitute one.
      when(() => mockAtLookup.pkamAuthenticate(enrollmentId: null))
          .thenAnswer((_) async => true);

      await pkamAuthenticator.authenticate(atSign, mockAtLookup);

      verify(() => mockAtLookup.pkamAuthenticate(enrollmentId: null)).called(1);
    });
  });
}
