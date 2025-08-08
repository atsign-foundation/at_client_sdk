import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

void main() {
  group('A group of test to validate the metadata', () {
    test('Test to validate 0 is a valid TTL value', () {
      expect(AtMetadataUtil.validateTTL('0'), 0);
    });
    test('Test to validate 0 is a valid TTB value', () {
      expect(AtMetadataUtil.validateTTB('0'), 0);
    });
    test('Test to validate positive number is a valid TTL value', () {
      expect(AtMetadataUtil.validateTTL('100'), 100);
    });
    test('Test to validate positive number is a valid TTB value', () {
      expect(AtMetadataUtil.validateTTB('100'), 100);
    });
    test('Empty string to validateTTL returns 0', () {
      expect(AtMetadataUtil.validateTTL(' '), 0);
    });
    test('Empty string to validateTTB returns 0', () {
      expect(AtMetadataUtil.validateTTB(' '), 0);
    });
  });

  group('A group of negative tests to validate metadata', () {
    test('Test to validata a negative number as TTL throws error', () {
      expect(
          () => AtMetadataUtil.validateTTL('-100'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message ==
                  'Valid value for TTL should be greater than or equal to 0')));
    });

    test('Test to validata a negative number as TTB throws error', () {
      expect(
          () => AtMetadataUtil.validateTTB('-100'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message ==
                  'Valid value for TTB should be greater than or equal to 0')));
    });

    test(
        'Test to verify validateTTL method throws error when alphabets are passed',
        () {
      expect(
          () => AtMetadataUtil.validateTTL('ABC'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message ==
                  'Valid value for TTL should be greater than or equal to 0')));
    });

    test(
        'Test to verify validateTTB method throws error when alphabets are passed',
        () {
      expect(
          () => AtMetadataUtil.validateTTB('ABC'),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message ==
                  'Valid value for TTB should be greater than or equal to 0')));
    });
  });
}
