import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/argon2id_hashing_algo.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/default_hashing_algo.dart';
import 'package:at_commons/at_commons.dart';

/// A factory class for creating instances of different hashing algorithms
/// based on the specified [HashingAlgoType].
///
/// The [AtHashingAlgorithmFactory] class provides a static method
/// [withHashingAlgorithm] which returns the appropriate hashing algorithm
/// implementation corresponding to the provided [HashingAlgoType].
class AtHashingAlgorithmFactory {
  /// Returns an instance of [AtHashingAlgorithm] based on the provided [HashingAlgoType].
  ///
  /// The method supports the following hashing algorithms:
  /// - [HashingAlgoType.md5]: returns an instance of [DefaultHash] (MD5 hashing).
  /// - [HashingAlgoType.argon2id]: returns an instance of [Argon2idHashingAlgo] (Argon2id hashing).
  ///
  /// Throws an [AtException] if an unsupported hashing algorithm is passed.
  static AtHashingAlgorithm withHashingAlgorithm(HashingAlgoType algoType) {
    switch (algoType) {
      case HashingAlgoType.argon2id:
        return Argon2idHashingAlgo();
      case HashingAlgoType.sha512:
        return SHA512HashingAlgo();
      default:
        throw AtException('Unsupported hashing algorithm');
    }
  }
}
