import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/hex.dart';
import 'package:at_chops/src/hashing/types.dart';
import 'package:pointycastle/digests/md5.dart';

import '../at_algorithm.dart';

class Md5HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String get name => HashingAlgoType.md5.name;
  @override
  String hash(List<int> data, {HashParams? hashParams}) {
    return hexEncode(MD5Digest().process(Uint8List.fromList(data)));
  }
}
