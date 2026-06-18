import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/model/hash_params.dart';
import 'package:crypto/crypto.dart';

class DefaultHash implements AtHashingAlgorithm<List<int>, String> {
  @override
  String hash(List<int> data, {HashParams? hashParams}) {
    return md5.convert(data).toString();
  }
}

class SHA512HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    Digest digest = sha512.convert(data);
    return digest.toString();
  }
}

class SHA256HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    Digest digest = sha256.convert(data);
    return digest.toString();
  }
}
