import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:test/test.dart';
import 'package:at_commons/at_commons.dart';

void main() {
  group('A group of test related to validation of atKey', () {
    test('A test to verify atKey with spaces throws error', () {
      expect(
          () => AtClientValidation.validateKey('phone wavi'),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == 'Key cannot contain whitespaces')));
    });

    test('A test to verify atKey with @ throws error', () {
      expect(
          () => AtClientValidation.validateKey('phone@wavi'),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException && e.message == 'Key cannot contain @')));
    });

    test('A test to verify atKey with space throws error', () {
      expect(
          () => AtClientValidation.validateKey(''),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == 'Key cannot be null or empty')));
    });
  });

  test('Verify empty atsign throws exception', () async {
    var atSign = '';
    final namespace = 'test';
    final preference = AtClientPreference();
    expect(() async => await AtClientManager.getInstance().setCurrentAtSign(atSign, namespace, preference),
        throwsA(predicate((dynamic e) => e is InvalidAtSignException)));
  });
}
