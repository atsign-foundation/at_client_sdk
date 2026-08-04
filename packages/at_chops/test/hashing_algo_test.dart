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

  group('name is the pkam:/envelope wire identifier for this algorithm', () {
    test('SHA256HashingAlgo', () {
      expect(SHA256HashingAlgo().name, equals(HashingAlgoType.sha256.name));
    });

    test('SHA512HashingAlgo', () {
      expect(SHA512HashingAlgo().name, equals(HashingAlgoType.sha512.name));
    });

    test('Md5HashingAlgo', () {
      expect(Md5HashingAlgo().name, equals(HashingAlgoType.md5.name));
    });

    test('Argon2idHashingAlgo', () {
      expect(Argon2idHashingAlgo().name, equals(HashingAlgoType.argon2id.name));
    });

    test('DefaultHash inherits Md5HashingAlgo.name', () {
      // ignore: deprecated_member_use_from_same_package
      expect(DefaultHash().name, equals(HashingAlgoType.md5.name));
    });

    test('round-trips through HashingAlgoType.values.byName', () {
      // envelope_signing.dart writes hashingAlgoType.name into the wire and
      // reads it back with HashingAlgoType.values.byName — algo.name must
      // feed that same round trip.
      final algos = <AtHashingAlgorithm>[
        SHA256HashingAlgo(),
        SHA512HashingAlgo(),
        Md5HashingAlgo(),
        Argon2idHashingAlgo(),
      ];
      for (final algo in algos) {
        expect(
            HashingAlgoType.values.byName(algo.name).name, equals(algo.name));
      }
    });
  });
}
