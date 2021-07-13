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
      var response = DefaultResponseParser().parse('error:AT-1234:Test Exception');
      expect(response.isError, true);
      expect(response.errorCode, 'AT-1234');
      expect(response.errorDescription, 'Test Exception');
    });

    test('test error response with error code only', () {
      var response = DefaultResponseParser().parse('error:AT-1234');
      expect(response.isError, true);
      expect(response.errorCode, 'AT-1234');
      expect(response.errorDescription, '');
    });

    test('test error response without error code', () {
      var response = DefaultResponseParser().parse('error:Exception');
      expect(response.isError, true);
      expect(response.errorDescription, 'Exception');
    });

    test('test random response string', () {
      var response = DefaultResponseParser().parse('this is some random text');
      expect(response.isError, false);
      expect(response.response, 'this is some random text');
    });

  });
}
