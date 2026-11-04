import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookup extends Mock implements AtLookUp {}

void main() {
  group('PkamAuthenticator tests', () {
    late PkamAuthenticator pkamAuthenticator;
    late MockAtLookup mockAtLookup;
    final String atSign = '@alice';

    setUp(() {
      mockAtLookup = MockAtLookup();
      pkamAuthenticator = PkamAuthenticator();
    });

    test('authenticate() should return a successful AtAuthResponse', () async {
      when(() => mockAtLookup.pkamAuthenticate()).thenAnswer((_) async => true);

      final result = await pkamAuthenticator.authenticate(atSign, mockAtLookup);

      expect(result, isTrue);
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate())
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await pkamAuthenticator.authenticate(atSign, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });
}
