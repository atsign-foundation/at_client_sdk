import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
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
