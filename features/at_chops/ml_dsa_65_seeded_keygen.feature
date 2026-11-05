Feature: at_chops derives an ML-DSA-65 key pair from a 32-byte seed

  at_chops 3.8.0 adds keyPairFromSeed to both ML-DSA-65 backends (pure Dart
  and OpenSSL FFI) through AtSeededSignatureAlgorithm, and types AtPqc.mlDsa65
  as one. A caller can persist the 32-byte seed (FIPS 204 xi) and rebuild the
  same key pair from it on either backend.

  Races: none arise; keyPairFromSeed is a pure function of the seed and sets
  no state on the algorithm.
  Replay: none arise; nothing here changes what an atServer issues or
  accepts.
  DoS: none arise; a wrong-length seed is refused before any key work.
  Forgery and impersonation: the seed is the private key. Whoever holds it
  rebuilds the secret key and signs, PKAM included, as the enrollment it
  belongs to. It must be 32 secret, uniformly random bytes, never a constant;
  a seed taken from other key material, such as a passkey PRF output, first
  goes through a KDF with a label of its own so the same bytes never seed
  another key. The FFI backend hands the seed to OpenSSL by reference, so
  at_chops zeroes and frees the buffer it passed; the EVP_PKEY OpenSSL builds
  keeps its own copy, which EVP_PKEY_free clears.

  Scenario: Every ACVP keyGen vector derives its key pair
    Given the 25 ACVP ML-DSA-65 keyGen vectors
    When keyPairFromSeed runs on each seed, on the pure Dart backend, the FFI backend, and AtPqc.mlDsa65
    Then each returns the vector's public key and secret key

  Scenario: Both backends derive the same key pair
    Given a random 32-byte seed
    When MlDsa65PureDartAlgo and MlDsa65FfiAlgo each run keyPairFromSeed on it
    Then both return the same public key and secret key
    And a signature from one verifies with the other

  Scenario: newSeed returns a seed the backend accepts
    Given any ML-DSA-65 backend, or AtPqc.mlDsa65
    When newSeed runs twice
    Then each result is 32 bytes and keyPairFromSeed accepts it
    And the two results differ

  Scenario: A seed of the wrong length is refused
    Given a seed of 0, 31, 33 or 64 bytes
    When keyPairFromSeed runs on either backend
    Then it throws an ArgumentError named seed
