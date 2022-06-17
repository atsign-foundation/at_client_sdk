import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference? getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

void main() {
  LocalSecondary mockLocalSecondary = MockLocalSecondary();

  AtClient mockAtClient = MockAtClient();

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

  group('A group of tests related positive scenario of encryption', () {
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

  group('A group of test to sign the public data', () {
    test('A test to verify the sign the public data', () async {
      String encryptionPrivateKey =
          'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCTauOYbRGwtdJUdIhUyRCXZggjPw2T2y8l6oo+DRb7qaeWqTruvcqmCj9lL+yCauu7VHYdzN9Gn6wQogMutl7LaNcBaDrfmyclpRGFJBuvJHazM4DAA1WZntQYkFVErihAdB+tzui+MzE7Io5av8OsfPH/mKBz7AQi8pAEOW1IoRIOKAcdX0wzuL8lXbn6dYZPejyQhT3344xElWmr6jzuxZC4sVnjIBOGiUY3Y3Nj6g4byJ1LYbyOuaYTll3lD4id0YgAoNS4M9SG8Hnyu7BH9QLLJKJTLmko2vLg/FywbHBRJhhfiwaVi4gp+G4UNHAdEhswciJHmqrQY9xoEaj5AgMBAAECggEAerzDE/SzhuJLZV/E5nqlYrhjzBzCTDlwruvw/6rcWNovG2R5Ga9RWx8rGy9khk1JSaYP1c3ulBl7JDoP1kOm90qpwJUsd2HxnQkrZiPjHNaKMbeO2c+s5IN16aG6LL2n68oDWi3sX/e1ZJvn1CzXWPSKdBl6dimqZAJ639mEYLPfEbfo2jqZpJktmpdaVvI8cgi+TSnOdLdSF+uAZzEOuG1SK7hg05SjOb4WuWT7ZmE/jipL/u7LLI77bOHkSWU8Eg2hxkAjy0x+TkYc/Gimf2SqDVsdutA3egpAX/sVHNJT8pE0u9WtFiiKlTx84ebtBmAV8K4/Kx5dBCO5G7vdtQKBgQDFa9LH9WSJJGiPJ/ngGZ4fM4FF1GbGpfvaHl2DB32LFTbNECjs/9+QQWkijJPSSUhdbNBIzm0qR8XM65vtGEUn8bIxX8OtFuRDVlTYPBjFJN0eLtPQyfguBsimQdnRdghJBdBENuwVJJHh9Hac0uiKRd+yN6i3p2XfeGcmjOBXswKBgQC/KMW7J+gzzwUJHtxJP1CEFDYtzRtirc0vK9rdLQxLtwlLGfhEXuv5jKrFUNrNFPYHEaVDeaARzdKeC/Lo5A3Sl/y7y4aF8vQei7aR56DayCKw7C5PnXYVQGF+ENvCrd6WgqiUJUTkVWdy/viTnnbWDnWZA/O4yq1g5t4x2FXmowKBgCo337CRQrmtRoruspoBAHaNriR/wqbSkiRYAAloTamzlK+PuCDOq0GPK2uPAoGi2E3aWkRnmKLFDIDBFexDF27uWfwDDbZzQcdArA4989IdCwhMXVG2D1PQcZJUXL9VbXooOxyLXjs7QdM/UypAVChVvvu+uV7k9n0uo2h0EfnPAoGBAIPiPmE8TDCKUIAVYYfLfeJSC3sX+h/fpyM3T32u2b/XHTtKRIXvM0DtcthFS1+YaZFA9FMUM4J1DS1rMwDIblzv7TcnWL1LfG8ilygctVacI4sKt3zINzK8Q0b1nJi42kvfAy2KdPhPj9q/3IIEHxrZyPpzxo+kjW/AeGXNSp6fAoGBAIs0AWG/LR1VsSw4D9/Zareo0lUr72A4awoPVRqzD70RvwT1+hC3jOxjt6tSi9fY2oSYUPx++mBd+G+CYIqBESRBLhvJLoSTKGZuQyWnJfslkZDg6ojWCXxKAv90J3QRikh/1XRtTqVqIOBBVvF72faC3Dn/jPOB/N0ggvUL1URJ';
      var putRequestTransformer = PutRequestTransformer(mockAtClient);
      var atKey = (AtKey.public('location', namespace: 'wavi')
            ..sharedBy('@alice'))
          .build();
      var value = '+91-8087656456';
      var updateVerbBuilder = await putRequestTransformer.transform(
          Tuple()
            ..one = atKey
            ..two = value,
          encryptionPrivateKey: encryptionPrivateKey);
      assert(updateVerbBuilder.dataSignature != null);
    });
  });
  group('A group of test to validate the encryption service manager', () {
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
