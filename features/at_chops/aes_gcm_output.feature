Feature: AES-256-GCM encryption builds its output in one buffer

  AesGcm256FfiAlgo (OpenSSL through FFI) and AesGcm256EncryptionAlgo (pure
  Dart) each return the ciphertext followed by the 16-byte tag from encrypt.
  The FFI implementation has OpenSSL write the ciphertext and then the tag
  into one native buffer, and copies that buffer once into the Uint8List it
  returns. The pure-Dart implementation encrypts through one encrypt step,
  shared with ChaCha20Poly1305Algo, which copies the cipher's ciphertext and
  tag into one Uint8List of exactly their combined length. Either way the
  assembly costs one copy of the ciphertext and builds no concatenated list.
  With the same key and nonce and no associated data, the two classes produce
  the same bytes, so each decrypts the other's output. With associated data,
  each returns a published test vector's ciphertext followed by its tag.
  AesGcm256FfiAlgo encrypts and decrypts through one update step, which
  refuses a reported output length other than the input length, so
  encryption never writes the tag outside its buffer and decryption never
  reads past its plaintext buffer.

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

  Scenario: AES-256-GCM encryption with associated data returns the published ciphertext followed by the tag
    Given the 256-bit key, 96-bit nonce, plaintext and associated data of a published AES-GCM test vector
    When at_chops encrypts it with the FFI implementation and with the pure-Dart implementation
    Then each output is the vector's ciphertext followed by its 16-byte tag

  Scenario Outline: The pure-Dart encrypt step copies the ciphertext and tag into one buffer of exactly their length
    Given a 1000-byte plaintext, a key, a nonce and associated data
    And a <cipher> cipher whose ciphertext and tag fail the test if concatenated, iterated or copied into a new list
    When at_chops encrypts the plaintext with that cipher through the pure-Dart encrypt step
    Then the output is the ciphertext followed by the tag that <cipher> computes
    And the output owns a buffer of exactly the ciphertext and tag length

    Examples:
      | cipher            |
      | AES-256-GCM       |
      | ChaCha20-Poly1305 |

  Scenario Outline: The AES-256-GCM FFI update step refuses a reported length that differs from its input length
    Given a 60-byte <input>
    And an <operation> call that reports a <length>-byte <output>
    When at_chops runs that call as the FFI implementation's update step
    Then the step fails with a StateError naming <operation>, the <length>-byte <output> and the expected 60

    Examples:
      | operation         | input      | output     | length |
      | EVP_EncryptUpdate | plaintext  | ciphertext | 59     |
      | EVP_EncryptUpdate | plaintext  | ciphertext | 61     |
      | EVP_DecryptUpdate | ciphertext | plaintext  | 59     |
      | EVP_DecryptUpdate | ciphertext | plaintext  | 61     |
