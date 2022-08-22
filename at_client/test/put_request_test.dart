import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:test/test.dart';

void main() {
  group('A group of test to validate metadata', () {
    test('A test to verify invalid TTL value throws exception', () {
      var atKey = (AtKey.shared('@bob:phone@alice', namespace: 'wavi')
            ..timeToLive(-1)
            ..sharedWith('@bob'))
          .build();
      var value = '+91 807676754';
      var atClientPreference = AtClientPreference();
      expect(
          () => AtClientValidation.validatePutRequest(
              atKey, value, atClientPreference),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTL value: -1. TTL value cannot be less than 0')));
    });

    test('A test to verify invalid TTB value throws exception', () {
      var atKey = (AtKey.shared('@bob:phone@alice', namespace: 'wavi')
            ..timeToBirth(-1)
            ..sharedWith('@bob'))
          .build();
      var value = '+91 807676754';
      var atClientPreference = AtClientPreference();
      expect(
          () => AtClientValidation.validatePutRequest(
              atKey, value, atClientPreference),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTB value: -1. TTB value cannot be less than 0')));
    });

    test('A test to verify invalid TTR value throws exception', () {
      var atKey = (AtKey.shared('@bob:phone@alice', namespace: 'wavi')
            ..cache(-2, true)
            ..sharedWith('@bob'))
          .build();
      var value = '+91 807676754';
      var atClientPreference = AtClientPreference();
      expect(
          () => AtClientValidation.validatePutRequest(
              atKey, value, atClientPreference),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTR value: -2. valid values for TTR are -1 and greater than or equal to 1')));
    });
  });
}
