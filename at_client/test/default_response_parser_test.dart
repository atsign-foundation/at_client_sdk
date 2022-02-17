import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:test/test.dart';

void main() {
  group('A group of default response parser tests', () {
    test('test success response', () {
      var response = DefaultResponseParser().parse('data:success');
      expect(response.response, 'success');
      expect(response.isError, false);
    });

    test('test error response', () {
      expect(
          () => DefaultResponseParser().parse('error:AT1234-Test Exception'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException && e.errorMessage == 'Test Exception')));
    });

    test('test errors with unexpected response', () {
      expect(
          () => DefaultResponseParser().parse('error:Unexpected response found'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException && e.errorCode == 'AT0014')));
    });

    test('test error response without error code', () {
      expect(() => DefaultResponseParser().parse('error:Exception'),
          throwsA(predicate((dynamic e) => e is AtClientException)));
    });

    test('test random response string', () {
      var response = DefaultResponseParser().parse('this is some random text');
      expect(response.isError, false);
      expect(response.response, 'this is some random text');
    });
  });
}
