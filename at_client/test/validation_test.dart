import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The tests emphasis on validating the negative scenarios of AtClient methods
void main() {
  group('A group of tests to validate the negative scenarios of put method',
      () {
    test('A test to validate invalid type passed to put method', () async {
      var atClientImpl =
          await AtClientImpl.create('@bob', 'wavi', AtClientPreference());
      expect(
          () => atClientImpl.put(
              AtKey.public('phone', namespace: 'wavi', sharedBy: '@bob')
                  .build(),
              []),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.errorMessage ==
                  'Invalid value type found List<dynamic>. Expected String or List<int>')));
    });

    test('A test to validate cached key passed to put method', () async {
      var atClientImpl =
          await AtClientImpl.create('@bob', 'wavi', AtClientPreference());
      expect(
          () => atClientImpl.put(
              AtKey()
                ..key = 'phone'
                ..sharedWith = '@alice'
                ..metadata = (Metadata()..isCached = true),
              '+91 984822334'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.errorMessage == 'User cannot create a cached key')));
    });
  });
}
