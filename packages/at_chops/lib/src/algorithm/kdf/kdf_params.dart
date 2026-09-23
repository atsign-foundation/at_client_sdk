/// Thrown by [KdfParams.fromJson] for an unknown `alg` or a missing or
/// mistyped field.
class UnsupportedKdfException implements Exception {
  final String message;
  UnsupportedKdfException(this.message);
  @override
  String toString() => 'UnsupportedKdfException: $message';
}

/// The parameters of a passphrase KDF, serialisable so that a stored record
/// carries the parameters it was derived with.
sealed class KdfParams {
  const KdfParams();

  /// `{'alg': 'argon2id', 'm', 't', 'p'}` or
  /// `{'alg': 'pbkdf2-sha256', 'iterations'}`.
  Map<String, Object> toJson();

  /// The inverse of [toJson]. Throws [UnsupportedKdfException] for anything
  /// else.
  static KdfParams fromJson(Map<String, Object?> json) => switch (json) {
        {'alg': 'argon2id', 'm': int m, 't': int t, 'p': int p} =>
          Argon2idParams(memoryKiB: m, iterations: t, parallelism: p),
        {'alg': 'pbkdf2-sha256', 'iterations': int iterations} =>
          Pbkdf2Sha256Params(iterations: iterations),
        _ => throw UnsupportedKdfException('not a supported KDF: $json'),
      };
}

/// Argon2id (RFC 9106) with [memoryKiB] of memory, [iterations] passes and
/// [parallelism] lanes.
final class Argon2idParams extends KdfParams {
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  const Argon2idParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  @override
  Map<String, Object> toJson() =>
      {'alg': 'argon2id', 'm': memoryKiB, 't': iterations, 'p': parallelism};

  @override
  bool operator ==(Object other) =>
      other is Argon2idParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);
}

/// PBKDF2 with HMAC-SHA256 (RFC 8018) over [iterations] rounds.
final class Pbkdf2Sha256Params extends KdfParams {
  final int iterations;

  const Pbkdf2Sha256Params({required this.iterations});

  @override
  Map<String, Object> toJson() =>
      {'alg': 'pbkdf2-sha256', 'iterations': iterations};

  @override
  bool operator ==(Object other) =>
      other is Pbkdf2Sha256Params && other.iterations == iterations;

  @override
  int get hashCode => iterations.hashCode;
}
