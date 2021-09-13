import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of update builder tests', () {
    test('test non public key', () {
      var builder = UpdateVerbBuilder()..atKey = 'privatekey:at_pkam_privatekey';
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, 'privatekey:at_pkam_privatekey');
    });

    test('test public key', () {
      var builder = UpdateVerbBuilder()
        ..isPublic = true
        ..atKey = 'phone'
        ..sharedBy = 'alice';
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, 'public:phone@alice');
    });

    test('test key sharedwith another atsign', () {
      var builder = UpdateVerbBuilder()
        ..sharedWith = 'bob'
        ..atKey = 'phone'
        ..sharedBy = 'alice';
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, '@bob:phone@alice');
    });
  });

  group('A group of validation tests', () {
    test('test validating invalid AtKey.key', () async {
      AtKey atKey = AtKey()
        ..key = 'ph one'
        ..sharedBy = '@alice'
        ..namespace = 'me'
        ..metadata = null;
      // preferences: AtClientManager.getInstance().atClient.getPreferences());
      expect(
        () async => AtClientValidation.validateAtKey(atKey, '@alice'),
        throwsA(
          predicate(
            (dynamic e) =>
                e is AtClientException && e.errorMessage == 'Key cannot contain whitespaces' && e.errorCode == 'AT0023',
          ),
        ),
      );
    });
    test('test validating invalid sharedWith', () async {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..namespace = 'me'
        ..metadata = null;
      // preferences: AtClientManager.getInstance().atClient.getPreferences());
      expect(
        () async => AtClientValidation.validateAtSign(atKey.sharedWith, null, null),
        throwsA(
          predicate(
            (dynamic e) =>
                (e is InvalidAtSignException && e.message == '@sign cannot be null or empty') ||
                (e is AtServerException && e.message == 'rootDomain and rootPort cannot be null'),
          ),
        ),
      );
    });
    test('test validating Namespace', () async {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = null;
      expect(
        () async => AtClientValidation.validateAtKey(atKey, '@alice'),
        throwsA(
          predicate(
            (dynamic e) =>
                e is AtNamespaceException &&
                e.errorMessage == 'Namespace cannot be null or empty' &&
                e.errorCode == 'AT0026',
          ),
        ),
      );
    });
    test('test validating Metadata invalid  TTL', () async {
      Metadata _metadata = Metadata()..ttl = -1;
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..namespace = 'me'
        ..metadata = _metadata;
      expect(
        () async => AtClientValidation.validateAtKey(atKey, '@alice'),
        throwsA(
          predicate(
            (dynamic e) =>
                e is AtKeyException &&
                e.errorMessage == 'Invalid TTL value: -1. TTL value cannot be less than 0' &&
                e.errorCode == 'AT0023',
          ),
        ),
      );
    });
    test('test validating Metadata invalid  TTB', () async {
      Metadata _metadata = Metadata()..ttb = -1;
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..namespace = 'me'
        ..metadata = _metadata;
      expect(
        () async => AtClientValidation.validateAtKey(atKey, '@alice'),
        throwsA(
          predicate(
            (dynamic e) =>
                e is AtKeyException &&
                e.errorMessage == 'Invalid TTB value: -1. TTB value cannot be less than 0' &&
                e.errorCode == 'AT0023',
          ),
        ),
      );
    });
    test('test validating Metadata invalid  TTR', () async {
      Metadata _metadata = Metadata()..ttr = -2;
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..namespace = 'me'
        ..metadata = _metadata;
      expect(
        () async => AtClientValidation.validateAtKey(atKey, '@alice'),
        throwsA(
          predicate(
            (dynamic e) =>
                e is AtKeyException &&
                e.errorMessage == 'Invalid TTR value: -2. valid values for TTR are -1 and greater than or equal to 1' &&
                e.errorCode == 'AT0023',
          ),
        ),
      );
    });
  });
  group('A group of get secondary info tests', () {
    test('get secondary url and port', () {
      var url = 'atsign.com:6400';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo[0], 'atsign.com');
      expect(secondaryInfo[1], '6400');
    });

    test('url is null', () {
      var url;
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });

    test('url is empty', () {
      var url = '';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });
  });
}
