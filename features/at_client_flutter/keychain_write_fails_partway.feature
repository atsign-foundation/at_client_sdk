Feature: A keychain write that fails partway leaves the entry as it was

  On Windows the keychain entry that holds every Atsign's keys is a header
  and segments, each written on its own, so a write can fail after some of
  them are written.

  Races: the undo is a second write, so a write another isolate makes
  between the read and the undo is overwritten by it; writes in other
  isolates already win or lose whole, since the keychain has no
  compare-and-swap. Replay: the undo writes back the entry's own earlier
  text, which no other party supplied. DoS: whoever can make a keychain
  write fail can make it undone, and already holds the user's session.
  Forgery and impersonation: none new; the keychain is the user's own store.

  Scenario: A keychain write that fails partway on Windows leaves the entry as it was
    Given a keychain on Windows holding @alice's keys
    When a write adding @bob's keys fails partway through its segments
    Then the write throws, the entry reads back as @alice's keys alone, and no segment of @bob's keys is left in the keychain
