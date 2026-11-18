import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of default response parser tests', () {
    test('test success response', () {
      var response = DefaultResponseParser().parse('data:success');
      expect(response.response, 'success');
      expect(response.isError, false);
    });

    test(
        'Given an atServer error reply in the dash, colon or JSON form, when '
        'DefaultResponseParser parses it, then it throws the exception that '
        'code stands for, carrying the reply\'s text', () {
      const replies = [
        'error:AT0015-key not found',
        'error:AT0015:key not found',
        'error:{"errorCode":"AT0015","errorDescription":"key not found"}',
      ];
      for (final reply in replies) {
        expect(
            () => DefaultResponseParser().parse(reply),
            throwsA(isA<KeyNotFoundException>()
                .having((e) => e.message, 'message', 'key not found')),
            reason: reply);
      }
    });

    test(
        'Given an atServer error reply in the dash, colon or JSON form, when '
        'parseFailureResponse reads it, then the response carries its code '
        'and text', () {
      const replies = [
        'error:AT0015-key not found',
        'error:AT0015:key not found',
        'error:{"errorCode":"AT0015","errorDescription":"key not found"}',
      ];
      for (final reply in replies) {
        final response = AtResponse();
        expect(
            () => DefaultResponseParser().parseFailureResponse(reply, response),
            throwsA(isA<KeyNotFoundException>()),
            reason: reply);
        expect(response.isError, isTrue, reason: reply);
        expect(response.errorCode, 'AT0015', reason: reply);
        expect(response.errorDescription, 'key not found', reason: reply);
      }
    });

    test(
        'Given a bare code, when DefaultResponseParser parses it, then it '
        'throws the exception that code stands for', () {
      expect(() => DefaultResponseParser().parse('error:AT0015'),
          throwsA(isA<KeyNotFoundException>()));
    });

    test('test errors with unexpected response', () {
      expect(
          () =>
              DefaultResponseParser().parse('error:Unexpected response found'),
          throwsA(isA<AtException>().having((e) => e.message, 'message',
              contains('Unexpected response found'))));
    });

    test('test random response string', () {
      var response = DefaultResponseParser().parse('this is some random text');
      expect(response.isError, false);
      expect(response.response, 'this is some random text');
    });
  });
}
