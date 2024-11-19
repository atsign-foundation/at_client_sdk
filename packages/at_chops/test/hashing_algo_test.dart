import 'package:at_chops/at_chops.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests related to hashing of the data', () {
    test('A test to verify hashing of data with SHA512', () async {
      String expectedHashValue = await AtChops.hashWith(HashingAlgoType.sha512)
          .hash('some-data'.codeUnits);
      String actualHashValue = sha512.convert('some-data'.codeUnits).toString();
      expect(expectedHashValue, actualHashValue);
    });
  });
}
