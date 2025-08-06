/// A class that holds the parameters for configuring a hashing algorithm.
///
/// This class is used to customize the behavior of a hashing algorithm by
/// providing control over key parameters such as parallelism, memory usage,
/// iteration count, and the length of the resulting hash.
///
/// These parameters are particularly useful when working with algorithms
/// like Argon2id, which can be adjusted for performance and security needs.
abstract class HashParams {}

class ArgonHashParams extends HashParams {
  /// The degree of parallelism, representing the number of threads used during hashing.
  ///
  /// The default value is 2, meaning the hashing algorithm will use 2 threads.
  int parallelism = 2;

  /// The amount of memory (in KB) to be used during the hashing process.
  ///
  /// The default value is 10,000 KB (10 MB). Increasing the memory value
  /// can make the hashing process more resistant to brute-force attacks.
  int memory = 10000;

  /// The number of iterations (time cost) applied during the hashing process.
  ///
  /// The default value is 2. A higher iteration count increases the time
  /// required to compute the hash, providing greater security.
  int iterations = 2;

  /// The length of the resulting hash in bytes.
  ///
  /// The default value is 32 bytes. This value controls the size of the
  /// derived hash or key.
  int hashLength = 32;
}

class DefaultHashParams extends HashParams {}
