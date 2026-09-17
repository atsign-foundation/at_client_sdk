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
  ///
  /// **The defaults on this class are pinned for backward compatibility, not
  /// recommended.** They sit below OWASP's current Argon2id floor, and every
  /// key file already written derived its key with them, so changing them here
  /// would make those files undecryptable. Use [ArgonHashParams.owaspMinimum]
  /// for anything new.
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

  /// The Argon2id salt.
  ///
  /// When null, [Argon2idHashingAlgo] falls back to using the password's own
  /// UTF-16 code units as the salt. That fallback exists solely to keep key
  /// files written before this field was added readable — it makes derivation
  /// deterministic, so the same passphrase always yields the same key and one
  /// precomputation table serves every user who chose it. **Always supply a
  /// unique random salt for new material.**
  List<int>? salt;

  ArgonHashParams();

  /// OWASP's current minimum for Argon2id: 19456 KiB of memory, 2 iterations
  /// and a parallelism of 1.
  ///
  /// [salt] is still the caller's responsibility and must be unique per
  /// derivation.
  ArgonHashParams.owaspMinimum({this.salt}) {
    memory = 19456;
    iterations = 2;
    parallelism = 1;
  }
}

class DefaultHashParams extends HashParams {}
