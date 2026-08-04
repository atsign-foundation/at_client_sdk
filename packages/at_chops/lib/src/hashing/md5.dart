import 'package:at_chops/src/hashing/types.dart';
import 'package:crypto/crypto.dart';

import '../at_algorithm.dart';

class Md5HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String hash(List<int> data, {HashParams? hashParams}) {
    return md5.convert(data).toString();
  }
}
