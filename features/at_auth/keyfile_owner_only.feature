Feature: Keyfiles are written owner-only
  On Linux and macOS, FileAtKeysIo writes every keyfile, and the .bak and
  .pre-v1 copies it keeps beside one, readable and writable by the owner
  alone (mode 0600), whatever the process umask and whatever mode the file
  had before. Each write goes to a temporary file that is created with mode
  0600 before any key material is written to it, and is then renamed into
  place. On Windows the file takes its directory's permissions, as before.

  Races: every write already holds the keyfile's lock; the temporary file is
  0600 from the moment it exists, and a temporary file left by an interrupted
  write is replaced rather than written into. Replay: nothing is issued or
  checked. Denial of service: one mode change per file written; a file system
  that cannot hold the mode gets a warning naming the file and the write
  proceeds. Forgery and impersonation: only the file's owner can read or
  change the key material it holds.

  Background:
    Given a process whose umask is 022

  Scenario: A new keyfile is created owner-only
    Given no keyfile for @alice🛠
    When FileAtKeysIo writes @alice🛠's keys
    Then the keyfile's mode is 0600

  Scenario: A keyfile at the default path is created owner-only
    Given HOME is an empty directory
    When FileAtKeysIo, constructed with no file path, writes @alice🛠's keys
    Then the keyfile under HOME/.atsign/keys has mode 0600

  Scenario: A rewritten keyfile keeps owner-only permissions
    Given @alice🛠's keyfile has mode 0600
    When FileAtKeysIo updates it
    Then the keyfile's mode is 0600

  Scenario: A keyfile flushed in full keeps owner-only permissions
    Given @alice🛠's keyfile has mode 0600
    When FileAtKeysIo flushes @alice🛠's keys onto it
    Then the keyfile's mode is 0600

  Scenario: A keyfile with a wider mode is owner-only once rewritten
    Given @alice🛠's keyfile has mode 0644
    When FileAtKeysIo updates it
    Then the keyfile's mode is 0600

  Scenario: The rolling backup is owner-only
    Given @alice🛠's keyfile has mode 0644
    And a .bak beside it has mode 0644
    When FileAtKeysIo updates the keyfile
    Then the .bak's mode is 0600

  Scenario: The pre-upgrade copy is owner-only
    Given @alice🛠's keyfile is in the flat shape with mode 0644
    When FileAtKeysIo updates it with typed key material
    Then the .pre-v1 copy's mode is 0600

  @race
  Scenario: A temporary file left by an interrupted write is replaced, not reused
    Given @alice🛠's keyfile has mode 0600
    And a temporary file left beside it has mode 0644 and is open for reading
    When FileAtKeysIo updates the keyfile
    Then reading the open temporary file returns none of the new document
    And the keyfile's mode is 0600

  Scenario: Narrowing a keyfile to owner-only is logged
    Given @alice🛠's keyfile has mode 0644
    When FileAtKeysIo updates it
    Then one info line names the keyfile, 0644 and 0600
    And a second update logs nothing for it

  @race
  Scenario: A symbolic link left at the temporary file's path is replaced, not followed
    Given @alice🛠's keyfile has mode 0600
    And a symbolic link left at its temporary file's path points elsewhere
    When FileAtKeysIo updates the keyfile
    Then nothing is written where the link points
    And the keyfile is a file with mode 0600
