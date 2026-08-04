import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookup extends Mock implements AtLookUp {}

void main() {
  group('CramAuthenticator tests', () {
    late CramAuthenticator cramAuthenticator;
    late MockAtLookup mockAtLookup;
    final Atsign atSign = '@alice'.toAtsign();
    final String cramSecret = 'testCramSecret';

    setUp(() {
      mockAtLookup = MockAtLookup();
      cramAuthenticator = CramAuthenticator();
    });

    test('authenticate() completes normally on success', () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenAnswer((_) async => true);

      await expectLater(
        cramAuthenticator.authenticate(atSign, cramSecret, mockAtLookup),
        completes,
      );
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await cramAuthenticator.authenticate(
              atSign, cramSecret, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('authenticate() should throw when lookup reports a soft failure',
        () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenAnswer((_) async => false);

      expect(
          () async => await cramAuthenticator.authenticate(
              atSign, cramSecret, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });
}
