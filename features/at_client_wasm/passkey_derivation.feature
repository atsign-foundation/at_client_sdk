Feature: The browser derives passkey keys with at_chops' HKDF
  The lookup id, pointer namespace, auth seed and seal key of a passkey are
  each HKDF-SHA256 of its PRF output, with an empty salt and the info
  `<label>|<atSign>`, computed by at_chops' HkdfSha256. In the browser the
  seal key's bytes are imported as a non-extractable AES-GCM key and then
  overwritten with zeroes: the seal key can't be exported once derived.

  Forgery and impersonation: the outputs are the ones the derivation
  vectors pin, so every record and pointer sealed before still opens and
  names the same enrollment; page code able to read Dart memory already
  holds the PRF output the seal key is derived from. Races, replay and
  denial of service: none; a derivation is local work on 32 bytes.

  Scenario: The browser's derivation matches the vectors
    Given the passkey derivation vectors
    When each is derived in the browser, compiled with dart2js and with dart2wasm
    Then every lookup id, namespace and auth seed matches its vector
    And every vector's sealed record opens with the derived seal key

  Scenario: The seal key can't be exported once derived
    Given a seal key derived in the browser
    When page code asks WebCrypto to export it
    Then the export is refused
    And the key's only usages are encrypt and decrypt

  Scenario: The seal key's bytes are overwritten once imported
    Given the browser derives a seal key
    Then the bytes it imported are all zeroes afterwards

  Scenario: at_client_wasm has no HKDF of its own
    Given the library sources of at_client_wasm
    Then none of them asks WebCrypto for HKDF
