Feature: A keychain entry that does not parse says why, and none of its text

  Races: none for a read, which parses one snapshot; a delete or a write
  takes the lock every write of the keys takes. Replay: none; nothing is
  sent. DoS: the message is fixed-size whatever the entry's size, and a
  header's segment count is bounded at 2560, so no read, delete or write
  looks at more segments than that. Forgery and impersonation: unchanged; a
  count out of bounds is refused, never followed, and what open does with an
  unreadable entry is decided separately.

  Scenario: A keychain entry that is not JSON names the reason and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When KeychainAtKeysIo reads it
    Then it throws AtKeysFormatException with the parser's reason and the 1-based character, holding none of the entry's text

  Scenario: Opening with that entry logs and keeps none of its text
    Given the same keychain entry
    When an app calls Atsign.open with KeychainAtKeysIo
    Then it throws AtKeysUnusableException, and no log record and no field of the exception holds any of the entry's text

  Scenario: Adding keys to a keychain whose entry does not parse says why, and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When an app adds keys for another atSign to the keychain
    Then it throws AtKeysFormatException holding none of the entry's text, and the entry is unchanged

  Scenario: Removing an atSign from a keychain whose entry does not parse says why, and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When an app removes an atSign from the keychain
    Then it throws AtKeysFormatException holding none of the entry's text, and the entry is unchanged

  Scenario Outline: A Windows header with a segment count out of bounds is refused
    Given a Windows keychain header, JSON or legacy, whose segment count is <count>
    When an app reads the keychain
    Then it throws AtKeysFormatException saying the count must be a whole number from 0 to 2560, and looks at no segment

    Examples:
      | count                     |
      | missing or not a number   |
      | -1                        |
      | 2561                      |

  Scenario: Deleting every atSign's keys removes every segment the header names
    Given a Windows keychain header naming 3 segments, one of which cannot be read
    When an app deletes every atSign's keys
    Then all 3 segments and the header are deleted, and a segment that stays stored is logged at severe, with the header deleted regardless

  Scenario: Deleting a keychain whose header cannot be used removes the segments present
    Given a Windows keychain whose header cannot be read, parsed or is out of bounds, over segments, one of them empty
    When an app deletes every atSign's keys
    Then every contiguous segment from 0 is deleted, an empty one not ending the search, and none at or above 2560 is looked at

  Scenario: Rewriting a Windows entry shorter removes the stale trailing segments
    Given a Windows entry of several segments, with stale segments above it
    When an app writes a shorter entry over it
    Then the header names the new count, the stale segments are deleted from the top down, and one that cannot be deleted is logged at severe without failing the write

  Scenario: Writing over an oversized legacy header still writes
    Given a Windows store whose legacy header is 2561
    When an app writes an entry to it
    Then the entry is written with a JSON header, and no segment at or above 2560 is looked at
