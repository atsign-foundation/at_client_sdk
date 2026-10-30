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
      when(() => mockAtLookup.pkamAuthenticate()).thenAnswer((_) async => true);

      final result = await cramAuthenticator.authenticate(
          atSign, cramSecret, mockAtLookup);

      expect(result, isTrue);
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate())
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await cramAuthenticator.authenticate(
              atSign, cramSecret, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });

  group('Given a lookup holding an authenticator of its own', () {
    for (final (outcome, reply) in [
      ('accepts', 'data:success'),
      ('refuses', 'error:AT0401-Exception: refused'),
    ]) {
      test(
          'when the atServer $outcome CRAM authentication, then the lookup '
          'holds its own authenticator again', () async {
        final atServer = FakeCramAtServer('@alice', cramReply: reply);
        final atLookUp = atServer.lookUp();
        addTearDown(atLookUp.close);
        Future<bool> held(AtCommandExecutor executor) async => true;
        atLookUp.authenticator = held;

        await CramAuthenticator()
            .authenticate('@alice', 'secret', atLookUp)
            .then<Object?>((result) => result, onError: (Object e) => e);

        expect(
            atServer.written.where((c) => c.startsWith('cram:')), hasLength(1),
            reason: 'the control: the CRAM handshake ran');
        expect(atLookUp.authenticator, same(held),
            reason: 'a CRAM secret authenticates the one connection it was '
                'given for, not every connection the lookup opens later');
      });
    }
  });

  group('Given a CRAM authentication running on a lookup', () {
    test(
        'when a second starts on the same lookup, then it fails and the '
        'lookup gets back the authenticator it held', () async {
      final atServer = FakeCramAtServer('@alice', cramReply: 'data:success');
      final atLookUp = atServer.lookUp();
      addTearDown(atLookUp.close);
      Future<bool> held(AtCommandExecutor executor) async => true;
      atLookUp.authenticator = held;

      final first =
          CramAuthenticator().authenticate('@alice', 'secret', atLookUp);
      await expectLater(
          CramAuthenticator().authenticate('@alice', 'secret', atLookUp),
          throwsA(isA<StateError>()));
      expect(await first, isTrue);

      expect(atServer.written.where((c) => c.startsWith('cram:')), hasLength(1),
          reason: 'only the first CRAM handshake ran');
      expect(atLookUp.authenticator, same(held));
    });

    test(
        'when the caller installs another authenticator meanwhile, then that '
        'one is kept', () async {
      final atServer = FakeCramAtServer('@alice', cramReply: 'data:success');
      final atLookUp = atServer.lookUp();
      addTearDown(atLookUp.close);
      Future<bool> held(AtCommandExecutor executor) async => true;
      Future<bool> installed(AtCommandExecutor executor) async => true;
      atLookUp.authenticator = held;

      final running =
          CramAuthenticator().authenticate('@alice', 'secret', atLookUp);
      atLookUp.authenticator = installed;
      expect(await running, isTrue);

      expect(atLookUp.authenticator, same(installed));
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
