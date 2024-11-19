import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests related to hashing of the data', () {
    test('A test to verify hashing of data with SHA512', () async {
      String hashedValue =
          await AtChops.hashWith(HashingAlgoType.sha512).hash('some-data'.codeUnits);
      expect(hashedValue.isNotNullOrEmpty, true);
    });
  });
}
