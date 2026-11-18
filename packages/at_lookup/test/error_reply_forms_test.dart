import 'dart:async';
import 'dart:convert';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/error_reply_forms.feature
void main() {
  late FakeAtServerTransportFactory transports;
  late MockSecondaryAddressFinder addressFinder;

  setUp(() {
    transports = FakeAtServerTransportFactory();
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress('127.0.0.1', 12345));
  });

  /// What an authenticated `llookup:` throws when the atServer answers it
  /// with [reply], framed as an atServer frames it: the reply's line, then
  /// the prompt for the next command.
  Future<Object> thrownFor(String reply) async {
    final atLookup = AtLookUp.withTransport(
      atSign: '@alice',
      rootDomain: const AtRootDomain('127.0.0.1', 64),
      authenticator: (_) async => true,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: transports),
    );
    final llookup = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice');
    final opened = transports.created.length;
    final verb = atLookup
        .executeVerb(llookup)
        .then<Object?>((_) => null, onError: (Object e) => e);
    for (var i = 0;
        i < 100 &&
            (transports.created.length == opened ||
                !transports.last.written.contains('llookup:phone@alice\n'));
        i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(transports.created, hasLength(opened + 1),
        reason: 'the control: this lookup opened its own connection');
    expect(transports.last.written, ['llookup:phone@alice\n'],
        reason: 'the control: the verb reached the atServer');
    await transports.last.serverSends('$reply\n@alice@');
    final thrown = await verb.timeout(const Duration(seconds: 5));
    await atLookup.close();
    return thrown ?? fail('the verb answered $reply succeeded');
  }

  test('A colon-form reply is read as its code', () async {
    const replies = {
      'error:AT0027:The enrollment id: '
          '9821c174-cd2a-4a96-b3a9-ea4eb8e13db9 is revoked': (
        'AT0027',
        'The enrollment id: 9821c174-cd2a-4a96-b3a9-ea4eb8e13db9 '
            'is revoked'
      ),
      'error:AT0028:enrollment_id: abc is expired or invalid': (
        'AT0028',
        'enrollment_id: abc is expired or invalid'
      ),
    };
    for (final MapEntry(key: reply, value: (code, text)) in replies.entries) {
      expect(
          await thrownFor(reply),
          isA<AtLookUpException>()
              .having((e) => e.errorCode, 'errorCode', code)
              .having((e) => e.errorMessage, 'errorMessage', text),
          reason: 'the code and the text after the colon of $reply');
    }
  });

  test('A dash-form or JSON reply is read as its code', () async {
    final replies = [
      'error:AT0015-key not found',
      'error:${jsonEncode({
            'errorCode': 'AT0015',
            'errorDescription': 'key not found'
          })}',
    ];
    for (final reply in replies) {
      expect(
          await thrownFor(reply),
          isA<AtLookUpException>()
              .having((e) => e.errorCode, 'errorCode', 'AT0015')
              .having((e) => e.errorMessage, 'errorMessage', 'key not found'),
          reason: 'the code and text of $reply');
    }
  });

  test('A reply with no code at its head is an unknown error', () async {
    const bodies = [
      'no route to the atServer',
      'no route - try again',
      'Exception: AT0015-key not found',
    ];
    for (final body in bodies) {
      expect(
          await thrownFor('error:$body'),
          isA<AtLookUpException>()
              .having((e) => e.errorCode, 'errorCode', 'AT0014')
              .having((e) => e.errorMessage, 'errorMessage', contains(body)),
          reason: 'error:$body names no code at its head');
    }
  });

  group('errorResponseException', () {
    test('reads a code followed by nothing as that code, with no text', () {
      expect(
          errorResponseException('error:AT0015'),
          isA<AtLookUpException>()
              .having((e) => e.errorCode, 'errorCode', 'AT0015')
              .having((e) => e.errorMessage, 'errorMessage', ''));
    });

    test('reads a JSON object with a string errorCode and no description', () {
      expect(
          errorResponseException('error:{"errorCode":"AT0015"}'),
          isA<AtLookUpException>()
              .having((e) => e.errorCode, 'errorCode', 'AT0015')
              .having((e) => e.errorMessage, 'errorMessage', ''));
    });

    const unknown = {
      'an empty body': '',
      'a dash with no code before it': '-key not found',
      'a code of five digits': 'AT00151-key not found',
      'a code in lower case': 'at0015-key not found',
      'a code with a space before it': ' AT0015-key not found',
      'a code followed by neither dash nor colon': 'AT0015 key not found',
      'JSON that is not an object': '["AT0015","key not found"]',
      'a JSON string': '"AT0015-key not found"',
      'a JSON object with no errorCode': '{"errorDescription":"key not found"}',
      'a JSON object whose errorCode is not a string':
          '{"errorCode":15,"errorDescription":"key not found"}',
      'malformed JSON': '{"errorCode":"AT0015",',
    };
    unknown.forEach((shape, body) {
      test('reads $shape as AT0014, holding the body', () {
        expect(
            errorResponseException('error:$body'),
            isA<AtLookUpException>()
                .having((e) => e.errorCode, 'errorCode', 'AT0014')
                .having((e) => e.errorMessage, 'errorMessage', contains(body)));
      });
    });

    group('Given a body that names no code', () {
      unknown.forEach((shape, body) {
        test('when it is $shape, then errorResponseCode reads none', () {
          expect(errorResponseCode('error:$body'), isNull);
        });
      });
    });

    test(
        'Given each form an atServer writes, when errorResponseCode reads '
        'it, then it reads the code errorResponseException throws', () {
      const replies = {
        'error:AT0027:enrollment_id: e-1 is revoked': 'AT0027',
        'error:AT0015-key not found': 'AT0015',
        'error:AT0015': 'AT0015',
        'error:{"errorCode":"AT0401","errorDescription":"refused"}': 'AT0401',
        'error:{"errorCode":"AT0015"}': 'AT0015',
      };
      replies.forEach((reply, code) {
        expect(errorResponseCode(reply), code, reason: reply);
        expect(errorResponseException(reply).errorCode, code, reason: reply);
      });
    });

    test(
        'Given a reply that is not an error: reply, when errorResponseCode '
        'reads it, then it reads none', () {
      for (final reply in [
        'data:AT0015-key not found',
        'AT0015-key not found',
        ' error:AT0015-key not found',
      ]) {
        expect(errorResponseCode(reply), isNull, reason: reply);
      }
    });
  });

  test(
      'Given an authenticator that throws, when executeVerb wraps what it '
      'threw, then the wrapper keeps it as its cause', () async {
    final refusal = UnAuthenticatedException(
        'Failed connecting to @alice. error:AT0027:enrollment_id: e-1 is '
        'revoked');
    final atLookup = AtLookUp.withTransport(
      atSign: '@alice',
      rootDomain: const AtRootDomain('127.0.0.1', 64),
      authenticator: (_) async => throw refusal,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: transports),
    );
    addTearDown(atLookup.close);

    await expectLater(
        atLookup.executeVerb(LLookupVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = '@alice')),
        throwsA(isA<AtLookUpException>()
            .having((e) => e.errorCode, 'errorCode', 'AT0401')
            .having((e) => e.cause, 'cause', same(refusal))));
  });
}
