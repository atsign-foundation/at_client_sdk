import 'package:at_commons/at_commons.dart';

enum SigningAlgoType {
  // Not lowerCamelCase on purpose, and the ignore has to sit on this line
  // rather than on the enum: the MEMBER NAME is the wire literal. It is what
  // `pkam:signingAlgo:ecc_secp256r1:hashingAlgo:sha256:...` carries, so
  // renaming it to `eccSecp256r1` would change the protocol, not the style.
  // ignore: constant_identifier_names
  ecc_secp256r1,
  rsa2048,
  rsa4096,
  ed25519,
  mldsa65;

  /// Every signing algorithm, strongest first — the order a verifier uses to
  /// choose which of several signatures to check.
  ///
  /// **Declaration order is not this order**, deliberately: the members above
  /// are in the order they were added, and reordering them would be a wire
  /// change wherever an index is persisted. This is a separate statement about
  /// preference, and it is here rather than in a consumer because a verifier
  /// and a signer that disagreed about "strongest" would negotiate against
  /// themselves.
  ///
  /// [mldsa65] is first and the gap to second place is not a matter of degree:
  /// it is the only member Shor's algorithm does not break, so no classical
  /// parameter size promotes anything above it. The rest are ranked by
  /// classical security level — RSA-4096 at roughly 150 bits, the two
  /// 128-bit curves, then RSA-2048 at roughly 112 — with [ed25519] above
  /// [ecc_secp256r1] on the tiebreak, being deterministic and the harder of the
  /// two to misuse.
  ///
  /// This is **this project's preference order**, not a universal ranking, and
  /// it is a total order on purpose: a partial one leaves the choice undefined
  /// for exactly the pair nobody thought about. A new member that is not placed
  /// here fails the completeness pin in `test/signing_strength_test.dart`.
  static const List<SigningAlgoType> strongestFirst = [
    mldsa65,
    rsa4096,
    ed25519,
    ecc_secp256r1,
    rsa2048,
  ];

  /// The strongest of [candidates] by [strongestFirst], or null if it is empty.
  ///
  /// A verifier picks with this and then verifies **only** that signature,
  /// refusing outright if it fails. Trying a weaker one after a failure hands
  /// the choice of algorithm to whoever tampered with the envelope, and reads
  /// as success in every log.
  static SigningAlgoType? strongestOf(Iterable<SigningAlgoType> candidates) {
    for (final algo in strongestFirst) {
      if (candidates.contains(algo)) return algo;
    }
    return null;
  }
}

enum HashingAlgoType {
  sha256,
  sha512,
  md5,
  argon2id;

  static HashingAlgoType fromString(String name) {
    return HashingAlgoType.values.firstWhere(
        (algo) => algo.name == name.toLowerCase(),
        orElse: () => throw AtException('Invalid hashing algo type'));
  }
}
