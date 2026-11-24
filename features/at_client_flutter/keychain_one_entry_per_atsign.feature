Feature: The keychain holds one entry per Atsign

  The keychain is an AtKeys store for many Atsigns, as the filesystem is.
  An entry here is logical: the keys the keychain holds for one Atsign,
  however many physical keychain items they are stored in.

  Races: an append takes the lock every write of the keys takes in the
  isolate, so two appends for one Atsign at once add one entry; one in
  another isolate is not excluded, since the keychain has no
  compare-and-swap. Replay: none; nothing is sent. DoS: none; the check
  looks through the entries the append already reads. Forgery and
  impersonation: keys may come from a keyfile the user imports, whose
  metadata can name any Atsign. The refusals turn a misfiling into an
  error, and nothing an entry names grants authority: keys authenticate
  only as the Atsign that issued them.

  Scenario: Appending keys for an Atsign the keychain already holds is refused
    Given a keychain holding keys for @alice
    When an app appends other keys for @alice with KeychainStorage.appendAtKeysToKeychain
    Then it throws AtKeysFileOverwriteException, and the keychain holds one entry for @alice, the first keys

  Scenario: Appending keys for another Atsign adds them
    Given a keychain holding keys for @alice
    When an app appends keys for @bob with KeychainStorage.appendAtKeysToKeychain
    Then the keychain holds one entry for each, and each reads back as it was written

  @race
  Scenario: Two appends for one Atsign at once add one entry
    Given a keychain holding no keys
    When an app starts two appends of keys for @alice at once
    Then one completes and the other throws AtKeysFileOverwriteException, and the keychain holds one entry for @alice

  Scenario: Appending keys that name their Atsign only in the typed field files them under that Atsign
    Given keys for @alice with no typed key material, whose Atsign is set only on the typed field
    When the app appends them to the keychain
    Then reading @alice returns them, and a second append for @alice is refused

  Scenario: Appending keys whose typed Atsign and metadata name different Atsigns is refused
    Given keys whose typed Atsign is @alice and whose metadata names @bob
    When the app appends them to the keychain
    Then it throws AtKeysValidationException before reading the keychain, leaving the keychain and the keys unchanged

  Scenario: Appending keys with no typed key material that name no Atsign adds them
    Given keys with no typed key material that name no Atsign
    When the app appends them twice
    Then both appends complete

  Scenario: Changing an Atsign's keys with keys that name another Atsign is refused
    Given the keychain holds @alice
    When the app calls updateAtKeysInKeychain for @carol with keys that name @alice
    Then it throws AtKeysValidationException before reading the keychain, leaving the keychain unchanged

  Scenario: Changing an Atsign's keys with keys that name no Atsign files them under that Atsign
    Given the keychain holds @alice
    When the app calls updateAtKeysInKeychain for @alice with keys that name no Atsign
    Then reading @alice returns the new keys

  Scenario: Writing keys whose metadata names another Atsign is refused
    Given a keychain that holds no keys, and keys with no typed key material whose metadata names @alice
    When the app writes them for @carol through KeychainAtKeysIo
    Then it throws AtKeysValidationException, leaving the keychain unchanged
