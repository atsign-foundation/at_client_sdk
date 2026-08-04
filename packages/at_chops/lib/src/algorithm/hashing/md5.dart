import 'package:at_chops/src/algorithm/hashing/types.dart';
import 'package:crypto/crypto.dart';

import '../algo_type.dart';
import '../at_algorithm.dart';

class Md5HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String get name => HashingAlgoType.md5.name;

  @override
  String hash(List<int> data, {HashParams? hashParams}) {
    return md5.convert(data).toString();
  }
}
