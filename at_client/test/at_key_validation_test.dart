import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:test/test.dart';

void main() {
  group('A group of test related to validation of atKey', () {
    test('A test to verify atKey with spaces throws error', () {
      expect(
          () => AtClientValidation.validateKey('phone wavi'),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.errorMessage == 'Key cannot contain whitespaces')));
    });

    test('A test to verify atKey with @ throws error', () {
      expect(
              () => AtClientValidation.validateKey('phone@wavi'),
          throwsA(predicate((dynamic e) =>
          e is AtKeyException &&
              e.errorMessage == 'Key cannot contain @')));
    });

    test('A test to verify atKey with space throws error', () {
      expect(
              () => AtClientValidation.validateKey(''),
          throwsA(predicate((dynamic e) =>
          e is AtKeyException &&
              e.errorMessage == 'Key cannot be null or empty')));
    });
  });
}
