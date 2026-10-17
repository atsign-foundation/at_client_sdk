import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/hex.dart';
import 'package:at_chops/src/hashing/types.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';

class SHA512HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String get name => HashingAlgoType.sha512.name;
  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    return hexEncode(SHA512Digest().process(Uint8List.fromList(data)));
  }
}

class SHA256HashingAlgo implements AtHashingAlgorithm<List<int>, String> {
  @override
  String get name => HashingAlgoType.sha256.name;
  @override
  String hash(List<int> data, {covariant HashParams? hashParams}) {
    return hexEncode(SHA256Digest().process(Uint8List.fromList(data)));
  }
}
