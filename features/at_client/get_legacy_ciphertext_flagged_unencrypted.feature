Feature: get reads legacy ciphertext stored with isEncrypted false
  at_client 3.0.10 to 3.2.1 sent no isEncrypted, or false, with values it had encrypted, and the atServer stores a missing flag as false. A get decrypts such a value when it has legacy ciphertext's shape (base64 of a non-zero multiple of 16 bytes, no provider other than legacy) and returns any other value flagged false unchanged.

  Races: none; a get reads one record. Replay: no new message or token. DoS: one legacy decryption attempt per get of a value flagged false with that shape, which for a record another atSign shared can include fetching that atSign's shared key; a value with no flag already costs the same. Forgery and impersonation: unchanged; the decryption uses this client's own keys, or the shared key the record's owner made for it, and a writer who can store a value flagged false could already store it flagged true.

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

  Scenario: A record shared before at_client 3.2.2 is decrypted by its recipient
    Given @bob shared a record with @alice as legacy ciphertext, stored with isEncrypted false
    When @alice gets it
    Then the value comes back decrypted
