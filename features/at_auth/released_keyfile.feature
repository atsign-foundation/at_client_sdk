Feature: A keyfile the previous published at_auth wrote still reads and updates
  The fixtures were written by running the published at_auth 3.3.0 and 3.2.0,
  not by this build. 3.3.0 is the previous release of the package that owns
  the keyfile format; 3.2.0 is what at_onboarding_cli 1.16.0 and at_client
  3.14.0 resolved on the day they were released. Beside each fixture are the
  package version, the archive checksum, the lockfile, the capture command,
  and the values that release read back from the same file, which are what
  this build must read.

  Races: none arise; each test works on its own keyfile, a copy of a
  fixture or one it writes. Replay:
  none; the fixtures' keys and enrollment ids are never presented to an
  atServer. Denial of service: the fixtures are fixed. Forgery: a fixture's
  origin is checked by a scenario that shows this build would not write it.
  Impersonation: the keys are freshly generated test keys for a test atSign,
  valid on no atServer.

  Scenario: The current build reads every value at_auth 3.3.0 wrote
    Given the keyfile at_auth 3.3.0 wrote for @alice🛠
    When FileAtKeysIo reads it
    Then each key, the enrollment id and the apkam symmetric key equal what at_auth 3.3.0 read
    And every top-level field is either one FileAtKeysIo reads or kept in metadata

  Scenario: Flushing it back unchanged keeps every value
    Given the keyfile at_auth 3.3.0 wrote for @alice🛠
    When FileAtKeysIo updates it without changing anything
    Then the update succeeds
    And reading it back gives every value at_auth 3.3.0 read

  Scenario: Filing typed key material keeps every value
    Given the keyfile at_auth 3.3.0 wrote for @alice🛠
    When FileAtKeysIo updates it, filing an enrollment's key material
    Then reading it back gives every value at_auth 3.3.0 read, and the new material

  @forgery
  Scenario: The fixture is not a document this build writes
    Given the keyfile at_auth 3.3.0 wrote for @alice🛠
    When the current build reads it and writes the same keys to a new keyfile
    Then the new document differs from the fixture

  Scenario: The current build reads every value at_auth 3.3.0 wrote under a passphrase
    Given the passphrase-protected keyfile at_auth 3.3.0 wrote for @alice🛠
    When FileAtKeysIo reads it with that passphrase
    Then each key, the enrollment id and the apkam symmetric key equal what at_auth 3.3.0 read

  Scenario: The current build reads every value at_auth 3.2.0 wrote
    Given the keyfile at_auth 3.2.0 wrote for @alice🛠
    When FileAtKeysIo reads it
    Then each key, the enrollment id and the apkam symmetric key equal what at_auth 3.2.0 read
    And every top-level field is either one FileAtKeysIo reads or kept in metadata

  Scenario: Flushing the keyfile at_auth 3.2.0 wrote back unchanged keeps every value
    Given the keyfile at_auth 3.2.0 wrote for @alice🛠
    When FileAtKeysIo updates it without changing anything
    Then the update succeeds
    And reading it back gives every value at_auth 3.2.0 read

  Scenario: Filing typed key material in the keyfile at_auth 3.2.0 wrote keeps every value
    Given the keyfile at_auth 3.2.0 wrote for @alice🛠
    When FileAtKeysIo updates it, filing an enrollment's key material
    Then reading it back gives every value at_auth 3.2.0 read, and the new material
    And the .pre-v1 copy holds the 3.2.0 document byte for byte

  Scenario: A typed keyfile with no typed key material is rewritten in the flat shape
    Given a keyfile for @alice🛠 carrying version 1, its atSign and an empty keys array, and no typed key material
    When FileAtKeysIo updates it without adding typed key material
    Then the update succeeds
    And the keyfile is written in the flat shape, with every value it held

  @forgery
  Scenario: A keyfile naming another atSign is still refused
    Given a keyfile at @alice🛠's path whose atsign field names @bob🛠
    When FileAtKeysIo updates it for @alice🛠
    Then the update fails

  @forgery
  Scenario: A keyfile naming another atSign and holding only pending content is still refused
    Given a keyfile at @alice🛠's path whose atsign field names @bob🛠, holding no credential and only a pending enrollment, an enrollment with no keys yet, or pending keys of @bob🛠's own
    When FileAtKeysIo flushes @alice🛠's keys to it
    Then the flush fails, as it does when that keyfile holds nothing typed
    And the keyfile is left as it was

  Scenario: A keyfile holding only its own pending content is rewritten in the flat shape
    Given a keyfile for @alice🛠 holding no credential and only a pending enrollment, an enrollment with no keys yet, or pending keys of @alice🛠's own
    When FileAtKeysIo flushes @alice🛠's keys to it
    Then the flush succeeds
    And the keyfile is written in the flat shape, with @alice🛠's keys
