Feature: Keyfiles are written owner-only
  On Linux and macOS, FileAtKeysIo writes every keyfile, and the .bak and
  .pre-v1 copies it keeps beside one, readable and writable by the owner
  alone (mode 0600), whatever the process umask and whatever mode the file
  had before. Written as root, the keyfile and its .bak and .pre-v1 copies
  take the owner and group of the keyfile as it was read; a keyfile that did
  not exist stays owned by root, and root does not rewrite a keyfile that is
  a symbolic link or whose directory is one. Each write goes to a temporary file that is created with
  mode 0600 before any key material is written to it, and is then renamed
  into place. On Windows the file takes its directory's permissions, as before.

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

  Scenario: A keyfile rewritten by root keeps its owner and group
    Given @alice🛠's keyfile is owned by another account, with mode 0600
    When FileAtKeysIo, running as root, updates it
    Then the keyfile keeps that owner and group
    And the keyfile's mode is 0600

  Scenario: Copies root writes for the first time take the keyfile's owner and group
    Given @alice🛠's keyfile is in the flat shape, owned by another account, with mode 0600
    And no .bak or .pre-v1 copy beside it
    When FileAtKeysIo, running as root, updates it with typed key material
    Then the .bak and the .pre-v1 copy have the keyfile's owner and group
    And their mode is 0600

  Scenario: A backup owned by another account takes the keyfile's owner and group when root rewrites it
    Given @alice🛠's keyfile is owned by one account, with mode 0600
    And a .bak beside it is owned by a second account
    When FileAtKeysIo, running as root, updates the keyfile
    Then the .bak has the keyfile's owner and group
    And the .bak's mode is 0600

  Scenario: Root does not rewrite a keyfile that is a symbolic link
    Given @alice🛠's keyfile is a symbolic link to a file owned by another account
    When FileAtKeysIo, running as root, updates it
    Then the update fails
    And the file the link points to is unchanged

  @race
  Scenario: A keyfile replaced while root updates it is written with the owner it was read with
    Given @alice🛠's keyfile is owned by one account, with mode 0600
    When FileAtKeysIo, running as root, updates it, and the keyfile is replaced by a link to a second account's file before the update writes
    Then the keyfile written is a file with the first account's owner and group
    And the second account's file is unchanged

  @race
  Scenario: A keys directory replaced while root updates a keyfile in it is not written through
    Given @alice🛠's keyfile is owned by one account, in a directory that account controls
    When FileAtKeysIo, running as root, updates it, and the directory is replaced by a link to a second account's directory before the update writes
    Then the second account's directory is unchanged
    And the keyfile written is a file with the first account's owner and group, in the directory the keyfile was read from

  Scenario: Root does not write a keyfile in a directory that is a symbolic link
    Given @alice🛠's keys directory is a symbolic link to a second account's directory
    When FileAtKeysIo, running as root, flushes keys onto the keyfile there
    Then the flush fails
    And the second account's directory is unchanged

  Scenario: A backup path that is a symbolic link is replaced when root rewrites the keyfile
    Given @alice🛠's keyfile is owned by one account
    And its .bak is a symbolic link to a second account's file
    When FileAtKeysIo, running as root, updates the keyfile
    Then the .bak is a file with the keyfile's owner and group
    And the second account's file is unchanged

  Scenario: A keyfile the writer cannot open is still there to root
    Given @alice🛠's keyfile has mode 0000, so the writer cannot open it
    When FileAtKeysIo asks the keys directory, opened as root opens it, whether the keyfile is there
    Then it is there, so a write is refused and a flush validates it before replacing it
