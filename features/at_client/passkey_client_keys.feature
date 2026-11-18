Feature: A passkey client authenticates with a key it holds in memory
  A passkey enrollment's APKAM key is derived from the passkey at each login,
  and the server-held @keys document never holds it. The client a passkey
  login or onboarding opens is handed that key in memory, and its
  authenticator reads it there, so re-authenticating never reads the @keys
  document, least of all over the connection being authenticated. Every
  write of the @keys document leaves the APKAM private key out.

  Races: a re-authentication runs under its connection's request lock and
  reads its key from memory, so it never waits on a request queued behind
  that lock. Replay: unchanged; each `pkam:` signs the atServer's challenge
  for that connection. Denial of service: the key pair is held once per
  client, for the client's life, as any keyfile client holds its keys.
  Forgery and impersonation: the client authenticates as the enrollment its
  passkey opened (from the device's hints or the passkey's pointer) with the
  key derived from that passkey; nothing read from the @keys document
  changes which enrollment it authenticates as or with which key.

  Scenario: Onboarding returns a client that is online as the new enrollment
    Given @alice🛠 is not yet activated and its CRAM secret is known
    When the app onboards @alice🛠 with a new passkey
    Then it gets a passkey session whose client is online
    And the client's enrollment id is the one the passkey's pointer names

  Scenario: Logging in on a device that remembers nothing returns a client online as the pointed enrollment
    Given @alice🛠 was onboarded with a passkey
    And the device remembers no passkey or enrollment for @alice🛠
    When the app logs in to @alice🛠 with that passkey
    Then it gets a passkey session whose client is online
    And the client's enrollment id is the one the passkey's pointer names

  @race
  Scenario: A passkey client re-authenticates after its connection drops
    Given a passkey session's client of @alice🛠 is online
    When the atServer closes the client's connection
    And the app then puts a self record through the client
    Then the put succeeds
    And the client sent `from:` and `pkam:` as its own enrollment before the put
    And no lookup of the @keys document was sent between that `from:` and `pkam:`

  Scenario: A @keys document a passkey client writes holds no APKAM private key
    Given a passkey session's client of @alice🛠 is online
    When the client files new key material in its @keys
    Then the @keys document, opened with the passkey, holds the new material
    And it holds no APKAM private key, neither the flat field nor a typed authentication material
