Feature: A keychain entry that does not parse says why, and none of its text

  Races: none; a read parses one snapshot. Replay: none; nothing is sent.
  DoS: the message is fixed-size whatever the entry's size. Forgery and
  impersonation: unchanged; what open does with an unreadable entry is
  decided separately.

  Scenario: A keychain entry that is not JSON names the reason and none of its text
    Given a keychain atKeys entry whose text is not JSON
    When KeychainAtKeysIo reads it
    Then it throws AtKeysFormatException with the parser's reason and the 1-based character, holding none of the entry's text

  Scenario: Opening with that entry logs and keeps none of its text
    Given the same keychain entry
    When an app calls Atsign.open with KeychainAtKeysIo
    Then no log record and no field of connection.current holds any of the entry's text
