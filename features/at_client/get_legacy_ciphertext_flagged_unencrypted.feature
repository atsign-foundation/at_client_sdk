Feature: get reads legacy ciphertext stored with isEncrypted false
  Clients before at_client 3.2.1 encrypted values without sending isEncrypted, and the atServer stores a missing flag as false. A get decrypts such a value when it has legacy ciphertext's shape (base64 of a non-zero multiple of 16 bytes, no provider other than legacy) and returns any other value flagged false unchanged.

  Races: none; a get reads one record. Replay: no new message or token. DoS: at most one extra legacy decryption per value flagged false with that shape. Forgery and impersonation: unchanged; the decryption uses this client's own keys, and the record comes from its own atServer.

  Scenario: Legacy ciphertext flagged isEncrypted false is decrypted
    Given a self record whose value is legacy ciphertext, stored with isEncrypted false
    When a client gets it
    Then the value comes back decrypted

  Scenario: A plain value flagged isEncrypted false comes back unchanged
    Given a self record whose value is plain JSON, stored with isEncrypted false
    When a client gets it
    Then the value comes back unchanged

  Scenario: A value with ciphertext's shape that does not decrypt comes back unchanged
    Given a self record stored with isEncrypted false whose value is base64 of 32 bytes that is not ciphertext under this client's self key
    When a client gets it
    Then the value comes back unchanged

  Scenario: A record shared before at_client 3.2.1 is decrypted by its recipient
    Given @bob shared a record with @alice as legacy ciphertext, stored with isEncrypted false
    When @alice gets it
    Then the value comes back decrypted
