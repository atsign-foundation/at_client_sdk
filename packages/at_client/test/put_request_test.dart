import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:at_chops/at_chops.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockPutRequestTransformer extends Mock implements PutRequestTransformer {}

class FakeTuple extends Fake implements Tuple<AtKey, dynamic> {}

void main() {
  AtClient mockAtClient = MockAtClient();
  final atClientPreferenceWithAtChops = AtClientPreference()
    ..namespace = 'wavi'
    ..useAtChops = true;
  final atClientPreferenceWithoutAtChops = AtClientPreference()
    ..namespace = 'wavi'
    ..useAtChops = false;

  group(
      'A group of test to validate public data encoding in put request transformer',
      () {
    var inputToExpectedOutput = {
      'A test to verify public data with \n character is encoded': {
        'isNewLineCharPresentInOutput': false,
        'encoding': 'base64',
        'isDataSignaturePresent': true
      },
      'A test to verify public data without new line character is encoded': {
        'isNewLineCharPresentInOutput': false,
        'encoding': null,
        'isDataSignaturePresent': true
      }
    };
    inputToExpectedOutput.forEach((putValue, expectedResults) {
      test(putValue, () async {
        String encryptionPrivateKey =
            'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCTauOYbRGwtdJUdIhUyRCXZggjPw2T2y8l6oo+DRb7qaeWqTruvcqmCj9lL+yCauu7VHYdzN9Gn6wQogMutl7LaNcBaDrfmyclpRGFJBuvJHazM4DAA1WZntQYkFVErihAdB+tzui+MzE7Io5av8OsfPH/mKBz7AQi8pAEOW1IoRIOKAcdX0wzuL8lXbn6dYZPejyQhT3344xElWmr6jzuxZC4sVnjIBOGiUY3Y3Nj6g4byJ1LYbyOuaYTll3lD4id0YgAoNS4M9SG8Hnyu7BH9QLLJKJTLmko2vLg/FywbHBRJhhfiwaVi4gp+G4UNHAdEhswciJHmqrQY9xoEaj5AgMBAAECggEAerzDE/SzhuJLZV/E5nqlYrhjzBzCTDlwruvw/6rcWNovG2R5Ga9RWx8rGy9khk1JSaYP1c3ulBl7JDoP1kOm90qpwJUsd2HxnQkrZiPjHNaKMbeO2c+s5IN16aG6LL2n68oDWi3sX/e1ZJvn1CzXWPSKdBl6dimqZAJ639mEYLPfEbfo2jqZpJktmpdaVvI8cgi+TSnOdLdSF+uAZzEOuG1SK7hg05SjOb4WuWT7ZmE/jipL/u7LLI77bOHkSWU8Eg2hxkAjy0x+TkYc/Gimf2SqDVsdutA3egpAX/sVHNJT8pE0u9WtFiiKlTx84ebtBmAV8K4/Kx5dBCO5G7vdtQKBgQDFa9LH9WSJJGiPJ/ngGZ4fM4FF1GbGpfvaHl2DB32LFTbNECjs/9+QQWkijJPSSUhdbNBIzm0qR8XM65vtGEUn8bIxX8OtFuRDVlTYPBjFJN0eLtPQyfguBsimQdnRdghJBdBENuwVJJHh9Hac0uiKRd+yN6i3p2XfeGcmjOBXswKBgQC/KMW7J+gzzwUJHtxJP1CEFDYtzRtirc0vK9rdLQxLtwlLGfhEXuv5jKrFUNrNFPYHEaVDeaARzdKeC/Lo5A3Sl/y7y4aF8vQei7aR56DayCKw7C5PnXYVQGF+ENvCrd6WgqiUJUTkVWdy/viTnnbWDnWZA/O4yq1g5t4x2FXmowKBgCo337CRQrmtRoruspoBAHaNriR/wqbSkiRYAAloTamzlK+PuCDOq0GPK2uPAoGi2E3aWkRnmKLFDIDBFexDF27uWfwDDbZzQcdArA4989IdCwhMXVG2D1PQcZJUXL9VbXooOxyLXjs7QdM/UypAVChVvvu+uV7k9n0uo2h0EfnPAoGBAIPiPmE8TDCKUIAVYYfLfeJSC3sX+h/fpyM3T32u2b/XHTtKRIXvM0DtcthFS1+YaZFA9FMUM4J1DS1rMwDIblzv7TcnWL1LfG8ilygctVacI4sKt3zINzK8Q0b1nJi42kvfAy2KdPhPj9q/3IIEHxrZyPpzxo+kjW/AeGXNSp6fAoGBAIs0AWG/LR1VsSw4D9/Zareo0lUr72A4awoPVRqzD70RvwT1+hC3jOxjt6tSi9fY2oSYUPx++mBd+G+CYIqBESRBLhvJLoSTKGZuQyWnJfslkZDg6ojWCXxKAv90J3QRikh/1XRtTqVqIOBBVvF72faC3Dn/jPOB/N0ggvUL1URJ';
        when(() => mockAtClient.getPreferences())
            .thenAnswer((_) => atClientPreferenceWithoutAtChops);
        var putRequestTransformer = PutRequestTransformer()
          ..atClient = mockAtClient;
        AtKey atKey =
            AtKey.public('location', namespace: 'wavi', sharedBy: '@alice')
                .build();
        var tuple = Tuple<AtKey, dynamic>()
          ..one = atKey
          ..two = putValue;
        UpdateVerbBuilder updateVerbBuilder = await putRequestTransformer
            .transform(tuple, encryptionPrivateKey: encryptionPrivateKey);
        expect(updateVerbBuilder.value.contains('\n'),
            expectedResults['isNewLineCharPresentInOutput']);
        expect(updateVerbBuilder.encoding, expectedResults['encoding']);
        expect(updateVerbBuilder.dataSignature.isNotNull,
            expectedResults['isDataSignaturePresent']);
        final dataSignatureWithoutAtChops = updateVerbBuilder.dataSignature;
        when(() => mockAtClient.getPreferences())
            .thenAnswer((_) => atClientPreferenceWithAtChops);
        final atChopsKeys = AtChopsKeys.create(
            AtEncryptionKeyPair.create('', encryptionPrivateKey), null);
        when(() => mockAtClient.atChops)
            .thenAnswer((_) => AtChopsImpl(atChopsKeys));
        putRequestTransformer = PutRequestTransformer()
          ..atClient = mockAtClient;
        updateVerbBuilder = await putRequestTransformer.transform(tuple,
            encryptionPrivateKey: encryptionPrivateKey);
        expect(updateVerbBuilder.value.contains('\n'),
            expectedResults['isNewLineCharPresentInOutput']);
        expect(updateVerbBuilder.encoding, expectedResults['encoding']);
        expect(updateVerbBuilder.dataSignature.isNotNull,
            expectedResults['isDataSignaturePresent']);
        expect(updateVerbBuilder.dataSignature, dataSignatureWithoutAtChops);
      });
    });
  });

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

  group('A group of test to validate value length', () {
    test(
        'A test to verify the exception is thrown when value exceeds the maxDataLimit',
        () async {
      registerFallbackValue(FakeTuple());
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      PutRequestTransformer mockPutRequestTransformer =
          MockPutRequestTransformer();

      AtKey atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@bob')
            ..sharedWith('@alice'))
          .build();
      var value = '+91-9876554432';
      when(() => mockPutRequestTransformer.transform(any(that: TupleMatcher())))
          .thenAnswer((_) async => UpdateVerbBuilder()..value = value);

      AtClientImpl atClientImpl = await AtClientImpl.create(
          '@bob',
          'wavi',
          AtClientPreference()
            ..isLocalStoreRequired = false
            ..maxDataSize = 1,
          remoteSecondary: mockRemoteSecondary) as AtClientImpl;
      atClientImpl.putRequestTransformer = mockPutRequestTransformer;

      expect(
          () async => await atClientImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message ==
                  'The length of value exceeds the buffer size. Maximum buffer size is 1 bytes. Found 14 bytes')));
    });
  });
}

class TupleMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description.add('test');
  }

  @override
  bool matches(item, Map matchState) {
    if (item is Tuple) {
      return true;
    }
    return false;
  }
}
