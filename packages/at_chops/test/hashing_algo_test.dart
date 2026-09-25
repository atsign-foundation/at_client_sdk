import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests related to hashing of the data', () {
    test('A test to verify hashing of data with SHA512', () async {
      // Independently produced by `printf 'some-data' | sha512sum`.
      expect(
          SHA512HashingAlgo().hash('some-data'.codeUnits),
          'e1c4fc67f1909e35083cc5309fcba36d274333a3c4009a94a9705273e41fc88b'
          '6189ad157551e3d39d1daa4412264d13120b6713c99d3be4d64c7df4ea7a4c7b');
    });
  });
}
