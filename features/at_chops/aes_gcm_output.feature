Feature: AES-256-GCM encryption builds its output in one buffer

  AesGcm256FfiAlgo (OpenSSL through FFI) and AesGcm256EncryptionAlgo (pure
  Dart) each return the ciphertext followed by the 16-byte tag from encrypt.
  Each assembles that result by copying the ciphertext and the tag into one
  Uint8List of exactly their combined length, so the assembly costs one copy
  of the ciphertext and builds no concatenated list.
  With the same key and nonce and no associated data, the two classes produce
  the same bytes, so each decrypts the other's output.

  Races: none arise; each call allocates its own output and shares it with
  nothing.
  Replay: none arise; the caller supplies the nonce, and nothing here changes
  what is issued or accepted.
  DoS: the caller supplies the plaintext. Assembling the result allocates one
  Uint8List of the plaintext's length plus 16 bytes and no concatenated list;
  the cipher's own working buffers, each about the plaintext's length, come
  on top of it.
  Forgery and impersonation: none arise; the tag is computed and checked by
  the same primitives, and its place at the end of the output is pinned
  against bytes computed without at_chops, so a misplaced tag fails
  decryption rather than passing it.

  Scenario: AES-256-GCM encryption returns the ciphertext followed by the tag
    Given a 1.1 MB plaintext, a key and a nonce
    When at_chops encrypts it with the FFI implementation and with the pure-Dart implementation
    Then each output is byte-identical to the ciphertext followed by the 16-byte tag
    And each implementation decrypts the other's output
