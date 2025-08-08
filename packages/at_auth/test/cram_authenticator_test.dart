import 'package:at_auth/src/auth/at_auth_response.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

void main() {
  group('CramAuthenticator tests', () {
    late CramAuthenticator cramAuthenticator;
    late MockAtLookupImpl mockAtLookup;
    final String atSign = '@alice';
    final String cramSecret = 'testCramSecret';

    setUp(() {
      mockAtLookup = MockAtLookupImpl();
      cramAuthenticator = CramAuthenticator(atSign, cramSecret, mockAtLookup);
    });

    test('authenticate() should return a successful AtAuthResponse', () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenAnswer((_) async => true);

      final result = await cramAuthenticator.authenticate();

      expect(result, isA<AtAuthResponse>());
      expect(result.isSuccessful, isTrue);
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(() async => await cramAuthenticator.authenticate(),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });
}
