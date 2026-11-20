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

  Scenario: A directory at the keyfile path is refused before anything is sent
    Given a directory, or anything else that is not a file, at the activation's keyfile path
    When the app activates the atSign with its CRAM secret
    Then it throws FileSystemException naming the path and what is there, sends nothing to the atServer, and leaves what is at the path as it was, with no probe file beside it

  Scenario: Activation with no keys store, or a read-only one, is refused before anything is sent
    Given an onboarding request for @alice with no atKeysIo, or with one that cannot be written
    When onboard is called with the CRAM secret
    Then it throws AtAuthenticationException saying where the keys must go, and sends nothing to the atServer

  Scenario: An absent keyfile still activates
    Given no atKeys file at the activation's path
    When the app activates the atSign with its CRAM secret
    Then activation completes and writes the keys

  Scenario: Activation refuses unusable keys with AtKeysUnusableException
    Given an atKeys store for @alice that exists but cannot be read, including a field of the wrong type or a keychain the platform refuses to read
    When the app activates @alice with its CRAM secret
    Then it throws AtKeysUnusableException with cause unreadable, naming the keys source and why, and sends nothing to the atServer

  @race
  Scenario: Two checks that one keyfile path can be written, run at once, both succeed
    Given a keyfile path in a directory this process can write
    When two checks that the keyfile can be written start together
    Then both succeed
    And nothing is left behind in the directory

  Scenario: The writability check removes the file it creates to find out
    Given a keyfile path in a directory this process can write
    When the check creates its probe file and deletes it
    Then nothing is left behind in the directory
    And when that delete fails, the check throws naming the keyfile's path

  Scenario: A keyfile path that cannot be resolved is unreadable keys
    Given a FileAtKeysIo whose path cannot be resolved, as the default path on a platform with no home directory
    When the app activates @alice with its CRAM secret
    Then it throws AtKeysUnusableException with cause unreadable, saying the path could not be resolved, and sends nothing to the atServer
