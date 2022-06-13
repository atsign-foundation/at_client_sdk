import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalSecondary extends Mock implements LocalSecondary {}

void main() {
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  group('A group of test to validate self key encryption exceptions', () {
    test(
        'A test to verify SelfKeyNotFoundException is thrown when self key is not found',
        () {
      when(() => mockLocalSecondary.getEncryptionSelfKey())
          .thenAnswer((_) => Future.value(''));

      var selfKeyEncryption =
          SelfKeyEncryption(localSecondary: mockLocalSecondary);

      expect(
          () => selfKeyEncryption.encrypt(
              AtKey.self('phone', namespace: 'wavi').build(), 'self_key_value'),
          throwsA(predicate((dynamic e) =>
              e is SelfKeyNotFoundException &&
              e.message ==
                  'Self encryption key is not set for current atSign')));
    });
  });

  group('A group of tests related positive scenario of self encryption', () {
    test(
        'A test to verify value gets encrypted when self encryption key is available',
        () async {
      var selfEncryptionKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
      var value = 'self_key_value';
      when(() => mockLocalSecondary.getEncryptionSelfKey())
          .thenAnswer((_) => Future.value(selfEncryptionKey));
      var selfKeyEncryption =
          SelfKeyEncryption(localSecondary: mockLocalSecondary);
      var encryptedData = await selfKeyEncryption.encrypt(
          AtKey.self('phone', namespace: 'wavi').build(), value);
      var response =
          EncryptionUtil.decryptValue(encryptedData, selfEncryptionKey);
      expect(response, value);
    });
  });
  group('A group of test to validate the encryption serice manager', () {
    test('Test to verify the encryption of shared key', () async {
      var currentAtSign = '@sitaram';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';

      var encryptionService = AtKeyEncryptionManager.get(atKey, currentAtSign);
      expect(encryptionService, isA<SharedKeyEncryption>());
    });

    test('Test to verify the encryption of self key', () async {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var encryptionService = AtKeyEncryptionManager.get(atKey, currentAtSign);
      expect(encryptionService, isA<SelfKeyEncryption>());
    });
  });

  group(
      'A group of test to validate the incorrect data type sent for encryption value',
      () {
    test('Throws error when encrypted value is of type Integer', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@bob'
        ..metadata = (Metadata()..isPublic = false);
      var value = 918078908676;

      var encryptionService = AtKeyEncryptionManager.get(atKey, currentAtSign);

      expect(
          () => encryptionService.encrypt(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message ==
                  'Invalid value type found: ${value.runtimeType}. Valid value type is String')));
    });
  });
}
