Feature: A keychain entry that does not parse says why, and none of its text

  Races: none for a read, which parses one snapshot; a delete or a write of
  the keys takes the lock every write of them takes in the isolate, and one
  in another isolate is not excluded, since the keychain has no
  compare-and-swap. Replay: none; nothing is sent. DoS: the message is
  fixed-size whatever the entry's size, and a header's segment count is
  bounded at 2560, so no read, delete or write looks at a segment numbered
  2560 or more. Forgery and impersonation: unchanged; a count out of bounds
  is never followed, and what open does with an unreadable entry is decided
  separately.

  Scenario: A keychain entry that is not JSON names the reason and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When KeychainAtKeysIo reads it
    Then it throws AtKeysFormatException with the parser's reason and the 1-based character, holding none of the entry's text

  Scenario: Opening with that entry logs and keeps none of its text
    Given the same keychain entry
    When an app calls Atsign.open with KeychainAtKeysIo
    Then it throws AtKeysUnusableException, and no log record and no field of the exception holds any of the entry's text

  Scenario: On Windows, opening with that entry held in segments logs and keeps none of its text
    Given a Windows keychain header that parses, naming 2 segments that hold the same entry between them
    When an app calls Atsign.open with KeychainAtKeysIo
    Then it throws AtKeysUnusableException, each segment read is logged, and no log record and no field of the exception holds any of the entry's text

  Scenario: Adding keys to a keychain whose entry does not parse says why, and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When an app adds keys for another atSign to the keychain
    Then it throws AtKeysFormatException holding none of the entry's text, and the entry is unchanged

  Scenario: Removing an atSign from a keychain whose entry does not parse says why, and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When an app removes an atSign from the keychain
    Then it throws AtKeysFormatException holding none of the entry's text, and the entry is unchanged

  Scenario Outline: a legacy header "<bad>" is refused on read
    Given a Windows keychain entry whose header is the legacy count "<bad>"
    When an app reads the keychain
    Then it throws AtKeysFormatException whose reason is "a legacy segment header whose segmentCount is not a whole number from 0 to 2560", and no segment numbered 2560 or more is looked at

    Examples:
      | bad  |
      | 2561 |
      | -1   |
      | abc  |

  Scenario: a delete-all whose read of one segment throws still deletes every segment the header names
    Given a Windows keychain entry whose header names 3 segments, the second of which throws when read
    When an app deletes every atSign's keys
    Then the header and all 3 segments are deleted

  Scenario: a delete-all whose header cannot be read still deletes the segments present
    Given a Windows keychain entry of 2 segments whose header throws when read
    When an app deletes every atSign's keys
    Then the header and both segments are deleted, and the failed read is logged at severe

  Scenario: an empty segment does not end the search for the next
    Given a Windows keychain entry whose header does not parse, over an empty first segment and a second that is not empty
    When an app deletes every atSign's keys
    Then the header and both segments are deleted

  Scenario: a delete-all whose segment stays stored still deletes the header, then throws
    Given a Windows keychain entry whose header names 2 segments, the second of which stays stored when deleted
    When an app deletes every atSign's keys
    Then the header is deleted, the second segment is still stored, and the delete-all throws the failure

  Scenario Outline: a delete-all over a <form> header naming <count> segments takes the count as it is
    Given a Windows keychain entry whose <form> header names <count> segments, each stored
    When an app deletes every atSign's keys
    Then the header and its segments are deleted, and nothing is logged at severe

    Examples:
      | form   | count |
      | legacy | 0     |
      | legacy | 2560  |
      | JSON   | 0     |
      | JSON   | 2560  |

  Scenario: a delete-all over a legacy header deletes only the segments it names
    Given a Windows keychain entry whose legacy header names 2 segments, with a third legacy segment stored above them
    When an app deletes every atSign's keys
    Then the header and the 2 segments it named are deleted and the third is left

  Scenario: a delete over an oversized legacy header clears what is there and looks at no segment past the bound
    Given a Windows keychain entry whose header is the legacy count 2561, over one segment
    When an app deletes every atSign's keys
    Then the header and the segment are deleted, the refused header is logged at severe, and no segment numbered 2560 or more is looked at

  Scenario: a rewrite deletes the stale trailing segments, an empty one among them
    Given a Windows keychain entry holding @alice's keys, with an empty segment and then a stale one above its last
    When an app writes @alice's keys again
    Then only the segments the new header names are held, the empty and the stale one deleted

  Scenario: a rewrite whose stale segment stays stored logs it at severe, and the write stands
    Given a Windows keychain entry holding @alice's keys, with a stale segment above its last that stays stored when deleted
    When an app writes @alice's keys again
    Then the write succeeds, its header naming as many segments as before, and the failed delete is logged at severe

  Scenario: a rewrite deletes every segment the old header names, one that reads as absent included
    Given a Windows keychain entry holding @alice's keys in 3 segments, the second of which reads as absent
    When an app writes @alice's keys again, in 1 segment
    Then the second and third segments are deleted

  Scenario: a rewrite over a legacy header deletes only the segments it names
    Given a Windows keychain entry holding @alice's keys under a legacy header naming 2 segments, with a third legacy segment stored above them
    When an app writes @alice's keys again
    Then the 2 legacy segments it named are deleted and the third is left

  Scenario: a write over an oversized legacy header succeeds and looks at no segment past the bound
    Given a Windows store of @alice's passcodes whose header is the legacy count 2561
    When an app saves a passcode for @alice
    Then the store is written with a JSON header naming 1 segment, and no segment numbered 2560 or more is looked at

  Scenario: a Windows keychain whose segments always read as stored does not make a write search without end
    Given a Windows keychain with no header, whose every segment reads as stored
    When an app adds keys for @alice
    Then the write ends, and no segment numbered 2560 or more is deleted

  Scenario: a Windows keychain whose segments always read as stored does not make a delete-all search without end
    Given a Windows keychain with a header that does not parse, whose every segment reads as stored
    When an app deletes every atSign's keys
    Then the delete ends, and no segment numbered 2560 or more is looked at
