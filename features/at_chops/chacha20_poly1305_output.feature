Feature: ChaCha20-Poly1305 encryption builds its output in one buffer

  ChaCha20Poly1305Algo returns the ciphertext followed by the 16-byte tag
  from encrypt. It assembles that result by copying the ciphertext and the
  tag into one Uint8List of exactly their combined length, so the assembly
  costs one copy of the ciphertext and builds no concatenated list. With
  associated data, it returns a published test vector's ciphertext followed
  by its tag.

  Races: none arise; each call allocates its own output and shares it with
  nothing.
  Replay: none arise; the caller supplies the key and nonce, and nothing here
  changes what is issued or accepted.
  DoS: the caller supplies the plaintext. Assembling the result allocates one
  Uint8List of the plaintext's length plus 16 bytes and no concatenated list;
  the cipher's own working buffers come on top of it.
  Forgery and impersonation: none arise; the tag is computed and checked by
  the same primitives, and its place at the end of the output is pinned
  against a published test vector, so a misplaced tag fails that test, and
  fails decryption rather than passing it.

  Scenario: ChaCha20-Poly1305 encryption with associated data returns the published ciphertext followed by the tag
    Given the 256-bit key, 96-bit nonce, plaintext and associated data of a published ChaCha20-Poly1305 test vector
    When at_chops encrypts it with ChaCha20Poly1305Algo
    Then the output is the vector's ciphertext followed by its 16-byte tag

  Scenario: ChaCha20-Poly1305 encryption copies the ciphertext and tag into one buffer of exactly their length
    Given a 1000-byte plaintext, a key and a nonce
    And a cipher whose ciphertext and tag fail the test if concatenated or copied into a new list
    When at_chops encrypts it with ChaCha20Poly1305Algo using that cipher
    Then the output is the bytes ChaCha20Poly1305Algo returns with its own cipher
    And the output owns a buffer of exactly the ciphertext and tag length
