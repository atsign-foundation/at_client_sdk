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

    test('A test to verify otp:put without a passcode parses, as before', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:put');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams['otp'], null);
      expect(verbParams['ttl'], null);
    });

    test('A test to verify otp:put:ttl without a passcode parses, as before',
        () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:put:ttl:100');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams['otp'], null);
      expect(verbParams['ttl'], '100');
    });

    test('A test to verify otp:put accepts an OTP longer than 6 characters',
        () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:put:abc1234');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams['otp'], 'abc1234');
    });
  });

  group('A group of tests to verify otp:list and otp:delete regex', () {
    test('A test to verify otp:list regex', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:list');
      expect(verbParams[AtConstants.operation], 'list');
      expect(verbParams['otp'], null);
    });

    test('A test to verify otp:list does not accept a passcode', () {
      expect(
          () => getVerbParams(VerbSyntax.otp, 'otp:list:abc123'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test('A test to verify otp:delete regex with an OTP', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:delete:ABC123');
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams['otp'], 'ABC123');
    });

    test('A test to verify otp:delete:spp regex', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:delete:spp');
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams['otp'], 'spp');
    });

    test('A test to verify otp:delete accepts an OTP longer than 6 characters',
        () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:delete:ABC1234');
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams['otp'], 'ABC1234');
    });

    test('A test to verify otp:delete:SPP names the SPP, as verbs ignore case',
        () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:delete:SPP');
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams['otp'], 'SPP');
    });

    test('A test to verify otp:delete reads spp123 as an OTP, not the SPP', () {
      Map<dynamic, dynamic> verbParams =
          getVerbParams(VerbSyntax.otp, 'otp:delete:spp123');
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams['otp'], 'spp123');
    });

    test(
        'A test to verify otp:delete throws error if otp is shorter than 6 characters',
        () {
      expect(
          () => getVerbParams(VerbSyntax.otp, 'otp:delete:abc12'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    for (final command in [
      'otp:delete',
      'otp:delete:ttl:5',
      'otp:delete:ABC123:ttl:5',
      'otp:delete:spp:ttl:5',
      'otp:list:ttl:5',
      'otp:list:spp',
      'otp:get:ABC123',
      'otp:put:spp',
      'otp:get:ttl:abc',
    ]) {
      test('A test to verify $command is refused', () {
        expect(
            () => getVerbParams(VerbSyntax.otp, command),
            throwsA(predicate((dynamic e) =>
                e is InvalidSyntaxException &&
                e.message == 'command does not match the regex')));
      });
    }
  });
}
