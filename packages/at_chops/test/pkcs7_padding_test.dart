import 'package:at_chops/src/padding/pkcs7.dart';
import 'package:at_chops/src/padding/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify pkcs7 padding', () {
    test('A test to verify padding when data length is less than block size',
        () {
      final paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 16);
      var dataString = 'Hello World';
      var unPaddedData = dataString.codeUnits;
      var paddedData = paddingAlgo.addPadding(dataString.codeUnits);
      int padValue = 5; //expected padding value
      expect(paddedData.last, padValue);
      for (int i = 1; i <= padValue; i++) {
        expect(paddedData[paddedData.length - i], padValue);
      }
      var dataAfterRemovingPadding = paddingAlgo.removePadding(paddedData);
      expect(dataAfterRemovingPadding, unPaddedData);
    });
    test('A test to verify padding when data length is equal to block size',
        () {
      final paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 16);
      var dataString = 'Hello World12345';
      var unPaddedData = dataString.codeUnits;
      var paddedData = paddingAlgo.addPadding(dataString.codeUnits);
      int padValue = 16; //expected padding value
      expect(paddedData.last, padValue);
      for (int i = 1; i <= padValue; i++) {
        expect(paddedData[paddedData.length - i], padValue);
      }
      var dataAfterRemovingPadding = paddingAlgo.removePadding(paddedData);
      expect(dataAfterRemovingPadding, unPaddedData);
    });
    test(
        'A test to verify padding when data length is one less than block size',
        () {
      final paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 16);
      var dataString = 'Hello World1234';
      var unPaddedData = dataString.codeUnits;
      var paddedData = paddingAlgo.addPadding(dataString.codeUnits);
      int padValue = 1; //expected padding value
      expect(paddedData.last, padValue);
      for (int i = 1; i <= padValue; i++) {
        expect(paddedData[paddedData.length - i], padValue);
      }
      var dataAfterRemovingPadding = paddingAlgo.removePadding(paddedData);
      expect(dataAfterRemovingPadding, unPaddedData);
    });
    test('A test to verify invalid block size', () {
      var paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = -10);
      var dataString = 'Hello World1234';
      expect(
          () => paddingAlgo.addPadding(dataString.codeUnits),
          throwsA(predicate((e) =>
              e is AtEncryptionException &&
              e.toString().contains('Block size must be between 1 and 255.'))));
      paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 0);
      expect(
          () => paddingAlgo.addPadding(dataString.codeUnits),
          throwsA(predicate((e) =>
              e is AtEncryptionException &&
              e.toString().contains('Block size must be between 1 and 255.'))));
      paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 300);
      expect(
          () => paddingAlgo.addPadding(dataString.codeUnits),
          throwsA(predicate((e) =>
              e is AtEncryptionException &&
              e.toString().contains('Block size must be between 1 and 255.'))));
    });
    test('A test to verify invalid input data to remove padding', () {
      var paddingAlgo = PKCS7Padding(PaddingParams());
      List<int> invalidInput = [];
      expect(
          () => paddingAlgo.removePadding(invalidInput),
          throwsA(predicate((e) =>
              e is AtDecryptionException &&
              e.toString().contains('Encrypted data cannot be empty'))));
    });
  });
}
