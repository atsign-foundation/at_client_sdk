import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/decryption_service/local_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of test to validate the decryption service manager', () {
    test(
        'Test to verify the SharedKeyDecryption instance is returned for shared key',
        () {
      var currentAtSign = '@bob';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedBy = '@alice';

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<SharedKeyDecryption>());
    });

    test(
        'Test to verify the LocalKeyDecryption instance is returned for local key',
        () {
      var currentAtSign = '@bob';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@bob'
        ..metadata = Metadata();

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<LocalKeyDecryption>());
    });

    test(
        'Test to verify SelfKeyDecryption instance is returned for '
        'self key when sharedWith is populated', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = '_phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<SelfKeyDecryption>());
    });

    test(
        'Test to verify SelfKeyDecryption instance is returned for '
        'self key when sharedWith is not populated', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService = AtKeyDecryptionManager.get(atKey, currentAtSign);
      expect(decryptionService, isA<SelfKeyDecryption>());
    });
  });

  group(
      'A group of tests to validate errors when empty value is passed as decrypted value',
      () {
    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - SharedKeyDecryption',
        () {
      expect(
          () => SharedKeyDecryption().decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });

    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - SelfKeyDecryption',
        () {
      expect(
          () => SelfKeyDecryption().decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });

    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - LocalKeyDecryption',
        () {
      expect(
          () => LocalKeyDecryption().decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });
  });
}
