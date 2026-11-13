Feature: Activation refuses a keyfile it cannot read or write before it uses the CRAM secret

  Races: a path that becomes unwritable between the check and the write
  still fails after CRAM; the check narrows that window but does not close
  it. Replay: none new; the CRAM secret is sent once, as before. DoS: none.
  Forgery and impersonation: unchanged.

  Scenario: An existing keyfile activation cannot read is refused before anything is sent
    Given an atKeys file at the activation's path that exists but cannot be read
    When the app activates the atSign with its CRAM secret
    Then it throws naming the path and why it cannot be read, and sends nothing to the atServer

  Scenario: A keyfile path activation cannot write is refused before anything is sent
    Given an activation path whose directory cannot be written
    When the app activates the atSign with its CRAM secret
    Then it throws naming the path, and sends nothing to the atServer

  Scenario: An absent keyfile still activates
    Given no atKeys file at the activation's path
    When the app activates the atSign with its CRAM secret
    Then activation completes and writes the keys

  Scenario: Activation refuses unusable keys with AtKeysUnusableException
    Given an atKeys store for @alice that exists but cannot be read, including a field of the wrong type or a keychain the platform refuses to read
    When the app activates @alice with its CRAM secret
    Then it throws AtKeysUnusableException with cause unreadable, naming the keys source and why, and sends nothing to the atServer
