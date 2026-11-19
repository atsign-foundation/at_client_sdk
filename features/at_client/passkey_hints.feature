Feature: The passkey hints are a convenience, so a login and an onboarding go on without them
  A device remembers, for each Atsign, the credential id of the passkey that
  last opened it and the enrollment id of its enrollment, once an
  onboarding or a login has authenticated and finished the activation. A
  login with them narrows the passkey prompt to that credential and reads
  no pointer; a login without them asserts any passkey and reads the
  enrollment id from the passkey's pointer. A write of the hints that fails
  with an Exception is logged as a warning naming the Atsign, and the
  onboarding or login returns its session all the same; the next login
  without hints writes them. A failure that is an Error, not an Exception,
  still fails the call. A remembered credential id or enrollment id that
  cannot be read, or an enrollment id outside the enrollment id alphabet,
  counts as no hints, so it is never sent to the atServer. An enrollment id
  the pointer holds that is outside the alphabet is still a lost passkey,
  refused before any PKAM.

  Races: tabs of one origin that log in at once each write the hints they
  authenticated with; a pair that no longer opens is retried without
  hints. When separate stores take the two ids in two writes and only the
  first lands, the device holds a new credential id beside an old
  enrollment id; a login with that pair is refused by PKAM and retried
  without hints, which writes both.
  Replay: nothing new is sent or checked.
  Denial of service: a hint store that always fails makes every login a
  login without hints, which prompts for any passkey, reads the pointer and
  sends the CRAM secret's delete once more; only this origin's pages and
  browser can make the store fail, and they already hold the session.
  Forgery and impersonation: only this origin's pages and browser write the
  hints, and they already hold the session; a remembered enrollment id
  reaches the atServer only once it passes the enrollment id check, and only
  in a PKAM signed with the passkey's key, which the atServer refuses for
  any enrollment the passkey did not create.

  Scenario: A login whose passkey hints cannot be written returns its session, and the next login writes them
    Given @alice🛠 was onboarded with a passkey and this device saved no passkey hints for @alice🛠
    And this device's hint store fails its next write with an Exception
    When the app logs in to @alice🛠 with that passkey
    Then it gets a passkey session whose client is online as the onboarding's enrollment
    And a warning names @alice🛠 and says its passkey hints were not saved
    And the session says the passkey hints were not saved
    When the app logs in to @alice🛠 with that passkey again
    Then the passkey hints are saved
    And the session says the passkey hints were saved

  Scenario: An onboarding whose passkey hints cannot be written returns its session
    Given this device's hint store fails the write of the passkey hints with an Exception
    When the app onboards @alice🛠 with a new passkey
    Then it gets a passkey session whose client is online as the new enrollment
    And the CRAM secret is deleted and the encryption public key is published
    And this device holds no passkey hints for @alice🛠
    And the session says the passkey hints were not saved

  Scenario: A hint write that fails with an Error, not an Exception, still fails the login
    Given @alice🛠 was onboarded with a passkey
    And this device's hint store fails its next write with an Error
    When the app logs in to @alice🛠 with that passkey
    Then the login throws that Error
    And the enrollment's session is closed

  Scenario: A remembered enrollment id that cannot be read counts as no hints
    Given this device remembers the passkey of @alice🛠
    And reading its remembered enrollment id fails with an Exception
    When the app logs in to @alice🛠 with that passkey
    Then the login asserts any passkey and reads the passkey's pointer
    And it gets a passkey session whose client is online as the enrollment the pointer names
    And a warning names @alice🛠 and says its remembered enrollment id could not be read

  Scenario: A remembered credential id that cannot be read counts as no hints
    Given this device remembers the passkey of @alice🛠
    And reading its remembered credential id fails with an Exception
    When the app logs in to @alice🛠 with that passkey
    Then the login asserts any passkey and reads the passkey's pointer
    And it gets a passkey session whose client is online as the enrollment the pointer names
    And a warning names @alice🛠 and says its remembered credential id could not be read

  Scenario: A remembered enrollment id outside the enrollment id alphabet counts as no hints
    Given this device remembers the passkey of @alice🛠 beside an enrollment id outside the enrollment id alphabet
    When the app logs in to @alice🛠 with that passkey
    Then the login asserts any passkey and reads the passkey's pointer, sending no PKAM for the remembered id
    And it gets a passkey session whose client is online as the enrollment the pointer names
    And the passkey hints are replaced

  Scenario: An enrollment id the pointer holds outside the enrollment id alphabet is a lost passkey
    Given the passkey pointer of @alice🛠 holds an enrollment id outside the enrollment id alphabet
    When the app logs in to @alice🛠 on a device with no saved hints
    Then it throws a PasskeyLostException
    And no PKAM is sent
