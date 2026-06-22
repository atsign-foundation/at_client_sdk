import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/default_hashing_algo.dart';
import 'package:at_chops/src/algorithm/hashing/argon2id.dart';
import 'package:at_chops/src/algorithm/hashing/sha_hashing_algo.dart';

/// A factory class for creating instances of different hashing algorithms
/// based on the specified [HashingAlgoType].
///
/// The [AtHashingAlgorithmFactory] class provides a static method
/// [withHashingAlgorithm] which returns the appropriate hashing algorithm
/// implementation corresponding to the provided [HashingAlgoType].
@Deprecated('Instantiate hashing algorithm classes directly instead. This '
    'compatibility API will be removed in the next major release.')
class AtHashingAlgorithmFactory {
  /// Returns an instance of [AtHashingAlgorithm] based on the provided [HashingAlgoType].
  ///
  /// The method supports the following hashing algorithms:
  /// - [HashingAlgoType.md5]: returns an instance of [DefaultHash] (MD5 hashing).
  /// - [HashingAlgoType.sha256]: returns an instance of [SHA256HashingAlgo].
  /// - [HashingAlgoType.sha512]: returns an instance of [SHA512HashingAlgo].
  /// - [HashingAlgoType.argon2id]: returns an instance of [Argon2idHashingAlgo] (Argon2id hashing).
  static AtHashingAlgorithm withHashingAlgorithm(HashingAlgoType algoType) {
    switch (algoType) {
      case HashingAlgoType.argon2id:
        return Argon2idHashingAlgo();
      case HashingAlgoType.sha512:
        return SHA512HashingAlgo();
      case HashingAlgoType.sha256:
        return SHA256HashingAlgo();
      case HashingAlgoType.md5:
        return DefaultHash();
    }
  }
}
