import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'syntax_test.dart';

void main() {
  group('A group of tests related to OTP verb syntax', () {
    test('A test to verify otp:get regex', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, "otp:get");
      expect(verbParams[AtConstants.operation], "get");
      expect(verbParams['ttl'], null);
      expect(verbParams['otp'], null);
    });

    test('A test to verify otp:get regex with TTL', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, "otp:get:ttl:100");
      expect(verbParams[AtConstants.operation], "get");
      expect(verbParams['ttl'], '100');
      expect(verbParams['otp'], null);
    });
  });

  group('A group of test to verify otp:put regex', () {
    test('A test to verify otp:put accepts alphanumeric characters', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:put:abc123');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams['otp'], 'abc123');
      expect(verbParams['ttl'], null);
    });

    test(
        'A test to verify otp:put throws error if otp is not 6 character length',
        () {
      expect(
          () => getVerbParams(VerbSyntax.otp, 'otp:put:abc12'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test('A test to verify otp:put with ttl', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:put:abc123:ttl:123');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams['otp'], 'abc123');
      expect(verbParams['ttl'], '123');
    });
  });
}
