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
    expect(
        () async => await AtClientManager.getInstance()
            .setCurrentAtSign(atSign, namespace, preference),
        throwsA(predicate((dynamic e) => e is InvalidAtSignException)));
  });

  test('Verify namespace is mandatory for public key', () {
    AtKey atKey = AtKey.public('key_no_namespace', sharedBy: '@noname').build();
    AtClientPreference preference = AtClientPreference()..namespace = null;

    expect(
        () => AtClientValidation.validatePutRequest(
            atKey, 'dummyvalue', preference),
        throwsA(predicate((dynamic e) =>
            e is AtKeyException && e.message == 'namespace is mandatory')));
  });

  test('Verify namespace is mandatory for private key', () {
    AtKey atKey = AtKey.private('key_no_namespace1').build()
      ..sharedBy = '@noname1';
    AtClientPreference preference = AtClientPreference()..namespace = null;

    expect(
        () => AtClientValidation.validatePutRequest(
            atKey, 'dummyvalue', preference),
        throwsA(predicate((dynamic e) =>
            e is AtKeyException && e.message == 'namespace is mandatory')));
  });

  test('Verify namespace is mandatory for shared key', () {
    AtKey atKey = (AtKey.shared('key_no_namespace2', namespace: null, sharedBy: '@sharer')
          ..sharedWith('@sharee')).build();
    AtClientPreference preference = AtClientPreference()..namespace = null;

    expect(
        () => AtClientValidation.validatePutRequest(
            atKey, 'dummyvalue', preference),
        throwsA(predicate((dynamic e) =>
            e is AtKeyException && e.message == 'namespace is mandatory')));
  });

  test('Verify namespace is NOT mandatory for local key', () {
    AtKey atKey = AtKey.local('key_no_namespace3', '@sharer').build();
    AtClientPreference preference = AtClientPreference()..namespace = null;
    // validatePutRequest() has a return type of void
    // error-less execution of this method should be considered as test passing
    AtClientValidation.validatePutRequest(atKey, 'dummyvalue', preference);
  });
}
