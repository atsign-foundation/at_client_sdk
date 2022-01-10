import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/decryption_service/local_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of test to validate the encryption service manager', () {
    test('Test to verify the encryption of shared key', () async {
      var currentAtSign = '@bob';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedBy = '@alice';

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<SharedKeyDecryption>());
    });

    test('Test to verify the encryption of self key', () async {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<LocalKeyDecryption>());
    });

    test('Test to verify the encryption of self key', () async {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = '_phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<SelfKeyDecryption>());
    });
  });
}
