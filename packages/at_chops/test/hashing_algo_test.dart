import 'package:at_chops/at_chops.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests related to hashing of the data', () {
    test('A test to verify hashing of data with SHA512', () async {
      String expectedHashValue =
          SHA512HashingAlgo().hash('some-data'.codeUnits);
      String actualHashValue = sha512.convert('some-data'.codeUnits).toString();
      expect(expectedHashValue, actualHashValue);
    });
  });

  group('A group of tests related to hashing algorithm wire identifiers', () {
    final algosByType = <HashingAlgoType, AtHashingAlgorithm>{
      HashingAlgoType.sha256: SHA256HashingAlgo(),
      HashingAlgoType.sha512: SHA512HashingAlgo(),
      HashingAlgoType.md5: Md5HashingAlgo(),
      HashingAlgoType.argon2id: Argon2idHashingAlgo(),
    };

    test('Each algorithm reports the type it is keyed under', () {
      algosByType.forEach((type, algo) {
        expect(algo.hashingAlgoType, equals(type),
            reason: '${algo.runtimeType} misreports its wire identifier');
      });
    });

    test('Every HashingAlgoType has an algorithm that reports it', () {
      // A new enum member with no algorithm behind it fails here rather than
      // at the point some caller tries to resolve it.
      expect(algosByType.keys, containsAll(HashingAlgoType.values));
    });

    test('DefaultHash inherits md5 from Md5HashingAlgo', () {
      expect(DefaultHash().hashingAlgoType, equals(HashingAlgoType.md5));
    });

    test('Wire spellings match what the atServer grammar accepts', () {
      // The pkam verb regex in at_commons accepts only these two literals, so
      // a rename of either enum member must fail here rather than at auth time.
      expect(SHA256HashingAlgo().hashingAlgoType.name, equals('sha256'));
      expect(SHA512HashingAlgo().hashingAlgoType.name, equals('sha512'));
    });
  });
}
