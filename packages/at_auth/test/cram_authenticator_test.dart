import 'dart:math';

import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/fake_cram_at_server.dart';
import 'test_utils/holds_none_of.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

void main() {
  group('CramAuthenticator tests', () {
    late CramAuthenticator cramAuthenticator;
    late MockAtLookupImpl mockAtLookup;
    final String atSign = '@alice';
    final String cramSecret = 'testCramSecret';

    setUp(() {
      mockAtLookup = MockAtLookupImpl();
      cramAuthenticator = CramAuthenticator();
    });

    test('authenticate() should return a successful AtAuthResponse', () async {
      when(() => mockAtLookup.cramAuthenticate(cramSecret))
          .thenAnswer((_) async => true);

      final result = await cramAuthenticator.authenticate(
          atSign, cramSecret, mockAtLookup);

      expect(result, isTrue);
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
  });

  group('Given an atSign and its CRAM secret', () {
    test(
        'when the atServer refuses CRAM authentication, then the exception '
        'names the atSign and the atServer\'s reason, and its text doesn\'t '
        'contain the secret', () async {
      final random = Random.secure();
      final atSign = '@cram${random.nextInt(1 << 32)}';
      final secret =
          List.generate(128, (_) => random.nextInt(16).toRadixString(16))
              .join();
      final reason =
          'error:AT0401-Exception: refused ${random.nextInt(1 << 32)}';
      final atServer = FakeCramAtServer(atSign, cramReply: reason);
      final atLookUp = atServer.lookUp();
      addTearDown(atLookUp.close);

      final thrown = await CramAuthenticator()
          .authenticate(atSign, secret, atLookUp)
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect('$thrown', holdsNoneOf(secret),
          reason: 'the exception holds none of the secret');
      final cram = atServer.written.where((c) => c.startsWith('cram:'));
      expect(cram, hasLength(1),
          reason: 'the refusal answers the one cram: the client sent');
      expect('$thrown', holdsNoneOf(cram.single.substring('cram:'.length)),
          reason: 'the exception holds none of the digest');
      expect(thrown, isA<UnAuthenticatedException>());
      expect('$thrown', contains(atSign));
      expect('$thrown', contains(reason));
    });
  });
}
