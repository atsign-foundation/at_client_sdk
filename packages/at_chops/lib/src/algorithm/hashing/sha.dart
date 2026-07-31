import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/hashing/types.dart';
import 'package:crypto/crypto.dart';

class SHA512HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  HashingAlgoType get hashingAlgoType => HashingAlgoType.sha512;

  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    Digest digest = sha512.convert(data);
    return digest.toString();
  }
}

class SHA256HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  HashingAlgoType get hashingAlgoType => HashingAlgoType.sha256;

  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    Digest digest = sha256.convert(data);
    return digest.toString();
  }
}
