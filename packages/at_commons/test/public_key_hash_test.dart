import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify public key hash methods', () {
    test('Test to verify toJson method', () {
      final publicKeyHash = PublicKeyHash('randomhash', 'sha512');
      var toJson = publicKeyHash.toJson();
      expect(toJson[AtConstants.sharedWithPublicKeyHashValue], 'randomhash');
      expect(toJson[AtConstants.sharedWithPublicKeyHashingAlgo], 'sha512');
    });
    test('Test to verify fromJson method', () {
      var jsonMap = {};
      jsonMap[AtConstants.sharedWithPublicKeyHashValue] = 'randomhash';
      jsonMap[AtConstants.sharedWithPublicKeyHashingAlgo] = 'sha256';
      final publicKeyHash = PublicKeyHash.fromJson(jsonMap);
      expect(publicKeyHash, isNotNull);
      expect(publicKeyHash?.hash, 'randomhash');
      expect(publicKeyHash?.hashingAlgo, 'sha256');
    });
    test('Test to verify equals operator two objects equals', () {
      final publicKeyHash_1 = PublicKeyHash('randomhash', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash', 'sha512');
      expect(publicKeyHash_1 == publicKeyHash_2, true);
    });
    test('Test to verify equals operator two objects different hash', () {
      final publicKeyHash_1 = PublicKeyHash('randomhash_1', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash_2', 'sha512');
      expect(publicKeyHash_1 == publicKeyHash_2, false);
    });
    test('Test to verify equals operator two objects different hash algo', () {
      final publicKeyHash_1 = PublicKeyHash('randomhash_1', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash_2', 'sha256');
      expect(publicKeyHash_1 == publicKeyHash_2, false);
    });
    test('Test to verify hashcodes are same - two objects equals', () {
      final publicKeyHash_1 = PublicKeyHash('randomhash', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash', 'sha512');
      equals(publicKeyHash_1.hashCode, publicKeyHash_2.hashCode);
    });
    test('Test to verify hashcodes are different - two objects different hash',
        () {
      final publicKeyHash_1 = PublicKeyHash('randomhash_1', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash_2', 'sha512');
      expect(publicKeyHash_1.hashCode == publicKeyHash_2.hashCode, false);
    });
    test(
        'Test to verify hashcodes are different - two objects different hash algo',
        () {
      final publicKeyHash_1 = PublicKeyHash('randomhash_1', 'sha512');
      final publicKeyHash_2 = PublicKeyHash('randomhash_2', 'sha256');
      expect(publicKeyHash_1.hashCode == publicKeyHash_2.hashCode, false);
    });
  });
}
