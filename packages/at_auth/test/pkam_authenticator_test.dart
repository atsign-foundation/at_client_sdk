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

  group('Given a lookup its owner has stopped', () {
    test(
        'when PkamAuthenticator authenticates on it, then the '
        'StoppedException passes through as thrown', () async {
      final lookUp = MockAtLookup();
      final stopped =
          StoppedException('the lookup for @alice has been stopped');
      when(() => lookUp.pkamAuthenticate()).thenThrow(stopped);

      await expectLater(PkamAuthenticator().authenticate('@alice', lookUp),
          throwsA(same(stopped)));
    });
  });

  group('Given a lookup whose PKAM times out', () {
    test(
        'when PkamAuthenticator authenticates on it, then it throws an '
        'UnAuthenticatedException naming the atSign', () async {
      final lookUp = MockAtLookup();
      when(() => lookUp.pkamAuthenticate())
          .thenThrow(AtTimeoutException('Waited for 10 millis. No response'));

      await expectLater(
          PkamAuthenticator().authenticate('@alice', lookUp),
          throwsA(isA<UnAuthenticatedException>()
              .having((e) => e.message, 'message', contains('@alice'))));
    });
  });
}
