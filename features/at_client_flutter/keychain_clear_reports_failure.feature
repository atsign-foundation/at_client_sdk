Feature: Clearing the keychain throws what the keychain throws

  KeychainStorage.deleteAllAtKeysData deletes the keychain's AtKeys entry,
  under its current name and under the legacy pre-2.0.0 one. It tries both,
  reading each back after its delete, then throws the first failure: a
  delete the keychain refused, or a store that is still there, or cannot be
  read back, after its delete. So a clear that did not happen never reads as
  done, except in two cases on Windows: when the credential store fails a
  delete and also hides the entry from a read, and when the clear cannot
  read or parse the entry's header, so it searches the segments from index
  0, stops at the first absent one, and leaves stored any segment above
  that gap. A store that holds nothing is not a failure.

  When both stores fail, the first failure is thrown and the second logged
  at warning. A failure to read the app's package name, which names both
  stores, is thrown before either store is tried. On Windows, a segment of
  the entry that cannot be deleted is thrown once the entry's header is
  deleted, and a clear also deletes the segments of a legacy Windows header
  that an earlier clear left behind, searching from index 0. After a clear
  that threw, a read can still return keys it did not remove, moving any
  left under the legacy store name to the current one; clearing again
  retries both stores.

  Races: the clear takes the keychain's write lock in this isolate, as every
  change to the AtKeys entry does; the SPP stores' changes, by saveSpp,
  deleteSppData and getAllSpps when it drops expired values, take no lock.
  Another isolate is excluded by nothing, as for every keychain change.
  Replay: none; nothing is sent. DoS: none; two deletes and a read-back of
  each, and on Windows, for each store, up to three segment searches (of its
  own segments, of a legacy header's segments when its count is refused,
  and of the legacy segments from index 0), each reading at most 2560
  segments, with a delete and a read-back of each segment found or named.
  Forgery and impersonation: only the app on the device calls it, and it
  already holds the keychain.

  Scenario: Clearing a keychain whose delete fails throws that failure
    Given a keychain whose delete of the AtKeys entry fails with a platform error
    When the app calls deleteAllAtKeysData
    Then it throws that error, after also trying to delete the legacy-named store

  Scenario: Clearing a keychain that holds nothing completes
    Given a keychain whose deletes report that nothing was stored
    When the app calls deleteAllAtKeysData
    Then it completes

  Scenario: Clearing a keychain whose delete leaves the entry stored throws
    Given a keychain whose delete of the AtKeys entry completes but leaves it stored
    When the app calls deleteAllAtKeysData
    Then it throws, after also trying to delete the legacy-named store

  @race
  Scenario: A read in flight while the keychain is cleared does not bring the cleared keys back
    Given a keychain holding keys only under the legacy store name, and a read that has read the legacy store but not yet moved it to the current name
    When the app clears the keychain, and the read then finishes
    Then the keychain holds no keys under either name
